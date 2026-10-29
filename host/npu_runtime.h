#ifndef NPU_RUNTIME_H
#define NPU_RUNTIME_H

#include <stdint.h>
#include <stddef.h>
#include "transport.h"
#include "include/npu_regs.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct npu npu_t;

// Information structure
typedef struct {
    uint32_t magic;
    uint32_t abi_version;
    uint32_t build_id;
    uint32_t status;
    uint32_t error_code;
    uint64_t last_cycles;
} npu_info_t;

// Diagnostics structure for benchmark and telemetry
typedef struct {
    uint64_t core_cycles;
    double   load_time_us;
    double   exec_time_us;
    double   read_time_us;
    double   total_time_us;
} npu_perf_t;

// Lifecycle
npu_t *npu_init(npu_transport_t *transport, int slot_id);
void   npu_close(npu_t *npu);
int    npu_get_info(npu_t *npu, npu_info_t *info);
int    npu_soft_reset(npu_t *npu);

// Tile Configuration and Buffer Loading
int npu_set_config(npu_t *npu,
                   uint32_t k,
                   uint32_t m_valid,
                   uint32_t n_valid,
                   uint32_t mode,
                   uint32_t mult,
                   uint32_t shift,
                   const int32_t *bias);

// Load 4 rows of A into A buffer (row-major: a_tile[m * k])
// Only m_valid rows are copied; inactive rows (up to 4) are zeroed.
int npu_load_a(npu_t *npu, const int8_t *a_tile, uint32_t m_valid, uint32_t k);

// Load 4 columns of B into B buffer (column-major: b_tile[n * k] or b_tile[k * n])
// In standard matrix multiply A[M,K] * B[K,N], column j has length K.
// b_tile is assumed column-major: b_tile[col * k + step].
// If b_tile is row-major (B[step * N + col]), pass column-major or use helper.
int npu_load_b_col_major(npu_t *npu, const int8_t *b_tile, uint32_t n_valid, uint32_t k);
int npu_load_b_row_major(npu_t *npu, const int8_t *b_tile, uint32_t n_valid, uint32_t k, uint32_t b_stride);

// Execution
int npu_run_tile(npu_t *npu, uint32_t seq, uint32_t timeout_ms, uint64_t *cycles_out);

// Read Results
int npu_read_c(npu_t *npu, int32_t *c_tile); // 16 int32_t elements (4x4)
int npu_read_y(npu_t *npu, int8_t *y_tile);   // 16 int8_t elements (4x4)

// High-level GEMM Engine for arbitrary M, N, K (tiled over 4x4 NPU accelerator)
// A is M x K (row-major, stride K)
// B is K x N (row-major, stride N)
// C is M x N (int32_t, row-major) - populated if mode == 0 or 1
// Y is M x N (int8_t, row-major)  - populated if mode == 2
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
             npu_perf_t *perf);

#ifdef __cplusplus
}
#endif

#endif // NPU_RUNTIME_H
