// insmod u-dma-buf.ko udmabuf0=16000

#define _GNU_SOURCE // for accept4

#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <netinet/in.h>
#include <errno.h>
#include <assert.h>

#include <real.h>
#include <chan.h>
#include <mock_cu.h>

#define MSG_BUF_SIZE 16000

#define ADDR 0x60

uint8_t xxx_buf[MSG_BUF_SIZE];
size_t xxx_buf_len = 0;

bool serve(int listen_sock, struct chan *chan);
void handle_client(int sock, struct chan *chan);
void handle_message(int sock, struct chan *chan, uint8_t *msg, size_t msg_len);
void test_and_send_status(int sock, struct chan *chan, uint8_t addr);
void purge_status(struct chan *chan, uint8_t addr);

int main(int argc, char **argv)
{
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
    addr.sin_port = htons(3174);

    if (bind(listen_sock, (struct sockaddr *) &addr, sizeof(addr)) < 0) {
        perror("bind");
        return EXIT_FAILURE;
    }

    if (listen(listen_sock, 10) < 0) {
        perror("listen");
        return EXIT_FAILURE;
    }

    bool frontend_enable = true;

    if (argc > 1 && strcmp(argv[1], "-l") == 0) {
        frontend_enable = false;
    }

    if (!frontend_enable) {
        printf("WARN: External interface not enabled, acting as loopback\n");
    }

    struct chan chan;

    if (chan_open(&chan, 0x40000000, mem_fd, "udmabuf0", frontend_enable) < 0) {
        perror("chan_open");
        return EXIT_FAILURE;
    }

    struct mock_cu mock_cu;

    if (mock_cu_open(&mock_cu, 0x40001000, mem_fd) < 0) {
        perror("mock_cu_open");
        return EXIT_FAILURE;
    }

    mock_cu_arrange(&mock_cu, false, false, 16);

    if (!serve(listen_sock, &chan)) {
        return EXIT_FAILURE;
    }

    mock_cu_close(&mock_cu);
    chan_close(&chan, true);

    close(listen_sock);
    close(mem_fd);

    return EXIT_SUCCESS;
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

    printf("READY\n");

    int client_sock = -1;

    while (true) {
        struct epoll_event event;

		int count = epoll_wait(epfd, &event, 1, 250);

        if (count > 0) {
            if (event.data.fd == listen_sock) {
                int sock;

                if ((sock = accept4(listen_sock, NULL, NULL, SOCK_NONBLOCK)) < 0) {
                    perror("accept4");
                    return false;
                }

                if (client_sock == -1) {
                    client_sock = sock;

xxx_buf_len = 0; // Reset, for new client...
purge_status(chan, ADDR);

                    printf("CONNECTED\n");

                    ev.events = EPOLLIN | EPOLLET | EPOLLRDHUP | EPOLLHUP;
                    ev.data.fd = client_sock;

                    if (epoll_ctl(epfd, EPOLL_CTL_ADD, client_sock, &ev) < 0) {
                        perror("epoll_ctl");
                        return false;
                    }

                    //test_and_send_status(client_sock, chan, ADDR /* TODO */);
                } else {
                    printf("CONNECTION REJECTED\n");

                    close(sock);
                }
            } else if (event.events & EPOLLIN) {
                assert(event.data.fd == client_sock);

                handle_client(client_sock, chan);
            }

            if (event.events & (EPOLLRDHUP | EPOLLHUP)) {
                assert(event.data.fd == client_sock);

				epoll_ctl(epfd, EPOLL_CTL_DEL, client_sock, NULL);

				close(client_sock);

                client_sock = -1;

                printf("DISCONNECTED\n");
			}
        }

        // Check for request in.
        if (client_sock != -1) {
            if (chan_request_in(chan)) {
                printf("REQUEST IN...\n");

                test_and_send_status(client_sock, chan, ADDR /* TODO */);
            }
        }
    }

    return true;
}

void handle_client(int sock, struct chan *chan)
{
    // First, read as much as we can into the buffer.
    uint8_t *buf_p = xxx_buf + xxx_buf_len;

    size_t buf_remaining = MSG_BUF_SIZE - xxx_buf_len;

    //printf("before reads, buf_len = %zu, buf_remaining = %zu\n", xxx_buf_len, buf_remaining);

    while (buf_remaining > 0) {
        ssize_t result = read(sock, buf_p, buf_remaining);

        if (result == 0 || (result == -1 && (errno == EAGAIN || errno == EWOULDBLOCK))) {
            break;
        }

        if (result < 0) {
            perror("read");
            break;
        }

        size_t count = result;

        //printf("read %zu bytes\n", count);

        xxx_buf_len += count;
        buf_remaining -= count;
    }

    //printf("after reads, buf_len = %zu, buf_remaining = %zu\n", xxx_buf_len, buf_remaining);

    // Then, execute any complete commands.
    buf_p = xxx_buf;

    while (xxx_buf_len >= 2 /* the minimum message length */) {
        uint16_t msg_len = (buf_p[0] << 8) | buf_p[1];

        //printf("msg_len = %d\n", msg_len);

        // Message is not complete...
        if (xxx_buf_len < msg_len + 2) {
            break;
        }

        buf_p += 2;

        handle_message(sock, chan, buf_p, msg_len);

        buf_p += msg_len;
        xxx_buf_len -= (2 + msg_len);
    }

    if (buf_p != xxx_buf && xxx_buf_len > 0) {
        memmove(xxx_buf, buf_p, xxx_buf_len);
    }
}

