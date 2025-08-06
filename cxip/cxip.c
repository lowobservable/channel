// insmod u-dma-buf.ko udmabuf0=16000

#define _GNU_SOURCE // for accept4

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <sys/param.h>
#include <netinet/in.h>
#include <assert.h>

#include <real.h>
#include <chan.h>
#include <mock_cu.h>

#define MSG_TYPE_ACK 0x00
#define MSG_TYPE_PING 0x01
#define MSG_TYPE_OPEN 0x02
#define MSG_TYPE_CLOSE 0x03
#define MSG_TYPE_START 0x04
#define MSG_TYPE_STATUS 0x05
#define MSG_TYPE_DATA 0x06
#define MSG_TYPE_ERROR 0xff

struct chan {
    struct chan_out out;
    uint8_t *recv_buf; // Client message buffer is used when sending data to the device
    bool solicited;
    uint8_t cmd;
    size_t count;
};

#define MSG_BUF_SIZE(D) (MAX((D) + 32, 1024))

struct client {
    int sock;
    uint8_t *msg_buf;
    size_t msg_buf_size;
    size_t msg_buf_len;
    uint8_t *msg;
    size_t msg_len;
    int dev_addr;
};

static bool serve(int listen_sock, struct chan *chan);

static bool handle_connect(struct client *client, struct chan *chan);
static bool handle_disconnect(struct client *client, struct chan *chan);
static bool handle_msg(struct client *client, uint8_t *msg, size_t len, struct chan *chan);
static bool handle_start_msg(struct client *client, uint8_t *msg, size_t len, struct chan *chan);
static bool handle_dev_status(struct client *client, struct chan *chan, uint8_t dev_addr, uint8_t status);

static bool init_client(struct client *client, struct chan *chan);
static bool close_client(struct client *client, struct chan *chan);
static bool recv_all(struct client *client);
static ssize_t get_msg(struct client *client, uint8_t **msg);
static bool send_msg(struct client *client, void *msg, size_t len);
static bool send_ack_msg(struct client *client);
static bool send_error_msg(struct client *client, uint8_t num, char *text);
static bool send_status_msg(struct client *client, uint8_t dev_addr, uint8_t status, bool solicited);
static bool send_data_msg(struct client *client, uint8_t dev_addr, void *data, size_t count);

int main(int argc, char **argv)
{
    int port = 3174;
    bool frontend_enable = true;
    bool mock_enable = false;

    int opt;

    while ((opt = getopt(argc, argv, "lm")) != -1) {
        switch (opt) {
            case 'l':
                frontend_enable = false;
                break;

            case 'm':
                mock_enable = true;
                break;

            default:
                printf("Usage: %s [-lm]\n", argv[0]);
                return EXIT_FAILURE;
        }
    }

    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("mem_open");
        return EXIT_FAILURE;
    }

    int listen_sock;

    if ((listen_sock = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0)) < 0) {
        perror("socket");
        return EXIT_FAILURE;
    }

    struct sockaddr_in addr;

    memset(&addr, 0, sizeof(addr));

    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);

    if (bind(listen_sock, (struct sockaddr *) &addr, sizeof(addr)) < 0) {
        perror("bind");
        return EXIT_FAILURE;
    }

    if (listen(listen_sock, 10) < 0) {
        perror("listen");
        return EXIT_FAILURE;
    }

    if (frontend_enable && mock_enable) {
        printf("WARN: Mock CU and physical interface enabled\n");
    } else if (!frontend_enable && !mock_enable) {
        printf("WARN: Loopback with no mock CU, no CUs available\n");
    } else if (!frontend_enable) {
        printf("WARN: Physical interface not enabled, acting as loopback\n");
    }

    struct chan chan;

    int result = chan_out_open(&chan.out, mem_fd, "udmabuf0", frontend_enable);

    if (result == -1) {
        perror("chan_open");
        return EXIT_FAILURE;
    } else if (result < -1) {
        printf("chan_open error: %d\n", result);
        return EXIT_FAILURE;
    }

    if ((chan.recv_buf = malloc(chan.out.udmabuf.size)) == NULL) {
        perror("malloc");
        return EXIT_FAILURE;
    }

    chan_out_enable(&chan.out);

    struct mock_cu mock_cu;

    if (mock_enable) {
        result = mock_cu_open(&mock_cu, mem_fd);

        if (result == -1) {
            perror("mock_cu_open");
            return EXIT_FAILURE;
        } else if (result < -1) {
            printf("mock_cu_open error: %d\n", result);
            return EXIT_FAILURE;
        }

        mock_cu_arrange(&mock_cu, false, false, false, 16);
    }

    bool success = serve(listen_sock, &chan);

    if (mock_enable) {
        mock_cu_close(&mock_cu);
    }

    chan_out_close(&chan.out);

    free(chan.recv_buf);

    close(listen_sock);
    close(mem_fd);

    return (success ? EXIT_SUCCESS : EXIT_FAILURE);
}

