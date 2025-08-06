// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <iconv.h>

#include <real.h>
#include <util.h>

#include "chan.h"

iconv_t ebcdic_conv;

static bool test(struct chan_out *out, uint8_t addr);
static bool test_device(struct chan_out *out, uint8_t addr);
static bool test_nop(struct chan_out *out, uint8_t addr);
static bool test_sense_id(struct chan_out *out, uint8_t addr);
static bool test_basic_sense(struct chan_out *out, uint8_t addr);
static bool test_erase_write(struct chan_out *out, uint8_t addr, bool first, uint8_t aid);
static bool test_read_modified(struct chan_out *out, uint8_t addr, uint8_t *aid);
static size_t format_screen(uint8_t *buf, size_t buf_size, bool first, uint8_t aid);
static ssize_t ebcdic_write(uint8_t *buf, size_t buf_size, char *ascii);

int main(void)
{
    if ((ebcdic_conv = iconv_open("IBM037", "ASCII")) < 0) {
        perror("iconv_open");
        return EXIT_FAILURE;
    }

    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("mem_open");
        return EXIT_FAILURE;
    }

    struct chan_out out;

    if (chan_out_open(&out, mem_fd, "udmabuf0", true) < 0) {
        perror("chan_open");
        return EXIT_FAILURE;
    }

    chan_out_enable(&out);

    printf("READY\n");

    test(&out, 0x60);

    chan_out_close(&out);

    close(mem_fd);

    iconv_close(ebcdic_conv);

    return EXIT_SUCCESS;
}

volatile bool stop = false;

static void signal_handler(int signum)
{
    if (signum == SIGINT) {
        stop = true;
    }
}

bool test(struct chan_out *out, uint8_t addr)
{
    chan_out_config(out, addr, false);

    printf("Device %.2x disabled, press ENTER to enable...\n", addr);

    char *line = NULL;
    size_t len = 0;

    getline(&line, &len, stdin);

    chan_out_debug(out);

    chan_out_config(out, addr, true);

    printf("Device %.2x enabled...\n", addr);

    bool device_online = false;

    uint8_t status;

    int result = chan_exec_nop(out, addr, &status);

    if (result == 0) {
        if (!test_device(out, addr)) {
            return false;
        }

        device_online = true;
    } else if (result == CHAN_ERR_STATUS_PENDING || result == CHAN_ERR_DEVICE_BUSY) {
        // Wait for status to be handled below.
    } else if (result == CHAN_ERR_DEVICE_NOTOP) { // Not Operational
        printf("Device appears not operational, turn it on...\n");
    } else if (result < 0) {
        printf("chan_exec NOP error: %d\n", result);
        return false;
    }

    signal(SIGINT, signal_handler);

    uint8_t aid = 0;

    while (!stop) {
        result = chan_out_test(out, addr, &status);

        if (result < 0) {
            printf("chan_out_test error: %d\n", result);
            break;
        }

        if (result == 0) {
            usleep(250000); // 250 ms
            continue;
        }

        // NOTE: There doesn't appear to be a unsolicitated status when the
        // device goes offline...

        if (status == CHAN_STATUS_DE) {
            if (!test_device(out, addr)) {
                return false;
            }

            device_online = true;
        } else if (device_online && status == CHAN_STATUS_ATTN) {
            printf("Device %.2x attention\n", addr);

            if (!test_read_modified(out, addr, &aid)) {
                return false;
            }

            if (!test_erase_write(out, addr, false, aid)) {
                return false;
            }

            // Don't check for exit until after sending the screen...
            if (aid == 0xf3) { // PF3
                break;
            }
        } else {
            printf("Unsolicited status: 0x%.2x\n", status);
        }
    }

    signal(SIGINT, SIG_DFL);

    printf("\n");

    if (stop) {
        printf("Stopped\n");
    }

    chan_out_debug(out);

    return true;
}

bool test_device(struct chan_out *out, uint8_t addr)
{
    printf("Device %.2x is online!\n", addr);

    if (!test_nop(out, addr)) {
        return false;
    }

    if (!test_sense_id(out, addr)) {
        return false;
    }

    if (!test_basic_sense(out, addr)) {
        return false;
    }

    if (!test_erase_write(out, addr, true, 0)) {
        return false;
    }

    return true;
}

bool test_nop(struct chan_out *out, uint8_t addr)
{
    printf("NOP...");

    uint8_t status;

    int result = chan_exec_nop(out, addr, &status);

    if (result != 0) {
        printf(" FAIL: result = %d\n", result);
        return false;
    }

    if (status != 0x0c) {
        printf(" FAIL: expected 0x0c status: 0x%.2x\n", status);
        return false;
    }

    printf(" PASS\n");

    return true;
}

