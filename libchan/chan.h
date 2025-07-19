#ifndef __CHAN_H
#define __CHAN_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include <udmabuf.h>

#define CHAN_STATUS_ATTN    0x80    // Attention
#define CHAN_STATUS_SM      0x40    // Status Modifier
#define CHAN_STATUS_CUE     0x20    // Control Unit End
#define CHAN_STATUS_BUSY    0x10    // Busy
#define CHAN_STATUS_CE      0x08    // Channel End
#define CHAN_STATUS_DE      0x04    // Device End
#define CHAN_STATUS_UC      0x02    // Unit Check
#define CHAN_STATUS_UX      0x01    // Unit Exception

struct chan_out {
    uintptr_t addr;
    void *base;
    volatile uint32_t *regs;
    struct udmabuf udmabuf;
};

int chan_out_open(struct chan_out *chan, uintptr_t addr, int mem_fd, char *udmabuf_path, bool frontend_enable);

int chan_out_close(struct chan_out *chan, bool disable);

int chan_out_test(struct chan_out *chan, uint8_t addr);

ssize_t chan_out_exec(struct chan_out *chan, uint8_t addr, uint8_t cmd, uint8_t *buf, size_t count);

uint8_t chan_out_device_status(struct chan_out *chan);

bool chan_out_request_in(struct chan_out *chan);

int chan_out_wrap_test(struct chan_out *chan, uint32_t driver, uint32_t *receiver);

#endif