volatile bool stop = false;

static void signal_handler(int signum)
{
    if (signum == SIGINT) {
        stop = true;
    }
}

bool serve(int listen_sock, struct chan *chan)
{
    int epfd;

    if ((epfd = epoll_create(1)) < 0) {
        perror("epoll_create");
        return false;
    }

    struct epoll_event ev;

    ev.events = EPOLLIN;
    ev.data.fd = listen_sock;

    if (epoll_ctl(epfd, EPOLL_CTL_ADD, listen_sock, &ev) < 0) {
        perror("epoll_ctl");
        return false;
    }

    printf("Listening...\n");

    struct client client;

    if (!init_client(&client, chan)) {
        return false;
    }

    signal(SIGINT, signal_handler);

    while (!stop) {
        struct epoll_event event;

        int count = epoll_wait(epfd, &event, 1, 100); // 100 ms

        if (count > 0) {
            if (event.data.fd == listen_sock) {
                int sock;

                if ((sock = accept4(listen_sock, NULL, NULL, SOCK_NONBLOCK)) < 0) {
                    perror("accept4");
                    return false;
                }

                if (client.sock != -1) {
                    printf("Connection rejected due to active client\n");

                    close(sock);
                    continue;
                }

                client.sock = sock;

                ev.events = EPOLLIN | EPOLLET | EPOLLRDHUP | EPOLLHUP;
                ev.data.fd = client.sock;

                if (epoll_ctl(epfd, EPOLL_CTL_ADD, client.sock, &ev) < 0) {
                    perror("epoll_ctl");
                    return false;
                }

                if (!handle_connect(&client, chan)) {
                    return false;
                }
            } else if (event.events & EPOLLIN) {
                assert(event.data.fd == client.sock);

                if (!recv_all(&client)) {
                    if (!close_client(&client, chan)) {
                        return false;
                    }
                }
            }

            if (event.events & (EPOLLRDHUP | EPOLLHUP)) {
                assert(event.data.fd == client.sock);

                if (!handle_disconnect(&client, chan)) {
                    return false;
                }

                if (!close_client(&client, chan)) {
                    return false;
                }
            }
        }

        if (client.sock != -1) {
            uint8_t *buf;

            ssize_t msg_result = get_msg(&client, &buf);

            if (msg_result < 0) {
                if (!close_client(&client, chan)) {
                    return false;
                }
            }

            if (msg_result > 0) {
                if (!handle_msg(&client, buf, msg_result, chan)) {
                    return false;
                }
            }
        }

        if (client.sock != -1 && client.dev_addr != -1) {
            uint8_t status;

            int test_result = chan_out_test(&chan->out, client.dev_addr, &status);

            if (test_result < 0) {
                printf("chan_out_test error: %d\n", test_result);
                return false;
            }

            if (test_result) {
                if (!handle_dev_status(&client, chan, client.dev_addr, status)) {
                    return false;
                }
            }
        }
    }

    signal(SIGINT, SIG_DFL);

    if (stop) {
        printf("\nStopped\n");
    }

    close(epfd);

    return true;
}

bool handle_connect(struct client *client, struct chan *chan)
{
    printf("Client connected\n");

    return true;
}

bool handle_disconnect(struct client *client, struct chan *chan)
{
    printf("Client disconnected\n");

    if (client->dev_addr != -1) {
        chan_out_config(&chan->out, client->dev_addr, false);

        client->dev_addr = -1;
    }

    return true;
}

