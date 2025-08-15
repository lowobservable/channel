// insmod u-dma-buf.ko udmabuf0=16000

#define _GNU_SOURCE // for accept4

#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
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

#define CLIENTS_MAX 1

struct chan {
    struct chan_out out;
    uint8_t *recv_buf; // Client message buffer is used when sending data to the device
};

struct dev {
    uint16_t num;
    struct chan *chan;
    uint8_t addr;
    struct client *client;
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
};

struct state {
    struct chan *chan;
    struct dev *dev;
    struct client clients[CLIENTS_MAX];
};

static bool serve(int listen_sock, struct chan *chan, struct dev *dev);

static bool handle_connect(int sock, struct client **client, struct state *state);
static bool handle_client_data(struct client *client, struct state *state);
static void discard_msg(struct client *client, size_t msg_len);
static bool handle_msg(struct client *client, uint8_t *msg, size_t msg_len, struct state *state);
static bool handle_start_msg(struct client *client, uint8_t *msg, size_t msg_len, struct state *state);
static bool handle_dev_status(struct dev *dev, uint8_t status);

static struct dev *find_dev(struct state *state, int num);
static struct client *find_client(struct state *state, int sock);
static bool close_client(struct client *client, struct state *state);

static void usage(char *cmd);
static bool parse_dev_config(char *config, uint16_t *num, uint8_t *addr);

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
                usage(argv[0]);
                return EXIT_FAILURE;
        }
    }

    if (optind >= argc) {
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    char *dev_config;

    if ((dev_config = strdup(argv[optind])) == NULL) {
        perror("strdup");
        return EXIT_FAILURE;
    }

    uint16_t dev_num;
    uint8_t dev_addr;

    if (!parse_dev_config(dev_config, &dev_num, &dev_addr)) {
        printf("Device config invalid: %s\n", argv[optind]);
        return EXIT_FAILURE;
    }

    free(dev_config);

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
        printf("WARN: Loopback with no mock CU, no devices will be operational\n");
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

    struct dev dev;

    dev.num = dev_num;
    dev.chan = &chan;
    dev.addr = dev_addr;
    dev.client = NULL;

    printf("Device number %.4X configured for address %.2X\n", dev.num, dev.addr);

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

    bool success = serve(listen_sock, &chan, &dev);

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

bool serve(int listen_sock, struct chan *chan, struct dev *dev)
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

    struct state state;

    state.chan = chan;
    state.dev = dev;

    for (size_t index = 0; index < CLIENTS_MAX; index++) {
        struct client *client = &state.clients[index];

        client->sock = -1;
        client->msg_buf_size = MSG_BUF_SIZE(chan->out.udmabuf.size);

        if ((client->msg_buf = malloc(client->msg_buf_size)) == NULL) {
            perror("malloc");
            return false;
        }

        client->msg_buf_len = 0;
    }

    printf("Listening...\n");

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

                struct client *client;

                if (!handle_connect(sock, &client, &state)) {
                    return false;
                }

                if (client == NULL) {
                    printf("Connection rejected, client connection limit reached\n");

                    close(sock);
                    continue;
                }

                ev.events = EPOLLIN | EPOLLET | EPOLLRDHUP | EPOLLHUP;
                ev.data.fd = client->sock;

                if (epoll_ctl(epfd, EPOLL_CTL_ADD, client->sock, &ev) < 0) {
                    perror("epoll_ctl");
                    return false;
                }

                printf("Client %s connected\n", client->name);
            } else if (event.events & EPOLLIN) {
                struct client *client = find_client(&state, event.data.fd);

                assert(client != NULL);

                if (!handle_client_data(client, &state)) {
                    if (!close_client(client, &state)) {
                        return false;
                    }
                }
            }

            if (event.events & (EPOLLRDHUP | EPOLLHUP)) {
                struct client *client = find_client(&state, event.data.fd);

                assert(client != NULL);

                printf("Client %s disconnected\n", client->name);

                if (!close_client(client, &state)) {
                    return false;
                }
            }
        }

        // TODO: It might be more efficient to only do this if there is socket
        // activity, although we'd need to burn down all the messages.
        for (size_t index = 0; index < CLIENTS_MAX; index++) {
            struct client *client = &state.clients[index];

            if (client->sock == -1) {
                continue;
            }

            uint8_t *msg;

            ssize_t msg_len = cxip_decode_msg(client->msg_buf, client->msg_buf_len, &msg);

            if (msg_len < 0) {
                printf("ERROR: Invalid message\n");

                if (!close_client(client, &state)) {
                    return false;
                }
            }

            if (msg_len > 0) {
                if (!handle_msg(client, msg, msg_len, &state)) {
                    return false;
                }

                discard_msg(client, msg_len);
            }
        }

        if (state.dev->client != NULL) {
            uint8_t status;

            int test_result = chan_out_test(&state.dev->chan->out, state.dev->addr, &status);

            if (test_result < 0) {
                printf("chan_out_test error: %d\n", test_result);
                return false;
            }

            if (test_result) {
                if (!handle_dev_status(state.dev, status)) {
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

bool handle_connect(int sock, struct client **client, struct state *state)
{
    *client = NULL;

    // Try and locate a free slot...
    struct client *free_client = find_client(state, -1);

    if (free_client == NULL) {
        return true;
    }

    struct sockaddr_in addr;
    socklen_t addr_len = sizeof(struct sockaddr_in);

    if (getpeername(sock, (struct sockaddr_in *) &addr, &addr_len) < 0) {
        perror("getpeername");
        return false;
    }

    if (inet_ntop(AF_INET, &addr.sin_addr, free_client->name, 15) == NULL) {
        perror("inet_ntop");
        return false;
    }

    free_client->sock = sock;

    free_client->msg_buf_size = MSG_BUF_SIZE(state->chan->out.udmabuf.size);

    if ((free_client->msg_buf = malloc(free_client->msg_buf_size)) == NULL) {
        perror("malloc");
        return false;
    }

    free_client->msg_buf_len = 0;

    *client = free_client;

    return true;
}

bool handle_client_data(struct client *client, struct state *state)
{
    size_t remaining = client->msg_buf_size - client->msg_buf_len;

    while (remaining > 0) {
        uint8_t *buf = client->msg_buf + client->msg_buf_len;

        ssize_t result = read(client->sock, buf, remaining);

        if (result == 0 || (result == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))) {
            break;
        }

        if (result < 0) {
            return close_client(client, state);
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

bool handle_msg(struct client *client, uint8_t *msg, size_t msg_len, struct state *state)
{
    uint16_t dev_num;

    if (cxip_decode_start(msg, msg_len, NULL, NULL, NULL, NULL, NULL)) {
        return handle_start_msg(client, msg, msg_len, state);
    } else if (cxip_decode_open(msg, msg_len, &dev_num)) {
        struct dev *dev = find_dev(state, dev_num);

        if (dev == NULL) {
            printf("WARN: Device %.4X is not defined\n", dev_num);
            return cxip_send_error(client->sock, 0, "Device not defined");
        }

        if (dev->client != NULL) {
            printf("WARN: Device %.4X already open\n", dev_num);
            return cxip_send_error(client->sock, 0, "Device already open");
        }

        chan_out_config(&dev->chan->out, dev->addr, true);

        printf("%.4X | %.2X | Open   |\n", dev->num, dev->addr);

        dev->client = client;

        return cxip_send_ack(client->sock);
    } else if (cxip_decode_close(msg, msg_len, &dev_num)) {
        struct dev *dev = find_dev(state, dev_num);

        if (dev == NULL) {
            printf("WARN: Device %.4X is not defined\n", dev_num);
            return cxip_send_error(client->sock, 0, "Device not defined");
        }

        if (dev->client != client) {
            printf("WARN: Device %.4X not open\n", dev_num);
            return cxip_send_error(client->sock, 0, "Device not open");
        }

        chan_out_config(&dev->chan->out, dev->addr, false);

        printf("%.4X | %.2X | Close  |\n", dev->num, dev->addr);

        dev->client = NULL;

        return cxip_send_ack(client->sock);
    } else {
        printf("ERROR: Invalid message\n");
        return close_client(client, state);
    }

    return true;
}

bool handle_start_msg(struct client *client, uint8_t *msg, size_t msg_len, struct state *state)
{
    uint16_t dev_num;
    uint8_t cmd;
    uint8_t flags;
    void *data;
    uint16_t count;

    if (!cxip_decode_start(msg, msg_len, &dev_num, &cmd, &flags, &data, &count)) {
        return false;
    }

    struct dev *dev = find_dev(state, dev_num);

    if (dev == NULL) {
        printf("WARN: Device %.4X is not defined\n", dev_num);
        return cxip_send_error(client->sock, 0, "Device not defined");
    }

    if (dev->client != client) {
        printf("WARN: Device %.4X not open\n", dev_num);
        return cxip_send_error(client->sock, 0, "Device not open");
    }

    // Determine if the command will result in data being received from the
    // device.
    bool is_recv_cmd = !(cmd & 0x01);

    if (is_recv_cmd) {
        data = NULL;
    }

    char fmt_cmd_buf[CHAN_FMT_CMD_BUF_SIZE];

    printf("%.4X | %.2X | Start  | %s [Count = %u]", dev->num, dev->addr, chan_fmt_cmd(cmd, fmt_cmd_buf, sizeof(fmt_cmd_buf)), count);

    int start_result = chan_out_start(&dev->chan->out, dev->addr, cmd, flags, data, count);

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

    dev->solicited = true;
    dev->cmd = cmd;
    dev->count = count;

    return true;
}

bool handle_dev_status(struct dev *dev, uint8_t status)
{
    assert(dev->client != NULL);

    int sock = dev->client->sock;

    bool solicited = dev->solicited;

    char fmt_status_buf[CHAN_FMT_STATUS_BUF_SIZE];

    if (solicited && dev->count > 0 && (status & CHAN_STATUS_CE)) {
        ssize_t result = chan_out_complete(&dev->chan->out, dev->cmd, dev->chan->recv_buf, dev->count);

        if (result < 0) {
            printf("chan_out_complete error: %zd\n", result);
            return false;
        }

        size_t transfer_count = result;
        size_t residual_count = dev->count - transfer_count;

        printf("%.4X | %.2X | Data   | [Transfer = %zu] [Count = %zu] [Residual = %zu]\n", dev->num, dev->addr, transfer_count, dev->count, residual_count);

        bool is_send_cmd = dev->cmd & 0x01;

        if (is_send_cmd) {
            cxip_send_count(sock, dev->num, transfer_count);
        } else {
            cxip_send_data(sock, dev->num, dev->chan->recv_buf, transfer_count);
        }
    }

    // I think a solitary CE is the only penultimate status, all other
    // combinations should indicate the command was not accepted or has been
    // completed.
    if (solicited && status != CHAN_STATUS_CE) {
        dev->solicited = false;
    }

    printf("%.4X | %.2X | Status | %s %s\n", dev->num, dev->addr, chan_fmt_status(status, fmt_status_buf, sizeof(fmt_status_buf)), solicited ? "[Solicited]" : "");

    return cxip_send_status(sock, dev->num, status, solicited);
}

struct dev *find_dev(struct state *state, int num)
{
    if (state->dev != NULL && state->dev->num == num) {
        return state->dev;
    }

    return NULL;
}

struct client *find_client(struct state *state, int sock)
{
    for (size_t index = 0; index < CLIENTS_MAX; index++) {
        struct client *client = &state->clients[index];

        if (client->sock == sock) {
            return client;
        }
    }

    return NULL;
}

bool close_client(struct client *client, struct state *state)
{
    if (state->dev != NULL && state->dev->client == client) {
        struct dev *dev = state->dev;

        chan_out_config(&dev->chan->out, dev->addr, false);

        dev->client = NULL;
    }

    if (client->sock != -1) {
        close(client->sock);

        client->sock = -1;
    }

    if (client->msg_buf != NULL) {
        free(client->msg_buf);

        client->msg_buf = NULL;
    }

    return true;
}

void usage(char *cmd)
{
    printf("Usage: %s [-lm] nnnn[:aa]\n", cmd);
}

bool parse_dev_config(char *config, uint16_t *num, uint8_t *addr)
{
    if (config == NULL) {
        return false;
    }

    char *token;
    char *rest = config;

    if ((token = strtok_r(rest, ":", &rest)) == NULL) {
        return false;
    }

    for (int element = 0; element < 2; element++) {
        for (size_t index = 0; index < strlen(token); index++) {
            if (!(isxdigit(token[index]) || isblank(token[index]))) {
                return false;
            }
        }

        char *end;

        errno = 0;

        unsigned long value = strtol(token, &end, 16);

        if (errno != 0 || *end != '\0') {
            return false;
        }

        if (element == 0 && value <= 0xffff) {
            *num = (uint16_t) value;
            *addr = (uint8_t) (value & 0xff);
        } else if (element == 1 && value <= 0xff) {
            *addr = (uint8_t) (value & 0xff);
        } else {
            return false;
        }

        if (strlen(rest) == 0) {
            break;
        }

        token = rest;
    }

    return true;
}
