#define _XOPEN_SOURCE 600
#define _DEFAULT_SOURCE 1
#include "npu_runtime.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <unistd.h>

struct npu {
    npu_transport_t *transport;
    int              slot_id;
    uint32_t         cmd_seq;
};

static double get_time_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e6 + (double)ts.tv_nsec / 1e3;
}

npu_t *npu_init(npu_transport_t *transport, int slot_id) {
    if (!transport) return NULL;

    npu_t *npu = (npu_t *)malloc(sizeof(npu_t));
    if (!npu) return NULL;

    if (!transport->attach || !transport->detach || !transport->poke || !transport->peek) {
        free(npu); return NULL;
    }
    npu->transport = transport;
    npu->slot_id   = slot_id;
    npu->cmd_seq   = 1;

    if (transport->attach(transport, slot_id) != 0) {
        fprintf(stderr, "[NPU ERROR] Failed to attach transport on slot %d\n", slot_id);
        free(npu);
        return NULL;
    }

    // Verify ID and ABI version
    uint32_t val = 0;
    if (transport->peek(transport, NPU_REG_ID, &val) != 0 || val != NPU_ID_MAGIC_EXPECTED) {
        fprintf(stderr, "[NPU ERROR] Magic ID mismatch: expected 0x%08X, got 0x%08X\n",
                NPU_ID_MAGIC_EXPECTED, val);
        transport->detach(transport);
        free(npu);
        return NULL;
    }

    if (transport->peek(transport, NPU_REG_ABI_VERSION, &val) != 0 || val != NPU_ABI_VERSION_EXPECTED) {
        fprintf(stderr, "[NPU ERROR] ABI Version mismatch: expected 0x%08X, got 0x%08X\n",
                NPU_ABI_VERSION_EXPECTED, val);
        transport->detach(transport);
        free(npu);
        return NULL;
    }

    // Perform soft reset to initialize hardware state
    if (npu_soft_reset(npu) != 0) { npu_close(npu); return NULL; }
    return npu;
}

void npu_close(npu_t *npu) {
    if (npu) {
        if (npu->transport) {
            npu->transport->detach(npu->transport);
        }
        free(npu);
    }
}

int npu_soft_reset(npu_t *npu) {
    if (!npu || !npu->transport) return -1;
    // Issue soft reset command
    if (npu->transport->poke(npu->transport, NPU_REG_CONTROL, NPU_CTRL_SOFT_RESET) != 0) {
        return -1;
    }
    // Clear status flags (W1C)
    if (npu->transport->poke(npu->transport, NPU_REG_STATUS, NPU_STATUS_DONE | NPU_STATUS_ERROR) != 0) return -2;
    return 0;
}

int npu_get_info(npu_t *npu, npu_info_t *info) {
    if (!npu || !info || !npu->transport) return -1;

    uint32_t lo = 0, hi = 0;
    if (npu->transport->peek(npu->transport, NPU_REG_ID, &info->magic) != 0) return -2;
    if (npu->transport->peek(npu->transport, NPU_REG_ABI_VERSION, &info->abi_version) != 0) return -2;
    if (npu->transport->peek(npu->transport, NPU_REG_BUILD_ID, &info->build_id) != 0) return -2;
    if (npu->transport->peek(npu->transport, NPU_REG_STATUS, &info->status) != 0) return -2;
    if (npu->transport->peek(npu->transport, NPU_REG_ERROR_CODE, &info->error_code) != 0) return -2;
    if (npu->transport->peek(npu->transport, NPU_REG_CYCLES_LO, &lo) != 0) return -2;
    if (npu->transport->peek(npu->transport, NPU_REG_CYCLES_HI, &hi) != 0) return -2;
    info->last_cycles = ((uint64_t)hi << 32) | (uint64_t)lo;

    return 0;
}

