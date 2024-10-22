#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <real.h>
#include <udmabuf.h>

#include "chan.h"

#define REGS_SIZE 1024

#define REG_CONTROL_1 0
#define REG_CONTROL_2 1
#define REG_STATUS_1 2
#define REG_STATUS_2 3
#define REG_CCW_1 4
#define REG_CCW_2 5

void config(struct chan *chan, bool enable, bool frontend_enable);
static inline bool is_read_cmd(uint8_t cmd);
static inline bool is_write_cmd(uint8_t cmd);

int chan_open(struct chan *chan, uintptr_t addr, int mem_fd, char *udmabuf_path, bool frontend_enable)
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

    config(chan, true, frontend_enable);

    return 0;
}

int chan_close(struct chan *chan, bool disable)
{
    if (chan == NULL) {
        return 0;
    }

    if (disable) {
        config(chan, false, false);
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

int chan_test(struct chan *chan, uint8_t addr)
{
    // Channel is active...
    if (chan->regs[REG_STATUS_1] & 0x01) {
        return -2;
    }

    chan->regs[REG_CCW_1] = 0x00 /* TEST */ << 24;
    chan->regs[REG_CCW_2] = chan->udmabuf.addr;

    chan->regs[REG_CONTROL_2] = (addr << 24) | 0x01; // Start...

    while (chan->regs[REG_STATUS_1] & 0x01) {
        usleep(100);
    }

    uint8_t condition_code = (uint8_t) ((chan->regs[REG_STATUS_1] & 0xc0) >> 6);

    if (condition_code != 0) {
        return -3;
    }

    return 0;
}

ssize_t chan_exec(struct chan *chan, uint8_t addr, uint8_t cmd, uint8_t *buf, size_t count)
{
    if (count > 0 && buf == NULL) {
        return -1;
    }

    if (count > UINT16_MAX) {
        return -1;
    }

    if (count > chan->udmabuf.size) {
        return -1;
    }

    // Channel is active...
    if (chan->regs[REG_STATUS_1] & 0x01) {
        return -2;
    }

    if (is_write_cmd(cmd) && count > 0) {
        udmabuf_copy_to_dma(&chan->udmabuf, buf, count);
    }

    chan->regs[REG_CCW_1] = (cmd << 24) | (uint16_t) count;
    chan->regs[REG_CCW_2] = chan->udmabuf.addr;

    chan->regs[REG_CONTROL_2] = (addr << 24) | 0x01; // Start...

    while (chan->regs[REG_STATUS_1] & 0x01) {
        usleep(100);
    }

    uint8_t condition_code = (uint8_t) ((chan->regs[REG_STATUS_1] & 0xc0) >> 6);

    if (condition_code != 0) {
        return -3;
    }

    uint8_t device_status = chan_device_status(chan);

    if (device_status & CHAN_STATUS_BUSY) {
        return -4;
    }

    // We expect channel end and device end...
    if (!((device_status & CHAN_STATUS_CE) && (device_status & CHAN_STATUS_DE))) {
        return -5;
    }

    // We don't expect unit check or unit exception...
    if (device_status & CHAN_STATUS_UC || device_status & CHAN_STATUS_UX) {
        return -6;
    }

    // The count in the status register is a "residual" count.
    size_t actual_count = count - (uint16_t) chan->regs[REG_STATUS_2];

    if (is_read_cmd(cmd) && actual_count > 0) {
        udmabuf_copy_from_dma(&chan->udmabuf, buf, actual_count);
    }

    return actual_count;
}

uint8_t chan_device_status(struct chan *chan)
{
    return (uint8_t) (chan->regs[REG_STATUS_2] >> 24);
}

bool chan_request_in(struct chan *chan)
{
    return chan->regs[REG_STATUS_1] & 0x02;
}

void config(struct chan *chan, bool enable, bool frontend_enable)
{
    chan->regs[REG_CONTROL_1] = (frontend_enable << 31) | (enable << 1);
}

static inline bool is_read_cmd(uint8_t cmd)
{
    return !(cmd & 1);
}

static inline bool is_write_cmd(uint8_t cmd)
{
    return (cmd & 1);
}
