// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <real.h>
#include <util.h>

#include "chan.h"
#include "mock_cu.h"

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
        if (buf[index] != index + 1) {
            bad_count++;
        }
    }

    if (bad_count > 0) {
        return -1;
    }

    return 0;
}

int test_read_command_cu_more(struct chan *chan, struct mock_cu *mock_cu)
{
    printf("TEST: read_command_cu_more\n");

    udmabuf_clear(&chan->udmabuf, 0);

    mock_cu_arrange(mock_cu, 0, 16);

    uint8_t buf[6];

    int result = chan_exec(chan, 0xff, 0x02 /* READ */, buf, 6);

    if (result < 0) {
        printf("FAIL: unable to start test\n");
        return -1;
    }

    if (mock_cu_assert(mock_cu, 0x02, 6) != 0) {
        printf("FAIL: mock CU assertions failed\n");
        return -1;
    }

    if (result != 6) {
        printf("FAIL: expected to receive 6 bytes, received %d\n", result);
        return -1;
    }

    if (buf_assert(buf, 6) != 0) {
        printf("FAIL: data received did not match expected data:\n");
        dump(buf, 6);
        return -1;
    }

    printf("PASS\n");

    return 0;
}

int test_read_command_cu_less(struct chan *chan, struct mock_cu *mock_cu)
{
    printf("TEST: read_command_cu_less\n");

    udmabuf_clear(&chan->udmabuf, 0);

    mock_cu_arrange(mock_cu, 0, 6);

    uint8_t buf[16];

    int result = chan_exec(chan, 0xff, 0x02 /* READ */, buf, 16);

    if (result < 0) {
        printf("FAIL: unable to start test\n");
        return -1;
    }

    if (mock_cu_assert(mock_cu, 0x02, 6) != 0) {
        printf("FAIL: mock CU assertions failed\n");
        return -1;
    }

    if (result != 6) {
        printf("FAIL: expected to receive 6 bytes, received %d\n", result);
        return -1;
    }

    if (buf_assert(buf, 6) != 0) {
        printf("FAIL: data received did not match expected data:\n");
        dump(buf, 6);
        return -1;
    }

    printf("PASS\n");

    return 0;
}

int test_write_command_cu_more(struct chan *chan, struct mock_cu *mock_cu)
{
    printf("TEST: write_command_cu_more\n");

    udmabuf_clear(&chan->udmabuf, 0);

    mock_cu_arrange(mock_cu, 0, 16);

    uint8_t buf[6];

    int result = chan_exec(chan, 0xff, 0x01 /* WRITE */, buf, 6);

    if (result < 0) {
        printf("FAIL: unable to start test\n");
        return -1;
    }

    if (mock_cu_assert(mock_cu, 0x01, 6) != 0) {
        printf("FAIL: mock CU assertions failed\n");
        return -1;
    }

    if (result != 6) {
        printf("FAIL: expected to transmit 6 bytes, sent %d\n", result);
        return -1;
    }

    printf("PASS\n");

    return 0;
}

int test_write_command_cu_less(struct chan *chan, struct mock_cu *mock_cu)
{
    printf("TEST: write_command_cu_less\n");

    udmabuf_clear(&chan->udmabuf, 0);

    mock_cu_arrange(mock_cu, 0, 6);

    uint8_t buf[16];

    buf_arrange(buf, 16);

    int result = chan_exec(chan, 0xff, 0x01 /* WRITE */, buf, 16);

    if (result < 0) {
        printf("FAIL: unable to start test\n");
        return -1;
    }

    if (mock_cu_assert(mock_cu, 0x01, 6) != 0) {
        printf("FAIL: mock CU assertions failed\n");
        return -1;
    }

    if (result != 6) {
        printf("FAIL: expected to transmit 6 bytes, sent %d\n", result);
        return -1;
    }

    printf("PASS\n");

    return 0;
}

int main(void)
{
    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("e1");
        return -1;
    }

    struct chan chan;

    if (chan_open(&chan, 0x40000000, mem_fd, "udmabuf0") < 0) {
        perror("e2");
        return -1;
    }

    struct mock_cu mock_cu;

    if (mock_cu_open(&mock_cu, 0x40001000, mem_fd) < 0) {
        perror("e3");
        return -1;
    }

    printf("READY\n");

    test_read_command_cu_more(&chan, &mock_cu);
    test_read_command_cu_less(&chan, &mock_cu);
    test_write_command_cu_more(&chan, &mock_cu);
    test_write_command_cu_less(&chan, &mock_cu);

    mock_cu_close(&mock_cu);

    chan_close(&chan);

    close(mem_fd);
}
