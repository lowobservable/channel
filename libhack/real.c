#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stddef.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

#include "real.h"

//#define REAL_DEBUG

void *real_map(uintptr_t addr, size_t size, int mem_fd)
{
    size_t page_size = sysconf(_SC_PAGE_SIZE);

    uintptr_t page_offset = addr % page_size;
    uintptr_t page_base = addr - page_offset;

#ifdef REAL_DEBUG
    printf("real_map(addr = %" PRIxPTR ", size = %zu)\n", addr, size);
    printf("    page_size     = %zu\n", page_size);
    printf("    page_base     = %" PRIxPTR "\n", page_base);
    printf("    page_offset   = %" PRIxPTR "\n", page_offset);
#endif

    void *virt_base;

    if ((virt_base = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, mem_fd, page_base)) == MAP_FAILED) {
#ifdef REAL_DEBUG
        perror("mmap failed");
#endif

        return NULL;
    }

    void *virt = ((uint8_t *) virt_base) + page_offset;

#ifdef REAL_DEBUG
    printf("    virt_base     = %p\n", virt_base);
    printf("    virt          = %p\n", virt);
#endif

    return virt;
}

int real_unmap(void *virt, size_t size)
{
    return munmap(virt, size);
}

int mem_open()
{
    return open("/dev/mem", O_RDWR | O_SYNC);
}