bool test_sense_id(struct chan_out *out, uint8_t addr)
{
    printf("SENSE ID...");

    uint8_t status;
    uint8_t sense_id[7];

    ssize_t result = chan_exec_sense_id(out, addr, &sense_id, 7, &status);

    if (result < 0) {
        printf(" FAIL: result = %zd\n", result);
        return false;
    }

    if (status != 0x0c) {
        printf(" FAIL: expected 0x0c status: 0x%.2x\n", status);
        return false;
    }

    if (result != 4) {
        printf(" FAIL: expected 4 byte SENSE ID response from 3174-1L: %zd\n", result);
        return false;
    }

    char type_model[8];

    snprintf(type_model, 8, "%.2X%.2X-%.2X", sense_id[1], sense_id[2], sense_id[3]);

    if (strncmp(type_model, "3174-1D", 7) != 0) {
        printf(" FAIL: expected '3174-1D' SENSE ID response from 3174-1L: '%s'\n", type_model);
        return false;
    }

    printf(" PASS: '%s'\n", type_model);

    return true;
}

bool test_basic_sense(struct chan_out *out, uint8_t addr)
{
    printf("BASIC SENSE...");

    uint8_t status;
    uint8_t sense;

    ssize_t result = chan_exec_basic_sense(out, addr, &sense, 32, &status);

    if (result < 0) {
        printf(" FAIL: result = %zd\n", result);
        return false;
    }

    if (result != 1) {
        printf(" FAIL: expected 1 byte BASIC SENSE response from 3174-1L: %zd\n", result);
        return false;
    }

    printf(" PASS: sense = 0x%.2x\n", sense);

    return true;
}

bool test_erase_write(struct chan_out *out, uint8_t addr, bool first, uint8_t aid)
{
    printf("ERASE/WRITE...");

    uint8_t buf[256];

    size_t buf_len = format_screen(buf, sizeof(buf), first, aid);

    uint8_t status;

    ssize_t result = chan_exec(out, addr, 0x05 /* ERASE/WRITE */, 0, buf, buf_len, &status);

    if (result < 0) {
        printf(" FAIL: result = %zd\n", result);
        return false;
    }

    if (status != 0x0c) {
        printf(" FAIL: status = %.2x\n", status);
        return false;
    }

    if (result != buf_len) {
        printf(" FAIL: expected to write %zu bytes: %zd\n", buf_len, result);
        return false;
    }

    printf(" PASS\n");

    return true;
}

bool test_read_modified(struct chan_out *out, uint8_t addr, uint8_t *aid)
{
    printf("READ MODIFIED...");

    uint8_t buf[64];
    uint8_t status;

    ssize_t result = chan_exec(out, addr, 0x06 /* READ MODIFIED */, 0, buf, 64, &status);

    if (result < 0) {
        printf(" FAIL: result = %zd\n", result);
        return false;
    }

    if (status != 0x0c) {
        printf(" FAIL: status = %.2x\n", status);
        return false;
    }

    if (result < 1) {
        printf(" FAIL: expected to read at least 1 byte: %zd\n", result);
        return false;
    }

    printf(" PASS: AID = 0x%.2x\n", buf[0]);

    if (aid != NULL) {
        *aid = buf[0];
    }

    return true;
}

size_t format_screen(uint8_t *buf, size_t buf_size, bool first, uint8_t aid)
{
    uint8_t *buf_p = buf;

    *buf_p++ = 0x43; // WCC

    *buf_p++ = 0x11; // SBA
    *buf_p++ = 0x40;
    *buf_p++ = 0x40;

    *buf_p++ = 0x1d; // SF
    *buf_p++ = 0xf8;

    buf_p += ebcdic_write(buf_p, 80, "3174-1L LIBCHAN TEST PROGRAM");

    *buf_p++ = 0x11; // SBA
    *buf_p++ = 0xc2;
    *buf_p++ = 0x60;

    *buf_p++ = 0x1d; // SF
    *buf_p++ = 0xf4;

    buf_p += ebcdic_write(buf_p, 80, "Press AID key, or PF3 to exit test");

    if (aid > 0) {
        *buf_p++ = 0x11; // SBA
        *buf_p++ = 0xc5;
        *buf_p++ = 0x40;

        *buf_p++ = 0x1d; // SF
        *buf_p++ = 0xf4;

        char msg[81];

        snprintf(msg, 81, "Last AID = %.2x (HEX)", aid);

        buf_p += ebcdic_write(buf_p, 80, msg);
    }

    size_t len = buf_p - buf;

    if (len > buf_size) {
        // Whoops, it's a little late!
    }

    return len;
}

ssize_t ebcdic_write(uint8_t *buf, size_t buf_size, char *ascii)
{
    size_t ascii_remaining = strlen(ascii);

    char *ebcdic = (char *) buf;
    size_t ebcdic_remaining = buf_size;

    if (iconv(ebcdic_conv, &ascii, &ascii_remaining, &ebcdic, &ebcdic_remaining) < 0) {
        return -1;
    }

    if (ascii_remaining != 0) {
        return -2;
    }

    return buf_size - ebcdic_remaining;
}
