#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>
#include <unistd.h>

#include "chan.h"

ssize_t chan_exec(struct chan_out *chan, uint8_t addr, uint8_t cmd, uint8_t flags, void *buf, size_t count, uint8_t *status)
{
    if (chan == NULL) {
        return CHAN_ERR_ARGS;
    }

    int result = (int) chan_out_prepare(chan, cmd, buf, count);

    if (result < 0) {
        return result;
    }

    result = chan_out_start(chan, addr, cmd, flags, count);

    if (result < 0) {
        return result;
    }

    uint8_t cumulative_status = 0;

    do {
        uint8_t pending_status;

        result = chan_out_test(chan, addr, &pending_status);

        if (result < 0) {
            return result;
        }

        if (result == 0) {
            usleep(50000); // 50ms
            continue;
        }

        cumulative_status |= pending_status;
    } while ((cumulative_status & 0x0c) != 0x0c);

    if (status != NULL) {
        *status = cumulative_status;
    }

    // TODO: check status... for UC?

    return chan_out_complete(chan, cmd, buf, count);
}

ssize_t chan_exec_basic_sense(struct chan_out *chan, uint8_t addr, void *buf, size_t count, uint8_t *status)
{
    if (buf == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (count < 1 || count > 32) {
        return CHAN_ERR_ARGS;
    }

    return chan_exec(chan, addr, CHAN_CMD_BASIC_SENSE, 0, buf, count, status);
}

ssize_t chan_exec_sense_id(struct chan_out *chan, uint8_t addr, void *buf, size_t count, uint8_t *status)
{
    if (buf == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (count < 4 || count > 7) {
        return CHAN_ERR_ARGS;
    }

    ssize_t result = chan_exec(chan, addr, CHAN_CMD_SENSE_ID, 0, buf, count, status);

    if (result < 0) {
        return result;
    }

    if (result < 4) {
        return -1;
    }

    uint8_t *p = buf;

    if (p[0] != 0xff) {
        return -1;
    }

    return result;
}

int chan_exec_nop(struct chan_out *chan, uint8_t addr, uint8_t *status)
{
    ssize_t result = chan_exec(chan, addr, CHAN_CMD_NOP, 0, NULL, 0, status);

    if (result < 0) {
        return result;
    }

    if (result != 0) {
        return -1;
    }

    return 0;
}
