// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <real.h>
#include <util.h>

#include "chan.h"
#include "mock_cu.h"

bool test_no_cu(struct chan *chan);
bool test_busy(struct chan *chan, struct mock_cu *mock_cu);
bool test_read_command(char *case_name, struct chan *chan, uint16_t count,
         struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count);
bool test_write_command(char *case_name, struct chan *chan, uint16_t count,
         struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count);
bool test_nop_command(struct chan *chan, struct mock_cu *mock_cu);

void buf_arrange(uint8_t *buf, size_t count);
bool buf_assert(uint8_t *buf, size_t count);

int main(void)
{
    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("mem_open");
        return EXIT_FAILURE;
    }

    struct chan chan;

    if (chan_open(&chan, 0x40000000, mem_fd, "udmabuf0", false) < 0) {
        perror("chan_open");
        return EXIT_FAILURE;
    }

    struct mock_cu mock_cu;

    if (mock_cu_open(&mock_cu, 0x40001000, mem_fd) < 0) {
        perror("mock_cu_open");
        return EXIT_FAILURE;
    }

    printf("READY\n");

    test_no_cu(&chan);
    test_busy(&chan, &mock_cu);
    test_read_command("read_command_cu_more", &chan, 6, &mock_cu, 16, 6);
    test_read_command("read_command_cu_less", &chan, 16, &mock_cu, 6, 6);
    test_write_command("write_command_cu_more", &chan, 6, &mock_cu, 16, 6);
    test_write_command("write_command_cu_less", &chan, 16, &mock_cu, 6, 6);
    test_read_command("big_read", &chan, 512, &mock_cu, 512, 512);
    test_nop_command(&chan, &mock_cu);

    mock_cu_close(&mock_cu);

    chan_close(&chan, true);

    close(mem_fd);

    return EXIT_SUCCESS;
}

bool test_no_cu(struct chan *chan)
{
    printf("TEST: test_no_cu\n");

    ssize_t result = chan_exec(chan, 0x10, 0x03 /* NOP */, NULL, 0);

    if (result != -3) {
        printf("FAIL: expected not operational condition code\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_busy(struct chan *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_busy\n");

    mock_cu_arrange(mock_cu, true, false, 0);

    ssize_t result = chan_exec(chan, 0xff, 0x03 /* NOP */, NULL, 0);

    if (result != -4) {
        printf("FAIL: expected busy result\n");
        return false;
    }

    uint8_t status = chan_device_status(chan);

    if (!(status & CHAN_STATUS_BUSY)) {
        printf("FAIL: expected busy status\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_read_command(char *case_name, struct chan *chan, uint16_t count,
        struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count)
{
    printf("TEST: %s\n", case_name);

    udmabuf_clear(&chan->udmabuf, 0);

    mock_cu_arrange(mock_cu, false, false, mock_cu_limit);

    uint8_t cmd = 0x02; // READ

    uint8_t buf[1024];

    ssize_t result = chan_exec(chan, 0xff, cmd, buf, count);

    if (result < 0) {
        printf("FAIL: unable to start channel\n");
        return false;
    }

    if (result != expected_count) {
        printf("FAIL: expected to receive %d bytes, received %zd\n", expected_count, result);
        return false;
    }

    if (!mock_cu_assert(mock_cu, cmd, expected_count)) {
        printf("FAIL: mock CU assertions failed\n");
        return false;
    }

    if (!buf_assert(buf, result)) {
        printf("FAIL: data received did not match expected data:\n");
        dump(buf, result);
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_write_command(char *case_name, struct chan *chan, uint16_t count,
        struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count)
{
    printf("TEST: %s\n", case_name);

    udmabuf_clear(&chan->udmabuf, 0);

    mock_cu_arrange(mock_cu, false, false, mock_cu_limit);

    uint8_t cmd = 0x01; // WRITE

    uint8_t buf[1024];

    buf_arrange(buf, count);

    ssize_t result = chan_exec(chan, 0xff, cmd, buf, count);

    if (result < 0) {
        printf("FAIL: unable to start channel\n");
        return false;
    }

    if (result != expected_count) {
        printf("FAIL: expected to send %d bytes, sent %zd\n", expected_count, result);
        return false;
    }

    if (!mock_cu_assert(mock_cu, cmd, expected_count)) {
        printf("FAIL: mock CU assertions failed\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_nop_command(struct chan *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_nop_command\n");

    mock_cu_arrange(mock_cu, false, false, 0);

    uint8_t cmd = 0x03; // NOP

    ssize_t result = chan_exec(chan, 0xff, cmd, NULL, 0);

    if (result < 0) {
        printf("FAIL: unable to start channel\n");
        return false;
    }

    if (result != 0) {
        printf("FAIL: expected to receive 0 bytes, received %zd\n", result);
        return false;
    }

    if (!mock_cu_assert(mock_cu, cmd, 0)) {
        printf("FAIL: mock CU assertions failed\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

void buf_arrange(uint8_t *buf, size_t count)
{
    for (size_t index = 0; index < count; index++) {
        buf[index] = index + 1;
    }
}

bool buf_assert(uint8_t *buf, size_t count)
{
    int bad_count = 0;

    for (size_t index = 0; index < count; index++) {
        if (buf[index] != (uint8_t) (index + 1)) {
            bad_count++;
        }
    }

    if (bad_count > 0) {
        return false;
    }

    return true;
}
