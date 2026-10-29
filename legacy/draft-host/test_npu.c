#include "npu_runtime.h"
#include "include/npu_regs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static void print_usage(const char *prog) {
    printf("NPU-1 Host Test & Diagnostic Utility\n");
    printf("Usage:\n");
    printf("  %s --info                           Display device registers and identification\n", prog);
    printf("  %s --selftest                       Run comprehensive self-test verification suite\n", prog);
    printf("  %s --gemm <M> <N> <K>               Run benchmark GEMM of size (M x N x K)\n", prog);
    printf("  %s --infer <model.bin> <test.bin>   Run complete digits inference using host runtime\n", prog);
}

static int run_info(npu_t *npu) {
    npu_info_t info;
    if (npu_get_info(npu, &info) != 0) {
        fprintf(stderr, "Failed to get NPU device info\n");
        return 1;
    }

    printf("============================================================\n");
    printf("                 NPU-1 ACCELERATOR INFO                     \n");
    printf("============================================================\n");
    printf("  Device ID Magic      : 0x%08X (\"%.4s\")\n", info.magic, (char *)&info.magic);
    printf("  ABI Version          : 0x%08X (v%u.%u)\n", info.abi_version,
           (info.abi_version >> 16) & 0xFFFF, info.abi_version & 0xFFFF);
    printf("  Build Identifier     : 0x%08X\n", info.build_id);
    printf("  Hardware Status      : 0x%08X (BUSY=%u, DONE=%u, ERROR=%u)\n",
           info.status,
           (info.status & NPU_STATUS_BUSY) ? 1 : 0,
           (info.status & NPU_STATUS_DONE) ? 1 : 0,
           (info.status & NPU_STATUS_ERROR) ? 1 : 0);
    printf("  Error Code           : 0x%08X\n", info.error_code);
    printf("  Last Cycle Count     : %llu cycles\n", (unsigned long long)info.last_cycles);
    printf("============================================================\n");
    return 0;
}

