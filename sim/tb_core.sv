`timescale 1ns/1ps

module tb_core;
  import npu_pkg::*;

  logic        clk;
  logic        rst_n;

  // Host Register / Control Interface
  logic        start_cmd;
  logic        soft_reset_cmd;
  logic [15:0] cfg_k;
  logic [2:0]  cfg_m_valid;
  logic [2:0]  cfg_n_valid;
  logic [1:0]  cfg_mode;
  logic [31:0] cfg_command_seq;
  logic [31:0] cfg_requant_mult;
  logic [5:0]  cfg_requant_shift;
  int32_t      cfg_bias [4];

  logic        status_busy;
  logic        status_done;
  logic        status_error;
  logic        status_done_w1c;
  logic        status_error_w1c;
  logic [31:0] error_code_out;
  logic [31:0] completed_seq_out;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [63:0] cycle_count_out;
  /* verilator lint_on UNUSEDSIGNAL */

  // Host A Buffer Interface
  logic        a_host_we;
  logic [1:0]  a_host_bank;
  logic [9:0]  a_host_addr;
  logic [31:0] a_host_wdata;
  logic [3:0]  a_host_wstrb;
  logic [1:0]  a_host_rdbank;
  logic [9:0]  a_host_rdaddr;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] a_host_rdata;
  /* verilator lint_on UNUSEDSIGNAL */

  // Host B Buffer Interface
  logic        b_host_we;
  logic [1:0]  b_host_bank;
  logic [9:0]  b_host_addr;
  logic [31:0] b_host_wdata;
  logic [3:0]  b_host_wstrb;
  logic [1:0]  b_host_rdbank;
  logic [9:0]  b_host_rdaddr;
  /* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] b_host_rdata;
  /* verilator lint_on UNUSEDSIGNAL */

  // Host Result Buffer Read Interface
  logic [5:0]  c_host_rd_word_addr;
  logic [31:0] c_host_rdata;
  logic [1:0]  y_host_rd_word_addr;
  logic [31:0] y_host_rdata;

  // Instantiate DUT (npu_core)
  npu_core dut (
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
    .a_host_we            (a_host_we),
    .a_host_bank          (a_host_bank),
    .a_host_addr          (a_host_addr),
    .a_host_wdata         (a_host_wdata),
    .a_host_wstrb         (a_host_wstrb),
    .a_host_rdbank        (a_host_rdbank),
    .a_host_rdaddr        (a_host_rdaddr),
    .a_host_rdata         (a_host_rdata),
    .b_host_we            (b_host_we),
    .b_host_bank          (b_host_bank),
    .b_host_addr          (b_host_addr),
    .b_host_wdata         (b_host_wdata),
    .b_host_wstrb         (b_host_wstrb),
    .b_host_rdbank        (b_host_rdbank),
    .b_host_rdaddr        (b_host_rdaddr),
    .b_host_rdata         (b_host_rdata),
    .c_host_rd_word_addr  (c_host_rd_word_addr),
    .c_host_rdata         (c_host_rdata),
    .y_host_rd_word_addr  (y_host_rd_word_addr),
    .y_host_rdata         (y_host_rdata)
  );

  // Clock Generation (100MHz / 10ns period)
  always #5 clk = ~clk;

  int errors = 0;

  // Helper Tasks
  task automatic do_reset();
    @(negedge clk);
    rst_n             = 0;
    start_cmd         = 0;
    soft_reset_cmd    = 0;
    status_done_w1c   = 0;
    status_error_w1c  = 0;
    a_host_we         = 0;
    b_host_we         = 0;
    a_host_rdbank     = 2'd0;
    a_host_rdaddr     = 10'd0;
    b_host_rdbank     = 2'd0;
    b_host_rdaddr     = 10'd0;
    c_host_rd_word_addr = 6'd0;
    y_host_rd_word_addr = 2'd0;
    repeat (2) @(negedge clk);
    rst_n = 1;
    @(negedge clk);
  endtask

  // Load A row into bank
  task automatic load_a_bank(input logic [1:0] bank, input int k_len, input int8_t data [K_MAX]);
    for (int k = 0; k < k_len; k += 4) begin
      @(negedge clk);
      a_host_we   = 1;
      a_host_bank = bank;
      a_host_addr = 10'(k);
      a_host_wdata = {
        ((k + 3 < k_len) ? uint8_t'(data[k + 3]) : 8'h00),
        ((k + 2 < k_len) ? uint8_t'(data[k + 2]) : 8'h00),
        ((k + 1 < k_len) ? uint8_t'(data[k + 1]) : 8'h00),
        uint8_t'(data[k])
      };
      a_host_wstrb = 4'b1111;
    end
    @(negedge clk);
    a_host_we = 0;
  endtask

  // Load B col into bank
  task automatic load_b_bank(input logic [1:0] bank, input int k_len, input int8_t data [K_MAX]);
    for (int k = 0; k < k_len; k += 4) begin
      @(negedge clk);
      b_host_we   = 1;
      b_host_bank = bank;
      b_host_addr = 10'(k);
      b_host_wdata = {
        ((k + 3 < k_len) ? uint8_t'(data[k + 3]) : 8'h00),
        ((k + 2 < k_len) ? uint8_t'(data[k + 2]) : 8'h00),
        ((k + 1 < k_len) ? uint8_t'(data[k + 1]) : 8'h00),
        uint8_t'(data[k])
      };
      b_host_wstrb = 4'b1111;
    end
    @(negedge clk);
    b_host_we = 0;
  endtask

  // Submit command and wait for completion
  task automatic execute_command(
    input logic [15:0] k,
    input logic [2:0]  m_val,
    input logic [2:0]  n_val,
    input logic [1:0]  mode,
    input logic [31:0] seq,
    input logic [31:0] mult,
    input logic [5:0]  shift,
    input int32_t      bias [4],
    output bit         success
  );
    @(negedge clk);
    cfg_k             = k;
    cfg_m_valid       = m_val;
    cfg_n_valid       = n_val;
    cfg_mode          = mode;
    cfg_command_seq   = seq;
    cfg_requant_mult  = mult;
    cfg_requant_shift = shift;
    for (int b = 0; b < 4; b++) cfg_bias[b] = bias[b];

    start_cmd = 1;
    @(negedge clk);
    start_cmd = 0;

    // Wait for DONE or ERROR
    while (!status_done && !status_error) begin
      @(posedge clk);
    end

    success = status_done;

    // Clear sticky status
    @(negedge clk);
    if (status_done)  status_done_w1c  = 1;
    if (status_error) status_error_w1c = 1;
    @(negedge clk);
    status_done_w1c  = 0;
    status_error_w1c = 0;
  endtask

  int8_t a_data [4][K_MAX];
  int8_t b_data [4][K_MAX];
  int32_t test_bias [4];

  initial begin
    $dumpfile("artifacts/tb_core.fst");
    $dumpvars(0, tb_core);

    clk = 0;
    do_reset();

    $display("--- Step 1: Legal Mode 0 (Raw GEMM) Execution ---");
    // Matrix test (4, 4, 8)
    for (int i = 0; i < 4; i++) begin
      for (int k = 0; k < 8; k++) a_data[i][k] = int8_t'($urandom_range(0, 255) - 128);
      load_a_bank(2'(i), 8, a_data[i]);
    end
    for (int j = 0; j < 4; j++) begin
      for (int k = 0; k < 8; k++) b_data[j][k] = int8_t'($urandom_range(0, 255) - 128);
      load_b_bank(2'(j), 8, b_data[j]);
    end
    for (int b = 0; b < 4; b++) test_bias[b] = 0;

    begin : test_gemm_block
      bit ok;
      execute_command(16'd8, 3'd4, 3'd4, 2'd0, 32'h0001, 32'd1, 6'd0, test_bias, ok);
      if (!ok) begin
        $display("ERROR: Command execution failed unexpectedly!");
        errors++;
      end
      if (completed_seq_out !== 32'h0001) begin
        $display("ERROR: Sequence mismatch! Expected 1, got %0d", completed_seq_out);
        errors++;
      end

      // Check results in C buffer
      for (int i = 0; i < 4; i++) begin
        for (int j = 0; j < 4; j++) begin
          int32_t exp;
          exp = 0;
          for (int k = 0; k < 8; k++) exp += int32_t'($signed(a_data[i][k]) * $signed(b_data[j][k]));

          c_host_rd_word_addr = 6'(i * 4 + j);
          #1;
          if (c_host_rdata !== uint32_t'(exp)) begin
            $display("ERROR: C buffer mismatch at (%0d,%0d)! Expected %0d, got %0d",
                     i, j, exp, int32_t'(c_host_rdata));
            errors++;
          end
        end
      end
    end

    $display("--- Step 2: Partial Tiles & Modes 1 and 2 ---");
    test_bias[0] = 32'sd100;
    test_bias[1] = -32'sd50;
    test_bias[2] = 32'sd25;
    test_bias[3] = 32'sd0;

    for (int i = 0; i < 2; i++) begin
      for (int k = 0; k < 4; k++) a_data[i][k] = int8_t'(k + i);
      load_a_bank(2'(i), 4, a_data[i]);
    end
    for (int j = 0; j < 3; j++) begin
      for (int k = 0; k < 4; k++) b_data[j][k] = int8_t'(k * 2);
      load_b_bank(2'(j), 4, b_data[j]);
    end

    begin : test_mode1_block
      bit ok;
      execute_command(16'd4, 3'd2, 3'd3, 2'd1, 32'h0002, 32'd1, 6'd0, test_bias, ok);
      if (!ok) begin
        $display("ERROR: Mode 1 execution failed!");
        errors++;
      end

      for (int i = 0; i < 2; i++) begin
        for (int j = 0; j < 3; j++) begin
          int32_t exp;
          exp = test_bias[j];
          for (int k = 0; k < 4; k++) exp += int32_t'($signed(a_data[i][k]) * $signed(b_data[j][k]));

          c_host_rd_word_addr = 6'(i * 4 + j);
          #1;
          if (c_host_rdata !== uint32_t'(exp)) begin
            $display("ERROR: Mode 1 C mismatch at (%0d,%0d)! Expected %0d, got %0d",
                     i, j, exp, int32_t'(c_host_rdata));
            errors++;
          end
        end
      end
    end

    // Test Mode 2 (Biased + ReLU + Requant INT8)
    begin : test_mode2_block
      bit ok;
      execute_command(16'd4, 3'd2, 3'd3, 2'd2, 32'h0003, 32'd2, 6'd1, test_bias, ok);
      if (!ok) begin
        $display("ERROR: Mode 2 execution failed!");
        errors++;
      end
      y_host_rd_word_addr = 2'd0;
      #1;
      $display("Mode 2 completed successfully. Y word 0 = 0x%08x", y_host_rdata);
    end

    $display("--- Step 3: Illegal Configuration Rejection ---");
    // Invalid K = 0
    begin : err_k0_block
      bit ok;
      execute_command(16'd0, 3'd4, 3'd4, 2'd0, 32'h0004, 32'd1, 6'd0, test_bias, ok);
      if (ok || error_code_out !== ERR_INVALID_K) begin
        $display("ERROR: Expected ERR_INVALID_K, got %08x", error_code_out);
        errors++;
      end
    end

    // Invalid K = 1025
    begin : err_k1025_block
      bit ok;
      execute_command(16'd1025, 3'd4, 3'd4, 2'd0, 32'h0005, 32'd1, 6'd0, test_bias, ok);
      if (ok || error_code_out !== ERR_INVALID_K) begin
        $display("ERROR: Expected ERR_INVALID_K, got %08x", error_code_out);
        errors++;
      end
    end

    // Invalid M_VALID = 0
    begin : err_m0_block
      bit ok;
      execute_command(16'd4, 3'd0, 3'd4, 2'd0, 32'h0006, 32'd1, 6'd0, test_bias, ok);
      if (ok || error_code_out !== ERR_INVALID_M) begin
        $display("ERROR: Expected ERR_INVALID_M, got %08x", error_code_out);
        errors++;
      end
    end

    // Invalid N_VALID = 5
    begin : err_n5_block
      bit ok;
      execute_command(16'd4, 3'd4, 3'd5, 2'd0, 32'h0007, 32'd1, 6'd0, test_bias, ok);
      if (ok || error_code_out !== ERR_INVALID_N) begin
        $display("ERROR: Expected ERR_INVALID_N, got %08x", error_code_out);
        errors++;
      end
    end

    // Invalid Mode = 3
    begin : err_mode3_block
      bit ok;
      execute_command(16'd4, 3'd4, 3'd4, 2'd3, 32'h0008, 32'd1, 6'd0, test_bias, ok);
      if (ok || error_code_out !== ERR_INVALID_MODE) begin
        $display("ERROR: Expected ERR_INVALID_MODE, got %08x", error_code_out);
        errors++;
      end
    end

    // Invalid Requant Mult = 0 in Mode 2
    begin : err_requant_block
      bit ok;
      execute_command(16'd4, 3'd4, 3'd4, 2'd2, 32'h0009, 32'd0, 6'd0, test_bias, ok);
      if (ok || error_code_out !== ERR_INVALID_REQUANT) begin
        $display("ERROR: Expected ERR_INVALID_REQUANT, got %08x", error_code_out);
        errors++;
      end
    end

    $display("--- Step 4: Soft Reset Abort and Recovery ---");
    cfg_k       = 16'd1024;
    cfg_m_valid = 3'd4;
    cfg_n_valid = 3'd4;
    cfg_mode    = 2'd0;
    start_cmd   = 1;
    @(negedge clk);
    start_cmd   = 0;
    repeat (20) @(posedge clk);
    if (!status_busy) begin
      $display("ERROR: Expected core to be busy during K=1024!");
      errors++;
    end

    // Assert soft_reset
    @(negedge clk);
    soft_reset_cmd = 1;
    @(negedge clk);
    soft_reset_cmd = 0;
    @(posedge clk);
    #1;
    if (status_busy) begin
      $display("ERROR: Core still busy after soft_reset!");
      errors++;
    end

    // Execute a new command to confirm recovery
    begin : recovery_block
      bit ok;
      execute_command(16'd4, 3'd4, 3'd4, 2'd0, 32'h000A, 32'd1, 6'd0, test_bias, ok);
      if (!ok) begin
        $display("ERROR: Core failed to execute new command after soft_reset!");
        errors++;
      end
    end

    if (errors == 0) begin
      $display("=================================================");
      $display("  ALL NPU CORE & TILE CONTROLLER TESTS PASSED!");
      $display("  Milestone M3 Gate G3: SUCCESS");
      $display("=================================================");
      $finish;
    end else begin
      $fatal(1, "NPU Core Verification FAILED with %0d errors!", errors);
    end
  end

endmodule