int npu_set_config(npu_t *npu,
                   uint32_t k,
                   uint32_t m_valid,
                   uint32_t n_valid,
                   uint32_t mode,
                   uint32_t mult,
                   uint32_t shift,
                   const int32_t *bias) {
    if (!npu || !npu->transport || k < 1 || k > 1024 || m_valid < 1 || m_valid > 4 || n_valid < 1 || n_valid > 4 || mode > 2 || (mode == 2 && (mult < 1 || mult > 0x7fffffff || shift > 62))) return -1;

    if (npu->transport->poke(npu->transport, NPU_REG_K, k) != 0) return -2;
    if (npu->transport->poke(npu->transport, NPU_REG_M_VALID, m_valid) != 0) return -2;
    if (npu->transport->poke(npu->transport, NPU_REG_N_VALID, n_valid) != 0) return -2;
    if (npu->transport->poke(npu->transport, NPU_REG_MODE, mode) != 0) return -2;
    if (npu->transport->poke(npu->transport, NPU_REG_REQUANT_MULT, mult) != 0) return -2;
    if (npu->transport->poke(npu->transport, NPU_REG_REQUANT_SHIFT, shift) != 0) return -2;

    for (int col = 0; col < 4; col++) {
        uint32_t b_val = (bias != NULL) ? (uint32_t)bias[col] : 0;
        if (npu->transport->poke(npu->transport, NPU_REG_BIAS(col), b_val) != 0) return -2;
    }
    return 0;
}

int npu_load_a(npu_t *npu, const int8_t *a_tile, uint32_t m_valid, uint32_t k) {
    if (!npu || !npu->transport || !a_tile || k == 0 || k > 1024 || m_valid == 0 || m_valid > 4) return -1;

    uint32_t num_words = (k + 3) / 4;

    for (uint32_t row = 0; row < 4; row++) {
        uint32_t bank_base = NPU_MEM_A_BUFFER_BASE + (row << 10);
        for (uint32_t w = 0; w < num_words; w++) {
            uint32_t word_val = 0;
            if (row < m_valid) {
                for (int b = 0; b < 4; b++) {
                    uint32_t step = w * 4 + b;
                    uint8_t byte_val = (step < k) ? (uint8_t)a_tile[row * k + step] : 0;
                    word_val |= ((uint32_t)byte_val) << (b * 8);
                }
            }
            if (npu->transport->poke(npu->transport, bank_base + (w * 4), word_val) != 0) return -2;
        }
    }
    return 0;
}

int npu_load_b_row_major(npu_t *npu, const int8_t *b_tile, uint32_t n_valid, uint32_t k, uint32_t b_stride) {
    if (!npu || !npu->transport || !b_tile || k == 0 || k > 1024 || n_valid == 0 || n_valid > 4) return -1;

    uint32_t num_words = (k + 3) / 4;

    for (uint32_t col = 0; col < 4; col++) {
        uint32_t bank_base = NPU_MEM_B_BUFFER_BASE + (col << 10);
        for (uint32_t w = 0; w < num_words; w++) {
            uint32_t word_val = 0;
            if (col < n_valid) {
                for (int b = 0; b < 4; b++) {
                    uint32_t step = w * 4 + b;
                    uint8_t byte_val = (step < k) ? (uint8_t)b_tile[step * b_stride + col] : 0;
                    word_val |= ((uint32_t)byte_val) << (b * 8);
                }
            }
            if (npu->transport->poke(npu->transport, bank_base + (w * 4), word_val) != 0) return -2;
        }
    }
    return 0;
}

int npu_load_b_col_major(npu_t *npu, const int8_t *b_tile, uint32_t n_valid, uint32_t k) {
    if (!npu || !npu->transport || !b_tile || k == 0 || k > 1024 || n_valid == 0 || n_valid > 4) return -1;

    uint32_t num_words = (k + 3) / 4;

    for (uint32_t col = 0; col < 4; col++) {
        uint32_t bank_base = NPU_MEM_B_BUFFER_BASE + (col << 10);
        for (uint32_t w = 0; w < num_words; w++) {
            uint32_t word_val = 0;
            if (col < n_valid) {
                for (int b = 0; b < 4; b++) {
                    uint32_t step = w * 4 + b;
                    uint8_t byte_val = (step < k) ? (uint8_t)b_tile[col * k + step] : 0;
                    word_val |= ((uint32_t)byte_val) << (b * 8);
                }
            }
            if (npu->transport->poke(npu->transport, bank_base + (w * 4), word_val) != 0) return -2;
        }
    }
    return 0;
}

