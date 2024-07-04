#ifndef __REAL_H
#define __REAL_H

#include <stdint.h>
#include <stddef.h>

void *real_map(uintptr_t addr, size_t size, int mem_fd);

int real_unmap(void *virt, size_t size);

int mem_open();

#endif
