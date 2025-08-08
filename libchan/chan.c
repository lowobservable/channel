#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>
#include <unistd.h>

#include "chan.h"

ssize_t chan_exec(struct chan_out *out, uint8_t addr, uint8_t cmd, uint8_t flags, void *buf, size_t count, uint8_t *status)
{
    if (out == NULL) {
        return CHAN_ERR_ARGS;
    }

    int result = chan_out_start(out, addr, cmd, flags, buf, count);

    if (result < 0) {
        return result;
    }

    uint8_t cumulative_status = 0;

    do {
        uint8_t pending_status;

        result = chan_out_test(out, addr, &pending_status);

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

    return chan_out_complete(out, cmd, buf, count);
}

ssize_t chan_exec_basic_sense(struct chan_out *out, uint8_t addr, void *buf, size_t count, uint8_t *status)
{
    if (buf == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (count < 1 || count > 32) {
        return CHAN_ERR_ARGS;
    }

    return chan_exec(out, addr, CHAN_CMD_BASIC_SENSE, 0, buf, count, status);
}

ssize_t chan_exec_sense_id(struct chan_out *out, uint8_t addr, void *buf, size_t count, uint8_t *status)
{
    if (buf == NULL) {
        return CHAN_ERR_ARGS;
    }

    if (count < 4 || count > 7) {
        return CHAN_ERR_ARGS;
    }

    ssize_t result = chan_exec(out, addr, CHAN_CMD_SENSE_ID, 0, buf, count, status);

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

int chan_exec_nop(struct chan_out *out, uint8_t addr, uint8_t *status)
{
    ssize_t result = chan_exec(out, addr, CHAN_CMD_NOP, 0, NULL, 0, status);

    if (result < 0) {
        return result;
    }

    if (result != 0) {
        return -1;
    }

    return 0;
}

char *chan_fmt_status(uint8_t status, char *buf, size_t size)
{
    if (size < CHAN_FMT_STATUS_BUF_SIZE) {
        return NULL;
    }

    if (status == CHAN_STATUS_CE) {
        return "<08:CE>";
    }

    if (status == CHAN_STATUS_DE) {
        return "<04:DE>";
    }

    if (status == (CHAN_STATUS_CE | CHAN_STATUS_DE)) {
        return "<0C:CE DE>";
    }

    char *p = buf;

    p += sprintf(p, "<%.2X", status);

    if (status > 0) {
        p += sprintf(p, ":");

        if (status & CHAN_STATUS_ATTN) {
            p += sprintf(p, "A ");
        }

        if (status & CHAN_STATUS_SM) {
            p += sprintf(p, "SM ");
        }

        if (status & CHAN_STATUS_CUE) {
            p += sprintf(p, "CUE ");
        }

        if (status & CHAN_STATUS_BUSY) {
            p += sprintf(p, "B ");
        }

        if (status & CHAN_STATUS_CE) {
            p += sprintf(p, "CE ");
        }

        if (status & CHAN_STATUS_DE) {
            p += sprintf(p, "DE ");
        }

        if (status & CHAN_STATUS_UC) {
            p += sprintf(p, "UC ");
        }

        if (status & CHAN_STATUS_UX) {
            p += sprintf(p, "UX ");
        }

        // Remove the trailing space.
        *(--p) = '\0';
    }

    sprintf(p, ">");

    return buf;
}

char *chan_fmt_cmd(uint8_t cmd, char *buf, size_t size)
{
    if (size < CHAN_FMT_CMD_BUF_SIZE) {
        return NULL;
    }

    if (cmd == CHAN_CMD_NOP) {
        return "<03:NOP>";
    }

    if (cmd == CHAN_CMD_BASIC_SENSE) {
        return "<04:SENSE>";
    }

    if (cmd == CHAN_CMD_SENSE_ID) {
        return "<E4:SENSE ID>";
    }

    char *p = buf;

    p += sprintf(p, "<%.2X", cmd);

    uint8_t modifier_mask = 0;

    if ((cmd & 0x0f) == 0x04) {
        p += sprintf(p, ":SENSE");

        modifier_mask = 0xf0;
    } else if ((cmd & 0x0f) == 0x0c) {
        p += sprintf(p, ":DAER");

        modifier_mask = 0xf0;
    } else if ((cmd & 0x03) == 0x01) {
        p += sprintf(p, ":WRITE");

        modifier_mask = 0xfc;
    } else if ((cmd & 0x03) == 0x02) {
        p += sprintf(p, ":READ");

        modifier_mask = 0xfc;
    } else if ((cmd & 0x03) == 0x03) {
        p += sprintf(p, ":CONTROL");

        modifier_mask = 0xfc;
    }

    if (cmd & modifier_mask) {
        p += sprintf(p, "*");
    }

    p += sprintf(p, ">");

    return buf;
}
