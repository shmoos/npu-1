`timescale 1ns/1ps

module result_buffer
  import npu_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // Write Interface from Post-Processor
  input  logic        store_en,
  input  logic [1:0]  store_row,
  input  logic [1:0]  store_col,
  input  int32_t      c_data_in,
  input  int8_t       y_data_in,

  // Host Read Port (32-bit aligned)
  input  logic [5:0]  c_rd_word_addr, // 0..15 for C buffer
  output logic [31:0] c_host_rdata,

  input  logic [1:0]  y_rd_word_addr, // 0..3 for Y buffer (4 words x 4 bytes)
  output logic [31:0] y_host_rdata
);

  int32_t c_storage [16];
  int8_t  y_storage [16];

  // Write Process
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int k = 0; k < 16; k++) begin
        c_storage[k] <= 32'sd0;
        y_storage[k] <= 8'sd0;
      end
    end else if (store_en) begin
      logic [3:0] idx;
      idx = {store_row, store_col};
      c_storage[idx] <= c_data_in;
      y_storage[idx] <= y_data_in;
    end
  end

  // Host Reads
  assign c_host_rdata = (c_rd_word_addr < 16) ? uint32_t'(c_storage[c_rd_word_addr[3:0]]) : 32'h0;

  // Y buffer word read: 4 bytes packed little-endian
  always_comb begin
    logic [3:0] base_idx;
    base_idx = {y_rd_word_addr, 2'b00};
    y_host_rdata = {
      uint8_t'(y_storage[base_idx + 4'd3]),
      uint8_t'(y_storage[base_idx + 4'd2]),
      uint8_t'(y_storage[base_idx + 4'd1]),
      uint8_t'(y_storage[base_idx + 4'd0])
    };
  end

endmodule
