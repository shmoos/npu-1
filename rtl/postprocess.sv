`timescale 1ns/1ps

module postprocess
  import npu_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,
  input  logic        valid_in,

  // Inputs
  input  int32_t      acc_in,
  input  int32_t      bias_in,
  input  npu_mode_e   mode_in,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0] requant_mult,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [5:0]  requant_shift,

  // Outputs (1 cycle latency)
  output logic        valid_out,
  output int32_t      c_out,
  output int8_t       y_out
);

  function automatic int32_t sat32(input int64_t x);
    if(x > 64'sd2147483647) return 32'sh7fffffff;
    if(x < -64'sd2147483648) return 32'sh80000000;
    return int32_t'(x);
  endfunction

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      valid_out <= 1'b0;
      c_out     <= 32'sd0;
      y_out     <= 8'sd0;
    end else if (valid_in) begin
      valid_out <= 1'b1;

      case (mode_in)
        MODE_RAW_GEMM: begin
          c_out <= acc_in;
          y_out <= 8'sd0;
        end

        MODE_BIASED_INT32: begin
          /* verilator lint_off UNUSEDSIGNAL */
          int64_t biased_sum;
          /* verilator lint_on UNUSEDSIGNAL */
          biased_sum = int64_t'(acc_in) + int64_t'(bias_in);
          c_out <= sat32(biased_sum);
          y_out <= 8'sd0;
        end

        MODE_REQUANT_INT8: begin
          int64_t biased_sum;
          int64_t z;
          int64_t abs_z;
          int64_t round_offset;
          int64_t rounded;
          int64_t q;
          int64_t relu;
          int8_t  sat_y;

          biased_sum = int64_t'(acc_in) + int64_t'(bias_in);
          c_out <= sat32(biased_sum);

          // Fixed-point scaling (64-bit integer product)
          z = int64_t'(sat32(biased_sum)) * int64_t'({1'b0, requant_mult[30:0]});

          // Symmetric round shift (ties away from zero)
          if (requant_shift == 6'd0) begin
            q = z;
          end else begin
            abs_z = (z < 64'sd0) ? -z : z;
            round_offset = 64'sd1 << (requant_shift - 6'd1);
            rounded = (abs_z + round_offset) >> requant_shift;
            q = (z < 64'sd0) ? -rounded : rounded;
          end

          // ReLU activation: max(0, q)
          relu = (q < 64'sd0) ? 64'sd0 : q;

          // INT8 Saturation to [0, 127]
          if (relu > 64'sd127) begin
            sat_y = 8'sd127;
          end else begin
            sat_y = int8_t'(relu[7:0]);
          end

          y_out <= sat_y;
        end

        default: begin
          c_out <= acc_in;
          y_out <= 8'sd0;
        end
      endcase
    end else begin
      valid_out <= 1'b0;
    end
  end

endmodule
