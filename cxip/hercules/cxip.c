#include <stdlib.h>

#include "hercules.h"

#include <cxip_protocol.h>

#define CXIP_HOST "10.83.5.62"
#define CXIP_PORT 3174
#define CXIP_DEV_NUM 0x0060 // 3174-1L

#define MSG_BUF_SIZE 16000

#define CXIP_LOG(...) logmsg(">>> CXIP <<< " __VA_ARGS__)

#if 0
#define CXIP_LOG_TRACE(...) logmsg(">>> CXIP <<< " __VA_ARGS__)
#else
#define CXIP_LOG_TRACE(...)
#endif

struct cxip {
    uint16_t dev_num;
    int sock;
    TID tid;
    uint8_t msg_buf[MSG_BUF_SIZE];
    size_t msg_buf_len;
    HLOCK msg_lock;
    bool msg_ready;
    COND msg_cond1;
    COND msg_cond2;
    bool error_sense_pending;
};

static void *cxip_worker(void *arg);
static ssize_t cxip_get_msg(struct cxip *cxip, void *msg, size_t msg_size);

static int cxip_init_handler(DEVBLK *dev, int argc, char **argv)
{
    UNREFERENCED(argc);
    UNREFERENCED(argv);

    // TODO: do we need to check and handle reinit here?

    if ((dev->dev_data = malloc(sizeof(struct cxip))) == NULL) {
        return -1;
    }

    struct cxip *cxip = (struct cxip *) dev->dev_data;

    cxip->dev_num = dev->devnum;
    cxip->sock = -1;

    cxip->dev_num = CXIP_DEV_NUM;

    if ((cxip->sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        goto error;
    }

    struct sockaddr_in addr;

    addr.sin_family = AF_INET;
    inet_pton(AF_INET, CXIP_HOST, &(addr.sin_addr));
    addr.sin_port = htons(CXIP_PORT);

    int result;

    if ((result = connect(cxip->sock, (struct sockaddr *) &addr, sizeof(addr))) < 0) {
        CXIP_LOG("ERROR: Unable to connect: %d\n", result);
        goto error;
    }

    CXIP_LOG("Connected\n");

    cxip->msg_buf_len = 0;
    cxip->msg_ready = false;

    hthread_mutex_init(&cxip->msg_lock, NULL);
    hthread_cond_init(&cxip->msg_cond1);
    hthread_cond_init(&cxip->msg_cond2);

    if ((result = create_thread(&cxip->tid, JOINABLE, cxip_worker, dev, "cxip_worker")) != 0) {
        CXIP_LOG("ERROR: Unable to create worker thread: %d\n", result);
        goto error;
    }

    // Need to delay opening the device until the worker thread has been
    // started.
    if (!cxip_send_open(cxip->sock, cxip->dev_num)) {
        CXIP_LOG("ERROR: Unable to send open message\n");
        goto error;
    }

    uint8_t msg[MSG_BUF_SIZE];

    ssize_t msg_len = cxip_get_msg(cxip, msg, sizeof(msg));

    if (!cxip_decode_ack(msg, msg_len)) {
        // TODO: try reading this as an error message...

        CXIP_LOG("ERROR: Something went wrong opening device\n");
        goto error;
    }

    CXIP_LOG("Ready\n");

    return 0;

error:
    if (cxip->sock != -1) {
        close(cxip->sock);
    }

    free(dev->dev_data);
    dev->dev_data = NULL;

    return -1;
}

static int cxip_close_device(DEVBLK *dev)
{
    if (dev->dev_data == NULL) {
        return 0;
    }

    struct cxip *cxip = (struct cxip *) dev->dev_data;

    if (cxip->sock != -1) {
        CXIP_LOG("Disconnected\n");

        close(cxip->sock);
    }

    // TODO: What about the worker thread? Is it interrupted by closing the
    // socket, if so we could join now to ensure it is complete.

    hthread_cond_destroy(&cxip->msg_cond1);
    hthread_cond_destroy(&cxip->msg_cond2);
    hthread_mutex_destroy(&cxip->msg_lock);

    free(dev->dev_data);
    dev->dev_data = NULL;

    return 0;
}

static void cxip_query_device(DEVBLK *dev, char **devclass, int buflen, char *buffer)
{
    UNREFERENCED(dev);
    UNREFERENCED(devclass);
    UNREFERENCED(buflen);
    UNREFERENCED(buffer);
}

static void cxip_execute_ccw(DEVBLK *dev, BYTE code, BYTE flags, BYTE chained, U32 count, BYTE prevcode, int ccwseq, BYTE *iobuf, BYTE *more, BYTE *unitstat, U32 *residual)
{
    UNREFERENCED(flags);
    UNREFERENCED(chained);
    UNREFERENCED(prevcode);
    UNREFERENCED(ccwseq);

    struct cxip *cxip = (struct cxip *) dev->dev_data;

    CXIP_LOG("Starting cmd %.2X, count %u\n", code, count);

    *residual = count;
    *more = 0;

    uint16_t transfer_count = 0;

    if (cxip->error_sense_pending && code == 0x04) {
        CXIP_LOG("Returning pending error sense data\n");

        transfer_count = MIN(dev->numsense, count);

        *residual -= transfer_count;

        if (transfer_count < count) {
            *more = 1;
        }

        memcpy(iobuf, dev->sense, transfer_count);

        memset(dev->sense, 0, dev->numsense);

        cxip->error_sense_pending = false;
        return;
    }

    bool is_send_cmd = code & 0x01;

    if (!cxip_send_start(cxip->sock, cxip->dev_num, code, 0, is_send_cmd ? iobuf : NULL, count)) {
        CXIP_LOG("ERROR: Unable to send start message\n");
        goto error;
    }

    uint8_t msg[MSG_BUF_SIZE];

    ssize_t msg_len = cxip_get_msg(cxip, msg, sizeof(msg));

    if (msg_len < 0) {
        // TODO: This would be an "error" getting a message.
        CXIP_LOG("ERROR: Unable to get message\n");
        goto error;
    }

    if (!cxip_decode_ack(msg, msg_len)) {
        uint8_t error_num;
        char error_text[101];

        if (cxip_decode_error(msg, msg_len, &error_num, error_text, sizeof(error_text))) {
            // TODO: Some of these need to be handled differently...
            if (error_num == 6) {
                CXIP_LOG("Start rejected, device busy\n");

                *unitstat = CSW_BUSY;
                return;
            }

            bool has_text = strlen(error_text) > 0;

            if (error_num == 0) {
                CXIP_LOG("ERROR: %s\n", has_text ? error_text : "Unknown error");
            } else if (has_text) {
                CXIP_LOG("ERROR: %s (%d)\n", error_text, error_num);
            } else {
                CXIP_LOG("ERROR: %d\n", error_num);
            }
        } else {
            CXIP_LOG("ERROR: Invalid or unexpected message\n");
        }

        goto error;
    }

    uint8_t cumulative_status = 0;
    bool done = false;

    do {
        msg_len = cxip_get_msg(cxip, msg, sizeof(msg));

        if (msg_len < 0) {
            // TODO: This would be an "error" getting a message.
            CXIP_LOG("ERROR: Unable to get message\n");
            goto error;
        }

        uint16_t dev_num;
        void *data;
        uint8_t status;
        bool solicited;

        if (is_send_cmd && cxip_decode_count(msg, msg_len, &dev_num, &transfer_count)) {
            ASSERT(dev_num == cxip->dev_num);
        } else if (!is_send_cmd && cxip_decode_data(msg, msg_len, &dev_num, &data, &transfer_count)) {
            ASSERT(dev_num == cxip->dev_num);

            memcpy(iobuf, data, transfer_count);
        } else if (cxip_decode_status(msg, msg_len, &dev_num, &status, &solicited)) {
            ASSERT(dev_num == cxip->dev_num);
            ASSERT(solicited);

            cumulative_status |= status;

            // NOTE: See libchan chan_exec for assumption.
            done = (status != CSW_CE);
        } else {
            CXIP_LOG("ERROR: Invalid or unexpected message\n");
            goto error;
        }
    } while (!done);

    *unitstat = cumulative_status;
    *residual -= transfer_count;

    CXIP_LOG("Completed cmd %.2X, status %.2X, transfered %u, residual %u\n", code, *unitstat, transfer_count, *residual);
    return;

error:
    // TODO: This may not be applicable to all devices, certainly not all
    // errors.
    CXIP_LOG("Simulating unit check with intervention required sense\n");

    dev->sense[0] = SENSE_IR;
    dev->numsense = 1;

    *unitstat = CSW_UC;

    cxip->error_sense_pending = true;
}

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
    xxx_loc3270_immed,      // Immediate CCW codes
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

void *cxip_worker(void *arg)
{
    DEVBLK *dev = (DEVBLK *) arg;
    struct cxip *cxip = (struct cxip *) dev->dev_data;

    CXIP_LOG("[Worker] Thread started\n");

    bool stop = false;

    while (!stop) {
        uint8_t buf[1024];
        ssize_t result;

        if ((result = read(cxip->sock, buf, sizeof(buf))) <= 0) {
            CXIP_LOG("[Worker] Read result = %zd, errno = %d\n", result, errno);
            break;
        }

        hthread_mutex_lock(&cxip->msg_lock);

        CXIP_LOG_TRACE("[Worker] Read %zd bytes\n", result);

        // Append the new bytes.
        memcpy(cxip->msg_buf + cxip->msg_buf_len, buf, result);

        cxip->msg_buf_len += result;

        CXIP_LOG_TRACE("[Worker] Have %zu bytes\n", cxip->msg_buf_len);

        // Process complete messages.
        while (true) {
            uint8_t *msg;

            ssize_t msg_len = cxip_decode_msg(cxip->msg_buf, cxip->msg_buf_len, &msg);

            if (msg_len < 0) {
                // TODO: How to communicate this error and disable the device?
                CXIP_LOG("[Worker] Invalid message\n");

                stop = true;
                break;
            }

            // Incomplete message, we'll need to continue reading.
            if (msg_len == 0) {
                break;
            }

            CXIP_LOG_TRACE("[Worker] Have complete %zu byte message (type = %.2x)\n", msg_len, msg[0]);

            uint16_t dev_num;
            uint8_t status;
            bool solicited;

            if (cxip_decode_status(msg, msg_len, &dev_num, &status, &solicited) && !solicited) {
                ASSERT(dev_num == cxip->dev_num);

                CXIP_LOG("[Worker] Unsolicited status %.2X\n", status);

                int result = device_attention(dev, status);

                if (result == 1) {
                    // TODO: What to do, queue this?
                    CXIP_LOG("ERROR: Hercules device is busy or pending\n");
                } else if (result == 3) {
                    // TODO: What to do, ignore this or queue it?
                    CXIP_LOG("ERROR: Hercules subchannel not valid or not enabled\n");
                }
            } else {
                cxip->msg_ready = true;

                // TODO: I shouldn't be writing multi-threaded C code, we are
                // trying to yield to execute CCW or other function here.
                hthread_mutex_unlock(&cxip->msg_lock);
                hthread_cond_signal(&cxip->msg_cond1);

                hthread_mutex_lock(&cxip->msg_lock);

                while (cxip->msg_ready) {
                    CXIP_LOG_TRACE("[Worker] Waiting for message to be read...\n");

                    hthread_cond_wait(&cxip->msg_cond2, &cxip->msg_lock);
                }
            }

            // Move to the next message.
            CXIP_LOG_TRACE("[Worker] Message read, moving to the next message\n");

            cxip->msg_buf_len -= (3 + msg_len);

            memmove(cxip->msg_buf, cxip->msg_buf + 3 + msg_len, cxip->msg_buf_len);

            CXIP_LOG_TRACE("[Worker] Have %zu bytes\n", cxip->msg_buf_len);
        }

        hthread_mutex_unlock(&cxip->msg_lock);
    }

    // TODO: How to notify any execute CCW functions waiting?

    CXIP_LOG("[Worker] Thread done\n");

    return NULL;
}

ssize_t cxip_get_msg(struct cxip *cxip, void *msg, size_t msg_size)
{
    hthread_mutex_lock(&cxip->msg_lock);

    while (!cxip->msg_ready) {
        hthread_cond_wait(&cxip->msg_cond1, &cxip->msg_lock);
    }

    size_t len = (cxip->msg_buf[1] << 8) | cxip->msg_buf[2];

    CXIP_LOG_TRACE("Got %zu byte message\n", len);

    ssize_t result;

    if (len <= msg_size) {
        memcpy(msg, cxip->msg_buf + 3, len);

        result = len;
    } else {
        result = -1;
    }

    cxip->msg_ready = false;

    hthread_mutex_unlock(&cxip->msg_lock);

    hthread_cond_signal(&cxip->msg_cond2);

    return result;
}