void handle_message(int sock, struct chan *chan, uint8_t *msg, size_t msg_len)
{
    uint8_t buf[MSG_BUF_SIZE];

    if (msg_len < 1) {
        return;
    }

    uint8_t type = msg[0];

    if (type == 1 /* PING */) {
        printf("PING\n");

        buf[0] = 0;
        buf[1] = 1;

        buf[2] = 2; // PONG

        if (write(sock, buf, 3) < 3) {
            perror("write");
        }
    } else if (type == 3 /* EXEC */) {
        printf("EXEC\n");

        if (msg_len < 6) {
            printf("\tinvalid message, len = %zu\n", msg_len);
            return;
        }

        uint8_t addr = msg[1];
        uint8_t cmd = msg[2];
        uint8_t flags = msg[3];
        size_t count = (msg[4] << 8) | msg[5];
        uint8_t *data;

        bool is_write_command = cmd & 0x01;

        if (is_write_command) {
            data = &msg[6];
        } else {
            data = &buf[7];
        }

        printf("\taddr = %.2x, cmd = %.2x, flags = %.2x, count = %zu\n", addr, cmd, flags, count);

        ssize_t result = chan_exec(chan, ADDR /* TODO */, cmd, data, count);

        uint8_t device_status = chan_device_status(chan);

        /*
        ssize_t result;
        uint8_t device_status;

        if (cmd == 0x03) {
            result = 0;
            device_status = CHAN_STATUS_CE | CHAN_STATUS_DE;
        } else if (cmd == 0xe4) {
            data[0] = 0xff;
            data[1] = 0x12;
            data[2] = 0x34;
            data[3] = 0x56;
            result = 4;
            device_status = CHAN_STATUS_CE | CHAN_STATUS_DE;
        } else if (cmd == 0x02) {
            int i;
            for (i = 0; i < count; i++) {
                data[i] = i + 1;
            }
            result = count;
            device_status = CHAN_STATUS_CE | CHAN_STATUS_DE;
        } else if (cmd == 0x01) {
            result = count;
            device_status = CHAN_STATUS_CE | CHAN_STATUS_DE;
        } else {
            result = 0;
            device_status = CHAN_STATUS_CE | CHAN_STATUS_DE | CHAN_STATUS_UC;
        }
        */

        printf("\tresult = %zd, status = %.2x\n", result, device_status);

        // special hack for DE...
        if ((device_status & CHAN_STATUS_CE) && !(device_status & CHAN_STATUS_DE)) {
            result = 0;

            // wait for it via request in...
            printf("\tgot CE without DE, waiting for DE via request in...\n");

            while (!chan_request_in(chan)) {
                usleep(100000); // 100ms
            }

            int test_result = chan_test(chan, ADDR /* TODO */);

            if (test_result < 0) {
                printf("\ttest result = %d\n", test_result);
                return;
            }

            device_status |= chan_device_status(chan);

            printf("\tupdated status = %.2x\n", device_status);

            if (!(device_status & CHAN_STATUS_DE)) {
                printf("\tstill no DE...\n");
            }
        }

        buf[2] = 4; // EXEC RESPONSE

        if (result < 0) {
            buf[3] = (-1) * result;

            count = 0;
        } else {
            buf[3] = 0;

            count = result;
        }

        buf[4] = device_status;
        buf[5] = (count >> 8) & 0xff;
        buf[6] = count & 0xff;

        msg_len = count + 5;

        buf[0] = (msg_len >> 8) & 0xff;
        buf[1] = msg_len & 0xff;

        if (write(sock, buf, msg_len + 2) < msg_len + 2) {
            perror("write");
        }

        printf("\tdone\n");
    }
}

void test_and_send_status(int sock, struct chan *chan, uint8_t addr)
{
    uint8_t buf[MSG_BUF_SIZE];

    int result = chan_test(chan, addr);

    if (result < 0) {
        printf("\tresult = %d\n", result);
        return;
    }

    uint8_t device_status = chan_device_status(chan);

    printf("\tstatus = %.2x\n", device_status);

    buf[0] = 0;
    buf[1] = 3;
    buf[2] = 5; // STATUS
    buf[3] = addr;
    buf[4] = device_status;

    if (write(sock, buf, 5) < 5) {
        perror("write");
    }
}

void purge_status(struct chan *chan, uint8_t addr)
{
    // Very hacky... this is no way to do error recovery!
    while (true) {
        printf("TEST...\n");

        int result = chan_test(chan, addr);

        if (result < 0) {
            printf("\tresult = %d\n", result);
            return;
        }

        uint8_t status = chan_device_status(chan);

        printf("\tstatus = 0x%.2x\n", status);

        if (status == 0x00) {
            break;
        }

        sleep(1);
    }
}
