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

#define CHAN_OUT_IS_SEND_CMD(C) ((C) & 0x01)
#define CHAN_OUT_IS_RECV_CMD(C) (!((C) & 0x01))

int chan_out_open(struct chan_out *out, int mem_fd, char *udmabuf_path, bool frontend_enable)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    out->base_addr = 0x40000000;

    if ((out->base = real_map(out->base_addr, REGS_SIZE, mem_fd)) == NULL) {
        return -1;
    }

    out->regs = out->base;

    if ((udmabuf_open(&out->udmabuf, udmabuf_path)) < 0) {
        real_unmap(out->base, REGS_SIZE);

        return -1;
    }

    out->regs[REG_CHANNEL_1] = false;
    out->regs[REG_CHANNEL_3] = frontend_enable;

    return 0;
}

int chan_out_close(struct chan_out *out)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    out->regs[REG_CHANNEL_1] = false;
    out->regs[REG_CHANNEL_3] = false;

    int result = 0;

    if (udmabuf_close(&out->udmabuf) < 0) {
        result = -1;
    }

    if (real_unmap(out->base, REGS_SIZE) < 0) {
        result = -1;
    }

    return result;
}

int chan_out_enable(struct chan_out *out)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    out->regs[REG_CHANNEL_1] = true;

    return 0;
}

int chan_out_disable(struct chan_out *out)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    out->regs[REG_CHANNEL_1] = false;

    return 0;
}

int chan_out_config(struct chan_out *out, uint8_t addr, bool enable)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    out->regs[REG_DEVICE_1] = (addr << 24) | enable;

    return 0;
}

int chan_out_test(struct chan_out *out, uint8_t addr, uint8_t *status)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (addr != (out->regs[REG_DEVICE_1] & 0xff000000) >> 24) {
        return -999;
    }

    uint32_t reg = out->regs[REG_DEVICE_2];

    bool pending = (reg & 0x00008000);

    if (!pending) {
        return 0;
    }

    // Clear pending status, this must only be done if the read above resulted
    // in pending status to avoid missing pending status.
    out->regs[REG_DEVICE_2] = 0x00008000;

    if (status != NULL) {
        *status = (reg & 0x00ff0000) >> 16;
    }

    return pending;
}

int chan_out_start(struct chan_out *out, uint8_t addr, uint8_t cmd, uint8_t flags, void *buf, size_t count)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    // TODO: This would not apply if a skip flag is implemented.
    if (count > 0 && buf == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (count > UINT16_MAX) {
        return CHAN_ERR_ARGS;
    }

    if (count > out->udmabuf.size) {
        return CHAN_ERR_DMA_SIZE;
    }

    if (CHAN_OUT_IS_SEND_CMD(cmd) && buf != NULL) {
        udmabuf_copy_to_dma(&out->udmabuf, buf, count);
    }

    if (addr != (out->regs[REG_DEVICE_1] & 0xff000000) >> 24) {
        return -999;
    }

    // Start pending...
    if (out->regs[REG_DEVICE_2] & 0x00000001) {
        return CHAN_ERR_START_PENDING;
    }

    out->regs[REG_DEVICE_3] = (((uint16_t) count) << 16) | cmd;
    out->regs[REG_DEVICE_4] = out->udmabuf.addr;
    out->regs[REG_DEVICE_2] = 0x00000001;

    while (out->regs[REG_DEVICE_2] & 0x00000001) {
        usleep(1000); // 1 ms
    }

    uint8_t condition_code = (out->regs[REG_DEVICE_2] & 0x000000f0) >> 4;

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

ssize_t chan_out_complete(struct chan_out *out, uint8_t cmd, void *buf, size_t count)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    // TODO: This would not apply if a skip flag is implemented.
    if (count > 0 && buf == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (count > out->udmabuf.size) {
        return CHAN_ERR_DMA_SIZE;
    }

    size_t residual_count = (out->regs[REG_DEVICE_3] & 0xffff0000) >> 16;
    size_t actual_count = count - residual_count;

    if (CHAN_OUT_IS_RECV_CMD(cmd) && buf != NULL) {
        udmabuf_copy_from_dma(&out->udmabuf, buf, actual_count);
    }

    return actual_count;
}

int chan_out_wrap_test(struct chan_out *out, uint32_t driver, uint32_t *receiver)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    // Channel must not be enabled during wrap test.
    if (out->regs[REG_CHANNEL_1] & 0x00000001) {
        return CHAN_ERR_CHANNEL_STATE;
    }

    out->regs[REG_CHANNEL_3] = ((driver & 0x000fffff) << 12) | 0x00000100 | (out->regs[REG_CHANNEL_3] & 0x000000ff);

    usleep(50000); // 50 ms

    uint32_t value = (out->regs[REG_CHANNEL_4] >> 12) & 0x000fffff;

    out->regs[REG_CHANNEL_3] &= ~0x00000100;

    if (receiver != NULL) {
        *receiver = value;
    }

    return (value ^ driver);
}

void chan_out_debug(struct chan_out *out)
{
    if (out == NULL) {
        return;
    }

    for (int index = 0; index < 8; index++) {
        uint32_t reg = out->regs[index];

        printf("R%d: %.8x", index, reg);

        if (index == 0) {
            if (reg & 0x00000001) {
                printf(" [ChEn]");
            }
        } else if (index == 2) {
            if (reg & 0x00000001) {
                printf(" [FeEn]");
            }

            if (reg & 0x00000100) {
                printf(" [WrapEn]");
            }
        } else if (index == 4) {
            if (reg & 0x00000001) {
                printf(" [DevEn]");
            }

            printf(" [Addr = %.2x]", (reg & 0xff000000) >> 24);
        } else if (index == 5) {
            if (reg & 0x00008000) {
                printf(" [StP]");

                printf(" [Stat = %.2x]", (reg & 0x00ff0000) >> 16);
            }

            if (reg & 0x00004000) {
                printf(" [StS]");
            }

            if (reg & 0x00000200) {
                printf(" [ChA]");
            }

            if (reg & 0x00000100) {
                printf(" [DevA]");
            }

            if (reg & 0x00000001) {
                printf(" [StartP]");
            } else {
                printf(" [Cond = %d]", (int) ((reg & 0x000000f0) >> 4));
            }
        } else if (index == 6) {
            printf(" [Cmd = %.2x]", reg & 0x000000ff);
            printf(" [Count = %d]", (int) ((reg & 0xffff0000) >> 16));
        }

        printf("\n");
    }
}
