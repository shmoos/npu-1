#include "transport.h"
#include "include/npu_regs.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct {
    uint32_t regs[64];
    uint8_t  mem_a[4096];
    uint8_t  mem_b[4096];
    int32_t  mem_c[16];
    int8_t   mem_y[16];
    int      attached;
} mock_state_t;

static int mock_attach(npu_transport_t *t, int slot_id) {
    (void)slot_id;
    mock_state_t *st = (mock_state_t *)t->priv;
    st->attached = 1;
    st->regs[NPU_REG_ID >> 2]          = NPU_ID_MAGIC_EXPECTED;
    st->regs[NPU_REG_ABI_VERSION >> 2] = NPU_ABI_VERSION_EXPECTED;
    st->regs[NPU_REG_BUILD_ID >> 2]    = 0x20261025;
    st->regs[NPU_REG_K >> 2]           = 4;
    st->regs[NPU_REG_M_VALID >> 2]     = 4;
    st->regs[NPU_REG_N_VALID >> 2]     = 4;
    st->regs[NPU_REG_MODE >> 2]        = 0;
    st->regs[NPU_REG_REQUANT_MULT >> 2]= 1;
    st->regs[NPU_REG_REQUANT_SHIFT >> 2]= 0;
    return 0;
}

static void mock_detach(npu_transport_t *t) {
    mock_state_t *st = (mock_state_t *)t->priv;
    st->attached = 0;
}

static int64_t mock_signed_round_shift(int64_t z, int shift) {
    if (shift == 0) return z;
    int sign = (z < 0) ? -1 : 1;
    int64_t abs_z = (z < 0) ? -z : z;
    int64_t rounded = (abs_z + (1LL << (shift - 1))) >> shift;
    return sign * rounded;
}

static void mock_execute_tile(mock_state_t *st) {
    uint32_t k       = st->regs[NPU_REG_K >> 2];
    uint32_t m_valid = st->regs[NPU_REG_M_VALID >> 2];
    uint32_t n_valid = st->regs[NPU_REG_N_VALID >> 2];
    uint32_t mode    = st->regs[NPU_REG_MODE >> 2];
    uint32_t mult    = st->regs[NPU_REG_REQUANT_MULT >> 2];
    uint32_t shift   = st->regs[NPU_REG_REQUANT_SHIFT >> 2];

    if (k < 1 || k > 1024) {
        st->regs[NPU_REG_STATUS >> 2] |= NPU_STATUS_ERROR;
        st->regs[NPU_REG_ERROR_CODE >> 2] = NPU_ERR_INVALID_K;
        return;
    }
    if (m_valid < 1 || m_valid > 4) {
        st->regs[NPU_REG_STATUS >> 2] |= NPU_STATUS_ERROR;
        st->regs[NPU_REG_ERROR_CODE >> 2] = NPU_ERR_INVALID_M;
        return;
    }
    if (n_valid < 1 || n_valid > 4) {
        st->regs[NPU_REG_STATUS >> 2] |= NPU_STATUS_ERROR;
        st->regs[NPU_REG_ERROR_CODE >> 2] = NPU_ERR_INVALID_N;
        return;
    }
    if (mode > 2) {
        st->regs[NPU_REG_STATUS >> 2] |= NPU_STATUS_ERROR;
        st->regs[NPU_REG_ERROR_CODE >> 2] = NPU_ERR_INVALID_MODE;
        return;
    }

    // Compute 4x4 Tile
    for (uint32_t i = 0; i < 4; i++) {
        for (uint32_t j = 0; j < 4; j++) {
            int32_t acc = 0;
            if (i < m_valid && j < n_valid) {
                for (uint32_t step = 0; step < k; step++) {
                    int8_t a = (int8_t)st->mem_a[i * 1024 + step];
                    int8_t b = (int8_t)st->mem_b[j * 1024 + step];
                    acc += (int32_t)a * (int32_t)b;
                }
            }

            int32_t bias = (int32_t)st->regs[NPU_REG_BIAS(j) >> 2];
            int32_t c_out = acc;
            int8_t  y_out = 0;

            if (mode == NPU_MODE_RAW_GEMM) {
                c_out = acc;
            } else if (mode == NPU_MODE_BIASED_INT32) {
                c_out = acc + bias;
            } else if (mode == NPU_MODE_REQUANT_INT8) {
                int64_t biased = (int64_t)acc + (int64_t)bias;
                c_out = (int32_t)biased;
                int64_t z = biased * (int64_t)mult;
                int64_t q = mock_signed_round_shift(z, shift);
                int64_t relu = (q < 0) ? 0 : q;
                if (relu > 127) relu = 127;
                y_out = (int8_t)relu;
            }

            st->mem_c[i * 4 + j] = c_out;
            st->mem_y[i * 4 + j] = y_out;
        }
    }

    st->regs[NPU_REG_COMPLETED_SEQ >> 2] = st->regs[NPU_REG_COMMAND_SEQ >> 2];
    st->regs[NPU_REG_CYCLES_LO >> 2]     = k + 22; // simulate total latency
    st->regs[NPU_REG_STATUS >> 2]       |= NPU_STATUS_DONE;
}