static int run_selftest(npu_t *npu) {
    int errors = 0;
    printf("=== Starting NPU-1 Self-Test Suite ===\n");

    // Test 1: Info verification
    printf("[Test 1/6] Reading Hardware Registers... ");
    npu_info_t info;
    if (npu_get_info(npu, &info) != 0 || info.magic != NPU_ID_MAGIC_EXPECTED) {
        printf("FAILED (Invalid ID 0x%08X)\n", info.magic);
        errors++;
    } else {
        printf("PASSED (ID=0x%08X, ABI=v%u.%u, Build=0x%08X)\n",
               info.magic, info.abi_version >> 16, info.abi_version & 0xFFFF, info.build_id);
    }

    // Test 2: Soft Reset
    printf("[Test 2/6] Verifying Soft Reset Command... ");
    if (npu_soft_reset(npu) != 0) {
        printf("FAILED\n");
        errors++;
    } else {
        npu_get_info(npu, &info);
        if (info.status != 0) {
            printf("FAILED (Status after reset is 0x%08X)\n", info.status);
            errors++;
        } else {
            printf("PASSED\n");
        }
    }

    // Test 3: Mode 0 Raw GEMM (4x4 Identity * Matrix)
    printf("[Test 3/6] Testing Mode 0 (Raw GEMM 4x4)... ");
    int8_t A[16] = {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    };
    int8_t B[16] = {
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 16
    };
    int32_t C[16];
    npu_perf_t perf;
    int rc = npu_gemm(npu, A, B, C, NULL, 4, 4, 4, NPU_MODE_RAW_GEMM, 1, 0, NULL, &perf);
    if (rc != 0) {
        printf("FAILED (npu_gemm returned %d)\n", rc);
        errors++;
    } else {
        int match = 1;
        for (int i = 0; i < 16; i++) {
            if (C[i] != (int32_t)B[i]) {
                match = 0;
                break;
            }
        }
        if (!match) {
            printf("FAILED (C values do not match expected B)\n");
            errors++;
        } else {
            printf("PASSED (Cycles=%llu, Total time=%.1f us)\n",
                   (unsigned long long)perf.core_cycles, perf.total_time_us);
        }
    }

    // Test 4: Mode 1 Biased INT32 GEMM
    printf("[Test 4/6] Testing Mode 1 (Biased INT32 4x4)... ");
    int32_t bias[4] = {100, 200, 300, 400};
    rc = npu_gemm(npu, A, B, C, NULL, 4, 4, 4, NPU_MODE_BIASED_INT32, 1, 0, bias, &perf);
    if (rc != 0) {
        printf("FAILED (npu_gemm returned %d)\n", rc);
        errors++;
    } else {
        int match = 1;
        for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                int32_t exp = (int32_t)B[i * 4 + j] + bias[j];
                if (C[i * 4 + j] != exp) {
                    match = 0;
                    break;
                }
            }
        }
        if (!match) {
            printf("FAILED (Biased values mismatch)\n");
            errors++;
        } else {
            printf("PASSED (Cycles=%llu)\n", (unsigned long long)perf.core_cycles);
        }
    }

    // Test 5: Mode 2 Requantized INT8 GEMM with ReLU
    printf("[Test 5/6] Testing Mode 2 (Requantized INT8 with ReLU)... ");
    int8_t Y[16];
    int32_t neg_bias[4] = {-6, -6, -6, -6};
    // Input B has [1,2,3,4], [5,6,7,8], ...
    // Mode 2: (B + bias) * mult / (1 << shift)
    // Mult = 1, Shift = 1.
    // For i=0: [1-6, 2-6, 3-6, 4-6] = [-5, -4, -3, -2] -> rounded shift 1 -> [-2, -2, -2, -1] -> ReLU -> [0, 0, 0, 0]
    // For i=1: [5-6, 6-6, 7-6, 8-6] = [-1, 0, 1, 2] -> rounded shift 1 -> [0, 0, 1, 1] -> ReLU -> [0, 0, 1, 1]
    rc = npu_gemm(npu, A, B, C, Y, 4, 4, 4, NPU_MODE_REQUANT_INT8, 1, 1, neg_bias, &perf);
    if (rc != 0) {
        printf("FAILED (npu_gemm returned %d)\n", rc);
        errors++;
    } else {
        if (Y[0] != 0 || Y[1] != 0 || Y[2] != 0 || Y[3] != 0 ||
            Y[4] != 0 || Y[5] != 0 || Y[6] != 1 || Y[7] != 1) {
            printf("FAILED (Unexpected Y outputs: [%d, %d, %d, %d], [%d, %d, %d, %d])\n",
                   Y[0], Y[1], Y[2], Y[3], Y[4], Y[5], Y[6], Y[7]);
            errors++;
        } else {
            printf("PASSED (Cycles=%llu)\n", (unsigned long long)perf.core_cycles);
        }
    }

    // Test 6: Illegal Command Rejection & Error Recovery
    printf("[Test 6/6] Testing Illegal Command Rejection & Recovery... ");
    npu_set_config(npu, 0, 4, 4, 0, 1, 0, NULL); // K=0 is illegal
    rc = npu_run_tile(npu, 999, 100, NULL);
    if (rc != NPU_ERR_INVALID_K) {
        printf("FAILED (Expected error NPU_ERR_INVALID_K, got %d)\n", rc);
        errors++;
    } else {
        // Recover with soft reset
        npu_soft_reset(npu);
        // Run legal tile to verify recovery
        rc = npu_gemm(npu, A, B, C, NULL, 4, 4, 4, NPU_MODE_RAW_GEMM, 1, 0, NULL, &perf);
        if (rc != 0) {
            printf("FAILED (Could not run after error recovery, rc=%d)\n", rc);
            errors++;
        } else {
            printf("PASSED (Correctly rejected K=0 and recovered)\n");
        }
    }

    printf("============================================================\n");
    if (errors == 0) {
        printf("  ALL SELF-TESTS PASSED (0 errors)\n");
        printf("============================================================\n");
        return 0;
    } else {
        printf("  SELF-TEST FAILED WITH %d ERRORS\n", errors);
        printf("============================================================\n");
        return 1;
    }
}

