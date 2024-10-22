#ifndef __MOCK_CU_H
#define __MOCK_CU_H

#include <stdint.h>
#include <stdbool.h>

struct mock_cu {
    uintptr_t addr;
    void *base;
    volatile uint32_t *regs;
};

int mock_cu_open(struct mock_cu *mock_cu, uintptr_t addr, int mem_fd);

int mock_cu_close(struct mock_cu *mock_cu);

void mock_cu_arrange(struct mock_cu *mock_cu, bool busy, bool short_busy, uint16_t limit);

bool mock_cu_assert(struct mock_cu *mock_cu, int8_t expected_command, int16_t expected_count);

#endif
