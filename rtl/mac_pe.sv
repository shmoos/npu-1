`timescale 1ns/1ps

module mac_pe
  import npu_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,
  input  logic        step,

  // Operands in
  input  int8_t       a_in,
  input  int8_t       b_in,
  input  logic        a_valid,
  input  logic        b_valid,

  // Forwarded operands out (one cycle register delay)
  output int8_t       a_out,
  output int8_t       b_out,
  output logic        a_valid_out,
  output logic        b_valid_out,

  // Accumulated sum
  output int32_t      acc_out
);

  // Combinational product
  int16_t product;
  int32_t product_ext;

  assign product     = $signed(a_in) * $signed(b_in);
  assign product_ext = {{16{product[15]}}, product};

  // Clocked register process
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      acc_out     <= 32'sd0;
      a_out       <= 8'sd0;
      b_out       <= 8'sd0;
      a_valid_out <= 1'b0;
      b_valid_out <= 1'b0;
    end else if (clear) begin
      acc_out     <= 32'sd0;
      a_out       <= 8'sd0;
      b_out       <= 8'sd0;
      a_valid_out <= 1'b0;
      b_valid_out <= 1'b0;
    end else if (step) begin
      // Forward operands and validity flags
      a_out       <= a_in;
      b_out       <= b_in;
      a_valid_out <= a_valid;
      b_valid_out <= b_valid;

      // Accumulate only if both operands are valid
      if (a_valid && b_valid) begin
        acc_out <= acc_out + product_ext;
      end
    end
    // else step == 0: hold all internal state
  end

// synthesis translate_off
  assert property (@(posedge clk) disable iff (!rst_n)
    (!clear && !step) |=> $stable({acc_out,a_out,b_out,a_valid_out,b_valid_out}));
  assert property (@(posedge clk) disable iff (!rst_n)
    (!clear && step && !(a_valid && b_valid)) |=> $stable(acc_out));
  assert property (@(posedge clk) (!rst_n || clear) |=> acc_out == 0);
  // synthesis translate_on
endmodule
