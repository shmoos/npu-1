`timescale 1ns/1ps

module npu_core
  import npu_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // Host Register / Control Interface
  input  logic        start_cmd,
  input  logic        soft_reset_cmd,
  input  logic [15:0] cfg_k,
  input  logic [2:0]  cfg_m_valid,
  input  logic [2:0]  cfg_n_valid,
  input  logic [1:0]  cfg_mode,
  input  logic [31:0] cfg_command_seq,
  input  logic [31:0] cfg_requant_mult,
  input  logic [5:0]  cfg_requant_shift,
  input  int32_t      cfg_bias [4],

  output logic        status_busy,
  output logic        status_done,
  output logic        status_error,
  input  logic        status_done_w1c,
  input  logic        status_error_w1c,
  output logic [31:0] error_code_out,
  output logic [31:0] completed_seq_out,
  output logic [63:0] cycle_count_out,

  // Host A Buffer Interface
  input  logic        a_host_we,
  input  logic [1:0]  a_host_bank,
  input  logic [9:0]  a_host_addr,
  input  logic [31:0] a_host_wdata,
  input  logic [3:0]  a_host_wstrb,
  input  logic [1:0]  a_host_rdbank,
  input  logic [9:0]  a_host_rdaddr,
  output logic [31:0] a_host_rdata,

  // Host B Buffer Interface
  input  logic        b_host_we,
  input  logic [1:0]  b_host_bank,
  input  logic [9:0]  b_host_addr,
  input  logic [31:0] b_host_wdata,
  input  logic [3:0]  b_host_wstrb,
  input  logic [1:0]  b_host_rdbank,
  input  logic [9:0]  b_host_rdaddr,
  output logic [31:0] b_host_rdata,

  // Host Result Buffer Read Interface
  input  logic [5:0]  c_host_rd_word_addr,
  output logic [31:0] c_host_rdata,
  input  logic [1:0]  y_host_rd_word_addr,
  output logic [31:0] y_host_rdata
);

  // Buffer Compute Read Signals
  logic        buf_compute_re;
  logic [9:0]  buf_k_addr;
  int8_t       a_compute_data [4];
  int8_t       b_compute_data [4];

  // Controller to Feeder / Array Signals
  logic        array_clear;
  logic        array_step;
  logic        a_valid_feeder [4];
  logic        b_valid_feeder [4];

  // Skew Feeder to Systolic Array Signals
  int8_t       a_skewed [4];
  logic        a_valid_skewed [4];
  int8_t       b_skewed [4];
  logic        b_valid_skewed [4];

  // Array Accumulators to Controller / Post-Processor
  int32_t      array_acc [4][4];

  // Post-Processor Signals
  logic        post_valid_in;
  int32_t      post_acc_in;
  int32_t      post_bias_in;
  npu_mode_e   post_mode_in;
  logic [31:0] post_mult_in;
  logic [5:0]  post_shift_in;

  logic        post_valid_out;
  int32_t      post_c_out;
  int8_t       post_y_out;

  // Result Buffer Store Signals
  logic        result_store_en;
  logic [1:0]  result_store_row;
  logic [1:0]  result_store_col;

  // Internal Synchronous Reset for Abort / Soft Reset
  logic core_rst_n;
  assign core_rst_n = rst_n && !soft_reset_cmd;

  // 1. Operand Buffer A (Activation Banks)
  operand_buffer buf_a_inst (
    .clk           (clk),
    .rst_n         (rst_n),
    .host_we       (a_host_we),
    .host_bank     (a_host_bank),
    .host_addr     (a_host_addr),
    .host_wdata    (a_host_wdata),
    .host_wstrb    (a_host_wstrb),
    .host_rdbank   (a_host_rdbank),
    .host_rdaddr   (a_host_rdaddr),
    .host_rdata    (a_host_rdata),
    .compute_re    (buf_compute_re),
    .compute_k_addr(buf_k_addr),
    .compute_data  (a_compute_data)
  );

  // 2. Operand Buffer B (Weight Banks)
  operand_buffer buf_b_inst (
    .clk           (clk),
    .rst_n         (rst_n),
    .host_we       (b_host_we),
    .host_bank     (b_host_bank),
    .host_addr     (b_host_addr),
    .host_wdata    (b_host_wdata),
    .host_wstrb    (b_host_wstrb),
    .host_rdbank   (b_host_rdbank),
    .host_rdaddr   (b_host_rdaddr),
    .host_rdata    (b_host_rdata),
    .compute_re    (buf_compute_re),
    .compute_k_addr(buf_k_addr),
    .compute_data  (b_compute_data)
  );

  // 3. Skew Feeder
  skew_feeder feeder_inst (
    .clk           (clk),
    .rst_n         (core_rst_n),
    .clear         (array_clear),
    .step          (array_step),
    .a_unskewed    (a_compute_data),
    .a_valid_raw   (a_valid_feeder),
    .b_unskewed    (b_compute_data),
    .b_valid_raw   (b_valid_feeder),
    .a_skewed      (a_skewed),
    .a_valid_skewed(a_valid_skewed),
    .b_skewed      (b_skewed),
    .b_valid_skewed(b_valid_skewed)
  );

  // 4. 4x4 Systolic Array
  systolic_array_4x4 array_inst (
    .clk           (clk),
    .rst_n         (core_rst_n),
    .clear         (array_clear),
    .step          (array_step),
    .a_skewed      (a_skewed),
    .a_valid_skewed(a_valid_skewed),
    .b_skewed      (b_skewed),
    .b_valid_skewed(b_valid_skewed),
    .acc_out       (array_acc)
  );

  // 5. Post-Processor
  postprocess post_inst (
    .clk          (clk),
    .rst_n        (core_rst_n),
    .valid_in     (post_valid_in),
    .acc_in       (post_acc_in),
    .bias_in      (post_bias_in),
    .mode_in      (post_mode_in),
    .requant_mult (post_mult_in),
    .requant_shift(post_shift_in),
    .valid_out    (post_valid_out),
    .c_out        (post_c_out),
    .y_out        (post_y_out)
  );

  // 6. Result Buffer
  result_buffer result_buf_inst (
    .clk               (clk),
    .rst_n             (rst_n),
    .store_en          (result_store_en && !soft_reset_cmd),
    .store_row         (result_store_row),
    .store_col         (result_store_col),
    .c_data_in         (post_c_out),
    .y_data_in         (post_y_out),
    .c_rd_word_addr    (c_host_rd_word_addr),
    .c_host_rdata      (c_host_rdata),
    .y_rd_word_addr    (y_host_rd_word_addr),
    .y_host_rdata      (y_host_rdata)
  );

  // 7. Tile Controller
  tile_controller ctrl_inst (
    .clk                  (clk),
    .rst_n                (rst_n),
    .start_cmd            (start_cmd),
    .soft_reset_cmd       (soft_reset_cmd),
    .cfg_k                (cfg_k),
    .cfg_m_valid          (cfg_m_valid),
    .cfg_n_valid          (cfg_n_valid),
    .cfg_mode             (cfg_mode),
    .cfg_command_seq      (cfg_command_seq),
    .cfg_requant_mult     (cfg_requant_mult),
    .cfg_requant_shift    (cfg_requant_shift),
    .cfg_bias             (cfg_bias),
    .status_busy          (status_busy),
    .status_done          (status_done),
    .status_error         (status_error),
    .status_done_w1c      (status_done_w1c),
    .status_error_w1c     (status_error_w1c),
    .error_code_out       (error_code_out),
    .completed_seq_out    (completed_seq_out),
    .cycle_count_out      (cycle_count_out),
    .buf_compute_re       (buf_compute_re),
    .buf_k_addr           (buf_k_addr),
    .array_clear          (array_clear),
    .array_step           (array_step),
    .a_valid_feeder       (a_valid_feeder),
    .b_valid_feeder       (b_valid_feeder),
    .post_valid_in        (post_valid_in),
    .post_acc_in          (post_acc_in),
    .post_bias_in         (post_bias_in),
    .post_mode_in         (post_mode_in),
    .post_mult_in         (post_mult_in),
    .post_shift_in        (post_shift_in),
    .result_store_en      (result_store_en),
    .result_store_row     (result_store_row),
    .result_store_col     (result_store_col),
    .array_acc_in         (array_acc),
    .post_valid_out       (post_valid_out)
  );

endmodule
