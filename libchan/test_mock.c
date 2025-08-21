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

static bool test_unsolicited_status_device_disabled(struct chan_out *out, struct mock_cu *mock_cu);
static bool test_unsolicited_status_device_enabled(struct chan_out *out, struct mock_cu *mock_cu);
static bool test_exec_device_disabled(struct chan_out *out, struct mock_cu *mock_cu);
static bool test_exec_device_not_operational(struct chan_out *out, struct mock_cu *mock_cu);
static bool test_exec_status_pending(struct chan_out *out, struct mock_cu *mock_cu);
static bool test_exec_device_busy(struct chan_out *out, struct mock_cu *mock_cu);
static bool test_exec_reserved_command(struct chan_out *out, struct mock_cu *mock_cu);
static bool test_exec_immediate_command(struct chan_out *out, struct mock_cu *mock_cu);
static bool test_exec_read_command(char *case_name, struct chan_out *out, uint16_t count, struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count);
static bool test_exec_write_command(char *case_name, struct chan_out *out, uint16_t count, struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count);
static bool test_command_chaining(struct chan_out *out, struct mock_cu *mock_cu);

static void buf_arrange(uint8_t *buf, size_t count);
static bool buf_assert(uint8_t *buf, size_t count);

int main(void)
{
    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("mem_open");
        return EXIT_FAILURE;
    }

    struct chan_out out;

    if (chan_out_open(&out, mem_fd, "udmabuf0", false) < 0) {
        perror("chan_open");
        return EXIT_FAILURE;
    }

    struct mock_cu mock_cu;

    if (mock_cu_open(&mock_cu, mem_fd) < 0) {
        perror("mock_cu_open");
        return EXIT_FAILURE;
    }

    printf("READY\n");

    test_unsolicited_status_device_disabled(&out, &mock_cu);
    test_unsolicited_status_device_enabled(&out, &mock_cu);
    test_exec_device_disabled(&out, &mock_cu);
    test_exec_device_not_operational(&out, &mock_cu);
    test_exec_status_pending(&out, &mock_cu);
    test_exec_device_busy(&out, &mock_cu);
    test_exec_reserved_command(&out, &mock_cu);
    test_exec_immediate_command(&out, &mock_cu);
    test_exec_read_command("channel_stop", &out, 6, &mock_cu, 16, 6);
    test_exec_read_command("cu_stop", &out, 16, &mock_cu, 6, 6);
    test_exec_write_command("channel_stop", &out, 6, &mock_cu, 16, 6);
    test_exec_write_command("cu_stop", &out, 16, &mock_cu, 6, 6);
    test_exec_read_command("big", &out, 512, &mock_cu, 512, 512);
    test_command_chaining(&out, &mock_cu);

    mock_cu_close(&mock_cu);

    chan_out_close(&out);

    close(mem_fd);

    return EXIT_SUCCESS;
}

