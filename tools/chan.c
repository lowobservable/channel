// insmod u-dma-buf.ko udmabuf0=16000

#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

#include <real.h>
#include <chan.h>

static void usage(char *cmd);
static bool regs(struct chan_out *out);
static bool sense_id(struct chan_out *out, uint8_t addr);
static bool wrap_test(struct chan_out *out);

int main(int argc, char **argv)
{
    bool ignore_state = false;
    bool reset_on_close = true;

    uint8_t dev_addr;

    if (argc == 1 || strcmp(argv[1], "regs") == 0) {
        ignore_state = true;
        reset_on_close = false;
    } else if (argc > 1 && strcmp(argv[1], "dev") == 0) {
        if (argc < 4) {
            usage(argv[0]);
            return EXIT_FAILURE;
        }

        if (!chan_parse_dev_addr(argv[2], &dev_addr)) {
            printf("Invalid device address: %s\n", argv[2]);
            return EXIT_FAILURE;
        }
    }

    int mem_fd;

    if ((mem_fd = mem_open()) < 0) {
        perror("mem_open");
        return EXIT_FAILURE;
    }

    struct chan_out out;

    int result = chan_out_open(&out, mem_fd, "udmabuf0", ignore_state);

    if (result == -1) {
        perror("chan_open");
        return EXIT_FAILURE;
    } else if (result < -1) {
        printf("chan_out_open error: %d\n", result);
        return EXIT_FAILURE;
    }

    bool success = false;

    if (argc == 1 || strcmp(argv[1], "regs") == 0) {
        success = regs(&out);
    } else if (argc == 4 && strcmp(argv[1], "dev") == 0 && strcmp(argv[3], "id") == 0) {
        success = sense_id(&out, dev_addr);
    } else if (strcmp(argv[1], "wrap") == 0) {
        success = wrap_test(&out);
    } else {
        usage(argv[0]);
    }

    chan_out_close(&out, reset_on_close);

    close(mem_fd);

    return (success ? EXIT_SUCCESS : EXIT_FAILURE);
}

void usage(char *cmd)
{
    printf("Usage:\n");
    printf("  %s [regs]\n", cmd);
    printf("  %s dev aa id\n", cmd);
    printf("  %s wrap\n", cmd);
}

bool regs(struct chan_out *out)
{
    chan_out_debug(out);

    return true;
}

bool sense_id(struct chan_out *out, uint8_t addr)
{
    if (chan_out_config(out, true, true) < 0) {
        return false;
    }

    if (chan_out_dev_config(out, addr, true) < 0) {
        return false;
    }

    uint8_t id[7];
    uint8_t status;

    ssize_t result = chan_exec_sense_id(out, addr, id, sizeof(id), &status);

    if (result < 0) {
        if (result == CHAN_ERR_DEVICE_NOTOP) {
            printf("Device not operational\n");
        } else if (result == CHAN_ERR_EXEC_STATUS) {
            char fmt_status_buf[CHAN_FMT_STATUS_BUF_SIZE];

            printf("Unexpected status: %s\n", chan_fmt_status(status, fmt_status_buf, sizeof(fmt_status_buf)));
        } else {
            printf("Error: %zd\n", result);
        }

        return false;
    }

    for (size_t index = 0; index < result; index++) {
        if (index > 0) {
            printf(" ");
        }

        printf("%.2X", id[index]);
    }

    printf("\n");

    return true;
}

struct wrap_test_case {
    uint32_t driver;
    char *driver_name;
    char *receiver_name;
};

struct wrap_test_case wrap_test_cases[] = {
    { 0x00001, "Operational Out", "-" },
    { 0x00002, "Service Out", "Data In" },
    { 0x00004, "Hold Out", "Select In" },
    { 0x00008, "Suppress Out", "Disconnect In" },
    { 0x00010, "Command Out", "Request In" },
    { 0x00020, "Data Out", "Service In" },
    { 0x00040, "Address Out", "Metering In" },
    { 0x00080, "Select Out", "Address In" },
    { 0x00100, "Metering Out", "Status In" },
    { 0x00200, "Clock Out", "Operational In" },
    { 0x00400, "Mark 0 Out", "Mark 0 In" },
    { 0x00800, "Data 0 Out", "Data 0 In" },
    { 0x01000, "Data 1 Out", "Data 1 In" },
    { 0x02000, "Data 2 Out", "Data 2 In" },
    { 0x04000, "Data 3 Out", "Data 3 In" },
    { 0x08000, "Data 4 Out", "Data 4 In" },
    { 0x10000, "Data 5 Out", "Data 5 In" },
    { 0x20000, "Data 6 Out", "Data 6 In" },
    { 0x40000, "Data 7 Out", "Data 7 In" },
    { 0x80000, "Bus Out Parity", "Bus In Parity" },
    { 0xfffff, "ALL", "ALL" },
    { 0x00000, "NONE", "NONE" }
};

bool wrap_test(struct chan_out *out)
{
    if (chan_out_config(out, false, true) < 0) {
        return false;
    }

    printf("Driver          | Receiver        | Result\n");
    printf("--------------- | --------------- | ------\n");

    bool success = true;

    size_t len = sizeof(wrap_test_cases) / sizeof(struct wrap_test_case);

    for (size_t index = 0; index < len; index++) {
        struct wrap_test_case *test_case = &wrap_test_cases[index];

        int result = chan_out_wrap_test(out, test_case->driver, NULL);

        if (result < 0) {
            printf("Wrap test error, channel may be enabled.\n");
            return false;
        }

        if (result == 0) {
            printf("%-15s | %-15s | pass\n", test_case->driver_name, test_case->receiver_name);
        } else {
            printf("%-15s | %-15s | FAIL\n", test_case->driver_name, test_case->receiver_name);

            success = false;
        }
    }

    return success;
}
