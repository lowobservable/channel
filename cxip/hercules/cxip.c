#include <stdlib.h>

#include "hercules.h"

#define CXIP_LOGMSG(...) logmsg(">>> CXIP <<< " __VA_ARGS__)

#define MSG_BUF_SIZE 16000

struct cxip {
    int sock;
    TID tid;
    TID tid2;
    uint8_t msg_buf[MSG_BUF_SIZE];
    size_t msg_buf_len;
    HLOCK msg_lock;
    COND msg_cond;
    bool msg_ready;
    COND msg_cond2;
};

bool cxip_send_msg(struct cxip *cxip, uint8_t *msg, size_t len);
ssize_t cxip_recv_msg(struct cxip *cxip, uint8_t *msg, size_t size);

static void *worker(void *arg)
{
    DEVBLK *dev = (DEVBLK *) arg;
    struct cxip *cxip = (struct cxip *) dev->dev_data;

    CXIP_LOGMSG("Worker thread started\n");

    uint8_t buf[1024];
    ssize_t result;

    while ((result = read(cxip->sock, &buf, 1024)) > 0) {
        size_t count = result;

        hthread_mutex_lock(&cxip->msg_lock);

        // Append the new bytes.
        memcpy(cxip->msg_buf + cxip->msg_buf_len, buf, count);

        cxip->msg_buf_len += count;

        // Process complete messages.
        while (true) {
            if (cxip->msg_buf_len < 2) {
                break;
            }

            size_t msg_len = (cxip->msg_buf[0] << 8) | cxip->msg_buf[1];

            if (cxip->msg_buf_len < 2 + msg_len) {
                break;
            }

            uint8_t msg_type = cxip->msg_buf[2];

            CXIP_LOGMSG("Worker received %zu byte message (type = %.2x)\n", msg_len, msg_type);

            if (msg_type == 0x05 /* STATUS */) {
                uint8_t device_status = cxip->msg_buf[4];

                device_attention(dev, device_status);
            } else {

                cxip->msg_ready = true;

                // TODO: I shouldn't be writing multi-threaded C code...
                hthread_mutex_unlock(&cxip->msg_lock);
                hthread_cond_signal(&cxip->msg_cond);

                // we are trying to yield here...

                hthread_mutex_lock(&cxip->msg_lock);

                while (cxip->msg_ready) {
                    CXIP_LOGMSG("Worker waiting on message pickup...\n");

                    hthread_cond_wait(&cxip->msg_cond2, &cxip->msg_lock);
                }
            }

            // Move to the next message.
            memmove(cxip->msg_buf, cxip->msg_buf + 2 + msg_len, 2 + msg_len);

            cxip->msg_buf_len -= (2 + msg_len);
        }

        hthread_mutex_unlock(&cxip->msg_lock);
    }

    CXIP_LOGMSG("Worker thread done\n");

    return NULL;
}

