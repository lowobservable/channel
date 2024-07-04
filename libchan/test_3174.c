// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <iconv.h>

#include <real.h>
#include <util.h>

#include "chan.h"

iconv_t ebcdic_conv;

bool test(struct chan *chan, uint8_t addr);
bool exec_nop(struct chan *chan, uint8_t addr);
bool exec_basic_sense(struct chan *chan, uint8_t addr);
bool exec_sense_id(struct chan *chan, uint8_t addr);
bool exec_erase_write(struct chan *chan, uint8_t addr, uint8_t *buf, size_t buf_len);
bool exec_read_modified(struct chan *chan, uint8_t addr, uint8_t *aid);
void wait_for_request_in(struct chan *chan);
size_t format_screen(uint8_t *buf, size_t buf_size, uint8_t aid);
ssize_t ebcdic_write(uint8_t *buf, size_t buf_size, char *ascii);

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

    struct chan chan;

    if (chan_open(&chan, 0x40000000, mem_fd, "udmabuf0", true) < 0) {
        perror("chan_open");
        return EXIT_FAILURE;
    }

    printf("READY\n");

    test(&chan, 0x60);

    chan_close(&chan, true);

    close(mem_fd);

    iconv_close(ebcdic_conv);

    return EXIT_SUCCESS;
}

bool test(struct chan *chan, uint8_t addr)
{
    while (true) {
        printf("TEST...\n");

        int result = chan_test(chan, addr);

        if (result < 0) {
            printf("\tresult = %d\n", result);
            return false;
        }

        uint8_t status = chan_device_status(chan);

        printf("\tstatus = 0x%.2x\n", status);

        if (status == 0x00) {
            break;
        }

        sleep(1);
    }

    if (!exec_nop(chan, addr)) {
        return false;
    }

    if (!exec_sense_id(chan, addr)) {
        return false;
    }

    uint8_t aid = 0;

    while (true) {
        uint8_t buf[256];

        size_t buf_len = format_screen(buf, sizeof(buf), aid);

        if (!exec_erase_write(chan, addr, buf, buf_len)) {
            return false;
        }

        // Don't check for exit until after sending the screen...
        if (aid == 0xf3 /* PF3 */) {
            break;
        }

        wait_for_request_in(chan);

        printf("REQUEST IN...\n");

        int result = chan_test(chan, addr);

        if (result < 0) {
            printf("result = %d\n", result);
            return false;
        }

        uint8_t status = chan_device_status(chan);

        if (status == 0x00) {
            continue;
        }

        printf("status = 0x%.2x\n", status);

        if (status & CHAN_STATUS_ATTN) {
            printf("ATTN...\n");

            if (!exec_read_modified(chan, addr, &aid)) {
                return false;
            }
        }
    }

    return true;
}

bool exec_nop(struct chan *chan, uint8_t addr)
{
    printf("NOP...\n");

    ssize_t result = chan_exec(chan, addr, 0x03 /* NOP */, NULL, 0);

    if (result < 0) {
        printf("\tresult = %zd\n", result);
        return false;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    return true;
}

bool exec_basic_sense(struct chan *chan, uint8_t addr)
{
    printf("BASIC SENSE...\n");

    uint8_t buf[32];

    ssize_t result = chan_exec(chan, 0x60, 0x04 /* BASIC SENSE */, buf, 32);

    if (result < 0) {
        printf("\tresult = %zd\n", result);
        return false;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    size_t count = result;

    printf("\tcount = %zu\n", count);

    if (count < 1) {
        printf("\texpected at least 1 byte, got %zu\n", count);
        return false;
    }

    dump(buf, count);

    return true;
}

bool exec_sense_id(struct chan *chan, uint8_t addr)
{
    printf("SENSE ID...\n");

    uint8_t buf[7];

    ssize_t result = chan_exec(chan, 0x60, 0xe4 /* SENSE ID */, buf, 7);

    if (result < 0) {
        printf("\tresult = %zd\n", result);
        return false;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    size_t count = result;

    printf("\tcount = %zu\n", count);

    if (count < 4) {
        printf("\texpected at least 4 bytes, got %zu\n", count);
        return false;
    }

    if (buf[0] != 0xff) {
        printf("\texpected first byte to be 0xff, got 0x%.2x\n", buf[0]);
        return false;
    }

    printf("\tCU = %.2x%.2x-%.2x\n", buf[1], buf[2], buf[3]);

    return true;
}

bool exec_erase_write(struct chan *chan, uint8_t addr, uint8_t *buf, size_t buf_len)
{
    printf("ERASE/WRITE...\n");

    ssize_t result = chan_exec(chan, addr, 0x05 /* ERASE/WRITE */, buf, buf_len);

    if (result < 0) {
        printf("\tresult = %zd\n", result);
        return false;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    size_t count = result;

    printf("\tcount = %zu\n", count);

    if (count != buf_len) {
        printf("\texpected to write %zu bytes, wrote %zu\n", buf_len, count);
        return false;
    }

    return true;
}

bool exec_read_modified(struct chan *chan, uint8_t addr, uint8_t *aid)
{
    printf("READ MODIFIED...\n");

    uint8_t buf[64];

    ssize_t result = chan_exec(chan, addr, 0x06 /* READ MODIFIED */, buf, 64);

    if (result < 0) {
        printf("\tresult = %zd\n", result);
        return false;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    size_t count = result;

    printf("\tcount = %zu\n", count);

    if (count < 1) {
        printf("\texpected at least 1 byte, got %zu\n", count);
        return false;
    }

    printf("\tAID = 0x%.2x\n", buf[0]);

    if (aid != NULL) {
        *aid = buf[0];
    }

    return true;
}

void wait_for_request_in(struct chan *chan)
{
    while (!chan_request_in(chan)) {
        usleep(250000); // 250ms
    }
}

size_t format_screen(uint8_t *buf, size_t buf_size, uint8_t aid)
{
    uint8_t *buf_p = buf;

    *buf_p++ = 0x43; // WCC

    *buf_p++ = 0x11; // SBA
    *buf_p++ = 0x40;
    *buf_p++ = 0x40;

    *buf_p++ = 0x1d; // SF
    *buf_p++ = 0xf8;

    buf_p += ebcdic_write(buf_p, 80, "3174-1L TEST PROGRAM");

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
