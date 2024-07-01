// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <real.h>
#include <util.h>

#include "chan.h"
#include "mock_cu.h"

int test_no_cu(struct chan *chan);
int test_busy(struct chan *chan, struct mock_cu *mock_cu);
int test_read_command(char *case_name, struct chan *chan, uint16_t count,
        struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count);
int test_write_command(char *case_name, struct chan *chan, uint16_t count,
        struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count);
int test_nop_command(struct chan *chan, struct mock_cu *mock_cu);

void buf_arrange(uint8_t *buf, size_t count);
int buf_assert(uint8_t *buf, size_t count);

int main(void)
{
    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("e1");
        return -1;
    }

    struct chan chan;

    if (chan_open(&chan, 0x40000000, mem_fd, "udmabuf0", false) < 0) {
        perror("e2");
        return -1;
    }

    struct mock_cu mock_cu;

    if (mock_cu_open(&mock_cu, 0x40001000, mem_fd) < 0) {
        perror("e3");
        return -1;
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
}

int test_no_cu(struct chan *chan)
{
    printf("TEST: test_no_cu\n");

    int result = chan_exec(chan, 0x10, 0x03 /* NOP */, NULL, 0);

    if (result != -3) {
        printf("FAIL: expected not operational condition code\n");
        return -1;
    }

    printf("PASS\n");

    return 0;
}

int test_busy(struct chan *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_busy\n");

    mock_cu_arrange(mock_cu, true, false, 0);

    int result = chan_exec(chan, 0xff, 0x03 /* NOP */, NULL, 0);

    if (result != -4) {
        printf("FAIL: expected busy result\n");
        return -1;
    }

    uint8_t status = chan_device_status(chan);

    if (!(status & CHAN_STATUS_BUSY)) {
        printf("FAIL: expected busy status\n");
        return -1;
    }

    printf("PASS\n");

    return 0;
}

int test_read_command(char *case_name, struct chan *chan, uint16_t count,
        struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count)
{
    printf("TEST: %s\n", case_name);

    udmabuf_clear(&chan->udmabuf, 0);

    mock_cu_arrange(mock_cu, false, false, mock_cu_limit);

    uint8_t cmd = 0x02; // READ

    uint8_t buf[1024];

    int result = chan_exec(chan, 0xff, cmd, buf, count);

    if (result < 0) {
        printf("FAIL: unable to start channel\n");
        return -1;
    }

    if (result != expected_count) {
        printf("FAIL: expected to receive %d bytes, received %d\n", expected_count, result);
        return -1;
    }

    if (mock_cu_assert(mock_cu, cmd, expected_count) != 0) {
        printf("FAIL: mock CU assertions failed\n");
        return -1;
    }

    if (buf_assert(buf, result) != 0) {
        printf("FAIL: data received did not match expected data:\n");
        dump(buf, result);
        return -1;
    }

    printf("PASS\n");

    return 0;
}

int test_write_command(char *case_name, struct chan *chan, uint16_t count,
        struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count)
{
    printf("TEST: %s\n", case_name);

    udmabuf_clear(&chan->udmabuf, 0);

    mock_cu_arrange(mock_cu, false, false, mock_cu_limit);

    uint8_t cmd = 0x01; // WRITE

    uint8_t buf[1024];

    buf_arrange(buf, count);

    int result = chan_exec(chan, 0xff, cmd, buf, count);

    if (result < 0) {
        printf("FAIL: unable to start channel\n");
        return -1;
    }

    if (result != expected_count) {
        printf("FAIL: expected to send %d bytes, sent %d\n", expected_count, result);
        return -1;
    }

    if (mock_cu_assert(mock_cu, cmd, expected_count) != 0) {
        printf("FAIL: mock CU assertions failed\n");
        return -1;
    }

    printf("PASS\n");

    return 0;
}

int test_nop_command(struct chan *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_nop_command\n");

    mock_cu_arrange(mock_cu, false, false, 0);

    uint8_t cmd = 0x03; // NOP

    int result = chan_exec(chan, 0xff, cmd, NULL, 0);

    if (result < 0) {
        printf("FAIL: unable to start channel\n");
        return -1;
    }

    if (result != 0) {
        printf("FAIL: expected to receive 0 bytes, received %d\n", result);
        return -1;
    }

    if (mock_cu_assert(mock_cu, cmd, 0) != 0) {
        printf("FAIL: mock CU assertions failed\n");
        return -1;
    }

    printf("PASS\n");

    return 0;
}

void buf_arrange(uint8_t *buf, size_t count)
{
    for (size_t index = 0; index < count; index++) {
        buf[index] = index + 1;
    }
}

int buf_assert(uint8_t *buf, size_t count)
{
    int bad_count = 0;

    for (size_t index = 0; index < count; index++) {
        if (buf[index] != (uint8_t) (index + 1)) {
            bad_count++;
        }
    }

    if (bad_count > 0) {
        return -1;
    }

    return 0;
}