static int mock_poke(npu_transport_t *t, uint32_t addr, uint32_t data) {
    mock_state_t *st = (mock_state_t *)t->priv;
    if (!st->attached) return -1;

    if (addr >= NPU_MEM_A_BUFFER_BASE && addr < NPU_MEM_A_BUFFER_BASE + 4096) {
        uint32_t offset = addr - NPU_MEM_A_BUFFER_BASE;
        memcpy(&st->mem_a[offset], &data, 4);
    } else if (addr >= NPU_MEM_B_BUFFER_BASE && addr < NPU_MEM_B_BUFFER_BASE + 4096) {
        uint32_t offset = addr - NPU_MEM_B_BUFFER_BASE;
        memcpy(&st->mem_b[offset], &data, 4);
    } else if (addr < 0x100) {
        if (addr == NPU_REG_CONTROL) {
            if (data & NPU_CTRL_SOFT_RESET) {
                st->regs[NPU_REG_STATUS >> 2] = 0;
            }
            if (data & NPU_CTRL_START) {
                st->regs[NPU_REG_STATUS >> 2] &= ~NPU_STATUS_DONE;
                mock_execute_tile(st);
            }
        } else if (addr == NPU_REG_STATUS) {
            // W1C
            st->regs[NPU_REG_STATUS >> 2] &= ~data;
        } else {
            st->regs[addr >> 2] = data;
        }
    }
    return 0;
}

static int mock_peek(npu_transport_t *t, uint32_t addr, uint32_t *data) {
    mock_state_t *st = (mock_state_t *)t->priv;
    if (!st->attached || !data) return -1;

    if (addr >= NPU_MEM_C_BUFFER_BASE && addr < NPU_MEM_C_BUFFER_BASE + 64) {
        uint32_t word_idx = (addr - NPU_MEM_C_BUFFER_BASE) >> 2;
        *data = (uint32_t)st->mem_c[word_idx];
    } else if (addr >= NPU_MEM_Y_BUFFER_BASE && addr < NPU_MEM_Y_BUFFER_BASE + 16) {
        uint32_t word_idx = (addr - NPU_MEM_Y_BUFFER_BASE) >> 2;
        memcpy(data, &st->mem_y[word_idx * 4], 4);
    } else if (addr < 0x100) {
        *data = st->regs[addr >> 2];
    } else {
        *data = 0xDEADBEEF;
    }
    return 0;
}

npu_transport_t *npu_transport_create_mock(void) {
    npu_transport_t *t = (npu_transport_t *)malloc(sizeof(npu_transport_t));
    mock_state_t *st = (mock_state_t *)calloc(1, sizeof(mock_state_t));
    t->attach = mock_attach;
    t->detach = mock_detach;
    t->poke   = mock_poke;
    t->peek   = mock_peek;
    t->priv   = st;
    return t;
}

void npu_transport_destroy(npu_transport_t *t) {
    if (t) {
        if (t->priv) free(t->priv);
        free(t);
    }
}
