// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <unistd.h>

#include <real.h>

#include "chan.h"

void test(struct chan *chan);

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

    test(&chan);

    chan_close(&chan);

    close(mem_fd);
}

void test(struct chan *chan)
{
    int result = chan_test(chan, 0x60);

    if (result < 0) {
        printf("result = %d\n", result);
    }

    uint8_t status = chan_device_status(chan);

    printf("status = 0x%.2x\n", status);
}