static int run_gemm(npu_t *npu, uint32_t M, uint32_t N, uint32_t K) {
    printf("=== Benchmarking NPU GEMM (%u x %u x %u) ===\n", M, N, K);

    int8_t *A = (int8_t *)malloc(M * K);
    int8_t *B = (int8_t *)malloc(K * N);
    int32_t *C = (int32_t *)malloc(M * N * sizeof(int32_t));
    int32_t *C_golden = (int32_t *)malloc(M * N * sizeof(int32_t));

    if (!A || !B || !C || !C_golden) {
        fprintf(stderr, "Out of memory\n");
        return 1;
    }

    // Fill pseudo-random patterns
    for (uint32_t i = 0; i < M * K; i++) A[i] = (int8_t)((i * 3 + 7) % 25 - 12);
    for (uint32_t i = 0; i < K * N; i++) B[i] = (int8_t)((i * 5 + 11) % 25 - 12);

    // Compute CPU golden reference
    for (uint32_t i = 0; i < M; i++) {
        for (uint32_t j = 0; j < N; j++) {
            int32_t sum = 0;
            for (uint32_t step = 0; step < K; step++) {
                sum += (int32_t)A[i * K + step] * (int32_t)B[step * N + j];
            }
            C_golden[i * N + j] = sum;
        }
    }

    npu_perf_t perf;
    int rc = npu_gemm(npu, A, B, C, NULL, M, N, K, NPU_MODE_RAW_GEMM, 1, 0, NULL, &perf);
    if (rc != 0) {
        fprintf(stderr, "npu_gemm failed with return code %d\n", rc);
        free(A); free(B); free(C); free(C_golden);
        return 1;
    }

    // Check correctness
    int mismatches = 0;
    for (uint32_t i = 0; i < M * N; i++) {
        if (C[i] != C_golden[i]) {
            mismatches++;
        }
    }

    double useful_macs = (double)M * (double)N * (double)K;
    double gops = (2.0 * useful_macs) / (perf.total_time_us * 1e-6) / 1e9;
    double core_gops = (2.0 * useful_macs) / ((double)perf.core_cycles / 250e6) / 1e9;

    printf("Results:\n");
    printf("  Verification     : %s (%d mismatches out of %u)\n",
           (mismatches == 0) ? "EXACT MATCH (PASSED)" : "MISMATCH (FAILED)",
           mismatches, M * N);
    printf("  Useful MACs      : %.0f\n", useful_macs);
    printf("  Core Clock Cycles: %llu\n", (unsigned long long)perf.core_cycles);
    printf("  MMIO Load Time   : %.2f us\n", perf.load_time_us);
    printf("  Execution Time   : %.2f us\n", perf.exec_time_us);
    printf("  MMIO Read Time   : %.2f us\n", perf.read_time_us);
    printf("  Total Host Time  : %.2f us\n", perf.total_time_us);
    printf("  Effective Array Throughput (@250MHz): %.3f GOPS\n", core_gops);
    printf("  System Wall-Clock Throughput        : %.3f GOPS\n", gops);

    free(A); free(B); free(C); free(C_golden);
    return (mismatches == 0) ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    // Create transport (defaults to mock on local machine)
    npu_transport_t *transport = npu_transport_create_mock();
    if (!transport) {
        fprintf(stderr, "Failed to create transport\n");
        return 1;
    }

    npu_t *npu = npu_init(transport, 0);
    if (!npu) {
        fprintf(stderr, "Failed to initialize NPU\n");
        npu_transport_destroy(transport);
        return 1;
    }

    int rc = 0;
    if (strcmp(argv[1], "--info") == 0) {
        rc = run_info(npu);
    } else if (strcmp(argv[1], "--selftest") == 0) {
        rc = run_selftest(npu);
    } else if (strcmp(argv[1], "--gemm") == 0) {
        uint32_t M = (argc > 2) ? (uint32_t)atoi(argv[2]) : 4;
        uint32_t N = (argc > 3) ? (uint32_t)atoi(argv[3]) : 4;
        uint32_t K = (argc > 4) ? (uint32_t)atoi(argv[4]) : 4;
        rc = run_gemm(npu, M, N, K);
    } else {
        print_usage(argv[0]);
        rc = 1;
    }

    npu_close(npu);
    npu_transport_destroy(transport);
    return rc;
}
