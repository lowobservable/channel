#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <real.h>
#include <udmabuf.h>

#include "chan.h"

#define REGS_SIZE 1024

#define REG_CONTROL 0
#define REG_STATUS 1
#define REG_DMA_ADDR 2

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

int chan_exec(struct chan *chan, uint8_t addr, uint8_t cmd, uint8_t *buf, size_t count)
{
    if (count > chan->udmabuf.size) {
        return -1;
    }

    if (chan->regs[REG_STATUS] & 2) {
        return -1;
    }

    /*
    if (is_write_cmd(cmd)) {
        udmabuf_copy_to_dma(&chan->udmabuf, buf, count);
    }
    */

    chan->regs[REG_DMA_ADDR] = chan->udmabuf.addr;
    chan->regs[REG_CONTROL] = (addr << 24) | (cmd << 16) | (count << 8) | 0x02; // Start...

    while (chan->regs[REG_STATUS] & 2) {
        usleep(100);
    }

    /*
    if (is_read_cmd(cmd)) {
        udmabuf_copy_from_dma(&chan->udmabuf, buf, count);
    }
    */

    return 0;
}
