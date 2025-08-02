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

#define REG_CHANNEL_1 0
#define REG_CHANNEL_3 2
#define REG_CHANNEL_4 3
#define REG_DEVICE_1 4
#define REG_DEVICE_2 5
#define REG_DEVICE_3 6
#define REG_DEVICE_4 7

int chan_out_open(struct chan_out *chan, uintptr_t base_addr, int mem_fd, char *udmabuf_path, bool frontend_enable)
{
    if (chan == NULL) {
        return CHAN_ERR_ARGS;
    }

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
        return CHAN_ERR_ARGS;
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
    if (chan == NULL) {
        return CHAN_ERR_ARGS;
    }

    chan->regs[REG_CHANNEL_1] = true;

    return 0;
}

int chan_out_disable(struct chan_out *chan)
{
    if (chan == NULL) {
        return CHAN_ERR_ARGS;
    }

    chan->regs[REG_CHANNEL_1] = false;

    return 0;
}

int chan_out_config(struct chan_out *chan, uint8_t addr, bool enable)
{
    if (chan == NULL) {
        return CHAN_ERR_ARGS;
    }

    chan->regs[REG_DEVICE_1] = (addr << 24) | enable;

    return 0;
}

int chan_out_test(struct chan_out *chan, uint8_t addr, uint8_t *status)
{
    if (chan == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (addr != (chan->regs[REG_DEVICE_1] & 0xff000000) >> 24) {
        return -999;
    }

    uint32_t reg = chan->regs[REG_DEVICE_2];

    bool pending = (reg & 0x00008000);

    if (!pending) {
        return 0;
    }

    // Clear pending status, this must only be done if the read above resulted
    // in pending status to avoid missing pending status.
    chan->regs[REG_DEVICE_2] = 0x00008000;

    if (status != NULL) {
        *status = (reg & 0x00ff0000) >> 16;
    }

    return pending;
}

int chan_out_start(struct chan_out *chan, uint8_t addr, uint8_t cmd, uint8_t flags, size_t count)
{
    if (chan == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (count > UINT16_MAX) {
        return CHAN_ERR_ARGS;
    }

    if (count > chan->udmabuf.size) {
        return CHAN_ERR_ARGS;
    }

    if (addr != (chan->regs[REG_DEVICE_1] & 0xff000000) >> 24) {
        return -999;
    }

    // Start pending...
    if (chan->regs[REG_DEVICE_2] & 0x00000001) {
        return CHAN_ERR_START_PENDING;
    }

    chan->regs[REG_DEVICE_3] = chan->udmabuf.addr;
    chan->regs[REG_DEVICE_4] = (((uint16_t) count) << 16) | cmd;
    chan->regs[REG_DEVICE_2] = 0x00000001;

    while (chan->regs[REG_DEVICE_2] & 0x00000001) {
        usleep(1000); // 1 ms
    }

    uint8_t condition_code = (chan->regs[REG_DEVICE_2] & 0x000000f0) >> 4;

    if (condition_code != 0) {
        switch (condition_code) {
            case 0x01: // XXX - Device Disabled
                return CHAN_ERR_DEVICE_STATE;

            case 0x02: // XXX - Device Not Operational
                return CHAN_ERR_DEVICE_NOTOP;

            case 0x03: // XXX - Status Pending
                return CHAN_ERR_STATUS_PENDING;

            case 0x04: // XXX - Device Busy
                return CHAN_ERR_DEVICE_BUSY;

            case 0x05: // XXX - Reserved Command
                return CHAN_ERR_CMD_RESERVED;

            default:
                return -1;
        }
    }

    return 0;
}

int chan_out_wrap_test(struct chan_out *chan, uint32_t driver, uint32_t *receiver)
{
    if (chan == NULL) {
        return CHAN_ERR_ARGS;
    }

    // Channel must not be enabled during wrap test.
    if (chan->regs[REG_CHANNEL_1] & 0x00000001) {
        return CHAN_ERR_CHANNEL_STATE;
    }

    chan->regs[REG_CHANNEL_3] = ((driver & 0x000fffff) << 12) | 0x00000100 | (chan->regs[REG_CHANNEL_3] & 0x000000ff);

    usleep(50000); // 50 ms

    uint32_t value = (chan->regs[REG_CHANNEL_4] >> 12) & 0x000fffff;

    chan->regs[REG_CHANNEL_3] &= ~0x00000100;

    if (receiver != NULL) {
        *receiver = value;
    }

    return (value ^ driver);
}

void chan_out_debug(struct chan_out *chan)
{
    if (chan == NULL) {
        return;
    }

    for (int index = 0; index < 8; index++) {
        printf("%d: %.8x\n", index, chan->regs[index]);
    }
}
