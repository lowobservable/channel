// insmod u-dma-buf.ko udmabuf0=1024

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <unistd.h>

#include <real.h>

#include "chan.h"

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

    // Enable channel and frontend.
    chan_config(&chan, true, true);

    printf("READY\n");

    printf("Press ENTER...");

    getchar();

    // Disable frontend.
    chan_config(&chan, true, false);

    chan_close(&chan);

    close(mem_fd);
}
