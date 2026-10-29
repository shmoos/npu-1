// Delay lane i by i enabled clock edges. Pauses freeze every delay register.
module skew_feeder (
  input  logic        clk,
  input  logic        reset,
  input  logic        clear,
  input  logic        step,
  input  logic [31:0] data_in,
  input  logic [3:0]  valid_in,
  output logic [31:0] data_out,
  output logic [3:0]  valid_out
);
  for (genvar lane = 0; lane < 4; lane++) begin : g_lane
    if (lane == 0) begin : g_direct
      assign data_out[lane*8 +: 8] = data_in[lane*8 +: 8];
      assign valid_out[lane] = valid_in[lane] && !clear && !reset;
    end else begin : g_delayed
      logic [7:0] data_pipe [lane];
      logic valid_pipe [lane];
      always_ff @(posedge clk) begin
        if (reset || clear) begin
          for (int d = 0; d < lane; d++) begin
            data_pipe[d] <= 8'd0;
            valid_pipe[d] <= 1'b0;
          end
        end else if (step) begin
          data_pipe[0] <= data_in[lane*8 +: 8];
          valid_pipe[0] <= valid_in[lane];
          for (int d = 1; d < lane; d++) begin
            data_pipe[d] <= data_pipe[d-1];
            valid_pipe[d] <= valid_pipe[d-1];
          end
        end
      end
      assign data_out[lane*8 +: 8] = data_pipe[lane-1];
      assign valid_out[lane] = valid_pipe[lane-1] && !clear && !reset;
    end
  end
endmodule