bool test_unsolicited_status_device_disabled(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_unsolicited_status_device_disabled\n");

    // Ensure that one-shot request mock is reset.
    mock_cu_arrange(mock_cu, false, false, false, 0);
    mock_cu_arrange(mock_cu, false, false, true, 0);

    chan_out_config(out, 0xff, false);
    chan_out_enable(out);

    int attempt;
    bool status_stacked = false;

    for (attempt = 1; attempt <= 5; attempt++) {
        if (out->regs[5] & 0x00004000) {
            status_stacked = true;
            break;
        }

        usleep(1000); // 1ms
    }

    if (!status_stacked) {
        printf("FAIL: expected status stacked after %d tests\n", attempt);
        return false;
    }

    // Enable the device.
    chan_out_config(out, 0xff, true);

    bool status_pending = false;
    uint8_t status;

    for (attempt = 1; attempt <= 5; attempt++) {
        int result = chan_out_test(out, 0xff, &status);

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

    if (chan_out_test(out, 0xff, NULL) != 0) {
        printf("FAIL: expected no status pending\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_unsolicited_status_device_enabled(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_unsolicited_status_device_enabled\n");

    // Ensure that one-shot request mock is reset.
    mock_cu_arrange(mock_cu, false, false, false, 0);
    mock_cu_arrange(mock_cu, false, false, true, 0);

    chan_out_config(out, 0xff, true);
    chan_out_enable(out);

    int attempt;
    bool status_pending = false;
    uint8_t status;

    for (attempt = 1; attempt <= 5; attempt++) {
        int result = chan_out_test(out, 0xff, &status);

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

    if (chan_out_test(out, 0xff, NULL) != 0) {
        printf("FAIL: expected no status pending\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_device_disabled(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_device_disabled\n");

    mock_cu_arrange(mock_cu, false, false, false, 0);

    chan_out_enable(out);
    chan_out_config(out, 0xff, false);

    ssize_t result = chan_exec(out, 0xff, CHAN_CMD_NOP, 0, NULL, 0, NULL);

    if (result != CHAN_ERR_DEVICE_STATE) {
        printf("FAIL: expected device state error: %zd\n", result);
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_device_not_operational(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_device_not_operational\n");

    mock_cu_arrange(mock_cu, false, false, false, 0);

    chan_out_enable(out);
    chan_out_config(out, 0x1b, true);

    ssize_t result = chan_exec(out, 0x1b, CHAN_CMD_NOP, 0, NULL, 0, NULL);

    if (result != CHAN_ERR_DEVICE_NOTOP) {
        printf("FAIL: expected device not operational error: %zd\n", result);
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_status_pending(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_status_pending\n");

    // Ensure that one-shot request mock is reset.
    mock_cu_arrange(mock_cu, false, false, false, 0);
    mock_cu_arrange(mock_cu, false, false, true, 0);

    chan_out_config(out, 0xff, true);
    chan_out_enable(out);

    int attempt;
    bool status_pending = false;

    for (attempt = 1; attempt <= 5; attempt++) {
        if (out->regs[5] & 0x00008000) {
            status_pending = true;
            break;
        }

        usleep(1000); // 1ms
    }

    if (!status_pending) {
        printf("FAIL: expected status pending after %d tests\n", attempt);
        return false;
    }

    ssize_t result = chan_exec(out, 0xff, CHAN_CMD_NOP, 0, NULL, 0, NULL);

    if (result != CHAN_ERR_STATUS_PENDING) {
        printf("FAIL: expected status pending error: %zd\n", result);
        return false;
    }

    chan_out_test(out, 0xff, NULL);

    printf("PASS\n");

    return true;
}

bool test_exec_device_busy(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_device_busy\n");

    mock_cu_arrange(mock_cu, true, false, false, 0);

    chan_out_enable(out);
    chan_out_config(out, 0xff, true);

    ssize_t result = chan_exec(out, 0xff, CHAN_CMD_NOP, 0, NULL, 0, NULL);

    if (result != CHAN_ERR_DEVICE_BUSY) {
        printf("FAIL: expected device busy error: %zd\n", result);
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_reserved_command(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_reserved_command\n");

    mock_cu_arrange(mock_cu, false, false, false, 0);

    chan_out_enable(out);
    chan_out_config(out, 0xff, true);

    ssize_t result = chan_exec(out, 0xff, 0x00, 0, NULL, 0, NULL);

    if (result != CHAN_ERR_CMD_RESERVED) {
        printf("FAIL: expected reserved command error: %zd\n", result);
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_immediate_command(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_exec_immediate_command\n");

    mock_cu_arrange(mock_cu, false, false, false, 0);

    chan_out_enable(out);
    chan_out_config(out, 0xff, true);

    uint8_t status;

    ssize_t result = chan_exec(out, 0xff, CHAN_CMD_NOP, 0, NULL, 0, &status);

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

bool test_exec_read_command(char *case_name, struct chan_out *out, uint16_t count, struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count)
{
    printf("TEST: test_exec_read_command_%s\n", case_name);

    udmabuf_clear(&out->udmabuf, 0);

    mock_cu_arrange(mock_cu, false, false, false, mock_cu_limit);

    chan_out_enable(out);
    chan_out_config(out, 0xff, true);

    uint8_t cmd = 0x02; // READ

    uint8_t buf[1024];
    uint8_t status;

    ssize_t result = chan_exec(out, 0xff, cmd, 0, buf, count, &status);

    if (result != expected_count) {
        printf("FAIL: expected successful count %d bytes: %zd\n", expected_count, result);
        return false;
    }

    if (status != 0x0c) {
        printf("FAIL: expected 0x0c status: 0x%.2x\n", status);
        return false;
    }

    if (!buf_assert(buf, result)) {
        printf("FAIL: data received did not match expected data:\n");
        dump(buf, result);
        return false;
    }

    if (!mock_cu_assert(mock_cu, cmd, expected_count, false, false)) {
        printf("FAIL: mock CU assertions failed\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_exec_write_command(char *case_name, struct chan_out *out, uint16_t count, struct mock_cu *mock_cu, uint16_t mock_cu_limit, uint16_t expected_count)
{
    printf("TEST: test_exec_write_command_%s\n", case_name);

    udmabuf_clear(&out->udmabuf, 0);

    mock_cu_arrange(mock_cu, false, false, false, mock_cu_limit);

    chan_out_enable(out);
    chan_out_config(out, 0xff, true);

    uint8_t cmd = 0x01; // WRITE

    uint8_t buf[1024];
    uint8_t status;

    buf_arrange(buf, count);

    ssize_t result = chan_exec(out, 0xff, cmd, 0, buf, count, &status);

    if (result != expected_count) {
        printf("FAIL: expected successful count %d bytes: %zd\n", expected_count, result);
        return false;
    }

    if (status != 0x0c) {
        printf("FAIL: expected 0x0c status: 0x%.2x\n", status);
        return false;
    }

    if (!mock_cu_assert(mock_cu, cmd, expected_count, false, false)) {
        printf("FAIL: mock CU assertions failed\n");
        return false;
    }

    printf("PASS\n");

    return true;
}

bool test_command_chaining(struct chan_out *out, struct mock_cu *mock_cu)
{
    printf("TEST: test_command_chaining\n");

    udmabuf_clear(&out->udmabuf, 0);

    mock_cu_arrange(mock_cu, false, false, false, 6);

    chan_out_enable(out);
    chan_out_config(out, 0xff, true);

    uint8_t buf[1024];
    uint8_t status;

    // Start READ with count 16 and command chaining.
    ssize_t result = chan_exec(out, 0xff, 0x02, CHAN_START_CHAINING, buf, 16, &status);

    if (result != 6) {
        printf("FAIL: expected successful count 6 bytes: %zd\n", result);
        return false;
    }

    if (status != 0x0c) {
        printf("FAIL: expected 0x0c status: 0x%.2x\n", status);
        return false;
    }

    if (!mock_cu_assert(mock_cu, 0x02, 6, false, true)) {
        printf("FAIL: mock CU assertions failed\n");
        return false;
    }

    // Start chained NOP.
    result = chan_exec(out, 0xff, CHAN_CMD_NOP, CHAN_START_CHAINED, NULL, 0, &status);

    if (result != 0) {
        printf("FAIL: expected successful count 0 bytes: %zd\n", result);
        return false;
    }

    if (status != 0x0c) {
        printf("FAIL: expected 0x0c status: 0x%.2x\n", status);
        return false;
    }

    if (!mock_cu_assert(mock_cu, CHAN_CMD_NOP, 0, true, false)) {
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
