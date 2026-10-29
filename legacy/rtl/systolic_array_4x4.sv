// Aligned input step k supplies A[0:3,k] and B[k,0:3]. Skew is internal.
module systolic_array_4x4 (
  input  logic         clk,
  input  logic         reset,
  input  logic         clear,
  input  logic         step,
  input  logic [31:0]  a_in,
  input  logic [31:0]  b_in,
  input  logic [3:0]   a_valid,
  input  logic [3:0]   b_valid,
  output logic [511:0] accumulators,
  output logic [31:0]  a_out,
  output logic [31:0]  b_out,
  output logic [3:0]   a_valid_out,
  output logic [3:0]   b_valid_out
);
  logic [31:0] a_skewed, b_skewed;
  logic [3:0] a_skewed_valid, b_skewed_valid;
  logic signed [7:0] a_link [4][5];
  logic signed [7:0] b_link [5][4];
  logic av_link [4][5];
  logic bv_link [5][4];

  skew_feeder a_feeder (
    .clk, .reset, .clear, .step, .data_in(a_in), .valid_in(a_valid),
    .data_out(a_skewed), .valid_out(a_skewed_valid)
  );
  skew_feeder b_feeder (
    .clk, .reset, .clear, .step, .data_in(b_in), .valid_in(b_valid),
    .data_out(b_skewed), .valid_out(b_skewed_valid)
  );

  for (genvar lane = 0; lane < 4; lane++) begin : g_edges
    assign a_link[lane][0] = a_skewed[lane*8 +: 8];
    assign av_link[lane][0] = a_skewed_valid[lane];
    assign b_link[0][lane] = b_skewed[lane*8 +: 8];
    assign bv_link[0][lane] = b_skewed_valid[lane];
    assign a_out[lane*8 +: 8] = a_link[lane][4];
    assign a_valid_out[lane] = av_link[lane][4];
    assign b_out[lane*8 +: 8] = b_link[4][lane];
    assign b_valid_out[lane] = bv_link[4][lane];
  end

  for (genvar row = 0; row < 4; row++) begin : g_row
    for (genvar col = 0; col < 4; col++) begin : g_col
      mac_pe pe (
        .clk, .reset, .clear, .step,
        .a_in(a_link[row][col]), .b_in(b_link[row][col]),
        // Clear discards internal in-flight operands; new external inputs are forbidden.
        .a_valid(av_link[row][col] && !clear),
        .b_valid(bv_link[row][col] && !clear),
        .a_out(a_link[row][col+1]), .b_out(b_link[row+1][col]),
        .a_valid_out(av_link[row][col+1]), .b_valid_out(bv_link[row+1][col]),
        .acc(accumulators[(row*4+col)*32 +: 32])
      );
    end
  end

  // synthesis translate_off
  assert property (@(posedge clk) disable iff (reset)
    clear |-> (a_valid == 0 && b_valid == 0))
    else $fatal(1, "ARRAY_CLEAR_WITH_VALID");
  // synthesis translate_on

`ifdef NPU_SIM_TAGS
  // Verification-only token IDs follow the same lane delay and hop count as data.
  // The actual PE valid links gate the comparison. No tag ports are synthesized.
  logic [31:0] token_id;
  logic [31:0] a_tag [4][5];
  logic [31:0] b_tag [5][4];
  always_ff @(posedge clk) begin
    if (reset || clear) token_id <= 32'd0;
    else if (step) token_id <= token_id + 32'd1;
  end
  for (genvar lane = 0; lane < 4; lane++) begin : g_tag_feeder
    if (lane == 0) begin : g_direct
      assign a_tag[lane][0] = token_id;
      assign b_tag[0][lane] = token_id;
    end else begin : g_delay
      logic [31:0] tag_pipe [lane];
      always_ff @(posedge clk) begin
        if (reset || clear) begin
          for (int d = 0; d < lane; d++) tag_pipe[d] <= 32'd0;
        end else if (step) begin
          tag_pipe[0] <= token_id;
          for (int d = 1; d < lane; d++) tag_pipe[d] <= tag_pipe[d-1];
        end
      end
      assign a_tag[lane][0] = tag_pipe[lane-1];
      assign b_tag[0][lane] = tag_pipe[lane-1];
    end
  end
  for (genvar row = 0; row < 4; row++) begin : g_tag_row
    for (genvar col = 0; col < 4; col++) begin : g_tag_col
      always_ff @(posedge clk) begin
        if (reset || clear) begin
          a_tag[row][col+1] <= 32'd0;
          b_tag[row+1][col] <= 32'd0;
        end else if (step) begin
          a_tag[row][col+1] <= a_tag[row][col];
          b_tag[row+1][col] <= b_tag[row][col];
        end
      end
      assert property (@(posedge clk) disable iff (reset)
        (!clear && step && av_link[row][col] && bv_link[row][col]) |->
          (a_tag[row][col] == b_tag[row][col]))
        else $fatal(1, "ARRAY_OPERAND_TAG_MISMATCH row=%0d col=%0d", row, col);
    end
  end
`endif
endmodule
