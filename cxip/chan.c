#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <real.h>
#include <udmabuf.h>
#include <util.h>

#include "chan.h"

#define REGS_SIZE 1024

#define REG_CONTROL 0
#define REG_STATUS 1
#define REG_ADDR 2
#define REG_COUNT 3
#define REG_DATA 4

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

int chan_test(struct chan *chan, uint8_t *buf, size_t count)
{
    if (count > chan->udmabuf.size) {
        return -1;
    }

    if (chan->regs[REG_STATUS] & 2) {
        return -1;
    }

    chan->regs[REG_ADDR] = chan->udmabuf.addr;
    chan->regs[REG_COUNT] = count;
    chan->regs[REG_DATA] = (uint8_t) count;

    chan->regs[REG_CONTROL] = 6; // Start write...

    while (chan->regs[REG_STATUS] & 2) {
        usleep(100);
    }

    dump(chan->udmabuf.buf, count);

    memcpy(buf, chan->udmabuf.buf, count);

    return 0;
}
