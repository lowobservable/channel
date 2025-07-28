// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>

#include <real.h>
#include <util.h>

#include "chan.h"
#include "mock_cu.h"

bool test_unsolicited_status_device_enabled(struct chan_out *chan, struct mock_cu *mock_cu);
bool test_exec_device_disabled(struct chan_out *chan, struct mock_cu *mock_cu);
bool test_exec_device_not_operational(struct chan_out *chan, struct mock_cu *mock_cu);
bool test_exec_status_pending(struct chan_out *chan, struct mock_cu *mock_cu);
bool test_exec_device_busy(struct chan_out *chan, struct mock_cu *mock_cu);
bool test_exec_immediate_command(struct chan_out *chan, struct mock_cu *mock_cu);

void buf_arrange(uint8_t *buf, size_t count);
bool buf_assert(uint8_t *buf, size_t count);

int main(void)
{
    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("mem_open");
        return EXIT_FAILURE;
    }

    struct chan_out chan;

    if (chan_out_open(&chan, 0x40000000, mem_fd, "udmabuf0", false) < 0) {
        perror("chan_open");
        return EXIT_FAILURE;
    }

    struct mock_cu mock_cu;

    if (mock_cu_open(&mock_cu, 0x40001000, mem_fd) < 0) {
        perror("mock_cu_open");
        return EXIT_FAILURE;
    }

    printf("READY\n");

    test_unsolicited_status_device_enabled(&chan, &mock_cu);
    test_exec_device_disabled(&chan, &mock_cu);
    test_exec_device_not_operational(&chan, &mock_cu);
    test_exec_status_pending(&chan, &mock_cu);
    test_exec_device_busy(&chan, &mock_cu);
    test_exec_immediate_command(&chan, &mock_cu);

    mock_cu_close(&mock_cu);

    chan_out_close(&chan);

    close(mem_fd);

    return EXIT_SUCCESS;
}

bool test_unsolicited_status_device_enabled(struct chan_out *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_unsolicited_status_device_enabled\n");

    // Ensure that one-shot request mock is reset.
    mock_cu_arrange(mock_cu, false, false, false, 0);
    mock_cu_arrange(mock_cu, false, false, true, 0);

    chan_out_config(chan, 0xff, true);
    chan_out_enable(chan);

    int attempt;
    bool status_pending = false;
    uint8_t status;

    for (attempt = 1; attempt <= 5; attempt++) {
        int result = chan_out_test(chan, 0xff, &status);

        if (result == 1) {
            status_pending = true;
            break;
        }

        if (result < 0) {
            printf("FAIL: test result error: %d\n", result);
            return false;
        }

        usleep(1000); // 1ms
    }

    if (!status_pending) {
        printf("FAIL: expected status pending after %d tests\n", attempt);
        return false;
    }

    if (status != 0x85) {
        printf("FAIL: expected 0x85 status: 0x%.2x\n", status);
        return false;
    }

    if (chan_out_test(chan, 0xff, NULL) != 0) {
        printf("FAIL: expected no status pending\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_device_disabled(struct chan_out *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_device_disabled\n");

    mock_cu_arrange(mock_cu, false, false, false, 0);

    chan_out_enable(chan);
    chan_out_config(chan, 0xff, false);

    ssize_t result = chan_exec(chan, 0xff, CHAN_CMD_NOP, 0, NULL, 0, NULL);

    if (result != -3) {
        printf("FAIL: expected device disabled: %zd\n", result);
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_device_not_operational(struct chan_out *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_device_not_operational\n");

    mock_cu_arrange(mock_cu, false, false, false, 0);

    chan_out_enable(chan);
    chan_out_config(chan, 0x1b, true);

    ssize_t result = chan_exec(chan, 0x1b, CHAN_CMD_NOP, 0, NULL, 0, NULL);

    if (result != -4) {
        printf("FAIL: expected device not operational: %zd\n", result);
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_status_pending(struct chan_out *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_status_pending\n");

    // Ensure that one-shot request mock is reset.
    mock_cu_arrange(mock_cu, false, false, false, 0);
    mock_cu_arrange(mock_cu, false, false, true, 0);

    chan_out_config(chan, 0xff, true);
    chan_out_enable(chan);

    int attempt;
    bool status_pending = false;

    for (attempt = 1; attempt <= 5; attempt++) {
        if (chan->regs[5] & 0x00002000) {
            status_pending = true;
            break;
        }

        usleep(1000); // 1ms
    }

    if (!status_pending) {
        printf("FAIL: expected status pending after %d tests\n", attempt);
        return false;
    }

    ssize_t result = chan_exec(chan, 0xff, CHAN_CMD_NOP, 0, NULL, 0, NULL);

    if (result != -6) {
        printf("FAIL: expected status pending: %zd\n", result);
        return false;
    }

    chan_out_test(chan, 0xff, NULL);

    printf("PASS\n");

    return true;
}

bool test_exec_device_busy(struct chan_out *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_device_busy\n");

    mock_cu_arrange(mock_cu, true, false, false, 0);

    chan_out_enable(chan);
    chan_out_config(chan, 0xff, true);

    ssize_t result = chan_exec(chan, 0xff, CHAN_CMD_NOP, 0, NULL, 0, NULL);

    if (result != -7) {
        printf("FAIL: expected device busy: %zd\n", result);
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_immediate_command(struct chan_out *chan, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_immediate_command\n");

    mock_cu_arrange(mock_cu, false, false, false, 0);

    chan_out_enable(chan);
    chan_out_config(chan, 0xff, true);

    uint8_t status;

    ssize_t result = chan_exec(chan, 0xff, CHAN_CMD_NOP, 0, NULL, 0, &status);

    if (result != 0) {
        printf("FAIL: expected successful count 0 bytes: %zd\n", result);
        return false;
    }

    if (status != 0x0c) {
        printf("FAIL: expected 0x0c status: 0x%.2x\n", status);
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
