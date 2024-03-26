#include <stdint.h>
#include <stddef.h>

#include <real.h>
#include <udmabuf.h>

#include "chan.h"

#define REGS_SIZE 1024

int chan_open(struct chan *chan, uintptr_t addr, int mem_fd, char *udmabuf_path)
{
    chan->addr = addr;

    if ((chan->base = real_map(chan->addr, REGS_SIZE, mem_fd)) == NULL) {
        return -1;
    }

    chan->regs = chan->base;

    if ((udmabuf_open(&chan->udmabuf, udmabuf_path)) < 0) {
        real_unmap(chan->base, REGS_SIZE);

        return -1;
    }

    return 0;
}

int chan_close(struct chan *chan)
{
    if (chan == NULL) {
        return 0;
    }

    int result = 0;

    if (udmabuf_close(&chan->udmabuf) < 0) {
        result = -1;
    }

    if (real_unmap(chan->base, REGS_SIZE) < 0) {
        result = -1;
    }

    return result;
}
