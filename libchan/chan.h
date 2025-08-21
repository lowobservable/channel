#ifndef __CHAN_H
#define __CHAN_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <sys/types.h>

#include <udmabuf.h>

#define CHAN_CMD_BASIC_SENSE    0x04
#define CHAN_CMD_SENSE_ID       0xe4
#define CHAN_CMD_NOP            0x03

#define CHAN_START_CHAINED      0x02
#define CHAN_START_CHAINING     0x01

#define CHAN_STATUS_ATTN        0x80    // Attention
#define CHAN_STATUS_SM          0x40    // Status Modifier
#define CHAN_STATUS_CUE         0x20    // Control Unit End
#define CHAN_STATUS_BUSY        0x10    // Busy
#define CHAN_STATUS_CE          0x08    // Channel End
#define CHAN_STATUS_DE          0x04    // Device End
#define CHAN_STATUS_UC          0x02    // Unit Check
#define CHAN_STATUS_UX          0x01    // Unit Exception

#define CHAN_FMT_STATUS_BUF_SIZE 28
#define CHAN_FMT_CMD_BUF_SIZE   13

#define CHAN_ERR_ARGS           -2      // Invalid arguments
#define CHAN_ERR_CHANNEL_STATE  -3      // Invalid channel state
#define CHAN_ERR_DEVICE_STATE   -4      // Invalid device state
#define CHAN_ERR_DEVICE_NOTOP   -5      // Device not operational
#define CHAN_ERR_DEVICE_BUSY    -6      // Device busy
#define CHAN_ERR_START_PENDING  -7      // Start pending
#define CHAN_ERR_STATUS_PENDING -8      // Status pending
#define CHAN_ERR_CMD_RESERVED   -9      // Reserved command
#define CHAN_ERR_DMA_SIZE       -10     // DMA buffer limit

struct chan_out {
    uintptr_t base_addr;
    void *base;
    volatile uint32_t *regs;
    struct udmabuf udmabuf;
};

int chan_out_open(struct chan_out *out, int mem_fd, char *udmabuf_path, bool frontend_enable);

int chan_out_close(struct chan_out *out);

int chan_out_enable(struct chan_out *out);

int chan_out_disable(struct chan_out *out);

int chan_out_config(struct chan_out *out, uint8_t addr, bool enable);

int chan_out_test(struct chan_out *out, uint8_t addr, uint8_t *status);

int chan_out_start(struct chan_out *out, uint8_t addr, uint8_t cmd, uint8_t flags, void *buf, size_t count);

ssize_t chan_out_complete(struct chan_out *out, uint8_t cmd, void *buf, size_t count);

int chan_out_wrap_test(struct chan_out *out, uint32_t driver, uint32_t *receiver);

void chan_out_debug(struct chan_out *out);

ssize_t chan_exec(struct chan_out *out, uint8_t addr, uint8_t cmd, uint8_t flags, void *buf, size_t count, uint8_t *status);

ssize_t chan_exec_basic_sense(struct chan_out *out, uint8_t addr, void *buf, size_t count, uint8_t *status);

ssize_t chan_exec_sense_id(struct chan_out *out, uint8_t addr, void *buf, size_t count, uint8_t *status);

int chan_exec_nop(struct chan_out *out, uint8_t addr, uint8_t *status);

char *chan_fmt_status(uint8_t status, char *buf, size_t size);

char *chan_fmt_cmd(uint8_t cmd, char *buf, size_t size);

#endif
