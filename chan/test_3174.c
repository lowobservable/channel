// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <unistd.h>

#include <real.h>

#include "chan.h"

int test_no_cu(struct chan *chan);

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

    test_no_cu(&chan);

    chan_close(&chan);

    close(mem_fd);
}

int test_no_cu(struct chan *chan)
{
    printf("TEST: test_no_cu\n");

    int result = chan_exec(chan, 0x10, 0x03 /* NOP */, NULL, 0);

    if (result != -3) {
        printf("FAIL: Expected not operational condition code\n");
        return -1;
    }

    printf("PASS\n");

    return 0;
}
