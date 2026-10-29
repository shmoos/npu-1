`timescale 1ns/1ps

/* verilator lint_off UNUSEDPARAM */
package npu_pkg;

  // Array Dimensions
  localparam int ARRAY_M = 4;
  localparam int ARRAY_N = 4;
  localparam int K_MAX   = 1024;

  // Data Types
  typedef logic signed [7:0]   int8_t;
  typedef logic signed [15:0]  int16_t;
  typedef logic signed [31:0]  int32_t;
  typedef logic signed [63:0]  int64_t;

  typedef logic [7:0]          uint8_t;
  typedef logic [15:0]         uint16_t;
  typedef logic [31:0]         uint32_t;
  typedef logic [63:0]         uint64_t;

  // Identification & ABI
  localparam logic [31:0] NPU_ID_MAGIC    = 32'h4e505531; // "NPU1"
  localparam logic [31:0] NPU_ABI_VERSION = 32'h00010000; // v1.0
  localparam logic [31:0] NPU_BUILD_ID    = 32'h20261029; // 2026-10-29

  // Modes
  typedef enum logic [1:0] {
    MODE_RAW_GEMM     = 2'b00,
    MODE_BIASED_INT32 = 2'b01,
    MODE_REQUANT_INT8 = 2'b10
  } npu_mode_e;

  // Error Codes
  typedef enum logic [31:0] {
    ERR_NONE             = 32'h00000000,
    ERR_INVALID_K        = 32'h00000001,
    ERR_INVALID_M        = 32'h00000002,
    ERR_INVALID_N        = 32'h00000003,
    ERR_INVALID_MODE     = 32'h00000004,
    ERR_BUSY_VIOLATION   = 32'h00000005,
    ERR_WATCHDOG_TIMEOUT = 32'h00000006,
    ERR_INVALID_REQUANT  = 32'h00000007,
    ERR_UNMAPPED_ACCESS  = 32'h00000008
  } npu_error_e;

  // Status Register Bit Masks
  localparam logic [31:0] STATUS_BUSY_MASK  = 32'h00000001;
  localparam logic [31:0] STATUS_DONE_MASK  = 32'h00000002;
  localparam logic [31:0] STATUS_ERROR_MASK = 32'h00000004;

  // Control Register Bit Masks
  localparam logic [31:0] CONTROL_START_MASK      = 32'h00000001;
  localparam logic [31:0] CONTROL_SOFT_RESET_MASK = 32'h00000002;

  // Memory Base Addresses
  localparam logic [15:0] ADDR_A_BUFFER_BASE = 16'h1000;
  localparam logic [15:0] ADDR_B_BUFFER_BASE = 16'h2000;
  localparam logic [15:0] ADDR_C_BUFFER_BASE = 16'h3000;
  localparam logic [15:0] ADDR_Y_BUFFER_BASE = 16'h3100;

endpackage: npu_pkg
/* verilator lint_on UNUSEDPARAM */
