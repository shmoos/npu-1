`timescale 1ns/1ps

module systolic_array_4x4
  import npu_pkg::*;
#(parameter int ROWS = 4, COLS = 4)
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        step,

  // Skewed inputs (Row 0..3 from left, Col 0..3 from top)
  input  int8_t       a_skewed     [ROWS],
  input  logic        a_valid_skewed [ROWS],

  input  int8_t       b_skewed     [COLS],
  input  logic        b_valid_skewed [COLS],

  // 16 Accumulator outputs
  output int32_t      acc_out      [ROWS][COLS]
);

  // Inter-PE interconnects
  int8_t a_pipe      [ROWS][COLS];
  logic  a_valid_pipe[ROWS][COLS];

  int8_t b_pipe      [ROWS][COLS];
  logic  b_valid_pipe[ROWS][COLS];

  genvar i, j;
  generate
    for (i = 0; i < ROWS; i++) begin: gen_rows
      for (j = 0; j < COLS; j++) begin: gen_cols

        // Wire A inputs
        int8_t a_in_local;
        logic  a_valid_local;
        if (j == 0) begin: gen_a_left
          assign a_in_local    = a_skewed[i];
          assign a_valid_local = a_valid_skewed[i];
        end else begin: gen_a_hop
          assign a_in_local    = a_pipe[i][j-1];
          assign a_valid_local = a_valid_pipe[i][j-1];
        end

        // Wire B inputs
        int8_t b_in_local;
        logic  b_valid_local;
        if (i == 0) begin: gen_b_top
          assign b_in_local    = b_skewed[j];
          assign b_valid_local = b_valid_skewed[j];
        end else begin: gen_b_hop
          assign b_in_local    = b_pipe[i-1][j];
          assign b_valid_local = b_valid_pipe[i-1][j];
        end

        // Instantiate Processing Element
        mac_pe pe_inst (
          .clk        (clk),
          .rst_n      (rst_n),
          .clear      (clear),
          .step       (step),
          .a_in       (a_in_local),
          .b_in       (b_in_local),
          .a_valid    (a_valid_local),
          .b_valid    (b_valid_local),
          .a_out      (a_pipe[i][j]),
          .b_out      (b_pipe[i][j]),
          .a_valid_out(a_valid_pipe[i][j]),
          .b_valid_out(b_valid_pipe[i][j]),
          .acc_out    (acc_out[i][j])
        );

      end
    end
  endgenerate

endmodule
