#ifndef __CHAN_H
#define __CHAN_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include <udmabuf.h>

struct chan {
    uintptr_t addr;
    void *base;
    volatile uint32_t *regs;
    struct udmabuf udmabuf;
};

int chan_open(struct chan *chan, uintptr_t addr, int mem_fd, char *udmabuf_path, bool frontend_enable);

int chan_close(struct chan *chan);

ssize_t chan_exec(struct chan *chan, uint8_t addr, uint8_t cmd, uint8_t *buf, size_t count);

#endif
