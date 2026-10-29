`timescale 1ns/1ps

module operand_buffer
  import npu_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  // Host Write Port (32-bit with byte strobes)
  input  logic        host_we,
  input  logic [1:0]  host_bank,       // Bank 0..3
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [9:0]  host_addr,       // Byte address within bank (0..1023)
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [31:0] host_wdata,
  input  logic [3:0]  host_wstrb,

  // Host Read Port (32-bit word aligned)
  input  logic [1:0]  host_rdbank,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [9:0]  host_rdaddr,     // Byte address (bits [1:0] should be 0)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [31:0] host_rdata,

  // Compute Read Port (1 byte per bank, synchronous read)
  input  logic        compute_re,
  input  logic [9:0]  compute_k_addr,  // k reduction index (0..1023)
  output int8_t       compute_data [4]
);

  // Four 256x32 banks with byte-write enables; RAM contents are not reset.
  for (genvar bank=0; bank<4; bank++) begin: banks
    (* ram_style = "block" *) logic [31:0] mem [256];
    logic [31:0] read_word;
    logic [1:0] byte_select;
    wire [7:0] read_addr = compute_re ? compute_k_addr[9:2] : host_rdaddr[9:2];
    always_ff @(posedge clk) begin
      if (host_we && host_bank == 2'(bank)) begin
        for(int b=0;b<4;b++)
          if(host_wstrb[b]) mem[host_addr[9:2]][b*8+:8] <= host_wdata[b*8+:8];
      end
      read_word <= mem[read_addr];
      byte_select <= compute_k_addr[1:0];
    end
    assign compute_data[bank] = int8_t'(read_word[byte_select*8+:8]);
  end
  logic [1:0] read_bank;
  always_ff @(posedge clk) read_bank <= host_rdbank;
  always_comb begin
    case(read_bank)
      0: host_rdata=banks[0].read_word;
      1: host_rdata=banks[1].read_word;
      2: host_rdata=banks[2].read_word;
      3: host_rdata=banks[3].read_word;
    endcase
  end
  // rst_n deliberately does not clear RAM; the host must initialize every used byte.
  /* verilator lint_off UNUSEDSIGNAL */
  wire unused_rst = rst_n;
  /* verilator lint_on UNUSEDSIGNAL */
endmodule
