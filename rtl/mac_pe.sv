// NPU-1 v0.1: fixed signed INT8 multiply / INT32 accumulate.
// Priority: synchronous reset > clear > step > hold.
module mac_pe (
  input  logic               clk,
  input  logic               reset,
  input  logic               clear,
  input  logic               step,
  input  logic signed [7:0]  a_in,
  input  logic signed [7:0]  b_in,
  input  logic               a_valid,
  input  logic               b_valid,
  output logic signed [7:0]  a_out,
  output logic signed [7:0]  b_out,
  output logic               a_valid_out,
  output logic               b_valid_out,
  output logic signed [31:0] acc
);
  logic signed [15:0] product;
  logic signed [31:0] product_ext;
  logic signed [32:0] checked_sum;

  assign product = $signed(a_in) * $signed(b_in);
  assign product_ext = {{16{product[15]}}, product};
  assign checked_sum = {acc[31], acc} + {product_ext[31], product_ext};

  always_ff @(posedge clk) begin
    if (reset || clear) begin
      acc         <= 32'sd0;
      a_out       <= 8'sd0;
      b_out       <= 8'sd0;
      a_valid_out <= 1'b0;
      b_valid_out <= 1'b0;
    end else if (step) begin
      a_out       <= a_in;
      b_out       <= b_in;
      a_valid_out <= a_valid;
      b_valid_out <= b_valid;
      if (a_valid && b_valid)
        acc <= checked_sum[31:0];
    end
  end

  // These properties document the protocol and are enabled by --assert.
  // synthesis translate_off
  assert property (@(posedge clk) disable iff (reset)
    clear |-> (!a_valid && !b_valid))
    else $fatal(1, "PE_CLEAR_WITH_VALID");

  assert property (@(posedge clk)
    (reset || clear) |=>
      (acc == 0 && a_out == 0 && b_out == 0 &&
       !a_valid_out && !b_valid_out))
    else $fatal(1, "PE_RESET_OR_CLEAR_FAILED");

  assert property (@(posedge clk) disable iff (reset)
    (!clear && !step) |=>
      $stable({acc, a_out, b_out, a_valid_out, b_valid_out}))
    else $fatal(1, "PE_HOLD_FAILED");

  assert property (@(posedge clk) disable iff (reset)
    (!clear && step && !(a_valid && b_valid)) |=> $stable(acc))
    else $fatal(1, "PE_INVALID_ACCUMULATED");

  assert property (@(posedge clk) disable iff (reset)
    (!clear && step) |=>
      (a_out == $past(a_in) && b_out == $past(b_in) &&
       a_valid_out == $past(a_valid) && b_valid_out == $past(b_valid)))
    else $fatal(1, "PE_FORWARD_FAILED");

  assert property (@(posedge clk) disable iff (reset)
    (!clear && step && a_valid && b_valid) |->
      (checked_sum[32] == checked_sum[31]))
    else $fatal(1, "PE_ACCUMULATOR_OVERFLOW");
  // synthesis translate_on
endmodule
