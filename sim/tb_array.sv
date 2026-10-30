`timescale 1ns/1ps

module tb_array;
  import npu_pkg::*;

  logic   clk;
  logic   rst_n;
  logic   clear;
  logic   step;

  int8_t  a_unskewed    [ARRAY_M];
  logic   a_valid_raw   [ARRAY_M];
  int8_t  b_unskewed    [ARRAY_N];
  logic   b_valid_raw   [ARRAY_N];

  int8_t  a_skewed      [ARRAY_M];
  logic   a_valid_skewed[ARRAY_M];
  int8_t  b_skewed      [ARRAY_N];
  logic   b_valid_skewed[ARRAY_N];

  int32_t acc_out       [ARRAY_M][ARRAY_N];

  // Instantiate Skew Feeder
  skew_feeder feeder_inst (
    .clk           (clk),
    .rst_n         (rst_n),
    .clear         (clear),
    .step          (step),
    .a_unskewed    (a_unskewed),
    .a_valid_raw   (a_valid_raw),
    .b_unskewed    (b_unskewed),
    .b_valid_raw   (b_valid_raw),
    .a_skewed      (a_skewed),
    .a_valid_skewed(a_valid_skewed),
    .b_skewed      (b_skewed),
    .b_valid_skewed(b_valid_skewed)
  );

  // Instantiate 4x4 Systolic Array
  systolic_array_4x4 array_inst (
    .clk           (clk),
    .rst_n         (rst_n),
    .clear         (clear),
    .step          (step),
    .a_skewed      (a_skewed),
    .a_valid_skewed(a_valid_skewed),
    .b_skewed      (b_skewed),
    .b_valid_skewed(b_valid_skewed),
    .acc_out       (acc_out)
  );

  // Clock generation (100MHz / 10ns period)
  // Behavioral testbench clock; blocking assignment is intentional.
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  int errors = 0;

  task automatic do_reset();
    @(negedge clk);
    rst_n = 0;
    clear = 0;
    step  = 1;
    for (int i = 0; i < ARRAY_M; i++) begin
      a_unskewed[i]  = 0;
      a_valid_raw[i] = 0;
    end
    for (int j = 0; j < ARRAY_N; j++) begin
      b_unskewed[j]  = 0;
      b_valid_raw[j] = 0;
    end
    repeat (2) @(negedge clk);
    rst_n = 1;
    @(negedge clk);
  endtask

  task automatic do_clear();
    @(negedge clk);
    clear = 1;
    for (int i = 0; i < ARRAY_M; i++) a_valid_raw[i] = 0;
    for (int j = 0; j < ARRAY_N; j++) b_valid_raw[j] = 0;
    @(negedge clk);
    clear = 0;
  endtask

  // Feeds a 4xK and Kx4 tile, runs K+6 steps, checks results
  task automatic run_tile(
    input int k_len,
    input int8_t a_mat [ARRAY_M][K_MAX],
    input int8_t b_mat [K_MAX][ARRAY_N],
    input bit pause_test = 0
  );
    int32_t expected [ARRAY_M][ARRAY_N];

    // Calculate golden output
    for (int i = 0; i < ARRAY_M; i++) begin
      for (int j = 0; j < ARRAY_N; j++) begin
        expected[i][j] = 0;
        for (int k = 0; k < k_len; k++) begin
          expected[i][j] += int32_t'($signed(a_mat[i][k]) * $signed(b_mat[k][j]));
        end
      end
    end

    do_clear();

    // Stream inputs for K cycles
    for (int k = 0; k < k_len; k++) begin
      if (pause_test && k == (k_len / 2)) begin
        @(negedge clk);
        step = 0; // Pause array
        repeat (3) @(negedge clk);
      end

      @(negedge clk);
      step = 1;
      for (int i = 0; i < ARRAY_M; i++) begin
        a_unskewed[i]  = a_mat[i][k];
        a_valid_raw[i] = 1'b1;
      end
      for (int j = 0; j < ARRAY_N; j++) begin
        b_unskewed[j]  = b_mat[k][j];
        b_valid_raw[j] = 1'b1;
      end
    end

    // Deassert valid inputs; drain for 6 cycles to flush through skew and array
    for (int drain = 0; drain < 6; drain++) begin
      @(negedge clk);
      step = 1;
      for (int i = 0; i < ARRAY_M; i++) a_valid_raw[i] = 1'b0;
      for (int j = 0; j < ARRAY_N; j++) b_valid_raw[j] = 1'b0;
    end

    // Wait for the final clock edge to commit the last PE (3,3) update
    @(posedge clk);
    #1;

    // Check all 16 accumulators
    for (int i = 0; i < ARRAY_M; i++) begin
      for (int j = 0; j < ARRAY_N; j++) begin
        if (acc_out[i][j] !== expected[i][j]) begin
          $display("ERROR at PE(%0d,%0d) for K=%0d! Expected %0d, got %0d",
                   i, j, k_len, expected[i][j], acc_out[i][j]);
          errors++;
        end
      end
    end
  endtask

  int8_t a_test [ARRAY_M][K_MAX];
  int8_t b_test [K_MAX][ARRAY_N];

  initial begin
    $dumpfile("artifacts/tb_array.fst");
    $dumpvars(0, tb_array);

    clk = 0;
    do_reset();

    $display("--- Step 1: Directed Matrices (Identity, Zeros, Extremes, Asymmetric) ---");
    // 1. Identity 4x4
    for (int i = 0; i < 4; i++) begin
      for (int k = 0; k < 4; k++) a_test[i][k] = (i == k) ? 8'sd1 : 8'sd0;
    end
    for (int k = 0; k < 4; k++) begin
      for (int j = 0; j < 4; j++) b_test[k][j] = (k == j) ? 8'sd1 : 8'sd0;
    end
    run_tile(4, a_test, b_test);

    // 2. All zeros
    for (int i = 0; i < 4; i++) for (int k = 0; k < 4; k++) a_test[i][k] = 8'sd0;
    for (int k = 0; k < 4; k++) for (int j = 0; j < 4; j++) b_test[k][j] = 8'sd0;
    run_tile(4, a_test, b_test);

    // 3. All ones
    for (int i = 0; i < 4; i++) for (int k = 0; k < 4; k++) a_test[i][k] = 8'sd1;
    for (int k = 0; k < 4; k++) for (int j = 0; j < 4; j++) b_test[k][j] = 8'sd1;
    run_tile(4, a_test, b_test);

    // 4. Signed Extremes (-128)
    for (int i = 0; i < 4; i++) for (int k = 0; k < 4; k++) a_test[i][k] = -8'sd128;
    for (int k = 0; k < 4; k++) for (int j = 0; j < 4; j++) b_test[k][j] = -8'sd128;
    run_tile(4, a_test, b_test);

    // 5. Asymmetric Transpose Exposure
    for (int i = 0; i < 4; i++) begin
      for (int k = 0; k < 4; k++) a_test[i][k] = int8_t'(i * 10 + k);
    end
    for (int k = 0; k < 4; k++) begin
      for (int j = 0; j < 4; j++) b_test[k][j] = int8_t'(k * 2 - j);
    end
    run_tile(4, a_test, b_test);

    $display("--- Step 2: K Parameter Sweep ---");
    begin : k_sweep_block
      static int k_sweep [12] = '{1, 2, 3, 4, 7, 8, 15, 16, 31, 32, 64, 255};
      for (int s = 0; s < 12; s++) begin
        static int cur_k;
        cur_k = k_sweep[s];
        for (int i = 0; i < 4; i++) begin
          for (int k = 0; k < cur_k; k++) begin
            a_test[i][k] = int8_t'($urandom_range(0, 255) - 128);
          end
        end
        for (int k = 0; k < cur_k; k++) begin
          for (int j = 0; j < 4; j++) begin
            b_test[k][j] = int8_t'($urandom_range(0, 255) - 128);
          end
        end
        run_tile(cur_k, a_test, b_test);
      end
    end

    $display("--- Step 3: Pause and Resume (step=0) Test ---");
    for (int i = 0; i < 4; i++) begin
      for (int k = 0; k < 16; k++) a_test[i][k] = int8_t'($urandom_range(0, 255) - 128);
    end
    for (int k = 0; k < 16; k++) begin
      for (int j = 0; j < 4; j++) b_test[k][j] = int8_t'($urandom_range(0, 255) - 128);
    end
    run_tile(16, a_test, b_test, 1); // pause_test = 1

    $display("--- Step 4: Back-to-Back Consecutive Tiles ---");
    // Tile 1
    for (int i = 0; i < 4; i++) for (int k = 0; k < 8; k++) a_test[i][k] = 8'sd10;
    for (int k = 0; k < 8; k++) for (int j = 0; j < 4; j++) b_test[k][j] = 8'sd2;
    run_tile(8, a_test, b_test);
    // Tile 2 immediately after
    for (int i = 0; i < 4; i++) for (int k = 0; k < 8; k++) a_test[i][k] = -8'sd5;
    for (int k = 0; k < 8; k++) for (int j = 0; j < 4; j++) b_test[k][j] = 8'sd3;
    run_tile(8, a_test, b_test);

    $display("--- Step 5: Large K Test (K = 1024) ---");
    for (int i = 0; i < 4; i++) begin
      for (int k = 0; k < 1024; k++) a_test[i][k] = int8_t'($urandom_range(0, 255) - 128);
    end
    for (int k = 0; k < 1024; k++) begin
      for (int j = 0; j < 4; j++) b_test[k][j] = int8_t'($urandom_range(0, 255) - 128);
    end
    run_tile(1024, a_test, b_test);

    if (errors == 0) begin
      $display("=================================================");
      $display("  ALL 4x4 SYSTOLIC ARRAY TESTS PASSED!");
      $display("  Milestone M2 Gate G2: SUCCESS");
      $display("=================================================");
      $finish;
    end else begin
      $fatal(1, "4x4 Systolic Array Verification FAILED with %0d errors!", errors);
    end
  end

endmodule
