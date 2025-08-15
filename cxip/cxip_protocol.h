#ifndef __CXIP_PROTOCOL_H
#define __CXIP_PROTOCOL_H

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <sys/types.h>

enum cxip_msg_type {
    ACK = 0x00,
    OPEN = 0x01,
    CLOSE = 0x02,
    START = 0x03,
    STATUS = 0x04,
    DATA = 0x05,
    COUNT = 0x06,
    ERROR = 0xff
};

ssize_t cxip_decode_msg(void *buf, size_t buf_len, uint8_t **msg);

bool cxip_send_ack(int sock);
bool cxip_decode_ack(uint8_t *msg, size_t msg_len);

bool cxip_send_open(int sock, uint8_t dev_addr);
bool cxip_decode_open(uint8_t *msg, size_t msg_len, uint8_t *dev_addr);

bool cxip_send_close(int sock, uint8_t dev_addr);
bool cxip_decode_close(uint8_t *msg, size_t msg_len, uint8_t *dev_addr);

bool cxip_send_start(int sock, uint8_t dev_addr, uint8_t cmd, uint8_t flags, void *data, uint16_t count);
bool cxip_decode_start(uint8_t *msg, size_t msg_len, uint8_t *dev_addr, uint8_t *cmd, uint8_t *flags, void **data, uint16_t *count);

bool cxip_send_status(int sock, uint8_t dev_addr, uint8_t status, bool solicited);
bool cxip_decode_status(uint8_t *msg, size_t msg_len, uint8_t *dev_addr, uint8_t *status, bool *solicited);

bool cxip_send_data(int sock, uint8_t dev_addr, void *data, uint16_t count);
bool cxip_decode_data(uint8_t *msg, size_t msg_len, uint8_t *dev_addr, void **data, uint16_t *count);

bool cxip_send_count(int sock, uint8_t dev_addr, uint16_t count);
bool cxip_decode_count(uint8_t *msg, size_t msg_len, uint8_t *dev_addr, uint16_t *count);

bool cxip_send_error(int sock, uint8_t num, char *text);
bool cxip_decode_error(uint8_t *msg, size_t msg_len, uint8_t *num, char *text, size_t text_size);

#endif
