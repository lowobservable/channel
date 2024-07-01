// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <unistd.h>

#include <real.h>
#include <util.h>

#include "chan.h"

void test(struct chan *chan, uint8_t addr);
int exec_nop(struct chan *chan, uint8_t addr);
int exec_basic_sense(struct chan *chan, uint8_t addr);
int exec_sense_id(struct chan *chan, uint8_t addr);
int exec_erase_write(struct chan *chan, uint8_t addr);

int main(void)
{
    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("e1");
        return -1;
    }

    struct chan chan;

    if (chan_open(&chan, 0x40000000, mem_fd, "udmabuf0", true) < 0) {
        perror("e2");
        return -1;
    }

    printf("READY\n");

    test(&chan, 0x60);

    chan_close(&chan, false);

    close(mem_fd);
}

void test(struct chan *chan, uint8_t addr)
{
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

    if (exec_sense_id(chan, addr) < 0) {
        return;
    }

    if (exec_erase_write(chan, addr) < 0) {
        return;
    }
}

int exec_nop(struct chan *chan, uint8_t addr)
{
    printf("NOP...\n");

    ssize_t result = chan_exec(chan, addr, 0x03 /* NOP */, NULL, 0);

    if (result < 0) {
        printf("\tresult = %d\n", result);
        return -1;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    return 0;
}

int exec_basic_sense(struct chan *chan, uint8_t addr)
{
    printf("BASIC SENSE...\n");

    uint8_t buf[32];

    ssize_t result = chan_exec(chan, 0x60, 0x04 /* BASIC SENSE */, buf, 32);

    if (result < 0) {
        printf("\tresult = %d\n", result);
        return -1;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    size_t count = result;

    if (count < 1) {
        printf("\texpected at least 1 byte, got %d\n", count);
        return -1;
    }

    printf("\tcount = %d\n", count);

    dump(buf, count);

    return 0;
}

int exec_sense_id(struct chan *chan, uint8_t addr)
{
    printf("SENSE ID...\n");

    uint8_t buf[7];

    ssize_t result = chan_exec(chan, 0x60, 0xe4 /* SENSE ID */, buf, 7);

    if (result < 0) {
        printf("\tresult = %d\n", result);
        return -1;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    size_t count = result;

    if (count < 4) {
        printf("\texpected at least 4 bytes, got %d\n", count);
        return -1;
    }

    if (buf[0] != 0xff) {
        printf("\texpected first byte to be 0xff, got 0x%.2x\n", buf[0]);
        return -1;
    }

    printf("\tcount = %d\n", count);
    printf("\tCU = %.2x%.2x-%.2x\n", buf[1], buf[2], buf[3]);

    return 0;
}

int exec_erase_write(struct chan *chan, uint8_t addr)
{
    printf("ERASE/WRITE...\n");

    uint8_t buf[19] = {
        0x43, /* WCC */
        0x11, 0x40, 0x40, /* SBA */
        0x1d, 0xf8, /* SF */
        0xc8, 0x85, 0x93, 0x93, 0x96, 0x6b, 0x40, 0xa6, 0x96, 0x99, 0x93, 0x84, 0x5a
    };

    ssize_t result = chan_exec(chan, addr, 0x05 /* ERASE/WRITE */, buf, 19);

    if (result < 0) {
        printf("\tresult = %d\n", result);
        return -1;
    }

    uint8_t status = chan_device_status(chan);

    printf("\tstatus = 0x%.2x\n", status);

    size_t count = result;

    printf("\tcount = %d\n", count);

    return 0;
}
