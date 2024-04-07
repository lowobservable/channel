#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <real.h>
#include <udmabuf.h>

#include "chan.h"

#define REGS_SIZE 1024

#define REG_CONTROL 0
#define REG_STATUS_1 1
#define REG_STATUS_2 2
#define REG_CCW_1 3
#define REG_CCW_2 4

static inline bool is_read_cmd(uint8_t cmd);
static inline bool is_write_cmd(uint8_t cmd);

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

ssize_t chan_exec(struct chan *chan, uint8_t addr, uint8_t cmd, uint8_t *buf, size_t count)
{
    if (count > UINT16_MAX) {
        return -1;
    }

    if (count > chan->udmabuf.size) {
        return -1;
    }

    if (chan->regs[REG_STATUS_1] & 2) {
        return -1;
    }

    if (is_write_cmd(cmd)) {
        udmabuf_copy_to_dma(&chan->udmabuf, buf, count);
    }

    chan->regs[REG_CCW_1] = (cmd << 24) | (uint16_t) count;
    chan->regs[REG_CCW_2] = chan->udmabuf.addr;

    chan->regs[REG_CONTROL] = (addr << 24) | 0x02; // Start...

    while (chan->regs[REG_STATUS_1] & 2) {
        usleep(100);
    }

    uint32_t status_2 = chan->regs[REG_STATUS_2];

    uint8_t device_status = (uint8_t) (status_2 >> 24);

    if (device_status != 0x30) {
        printf("device_status = 0x%.2x\n", device_status);
        return -1;
    }

    // The count in the status register is a "residual" count.
    size_t actual_count = count - (uint16_t) status_2;

    if (is_read_cmd(cmd)) {
        udmabuf_copy_from_dma(&chan->udmabuf, buf, actual_count);
    }

    return actual_count;
}

static inline bool is_read_cmd(uint8_t cmd)
{
    return !(cmd & 1);
}

static inline bool is_write_cmd(uint8_t cmd)
{
    return (cmd & 1);
}
