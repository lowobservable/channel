#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <sys/types.h>
#include <sys/param.h>
#include <sys/uio.h>

#include <cxip_protocol.h>

static bool send_msg(int sock, void *msg, size_t msg_len, void *rest, size_t rest_len);

ssize_t cxip_decode_msg(void *buf, size_t buf_len, uint8_t **msg)
{
    // Header is incomplete.
    if (buf_len < 3) {
        return 0;
    }

    uint8_t *p = buf;

    uint8_t version = p[0];

    if (version != 0) {
        return -1;
    }

    size_t len = (p[1] << 8) | p[2];

    if (len == 0) {
        return -1;
    }

    // Message is incomplete.
    if (buf_len < 3 + len) {
        return 0;
    }

    if (msg != NULL) {
        *msg = &p[3];
    }

    return len;
}

bool cxip_send_ack(int sock)
{
    uint8_t msg[1];

    msg[0] = (enum cxip_msg_type) ACK;

    return send_msg(sock, msg, sizeof(msg), NULL, 0);
}

bool cxip_decode_ack(uint8_t *msg, size_t msg_len)
{
    return (msg_len == 1 && (enum cxip_msg_type) msg[0] == ACK);
}

bool cxip_send_open(int sock, uint16_t dev_num)
{
    uint8_t msg[3];

    msg[0] = (enum cxip_msg_type) OPEN;
    msg[1] = (dev_num & 0xff00) >> 8;
    msg[2] = dev_num & 0x00ff;

    return send_msg(sock, msg, sizeof(msg), NULL, 0);
}

bool cxip_decode_open(uint8_t *msg, size_t msg_len, uint16_t *dev_num)
{
    if (msg_len != 3 || (enum cxip_msg_type) msg[0] != OPEN) {
        return false;
    }

    if (dev_num != NULL) {
        *dev_num = (msg[1] << 8) | msg[2];
    }

    return true;
}

bool cxip_send_close(int sock, uint16_t dev_num)
{
    uint8_t msg[3];

    msg[0] = (enum cxip_msg_type) CLOSE;
    msg[1] = (dev_num & 0xff00) >> 8;
    msg[2] = dev_num & 0x00ff;

    return send_msg(sock, msg, sizeof(msg), NULL, 0);
}

bool cxip_decode_close(uint8_t *msg, size_t msg_len, uint16_t *dev_num)
{
    if (msg_len != 3 || (enum cxip_msg_type) msg[0] != CLOSE) {
        return false;
    }

    if (dev_num != NULL) {
        *dev_num = (msg[1] << 8) | msg[2];
    }

    return true;
}

bool cxip_send_start(int sock, uint16_t dev_num, uint8_t cmd, uint8_t flags, void *data, uint16_t count)
{
    uint8_t msg[7];

    msg[0] = (enum cxip_msg_type) START;
    msg[1] = (dev_num & 0xff00) >> 8;
    msg[2] = dev_num & 0x00ff;
    msg[3] = cmd;
    msg[4] = flags;

    size_t msg_len = 5;

    if (data == NULL) {
        msg[5] = (count & 0xff00) >> 8;
        msg[6] = count & 0x00ff;

        msg_len += 2;
    }

    return send_msg(sock, msg, msg_len, data, data != NULL ? count : 0);
}

bool cxip_decode_start(uint8_t *msg, size_t msg_len, uint16_t *dev_num, uint8_t *cmd, uint8_t *flags, void **data, uint16_t *count)
{
    if (msg_len < 5 || (enum cxip_msg_type) msg[0] != START) {
        return false;
    }

    // Determine if the command will result in data being sent to the device.
    bool is_send_cmd = msg[3] & 0x01;

    if (!is_send_cmd && msg_len < 7) {
        return false;
    }

    if (dev_num != NULL) {
        *dev_num = (msg[1] << 8) | msg[2];
    }

    if (cmd != NULL) {
        *cmd = msg[3];
    }

    if (flags != NULL) {
        *flags = msg[4];
    }

    if (is_send_cmd) {
        if (data != NULL) {
            *data = &msg[5];
        }

        if (count != NULL) {
            *count = msg_len - 5;
        }
    } else {
        if (count != NULL) {
            *count = (msg[5] << 8) | msg[6];
        }
    }

    return true;
}