bool handle_msg(struct client *client, uint8_t *msg, size_t len, struct chan *chan)
{
    if (len < 1) {
        printf("ERROR: Invalid message length: %zu\n", len);
        return close_client(client, chan);
    }

    uint8_t msg_type = msg[0];

    if (msg_type == MSG_TYPE_PING) {
        printf("Ping\n");

        if (len != 1) {
            printf("ERROR: Invalid message length: %zu\n", len);
            return close_client(client, chan);
        }

        return send_ack_msg(client);
    } else if (msg_type == MSG_TYPE_OPEN) {
        printf("Open\n");

        if (len != 2) {
            printf("ERROR: Invalid message length: %zu\n", len);
            return close_client(client, chan);
        }

        uint8_t dev_addr = msg[1];

        printf("\tAddr = %.2x\n", dev_addr);

        if (client->dev_addr == dev_addr) {
            printf("\tWarn: Already open\n");
            return send_error_msg(client, 0, "Device already open");
        }

        chan_out_config(&chan->out, dev_addr, true);

        client->dev_addr = dev_addr;

        return send_ack_msg(client);
    } else if (msg_type == MSG_TYPE_CLOSE) {
        printf("Close\n");

        if (len != 2) {
            printf("ERROR: Invalid message length: %zu\n", len);
            return close_client(client, chan);
        }

        uint8_t dev_addr = msg[1];

        printf("\tAddr = %.2x\n", dev_addr);

        if (client->dev_addr != dev_addr) {
            printf("\tWarn: Not open\n");
            return send_error_msg(client, 0, "Device not open");
        }

        chan_out_config(&chan->out, dev_addr, false);

        client->dev_addr = -1;

        return send_ack_msg(client);
    } else if (msg_type == MSG_TYPE_START) {
        return handle_start_msg(client, msg, len, chan);
    } else {
        printf("ERROR: Unsupported message type: %d\n", msg_type);
        return close_client(client, chan);
    }

    return true;
}

bool handle_start_msg(struct client *client, uint8_t *msg, size_t len, struct chan *chan)
{
    printf("Start\n");

    if (len < 4) {
        printf("\tERROR: Invalid message length: %zu\n", len);
        return close_client(client, chan);
    }

    uint8_t dev_addr = msg[1];

    printf("\tAddr = %.2x\n", dev_addr);

    if (client->dev_addr != dev_addr) {
        printf("\tWarn: Not open\n");
        return send_error_msg(client, 0, "Device not open");
    }

    uint8_t cmd = msg[2];
    uint8_t flags = msg[3];

    // Determine if the command will result in data being sent to the device.
    bool is_send_cmd = cmd & 0x01;

    void *data;
    size_t count;

    if (is_send_cmd) {
        data = &msg[4];
        count = len - 4;
    } else {
        if (len < 6) {
            printf("\tERROR: Invalid message length: %zu\n", len);
            return close_client(client, chan);
        }

        data = chan->recv_buf;
        count = (msg[4] << 8) | msg[5];
    }

    printf("\tCmd = %.2x, Flags = %.2x, Count = %zu\n", cmd, flags, count);

    int start_result = chan_out_start(&chan->out, dev_addr, cmd, flags, data, count);

    if (start_result == -1) {
        printf("chan_out_start error: %d\n", start_result);
        return false;
    } else if (start_result < -1) {
        printf("\tError = %d\n", start_result);
        return send_error_msg(client, start_result * (-1), "Start error");
    }

    chan->solicited = true;
    chan->cmd = cmd;
    chan->count = count;

    return true;
}

bool handle_dev_status(struct client *client, struct chan *chan, uint8_t dev_addr, uint8_t status)
{
    printf("Status\n");
    printf("\tAddr = %.2x, Status = %.2x\n", dev_addr, status);

    bool solicited = chan->solicited;
    bool is_send_cmd = chan->cmd & 0x01;

    if (solicited && (status & CHAN_STATUS_CE)) {
        ssize_t result = chan_out_complete(&chan->out, chan->cmd, chan->recv_buf, chan->count);

        if (result < 0) {
            printf("chan_out_complete error: %zd\n", result);
            return false;
        }

        if (chan->count > 0) {
            if (is_send_cmd) {
                send_data_msg(client, dev_addr, NULL, result);
            } else {
                send_data_msg(client, dev_addr, chan->recv_buf, result);
            }
        }
    }

    if (solicited && (status & CHAN_STATUS_DE)) {
        chan->solicited = false;
    }

    return send_status_msg(client, dev_addr, status, solicited);
}

