#ifndef __UDMABUF_H
#define __UDMABUF_H

#include <stdint.h>
#include <stddef.h>

struct udmabuf {
    int fd;
    void *buf;
    uintptr_t addr;
    size_t size;
};

int udmabuf_open(struct udmabuf *udmabuf, char *path);

int udmabuf_close(struct udmabuf *udmabuf);

void udmabuf_clear(struct udmabuf *udmabuf, uint8_t value);

size_t udmabuf_copy_to_dma(struct udmabuf *udmabuf, void *buf, size_t count);

size_t udmabuf_copy_from_dma(struct udmabuf *udmabuf, void *buf, size_t count);

#endif
