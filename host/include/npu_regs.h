#ifndef NPU_REGS_H
#define NPU_REGS_H

#include <stdint.h>

// Identification
#define NPU_REG_ID                0x0000
#define NPU_REG_ABI_VERSION       0x0004
#define NPU_ID_MAGIC_EXPECTED     0x4E505531  // "NPU1"
#define NPU_ABI_VERSION_EXPECTED  0x00010000  // v1.0

// Control & Status
#define NPU_REG_CONTROL           0x0008
#define NPU_REG_STATUS            0x000C

#define NPU_CTRL_START            (1u << 0)
#define NPU_CTRL_SOFT_RESET       (1u << 1)

#define NPU_STATUS_BUSY           (1u << 0)
#define NPU_STATUS_DONE           (1u << 1)
#define NPU_STATUS_ERROR          (1u << 2)

// Configuration Registers
#define NPU_REG_K                 0x0010
#define NPU_REG_M_VALID           0x0014
#define NPU_REG_N_VALID           0x0018
#define NPU_REG_MODE              0x001C

#define NPU_MODE_RAW_GEMM         0
#define NPU_MODE_BIASED_INT32     1
#define NPU_MODE_REQUANT_INT8     2

// Diagnostics & Counters
#define NPU_REG_CYCLES_LO         0x0020
#define NPU_REG_CYCLES_HI         0x0024
#define NPU_REG_ERROR_CODE        0x0028
#define NPU_REG_COMMAND_SEQ       0x002C
#define NPU_REG_COMPLETED_SEQ     0x0030

// Post-Processing & Build ID
#define NPU_REG_REQUANT_MULT      0x0034
#define NPU_REG_REQUANT_SHIFT     0x0038
#define NPU_REG_BUILD_ID          0x003C
#define NPU_REG_BIAS(col)         (0x0040 + ((col) * 4))

// Memory Base Addresses
#define NPU_MEM_A_BUFFER_BASE     0x1000  // 4 banks * 1024 bytes = 4096 bytes
#define NPU_MEM_B_BUFFER_BASE     0x2000  // 4 banks * 1024 bytes = 4096 bytes
#define NPU_MEM_C_BUFFER_BASE     0x3000  // 16 words * 4 bytes   = 64 bytes
#define NPU_MEM_Y_BUFFER_BASE     0x3100  // 4 words  * 4 bytes   = 16 bytes

// Error Code Enumerations
typedef enum {
    NPU_ERR_NONE             = 0x00000000,
    NPU_ERR_INVALID_K        = 0x00000001,
    NPU_ERR_INVALID_M        = 0x00000002,
    NPU_ERR_INVALID_N        = 0x00000003,
    NPU_ERR_INVALID_MODE     = 0x00000004,
    NPU_ERR_BUSY_VIOLATION   = 0x00000005,
    NPU_ERR_WATCHDOG_TIMEOUT = 0x00000006,
    NPU_ERR_INVALID_REQUANT  = 0x00000007,
    NPU_ERR_UNMAPPED_ACCESS  = 0x00000008
} npu_error_t;

#endif // NPU_REGS_H
