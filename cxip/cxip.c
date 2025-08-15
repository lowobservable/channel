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
#include <arpa/inet.h>
#include <assert.h>

#include <real.h>
#include <chan.h>
#include <mock_cu.h>

#include <cxip_protocol.h>

struct chan {
    struct chan_out out;
    uint8_t *recv_buf; // Client message buffer is used when sending data to the device
    bool solicited;
    uint8_t cmd;
    size_t count;
};

#define MSG_BUF_SIZE(D) (MAX((D) + 32, 1024))

struct client {
    char name[16]; // Client IP address for now
    int sock;
    uint8_t *msg_buf;
    size_t msg_buf_size;
    size_t msg_buf_len;
    int dev_addr;
};

static bool serve(int listen_sock, struct chan *chan);

static bool handle_connect(struct client *client, struct chan *chan);
static bool handle_client_data(struct client *client);
static void discard_msg(struct client *client, size_t msg_len);
static bool handle_msg(struct client *client, uint8_t *msg, size_t msg_len, struct chan *chan);
static bool handle_start_msg(struct client *client, uint8_t *msg, size_t msg_len, struct chan *chan);
static bool handle_dev_status(struct client *client, struct chan *chan, uint8_t dev_addr, uint8_t status);

static bool init_client(struct client *client, struct chan *chan);
static bool close_client(struct client *client, struct chan *chan);

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

                struct sockaddr_in addr;
                socklen_t addr_len = sizeof(struct sockaddr_in);

                if (getpeername(sock, (struct sockaddr_in *) &addr, &addr_len) < 0) {
                    perror("getpeername");
                    return false;
                }

                if (inet_ntop(AF_INET, &addr.sin_addr, client.name, 15) == NULL) {
                    perror("inet_ntop");
                    return false;
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

                if (!handle_client_data(&client)) {
                    if (!close_client(&client, chan)) {
                        return false;
                    }
                }
            }

            if (event.events & (EPOLLRDHUP | EPOLLHUP)) {
                assert(event.data.fd == client.sock);

                printf("Client %s disconnected\n", client.name);

                if (!close_client(&client, chan)) {
                    return false;
                }
            }
        }

        if (client.sock != -1) {
            uint8_t *msg;

            ssize_t msg_len = cxip_decode_msg(client.msg_buf, client.msg_buf_len, &msg);

            if (msg_len < 0) {
                printf("ERROR: Invalid message\n");

                if (!close_client(&client, chan)) {
                    return false;
                }
            }

            if (msg_len > 0) {
                if (!handle_msg(&client, msg, msg_len, chan)) {
                    return false;
                }

                discard_msg(&client, msg_len);
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
    printf("Client %s connected\n", client->name);

    return true;
}

bool handle_client_data(struct client *client)
{
    size_t remaining = client->msg_buf_size - client->msg_buf_len;

    while (remaining > 0) {
        uint8_t *buf = client->msg_buf + client->msg_buf_len;

        ssize_t result = read(client->sock, buf, remaining);

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

void discard_msg(struct client *client, size_t msg_len)
{
    client->msg_buf_len -= 3 + msg_len;

    if (client->msg_buf_len > 0) {
        memmove(client->msg_buf, client->msg_buf + 3 + msg_len, client->msg_buf_len);
    }
}

bool handle_msg(struct client *client, uint8_t *msg, size_t msg_len, struct chan *chan)
{
    uint8_t dev_addr;

    if (cxip_decode_start(msg, msg_len, NULL, NULL, NULL, NULL, NULL)) {
        return handle_start_msg(client, msg, msg_len, chan);
    } else if (cxip_decode_open(msg, msg_len, &dev_addr)) {
        if (client->dev_addr == dev_addr) {
            printf("WARN: Device %.2X already open\n", dev_addr);
            return cxip_send_error(client->sock, 0, "Device already open");
        }

        chan_out_config(&chan->out, dev_addr, true);

        printf("%.2X | Open   |\n", dev_addr);

        client->dev_addr = dev_addr;

        return cxip_send_ack(client->sock);
    } else if (cxip_decode_close(msg, msg_len, &dev_addr)) {
        if (client->dev_addr != dev_addr) {
            printf("WARN: Device %.2X not open\n", dev_addr);
            return cxip_send_error(client->sock, 0, "Device not open");
        }

        chan_out_config(&chan->out, dev_addr, false);

        printf("%.2X | Close  |\n", dev_addr);

        client->dev_addr = -1;

        return cxip_send_ack(client->sock);
    } else {
        printf("ERROR: Invalid message\n");
        return close_client(client, chan);
    }

    return true;
}

bool handle_start_msg(struct client *client, uint8_t *msg, size_t msg_len, struct chan *chan)
{
    uint8_t dev_addr;
    uint8_t cmd;
    uint8_t flags;
    void *data;
    uint16_t count;

    if (!cxip_decode_start(msg, msg_len, &dev_addr, &cmd, &flags, &data, &count)) {
        return false;
    }

    // Determine if the command will result in data being received from the
    // device.
    bool is_recv_cmd = !(cmd & 0x01);

    if (is_recv_cmd) {
        data = chan->recv_buf;
    }

    char fmt_cmd_buf[CHAN_FMT_CMD_BUF_SIZE];

    printf("%.2X | Start  | %s [Count = %u]", dev_addr, chan_fmt_cmd(cmd, fmt_cmd_buf, sizeof(fmt_cmd_buf)), count);

    int start_result = chan_out_start(&chan->out, dev_addr, cmd, flags, data, count);

    if (start_result == -1) {
        printf("\nchan_out_start error: %d\n", start_result);
        return false;
    } else if (start_result < -1) {
        printf(" [Error %d]\n", start_result);
        return cxip_send_error(client->sock, start_result * (-1), "Start error");
    }

    printf("\n");

    if (!cxip_send_ack(client->sock)) {
        return false;
    }

    chan->solicited = true;
    chan->cmd = cmd;
    chan->count = count;

    return true;
}

bool handle_dev_status(struct client *client, struct chan *chan, uint8_t dev_addr, uint8_t status)
{
    bool solicited = chan->solicited;

    char fmt_status_buf[CHAN_FMT_STATUS_BUF_SIZE];

    if (solicited && chan->count > 0 && (status & CHAN_STATUS_CE)) {
        ssize_t result = chan_out_complete(&chan->out, chan->cmd, chan->recv_buf, chan->count);

        if (result < 0) {
            printf("chan_out_complete error: %zd\n", result);
            return false;
        }

        size_t transfer_count = result;
        size_t residual_count = chan->count - transfer_count;

        printf("%.2X | Data   | [Transfer = %zu] [Count = %zu] [Residual = %zu]\n", dev_addr, transfer_count, chan->count, residual_count);

        bool is_send_cmd = chan->cmd & 0x01;

        if (is_send_cmd) {
            cxip_send_count(client->sock, dev_addr, transfer_count);
        } else {
            cxip_send_data(client->sock, dev_addr, chan->recv_buf, transfer_count);
        }
    }

    // I think a solitary CE is the only penultimate status, all other
    // combinations should indicate the command was not accepted or has been
    // completed.
    if (solicited && status != CHAN_STATUS_CE) {
        chan->solicited = false;
    }

    printf("%.2X | Status | %s %s\n", dev_addr, chan_fmt_status(status, fmt_status_buf, sizeof(fmt_status_buf)), solicited ? "[Solicited]" : "");

    return cxip_send_status(client->sock, dev_addr, status, solicited);
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
