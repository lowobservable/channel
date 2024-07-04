#include <stdio.h>
#include <stdint.h>

#include "util.h"

void dump(uint8_t *buf, size_t count)
{
    int i;

    for (i = 0; i < count; i++) {
        if (i % 16 == 0) {
            printf("%.4x: ", i);
        }

        printf("%.2x ", buf[i]);

        if ((i + 1) % 16 == 0) {
            printf("\n");
        }
    }

    if (i % 16 != 0) {
        printf("\n");
    }
}