bool init_client(struct client *client, struct chan *chan)
{
    client->sock = -1;

    client->msg_buf_size = MSG_BUF_SIZE(chan->out.udmabuf.size);

    if ((client->msg_buf = malloc(client->msg_buf_size)) == NULL) {
        perror("malloc");
        return false;
    }

    client->msg_buf_len = 0;

    client->msg = NULL;
    client->msg_len = 0;

    client->dev_addr = -1;

    return true;
}

bool close_client(struct client *client, struct chan *chan)
{
    if (client->sock != -1) {
        close(client->sock);

        client->sock = -1;
    }

    if (client->msg_buf != NULL) {
        free(client->msg_buf);

        client->msg_buf = NULL;
    }

    if (client->dev_addr != -1) {
        chan_out_config(&chan->out, client->dev_addr, false);

        client->dev_addr = -1;
    }

    return init_client(client, chan);
}

bool recv_all(struct client *client)
{
    uint8_t *p = client->msg_buf + client->msg_buf_len;

    size_t remaining = client->msg_buf_size - client->msg_buf_len;

    while (remaining > 0) {
        ssize_t result = read(client->sock, p, remaining);

        if (result == 0 || (result == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))) {
            break;
        }

        if (result < 0) {
            perror("read");
            return false;
        }

        client->msg_buf_len += result;
        remaining -= result;
    }

    return true;
}

ssize_t get_msg(struct client *client, uint8_t **msg)
{
    // Drop previous message.
    if (client->msg != NULL) {
        client->msg_buf_len -= 3 + client->msg_len;

        if (client->msg_buf_len > 0) {
            memmove(client->msg_buf, client->msg_buf + 3 + client->msg_len, client->msg_buf_len);
        }

        client->msg = NULL;
        client->msg_len = 0;
    }

    // Header is incomplete...
    if (client->msg_buf_len < 3) {
        return 0;
    }

    uint8_t version = client->msg_buf[0];

    if (version != 0) {
        printf("ERROR: Unsupported protocol version: %d\n", version);
        return -1;
    }

    uint16_t len = (client->msg_buf[1] << 8) | client->msg_buf[2];

    // Message is incomplete...
    if (client->msg_buf_len < 3 + len) {
        return 0;
    }

    client->msg = &client->msg_buf[3];
    client->msg_len = len;

    *msg = client->msg;

    return client->msg_len;
}

bool send_msg(struct client *client, void *msg, size_t len)
{
    uint8_t buf[3];

    buf[0] = 0;
    buf[1] = (len & 0xff00) >> 8;
    buf[2] = len & 0x00ff;

    if (write(client->sock, &buf, 3) < 3) {
        return false;
    }

    if (write(client->sock, msg, len) < len) {
        return false;
    }

    return true;
}

bool send_ack_msg(struct client *client)
{
    uint8_t buf[1];

    buf[0] = MSG_TYPE_ACK;

    return send_msg(client, &buf, 1);
}

bool send_error_msg(struct client *client, uint8_t num, char *text)
{
    uint8_t buf[102];

    buf[0] = MSG_TYPE_ERROR;
    buf[1] = num;

    size_t len = MIN(strlen(text), 100);

    memcpy(&buf[2], text, len);

    len += 2;

    return send_msg(client, &buf, len);
}

bool send_status_msg(struct client *client, uint8_t dev_addr, uint8_t status, bool solicited)
{
    uint8_t buf[4];

    buf[0] = MSG_TYPE_STATUS;
    buf[1] = dev_addr;
    buf[2] = status;
    buf[3] = solicited;

    return send_msg(client, &buf, 4);
}

bool send_data_msg(struct client *client, uint8_t dev_addr, void *data, size_t count)
{
    size_t len = 2;

    if (data != NULL) {
        len += count;
    } else {
        len += 2;
    }

    uint8_t buf[7];

    buf[0] = 0;
    buf[1] = (len & 0xff00) >> 8;
    buf[2] = len & 0x00ff;
    buf[3] = MSG_TYPE_DATA;
    buf[4] = dev_addr;

    if (data == NULL) {
        buf[5] = (count & 0xff00) >> 8;
        buf[6] = count & 0x00ff;
    }

    // Now, make len the buffer length.
    len = (data != NULL) ? 5 : 7;

    if (write(client->sock, &buf, len) < len) {
        return false;
    }

    if (data != NULL) {
        if (write(client->sock, data, count) < count) {
            return false;
        }
    }

    return true;
}
