#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <unistd.h>

#include <real.h>
#include <util.h>

#include "chan.h"

int main(void)
{
    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("e1");
        return -1;
    }

    struct chan chan;

    if (chan_open(&chan, 0x40000000, mem_fd, "udmabuf0") < 0) {
        perror("e2");
        return -1;
    }

    printf("ready\n");

    uint8_t buf[64];

    size_t count = 64;

    int result = chan_test(&chan, &buf, count);

    printf("result = %d\n", result);

    dump(buf, count);

    int bad_count = 0;

    for (int i = 0; i < count; i++) {
        uint8_t expected = count ^ (count - i);

        if (buf[i] != expected) {
            bad_count++;
        }
    }

    if (bad_count == 0) {
        printf("PASS\n");
    } else {
        printf("FAIL\n");
    }

    chan_close(&chan);

    close(mem_fd);
}
