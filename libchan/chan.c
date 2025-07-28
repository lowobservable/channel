#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>
#include <unistd.h>

#include "chan.h"

ssize_t chan_exec(struct chan_out *chan, uint8_t addr, uint8_t cmd, uint8_t flags, void *buf, size_t count, uint8_t *status)
{
    int start_result = chan_out_start(chan, addr, cmd, flags, count);

    if (start_result < 0) {
        return start_result;
    }

    uint8_t cumulative_status = 0;

    do {
        uint8_t pending_status;

        int test_result = chan_out_test(chan, addr, &pending_status);

        if (test_result < 0) {
            return test_result;
        }

        if (test_result == 0) {
            usleep(50000); // 50ms
            continue;
        }

        cumulative_status |= pending_status;
    } while ((cumulative_status & 0x0c) != 0x0c);

    if (status != NULL) {
        *status = cumulative_status;
    }

    return 0;
}