int npu_run_tile(npu_t *npu, uint32_t seq, uint32_t timeout_ms, uint64_t *cycles_out) {
    if (!npu || !npu->transport) return -1;

    // Clear prior sticky completion/error before assigning a new command.
    if (npu->transport->poke(npu->transport, NPU_REG_STATUS, 6) != 0) return -2;
    // Set sequence number and start execution
    if (npu->transport->poke(npu->transport, NPU_REG_COMMAND_SEQ, seq) != 0) return -2;
    if (npu->transport->poke(npu->transport, NPU_REG_CONTROL, NPU_CTRL_START) != 0) return -2;

    // Poll with timeout
    double t_start = get_time_us();
    double t_deadline = t_start + ((double)timeout_ms * 1000.0);

    while (1) {
        uint32_t status = 0;
        if (npu->transport->peek(npu->transport, NPU_REG_STATUS, &status) != 0) {
            return -2; // Transport error
        }

        if (status & NPU_STATUS_ERROR) {
            uint32_t err = 0;
            if (npu->transport->peek(npu->transport, NPU_REG_ERROR_CODE, &err) != 0) return -2;
            fprintf(stderr, "[NPU ERROR] Hardware error detected! Error code: 0x%08X\n", err);
            // Clear error flag (W1C)
            if (npu->transport->poke(npu->transport, NPU_REG_STATUS, NPU_STATUS_ERROR) != 0) return -2;
            return (int)err;
        }

        if (status & NPU_STATUS_DONE) {
            uint32_t completed_seq = 0;
            if (npu->transport->peek(npu->transport, NPU_REG_COMPLETED_SEQ, &completed_seq) != 0) return -2;
            if (completed_seq != seq) {
                fprintf(stderr, "[NPU ERROR] Sequence mismatch: expected %u, got %u\n",
                        seq, completed_seq);
                return -3;
            }

            if (cycles_out) {
                uint32_t lo = 0, hi = 0;
                if (npu->transport->peek(npu->transport, NPU_REG_CYCLES_LO, &lo) != 0) return -2;
                if (npu->transport->peek(npu->transport, NPU_REG_CYCLES_HI, &hi) != 0) return -2;
                *cycles_out = ((uint64_t)hi << 32) | (uint64_t)lo;
            }

            // Clear DONE flag (W1C)
            if (npu->transport->poke(npu->transport, NPU_REG_STATUS, NPU_STATUS_DONE) != 0) return -2;
            return 0; // Success
        }

        if (get_time_us() >= t_deadline) {
            fprintf(stderr, "[NPU ERROR] Tile execution timed out after %u ms! Status: 0x%08X\n",
                    timeout_ms, status);
            npu_soft_reset(npu);
            return -4; // Timeout
        }

        // Backoff slightly
        usleep(10);
    }
}

int npu_read_c(npu_t *npu, int32_t *c_tile) {
    if (!npu || !npu->transport || !c_tile) return -1;

    for (int i = 0; i < 16; i++) {
        uint32_t val = 0;
        if (npu->transport->peek(npu->transport, NPU_MEM_C_BUFFER_BASE + (i * 4), &val) != 0) {
            return -1;
        }
        c_tile[i] = (int32_t)val;
    }
    return 0;
}

int npu_read_y(npu_t *npu, int8_t *y_tile) {
    if (!npu || !npu->transport || !y_tile) return -1;

    for (int w = 0; w < 4; w++) {
        uint32_t val = 0;
        if (npu->transport->peek(npu->transport, NPU_MEM_Y_BUFFER_BASE + (w * 4), &val) != 0) {
            return -1;
        }
        for (int b = 0; b < 4; b++) {
            y_tile[w * 4 + b] = (int8_t)((val >> (b * 8)) & 0xFF);
        }
    }
    return 0;
}

