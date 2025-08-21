#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#include <real.h>

#include "mock_cu.h"

#define REGS_SIZE 1024

#define REG_CONTROL 0
#define REG_STATUS 1

int mock_cu_open(struct mock_cu *mock_cu, int mem_fd)
{
    mock_cu->base_addr = 0x40001000;

    if ((mock_cu->base = real_map(mock_cu->base_addr, REGS_SIZE, mem_fd)) == NULL) {
        return -1;
    }

    mock_cu->regs = mock_cu->base;

    return 0;
}

int mock_cu_close(struct mock_cu *mock_cu)
{
    if (mock_cu == NULL) {
        return 0;
    }

    if (real_unmap(mock_cu->base, REGS_SIZE) < 0) {
        return -1;
    }

    return 0;
}

void mock_cu_arrange(struct mock_cu *mock_cu, bool busy, bool short_busy, bool request, uint16_t limit)
{
    mock_cu->regs[REG_CONTROL] = (limit << 16) | (request << 3) | (short_busy << 2) | (busy << 1);
}

bool mock_cu_assert(struct mock_cu *mock_cu, int8_t expected_command, int16_t expected_count, int8_t expected_command_chained, int8_t expected_command_chaining)
{
    uint32_t status = mock_cu->regs[REG_STATUS];

    uint8_t command = (uint8_t) (status >> 8);
    uint16_t count = (uint16_t) (status >> 16);
    bool command_chained = status & 0x00000002;
    bool command_chaining = status & 0x00000001;

    if (expected_command >= 0 && command != expected_command) {
        printf("ASSERT: expected command = 0x%.2x, actual = 0x%.2x\n", expected_command, command);
        return false;
    }

    if (expected_count >= 0 && count != expected_count) {
        printf("ASSERT: expected count = %d, actual = %d\n", expected_count, count);
        return false;
    }

    if (expected_command_chained >= 0 && command_chained != (bool) expected_command_chained) {
        printf("ASSERT: expected cmd chained = %d, actual = %d\n", (bool) expected_command_chained, command_chained);
        return false;
    }

    if (expected_command_chaining >= 0 && command_chaining != (bool) expected_command_chaining) {
        printf("ASSERT: expected cmd chaining = %d, actual = %d\n", (bool) expected_command_chaining, command_chaining);
        return false;
    }

    return true;
}
