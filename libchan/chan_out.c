#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

#include <real.h>
#include <udmabuf.h>

#include "chan.h"

#define REGS_SIZE 1024

#define REG_CHANNEL_1 0
#define REG_CHANNEL_3 2
#define REG_CHANNEL_4 3
#define REG_DEVICE_1 4
#define REG_DEVICE_2 5
#define REG_DEVICE_3 6
#define REG_DEVICE_4 7

static inline bool is_read_cmd(uint8_t cmd);
static inline bool is_write_cmd(uint8_t cmd);

int chan_out_open(struct chan_out *chan, uintptr_t base_addr, int mem_fd, char *udmabuf_path, bool frontend_enable)
{
    chan->base_addr = base_addr;

    if ((chan->base = real_map(chan->base_addr, REGS_SIZE, mem_fd)) == NULL) {
        return -1;
    }

    chan->regs = chan->base;

    if ((udmabuf_open(&chan->udmabuf, udmabuf_path)) < 0) {
        real_unmap(chan->base, REGS_SIZE);

        return -1;
    }

    chan->regs[REG_CHANNEL_1] = false;
    chan->regs[REG_CHANNEL_3] = frontend_enable;

    return 0;
}

int chan_out_close(struct chan_out *chan)
{
    if (chan == NULL) {
        return 0;
    }

    chan->regs[REG_CHANNEL_1] = false;
    chan->regs[REG_CHANNEL_3] = false;

    int result = 0;

    if (udmabuf_close(&chan->udmabuf) < 0) {
        result = -1;
    }

    if (real_unmap(chan->base, REGS_SIZE) < 0) {
        result = -1;
    }

    return result;
}

int chan_out_enable(struct chan_out *chan)
{
    chan->regs[REG_CHANNEL_1] = true;

    return 0;
}

int chan_out_disable(struct chan_out *chan)
{
    chan->regs[REG_CHANNEL_1] = false;

    return 0;
}

int chan_out_config(struct chan_out *chan, uint8_t addr, bool enable)
{
    chan->regs[REG_DEVICE_1] = (addr << 24) | enable;

    return 0;
}

int chan_out_test(struct chan_out *chan, uint8_t addr, uint8_t *status)
{
    uint32_t reg = chan->regs[REG_DEVICE_2];

    bool pending = (reg & 0x00002000);

    if (!pending) {
        return 0;
    }

    // Clear pending status, this must only be done if the read above resulted
    // in pending status to avoid missing pending status.
    chan->regs[REG_DEVICE_2] = 0x00002000;

    if (status != NULL) {
        *status = (reg >> 16) & 0x000000ff;
    }

    return pending;
}

ssize_t chan_out_exec(struct chan_out *chan, uint8_t addr, uint8_t cmd, uint8_t *buf, size_t count)
{
    return -1;
    //if (count > 0 && buf == NULL) {
    //    return -1;
    //}

    //if (count > UINT16_MAX) {
    //    return -1;
    //}

    //if (count > chan->udmabuf.size) {
    //    return -1;
    //}

    //// Channel is active...
    //if (chan->regs[REG_STATUS_1] & 0x01) {
    //    return -2;
    //}

    //if (is_write_cmd(cmd) && count > 0) {
    //    udmabuf_copy_to_dma(&chan->udmabuf, buf, count);
    //}

    //chan->regs[REG_CCW_1] = (cmd << 24) | (uint16_t) count;
    //chan->regs[REG_CCW_2] = chan->udmabuf.addr;

    //chan->regs[REG_CONTROL_2] = (addr << 24) | 0x01; // Start...

    //while (chan->regs[REG_STATUS_1] & 0x01) {
    //    usleep(100);
    //}

    //uint8_t condition_code = (uint8_t) ((chan->regs[REG_STATUS_1] & 0xc0) >> 6);

    //if (condition_code != 0) {
    //    return -3;
    //}

    //uint8_t device_status = chan_out_device_status(chan);

    //if (device_status & CHAN_STATUS_BUSY) {
    //    return -4;
    //}

    //// We expect channel end and device end...
    //if (!((device_status & CHAN_STATUS_CE) && (device_status & CHAN_STATUS_DE))) {
    //    return -5;
    //}

    //// We don't expect unit check or unit exception...
    //if (device_status & CHAN_STATUS_UC || device_status & CHAN_STATUS_UX) {
    //    return -6;
    //}

    //// The count in the status register is a "residual" count.
    //size_t actual_count = count - (uint16_t) chan->regs[REG_STATUS_2];

    //if (is_read_cmd(cmd) && actual_count > 0) {
    //    udmabuf_copy_from_dma(&chan->udmabuf, buf, actual_count);
    //}

    //return actual_count;
}

int chan_out_wrap_test(struct chan_out *chan, uint32_t driver, uint32_t *receiver)
{
    // Channel must not be enabled during wrap test.
    if (chan->regs[REG_CHANNEL_1] & 0x00000001) {
        return -1;
    }

    chan->regs[REG_CHANNEL_3] = ((driver & 0x000fffff) << 12) | 0x00000100 | (chan->regs[REG_CHANNEL_3] & 0x000000ff);

    usleep(50000); // 50ms

    uint32_t value = (chan->regs[REG_CHANNEL_4] >> 12) & 0x000fffff;

    chan->regs[REG_CHANNEL_3] &= ~0x00000100;

    if (receiver != NULL) {
        *receiver = value;
    }

    return (value ^ driver);
}

static inline bool is_read_cmd(uint8_t cmd)
{
    return !(cmd & 1);
}

static inline bool is_write_cmd(uint8_t cmd)
{
    return (cmd & 1);
}