static int cxip_init_handler(DEVBLK *dev, int argc, char **argv)
{
    UNREFERENCED(argc);
    UNREFERENCED(argv);

    // TODO: do we need to check and handle reinit here?

    if ((dev->dev_data = malloc(sizeof(struct cxip))) == NULL) {
        return -1;
    }

    struct cxip *cxip = (struct cxip *) dev->dev_data;

    cxip->sock = -1;

    if ((cxip->sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        free(dev->dev_data);
        dev->dev_data = NULL;

        return -1;
    }

    struct sockaddr_in addr;

    addr.sin_family = AF_INET;
    inet_pton(AF_INET, "192.168.1.132", &(addr.sin_addr));
    addr.sin_port = htons(3174);

    if (connect(cxip->sock, (struct sockaddr *) &addr, sizeof(addr)) < 0) {
        CXIP_LOGMSG("Unable to connect\n");

        close(cxip->sock);

        free(dev->dev_data);
        dev->dev_data = NULL;

        return -1;
    }

    CXIP_LOGMSG("Connected\n");

    cxip->msg_buf_len = 0;
    cxip->msg_ready = false;

    hthread_mutex_init(&cxip->msg_lock, NULL);
    hthread_cond_init(&cxip->msg_cond);
    hthread_cond_init(&cxip->msg_cond2);

    int result;

    if ((result = create_thread(&cxip->tid, JOINABLE, worker, dev, "cxip_worker")) != 0) {
        CXIP_LOGMSG("Error creating worker thread: %d\n", result);
        return -1;
    }

    CXIP_LOGMSG("Ready\n");

    return 0;
}

static void cxip_execute_ccw(DEVBLK *dev, BYTE code, BYTE flags,
        BYTE chained, U32 count, BYTE prevcode, int ccwseq,
        BYTE *iobuf, BYTE *more, BYTE *unitstat, U32 *residual)
{
    UNREFERENCED(flags);
    UNREFERENCED(chained);
    UNREFERENCED(prevcode);
    UNREFERENCED(ccwseq);

    struct cxip *cxip = (struct cxip *) dev->dev_data;

    *residual = 0;
    *more = 0;

    CXIP_LOGMSG("Executing cmd = %.2x, count = %u\n", code, count);

    uint8_t msg[MSG_BUF_SIZE];

    msg[0] = 0x03; // EXEC
    msg[1] = dev->devnum;
    msg[2] = code;
    msg[3] = 0; // TODO: flags
    msg[4] = (count >> 8) & 0xff;
    msg[5] = count & 0xff;

    bool is_write_command = code & 0x01;

    if (is_write_command) {
        memcpy(msg + 6, iobuf, count);
    }

    cxip_send_msg(cxip, msg, 6 + (is_write_command ? count : 0));

    ssize_t result = cxip_recv_msg(cxip, msg, MSG_BUF_SIZE);

    if (msg[0] != 0x04) {
        CXIP_LOGMSG("Unexpected EXEC response message\n");
        return;
    }

    if (!(msg[1] == 0 || msg[1] == 4 || msg[1] == 5 || msg[1] == 6)) {
        CXIP_LOGMSG("EXEC error: %d\n", msg[1]);
        return;
    }

    uint8_t device_status = msg[2];
    size_t actual_count = (msg[3] << 8) | msg[4];

    CXIP_LOGMSG("    status = %.2x, transfer count = %zu\n", device_status, actual_count);

    if (is_write_command) {
        *residual = count - actual_count;
        //*more = ... // TODO
    } else {
        memcpy(iobuf, msg + 5, actual_count);

        *residual = count - actual_count;
    }

    *unitstat = device_status;

    CXIP_LOGMSG("    residual = %u, more = %d\n", *residual, *more);

    // TODO: poor man's concurrent sense
}

static int cxip_close_device(DEVBLK *dev)
{
    if (dev->dev_data == NULL) {
        return 0;
    }

    struct cxip *cxip = (struct cxip *) dev->dev_data;

    if (cxip->sock != -1) {
        CXIP_LOGMSG("Disconnected\n");

        close(cxip->sock);
    }

    // TODO: what about the worker thread?

    hthread_cond_destroy(&cxip->msg_cond);
    hthread_cond_destroy(&cxip->msg_cond2);
    hthread_mutex_destroy(&cxip->msg_lock);

    free(dev->dev_data);
    dev->dev_data = NULL;

    return 0;
}

static void cxip_query_device(DEVBLK *dev, char **devclass, int buflen,
        char *buffer)
{
    UNREFERENCED(dev);
    UNREFERENCED(devclass);
    UNREFERENCED(buflen);
    UNREFERENCED(buffer);
}

// vvv
bool cxip_send_msg(struct cxip *cxip, uint8_t *msg, size_t len)
{
    CXIP_LOGMSG("Sending %zu byte message\n", len);

    uint8_t buf[2];

    buf[0] = (len >> 8) & 0xff;
    buf[1] = len & 0xff;

    if (write(cxip->sock, buf, 2) < 2) {
        return false;
    }

    if (write(cxip->sock, msg, len) < (ssize_t) len) {
        return false;
    }

    return true;
}

ssize_t cxip_recv_msg(struct cxip *cxip, uint8_t *msg, size_t size)
{
    hthread_mutex_lock(&cxip->msg_lock);

    while (!cxip->msg_ready) {
        hthread_cond_wait(&cxip->msg_cond, &cxip->msg_lock);
    }

    size_t len = (cxip->msg_buf[0] << 8) | cxip->msg_buf[1];

    CXIP_LOGMSG("Received %zu byte message\n", len);

    memcpy(msg, cxip->msg_buf + 2, len);

    cxip->msg_ready = false;

    hthread_mutex_unlock(&cxip->msg_lock);

    hthread_cond_signal(&cxip->msg_cond2);

    return len;
}
// ^^^

static BYTE  xxx_loc3270_immed [256] =

 /* 0 1 2 3 4 5 6 7 8 9 A B C D E F */
  { 0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,1,  /* 00 */      // 03, 0B, 0F
    0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,  /* 10 */      //     1B
    0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,  /* 20 */      //     2B
    0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,  /* 30 */      //     3B
    0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,  /* 40 */      //     4B
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* 50 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* 60 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* 70 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* 80 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* 90 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* A0 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* B0 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* C0 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* D0 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,  /* E0 */
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}; /* F0 */

static DEVHND cxip_device_hndinfo = {
    &cxip_init_handler,     // Device initialization
    &cxip_execute_ccw,      // Device CCW execute
    &cxip_close_device,     // Device close
    &cxip_query_device,     // Device query
    NULL,                   // Device extended query
    NULL,                   // Device start channel program
    NULL,                   // Device end channel program
    NULL,                   // Device resume channel program
    NULL,                   // Device suspend channel program
    NULL,                   // Device halt channel program
    NULL,                   // Device read
    NULL,                   // Device write
    NULL,                   // Device query used
    NULL,                   // Device reserve
    NULL,                   // Device release
    NULL,                   // Device attention
    xxx_loc3270_immed,                   // Immediate CCW codes
    NULL,                   // Signal adapter input
    NULL,                   // Signal adapter output
    NULL,                   // Signal adapter sync
    NULL,                   // Signal adapter output multiple
    NULL,                   // QDIO subsystem desc
    NULL,                   // QDIO set subchan ind
    NULL,                   // Hercules suspend
    NULL,                   // Hercules resume
};

HDL_DEPENDENCY_SECTION;
{
    HDL_DEPENDENCY(HERCULES);
    HDL_DEPENDENCY(DEVBLK);
    HDL_DEPENDENCY(SYSBLK);
}
END_DEPENDENCY_SECTION;

HDL_DEVICE_SECTION;
{
    HDL_DEVICE(CXIP, cxip_device_hndinfo);
}
END_DEVICE_SECTION;
