module tb_toolchain_smoke;
  timeunit 1ns;
  timeprecision 1ps;
  logic clk;
  logic reset;
  logic [7:0] count;
  int unsigned expected;

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  always_ff @(posedge clk) begin
    if (reset) count <= 8'd0;
    else count <= count + 8'd1;
  end

  initial begin
    reset = 1'b1;
    expected = $test$plusargs("inject_failure") ? 5 : 4;
    $dumpfile("smoke.vcd");
    $dumpvars(0, tb_toolchain_smoke);
    repeat (2) @(negedge clk);
    if (count !== 8'd0) $fatal(1, "SMOKE_RESET_FAILED");
    reset = 1'b0;
    repeat (4) @(negedge clk);
    if ({24'b0, count} != expected)
      $fatal(1, "SMOKE_COUNTER_MISMATCH expected=%0d actual=%0d", expected, count);
    $display("PASS: toolchain smoke, clock/reset/count=4");
    $finish;
  end

  initial begin
    #200ns;
    $fatal(1, "SMOKE_TIMEOUT");
  end
endmodule
