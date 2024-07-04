#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>

#include <real.h>

int main(int argc, char **argv)
{
    int mem_fd;
    void *base;
    volatile uint32_t *regs;

    if ((mem_fd = mem_open()) < 0) {
        perror("mem_open");
        return EXIT_FAILURE;
    }

    if ((base = real_map(0x41200000, 1024, mem_fd)) == NULL) {
        perror("real_map");
        return EXIT_FAILURE;
    }

    regs = base;

    if (argc < 2) {
        regs[0] = 0; // Turn everything off...
    } else if (strcmp(argv[1], "a") == 0) {
        uint32_t drivers = strtoul(argv[2], NULL, 0);

        printf("d = 0x%08" PRIx32 "\n", drivers);

        regs[0] = drivers;

        usleep(50000); // 50ms

        uint32_t receivers = regs[2];

        printf("r = 0x%08" PRIx32 "\n", receivers);
    } else if (strcmp(argv[1], "b") == 0) {
        for (int i = 19; i > 0; i--) {
            uint32_t drivers = ((uint32_t) 1 << 31) | ((uint32_t) 1 << i);

            regs[0] = drivers;

            usleep(50000); // 50ms

            uint32_t receivers = regs[2];

            regs[0] = 0;

            // There is one missing tag wrap pair...
            if ((receivers & 0xffffe) == (drivers & 0xffffe)) {
                printf("%d OK\n", i);
            } else {
                printf("%d FAIL - d = %08" PRIx32 ", r = %08" PRIx32 "\n", i, drivers, receivers);
            }
        }
    }

    close(mem_fd);

    return EXIT_SUCCESS;
}
