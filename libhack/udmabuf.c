#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/mman.h>

#include "udmabuf.h"

intptr_t udmabuf_addr(char *name);
ssize_t udmabuf_size(char *name);

int udmabuf_open(struct udmabuf *udmabuf, char *name)
{
    intptr_t addr;

    if ((addr = udmabuf_addr(name)) < 0) {
        return -1;
    }

    ssize_t size;

    if ((size = udmabuf_size(name)) < 0) {
        return -1;
    }

    udmabuf->addr = addr;
    udmabuf->size = size;

    char path[1024];

    snprintf(path, 1024, "/dev/%s", name);

    if ((udmabuf->fd = open(path, O_RDWR | O_SYNC)) < 0) {
        return -1;
    }

    if ((udmabuf->buf = mmap(NULL, udmabuf->size, PROT_READ | PROT_WRITE, MAP_SHARED, udmabuf->fd, 0)) == MAP_FAILED) {
        close(udmabuf->fd);
        return -1;
    }

    return 0;
}

int udmabuf_close(struct udmabuf *udmabuf)
{
    if (udmabuf == NULL) {
        return 0;
    }

    if (munmap(udmabuf->buf, udmabuf->size) < 0) {
        return -1;
    }

    udmabuf->buf = NULL;
    udmabuf->addr = 0;
    udmabuf->size = 0;

    if (close(udmabuf->fd) < 0) {
        return -1;
    }

    udmabuf->fd = -1;

    return 0;
}

intptr_t udmabuf_addr(char *name)
{
    char path[1024];

    snprintf(path, 1024, "/sys/class/u-dma-buf/%s/phys_addr", name);

    int fd;

    if ((fd = open(path, O_RDONLY)) < 0) {
        return -1;
    }

    char buf[1024];

    if (read(fd, buf, 1024) < 0) {
        close(fd);
        return -1;
    }

    close(fd);

    uintptr_t addr;

    if (sscanf(buf, "%" PRIxPTR, &addr) != 1) {
        return -1;
    }

    return addr;
}

ssize_t udmabuf_size(char *name)
{
    char path[1024];

    snprintf(path, 1024, "/sys/class/u-dma-buf/%s/size", name);

    int fd;

    if ((fd = open(path, O_RDONLY)) < 0) {
        return -1;
    }

    char buf[1024];

    if (read(fd, buf, 1024) < 0) {
        close(fd);
        return -1;
    }

    close(fd);

    size_t size;

    if (sscanf(buf, "%zu", &size) != 1) {
        return -1;
    }

    return size;
}

void udmabuf_clear(struct udmabuf *udmabuf, uint8_t value)
{
    memset(udmabuf->buf, value, udmabuf->size);
}

size_t udmabuf_copy_to_dma(struct udmabuf *udmabuf, void *buf, size_t count)
{
    size_t actual_count = count > udmabuf->size ? udmabuf->size : count;

    memcpy(udmabuf->buf, buf, actual_count);

    return actual_count;
}

size_t udmabuf_copy_from_dma(struct udmabuf *udmabuf, void *buf, size_t count)
{
    size_t actual_count = count > udmabuf->size ? udmabuf->size : count;

    memcpy(buf, udmabuf->buf, actual_count);

    return actual_count;
}