int npu_gemm(npu_t *npu,
             const int8_t *A,
             const int8_t *B,
             int32_t *C,
             int8_t *Y,
             uint32_t M,
             uint32_t N,
             uint32_t K,
             uint32_t mode,
             uint32_t mult,
             uint32_t shift,
             const int32_t *bias,
             npu_perf_t *perf) {
    if (!npu || !A || !B || M == 0 || N == 0 || K == 0 || K > 1024) return -1;

    double t_total_start = get_time_us();
    double load_time = 0.0;
    double exec_time = 0.0;
    double read_time = 0.0;
    uint64_t total_cycles = 0;

    int8_t a_tile[4 * 1024];
    int32_t c_tile[16];
    int8_t y_tile[16];
    int32_t tile_bias[4];

    for (uint32_t r = 0; r < M; r += 4) {
        uint32_t m_valid = (M - r < 4) ? (M - r) : 4;

        // Pack A sub-tile: m_valid rows of length K
        for (uint32_t i = 0; i < m_valid; i++) {
            memcpy(&a_tile[i * K], &A[(r + i) * K], K);
        }

        for (uint32_t c = 0; c < N; c += 4) {
            uint32_t n_valid = (N - c < 4) ? (N - c) : 4;

            // Extract bias for active columns
            for (uint32_t j = 0; j < 4; j++) {
                if (bias && (c + j < N)) {
                    tile_bias[j] = bias[c + j];
                } else {
                    tile_bias[j] = 0;
                }
            }

            double t0 = get_time_us();
            if (npu_set_config(npu, K, m_valid, n_valid, mode, mult, shift, tile_bias) != 0) return -2;
            if (npu_load_a(npu, a_tile, m_valid, K) != 0) return -2;
            if (npu_load_b_row_major(npu, &B[c], n_valid, K, N) != 0) return -2;
            double t1 = get_time_us();
            load_time += (t1 - t0);

            uint64_t cycles = 0;
            uint32_t seq = npu->cmd_seq++;
            int rc = npu_run_tile(npu, seq, 1000, &cycles);
            double t2 = get_time_us();
            exec_time += (t2 - t1);
            total_cycles += cycles;

            if (rc != 0) return rc;

            double t3 = get_time_us();
            if (mode == NPU_MODE_RAW_GEMM || mode == NPU_MODE_BIASED_INT32) {
                if (npu_read_c(npu, c_tile) != 0) return -2;
                for (uint32_t i = 0; i < m_valid; i++) {
                    for (uint32_t j = 0; j < n_valid; j++) {
                        if (C) C[(r + i) * N + (c + j)] = c_tile[i * 4 + j];
                    }
                }
            } else if (mode == NPU_MODE_REQUANT_INT8) {
                if (npu_read_y(npu, y_tile) != 0) return -2;
                for (uint32_t i = 0; i < m_valid; i++) {
                    for (uint32_t j = 0; j < n_valid; j++) {
                        if (Y) Y[(r + i) * N + (c + j)] = y_tile[i * 4 + j];
                    }
                }
                if (C) {
                    if (npu_read_c(npu, c_tile) != 0) return -2;
                    for (uint32_t i = 0; i < m_valid; i++) {
                        for (uint32_t j = 0; j < n_valid; j++) {
                            C[(r + i) * N + (c + j)] = c_tile[i * 4 + j];
                        }
                    }
                }
            }
            double t4 = get_time_us();
            read_time += (t4 - t3);
        }
    }

    double t_total_end = get_time_us();

    if (perf) {
        perf->core_cycles   = total_cycles;
        perf->load_time_us  = load_time;
        perf->exec_time_us  = exec_time;
        perf->read_time_us  = read_time;
        perf->total_time_us = t_total_end - t_total_start;
    }

    return 0;
}
