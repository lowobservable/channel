#include <stdio.h>
#include <stdint.h>
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

    printf("ready\n");

    chan_close(&chan);

    close(mem_fd);
}
