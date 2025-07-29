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

bool test(struct chan_out *chan, uint8_t addr);
bool test_device(struct chan_out *chan, uint8_t addr);
bool test_attn(struct chan_out *chan, uint8_t addr, uint8_t status);
//bool exec_nop(struct chan_out *chan, uint8_t addr);
//bool exec_basic_sense(struct chan_out *chan, uint8_t addr);
//bool exec_sense_id(struct chan_out *chan, uint8_t addr);
//bool exec_erase_write(struct chan_out *chan, uint8_t addr, uint8_t *buf, size_t buf_len);
//bool exec_read_modified(struct chan_out *chan, uint8_t addr, uint8_t *aid);
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

    struct chan_out chan;

    if (chan_out_open(&chan, 0x40000000, mem_fd, "udmabuf0", true) < 0) {
        perror("chan_open");
        return EXIT_FAILURE;
    }

    chan_out_enable(&chan);

    printf("READY\n");

    test(&chan, 0x60);

    chan_out_close(&chan);

    close(mem_fd);

    iconv_close(ebcdic_conv);

    return EXIT_SUCCESS;
}

volatile bool stop = false;

void signal_handler(int signum)
{
    if (signum == SIGINT) {
        stop = true;
    }
}

bool test(struct chan_out *chan, uint8_t addr)
{
    chan_out_config(chan, addr, true);

    bool device_online = false;

    uint8_t status;

    int result = (int) chan_exec(chan, addr, CHAN_CMD_NOP, 0, NULL, 0, &status);

    if (result == 0) {
        if (!test_device(chan, addr)) {
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

    while (!stop) {
        result = chan_out_test(chan, addr, &status);

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
            if (!test_device(chan, addr)) {
                return false;
            }

            device_online = true;
        } else if (device_online && status == CHAN_STATUS_ATTN) {
            if (!test_attn(chan, addr, status)) {
                return false;
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

    return true;
}

bool test_device(struct chan_out *chan, uint8_t addr)
{
    printf("Device %.2x is online!\n", addr);

    printf("NOP...\n");

    uint8_t status;

    ssize_t result = chan_exec(chan, addr, CHAN_CMD_NOP, 0, NULL, 0, &status);

    if (result != 0) {
        printf("\tresult = %zd\n", result);
        return false;
    }

    // Expect 0x0c (CE + DE)
    printf("\tstatus = 0x%.2x\n", status);

    return true;
}

bool test_attn(struct chan_out *chan, uint8_t addr, uint8_t status)
{
    printf("Device %.2x attention\n", addr);

    return true;
}

//bool exec_nop(struct chan_out *chan, uint8_t addr)
//{
//    printf("NOP...\n");
//
//    ssize_t result = chan_out_exec(chan, addr, 0x03 /* NOP */, NULL, 0);
//
//    if (result < 0) {
//        printf("\tresult = %zd\n", result);
//        return false;
//    }
//
//    uint8_t status = chan_out_device_status(chan);
//
//    printf("\tstatus = 0x%.2x\n", status);
//
//    return true;
//}
//
//bool exec_basic_sense(struct chan_out *chan, uint8_t addr)
//{
//    printf("BASIC SENSE...\n");
//
//    uint8_t buf[32];
//
//    ssize_t result = chan_out_exec(chan, 0x60, 0x04 /* BASIC SENSE */, buf, 32);
//
//    if (result < 0) {
//        printf("\tresult = %zd\n", result);
//        return false;
//    }
//
//    uint8_t status = chan_out_device_status(chan);
//
//    printf("\tstatus = 0x%.2x\n", status);
//
//    size_t count = result;
//
//    printf("\tcount = %zu\n", count);
//
//    if (count < 1) {
//        printf("\texpected at least 1 byte, got %zu\n", count);
//        return false;
//    }
//
//    dump(buf, count);
//
//    return true;
//}
//
//bool exec_sense_id(struct chan_out *chan, uint8_t addr)
//{
//    printf("SENSE ID...\n");
//
//    uint8_t buf[7];
//
//    ssize_t result = chan_out_exec(chan, 0x60, 0xe4 /* SENSE ID */, buf, 7);
//
//    if (result < 0) {
//        printf("\tresult = %zd\n", result);
//        return false;
//    }
//
//    uint8_t status = chan_out_device_status(chan);
//
//    printf("\tstatus = 0x%.2x\n", status);
//
//    size_t count = result;
//
//    printf("\tcount = %zu\n", count);
//
//    if (count < 4) {
//        printf("\texpected at least 4 bytes, got %zu\n", count);
//        return false;
//    }
//
//    if (buf[0] != 0xff) {
//        printf("\texpected first byte to be 0xff, got 0x%.2x\n", buf[0]);
//        return false;
//    }
//
//    printf("\tCU = %.2x%.2x-%.2x\n", buf[1], buf[2], buf[3]);
//
//    return true;
//}
//
//bool exec_erase_write(struct chan_out *chan, uint8_t addr, uint8_t *buf, size_t buf_len)
//{
//    printf("ERASE/WRITE...\n");
//
//    ssize_t result = chan_out_exec(chan, addr, 0x05 /* ERASE/WRITE */, buf, buf_len);
//
//    if (result < 0) {
//        printf("\tresult = %zd\n", result);
//        return false;
//    }
//
//    uint8_t status = chan_out_device_status(chan);
//
//    printf("\tstatus = 0x%.2x\n", status);
//
//    size_t count = result;
//
//    printf("\tcount = %zu\n", count);
//
//    if (count != buf_len) {
//        printf("\texpected to write %zu bytes, wrote %zu\n", buf_len, count);
//        return false;
//    }
//
//    return true;
//}
//
//bool exec_read_modified(struct chan_out *chan, uint8_t addr, uint8_t *aid)
//{
//    printf("READ MODIFIED...\n");
//
//    uint8_t buf[64];
//
//    ssize_t result = chan_out_exec(chan, addr, 0x06 /* READ MODIFIED */, buf, 64);
//
//    if (result < 0) {
//        printf("\tresult = %zd\n", result);
//        return false;
//    }
//
//    uint8_t status = chan_out_device_status(chan);
//
//    printf("\tstatus = 0x%.2x\n", status);
//
//    size_t count = result;
//
//    printf("\tcount = %zu\n", count);
//
//    if (count < 1) {
//        printf("\texpected at least 1 byte, got %zu\n", count);
//        return false;
//    }
//
//    printf("\tAID = 0x%.2x\n", buf[0]);
//
//    if (aid != NULL) {
//        *aid = buf[0];
//    }
//
//    return true;
//}

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