bool cxip_send_status(int sock, uint16_t dev_num, uint8_t status, bool solicited)
{
    uint8_t msg[5];

    msg[0] = (enum cxip_msg_type) STATUS;
    msg[1] = (dev_num & 0xff00) >> 8;
    msg[2] = dev_num & 0x00ff;
    msg[3] = status;
    msg[4] = solicited;

    return send_msg(sock, msg, sizeof(msg), NULL, 0);
}

bool cxip_decode_status(uint8_t *msg, size_t msg_len, uint16_t *dev_num, uint8_t *status, bool *solicited)
{
    if (msg_len != 5 || (enum cxip_msg_type) msg[0] != STATUS) {
        return false;
    }

    if (dev_num != NULL) {
        *dev_num = (msg[1] << 8) | msg[2];
    }

    if (status != NULL) {
        *status = msg[3];
    }

    // cppcheck-suppress variableScope
    uint8_t flags = msg[4];

    if (solicited != NULL) {
        *solicited = flags & 0x01;
    }

    return true;
}

bool cxip_send_data(int sock, uint16_t dev_num, void *data, uint16_t count)
{
    uint8_t msg[3];

    msg[0] = (enum cxip_msg_type) DATA;
    msg[1] = (dev_num & 0xff00) >> 8;
    msg[2] = dev_num & 0x00ff;

    return send_msg(sock, msg, sizeof(msg), data, count);
}

bool cxip_decode_data(uint8_t *msg, size_t msg_len, uint16_t *dev_num, void **data, uint16_t *count)
{
    if (msg_len < 3 || (enum cxip_msg_type) msg[0] != DATA) {
        return false;
    }

    if (dev_num != NULL) {
        *dev_num = (msg[1] << 8) | msg[2];
    }

    if (data != NULL) {
        *data = &msg[3];
    }

    if (count != NULL) {
        *count = msg_len - 3;
    }

    return true;
}

bool cxip_send_count(int sock, uint16_t dev_num, uint16_t count)
{
    uint8_t msg[5];

    msg[0] = (enum cxip_msg_type) COUNT;
    msg[1] = (dev_num & 0xff00) >> 8;
    msg[2] = dev_num & 0x00ff;
    msg[3] = (count & 0xff00) >> 8;
    msg[4] = count & 0x00ff;

    return send_msg(sock, msg, sizeof(msg), NULL, 0);
}

bool cxip_decode_count(uint8_t *msg, size_t msg_len, uint16_t *dev_num, uint16_t *count)
{
    if (msg_len != 5 || (enum cxip_msg_type) msg[0] != COUNT) {
        return false;
    }

    if (dev_num != NULL) {
        *dev_num = (msg[1] << 8) | msg[2];
    }

    if (count != NULL) {
        *count = (msg[3] << 8) | msg[4];
    }

    return true;
}

bool cxip_send_error(int sock, uint8_t num, char *text)
{
    uint8_t msg[2];

    msg[0] = (enum cxip_msg_type) ERROR;
    msg[1] = num;

    size_t text_len = 0;

    if (text != NULL) {
        text_len = MIN(strlen(text), 100);
    }

    return send_msg(sock, msg, sizeof(msg), text, text_len);
}

bool cxip_decode_error(uint8_t *msg, size_t msg_len, uint8_t *num, char *text, size_t text_size)
{
    if (msg_len < 2 || (enum cxip_msg_type) msg[0] != ERROR) {
        return false;
    }

    if (num != NULL) {
        *num = msg[1];
    }

    if (text != NULL) {
        // Always clear text if caller requested, that way they can determine if
        // the message included text, or not.
        memset(text, 0, text_size);

        if (msg_len > 2) {
            strncpy(text, (char *) &msg[2], MIN(msg_len - 2, text_size));
        }
    }

    return true;
}

bool send_msg(int sock, void *msg, size_t msg_len, void *rest, size_t rest_len)
{
    size_t len = msg_len + rest_len;

    if (len == 0) {
        return false;
    }

    uint8_t buf[3];

    buf[0] = 0;
    buf[1] = (len & 0xff00) >> 8;
    buf[2] = len & 0x00ff;

    len += 3;

    // Use vectored write to avoid unnecessary packet fragmentation.
    struct iovec iov[3];
    int iov_count;

    iov[0].iov_base = buf;
    iov[0].iov_len = 3;
    iov[1].iov_base = msg;
    iov[1].iov_len = msg_len;

    iov_count = 2;

    if (rest != NULL) {
        iov[2].iov_base = rest;
        iov[2].iov_len = rest_len;

        iov_count++;
    }

    if (writev(sock, iov, iov_count) < (ssize_t) len) {
        return false;
    }

    return true;
}
