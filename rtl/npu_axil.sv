`timescale 1ns/1ps

module npu_axil
  import npu_pkg::*;
#(
  parameter int AXI_ADDR_WIDTH = 16,
  parameter int AXI_DATA_WIDTH = 32
)(
  input  logic                      clk,
  input  logic                      rst_n,

  // AXI4-Lite Write Address Channel
  input  logic [AXI_ADDR_WIDTH-1:0] s_axil_awaddr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [2:0]                s_axil_awprot,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                      s_axil_awvalid,
  output logic                      s_axil_awready,

  // AXI4-Lite Write Data Channel
  input  logic [AXI_DATA_WIDTH-1:0] s_axil_wdata,
  input  logic [3:0]                s_axil_wstrb,
  input  logic                      s_axil_wvalid,
  output logic                      s_axil_wready,

  // AXI4-Lite Write Response Channel
  output logic [1:0]                s_axil_bresp,
  output logic                      s_axil_bvalid,
  input  logic                      s_axil_bready,

  // AXI4-Lite Read Address Channel
  input  logic [AXI_ADDR_WIDTH-1:0] s_axil_araddr,
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [2:0]                s_axil_arprot,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                      s_axil_arvalid,
  output logic                      s_axil_arready,

  // AXI4-Lite Read Data Channel
  output logic [AXI_DATA_WIDTH-1:0] s_axil_rdata,
  output logic [1:0]                s_axil_rresp,
  output logic                      s_axil_rvalid,
  input  logic                      s_axil_rready
);

  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  // Internal Registers
  logic [15:0] reg_k;
  logic [2:0]  reg_m_valid;
  logic [2:0]  reg_n_valid;
  logic [1:0]  reg_mode;
  logic [31:0] reg_command_seq;
  logic [31:0] reg_requant_mult;
  logic [5:0]  reg_requant_shift;
  int32_t      reg_bias [4];

  logic        cmd_start;
  logic        cmd_soft_reset;
  logic        status_done_w1c;
  logic        status_error_w1c;

  // Status & Diagnostic Signals from Core
  logic        core_status_busy;
  logic        core_status_done;
  logic        core_status_error;
  logic [31:0] core_error_code;
  logic [31:0] core_completed_seq;
  logic [63:0] core_cycle_count;

  // Core Buffer Interfaces
  logic        a_host_we;
  logic [1:0]  a_host_bank;
  logic [9:0]  a_host_addr;
  logic [31:0] a_host_wdata;
  logic [3:0]  a_host_wstrb;
  logic [1:0]  a_host_rdbank;
  logic [9:0]  a_host_rdaddr;
  logic [31:0] a_host_rdata;

  logic        b_host_we;
  logic [1:0]  b_host_bank;
  logic [9:0]  b_host_addr;
  logic [31:0] b_host_wdata;
  logic [3:0]  b_host_wstrb;
  logic [1:0]  b_host_rdbank;
  logic [9:0]  b_host_rdaddr;
  logic [31:0] b_host_rdata;

  logic [5:0]  c_host_rd_word_addr;
  logic [31:0] c_host_rdata;
  logic [1:0]  y_host_rd_word_addr;
  logic [31:0] y_host_rdata;

  // Instantiate NPU Core
  npu_core core_inst (
    .clk                  (clk),
    .rst_n                (rst_n),
    .start_cmd            (cmd_start),
    .soft_reset_cmd       (cmd_soft_reset),
    .cfg_k                (reg_k),
    .cfg_m_valid          (reg_m_valid),
    .cfg_n_valid          (reg_n_valid),
    .cfg_mode             (reg_mode),
    .cfg_command_seq      (reg_command_seq),
    .cfg_requant_mult     (reg_requant_mult),
    .cfg_requant_shift    (reg_requant_shift),
    .cfg_bias             (reg_bias),
    .status_busy          (core_status_busy),
    .status_done          (core_status_done),
    .status_error         (core_status_error),
    .status_done_w1c      (status_done_w1c),
    .status_error_w1c     (status_error_w1c),
    .error_code_out       (core_error_code),
    .completed_seq_out    (core_completed_seq),
    .cycle_count_out      (core_cycle_count),
    .a_host_we            (a_host_we),
    .a_host_bank          (a_host_bank),
    .a_host_addr          (a_host_addr),
    .a_host_wdata         (a_host_wdata),
    .a_host_wstrb         (a_host_wstrb),
    .a_host_rdbank        (a_host_rdbank),
    .a_host_rdaddr        (a_host_rdaddr),
    .a_host_rdata         (a_host_rdata),
    .b_host_we            (b_host_we),
    .b_host_bank          (b_host_bank),
    .b_host_addr          (b_host_addr),
    .b_host_wdata         (b_host_wdata),
    .b_host_wstrb         (b_host_wstrb),
    .b_host_rdbank        (b_host_rdbank),
    .b_host_rdaddr        (b_host_rdaddr),
    .b_host_rdata         (b_host_rdata),
    .c_host_rd_word_addr  (c_host_rd_word_addr),
    .c_host_rdata         (c_host_rdata),
    .y_host_rd_word_addr  (y_host_rd_word_addr),
    .y_host_rdata         (y_host_rdata)
  );

  // =========================================================================
  // AXI-Lite Write Transaction Management (Decoupled AW and W Channels)
  // =========================================================================
  logic                      aw_latched;
  logic [AXI_ADDR_WIDTH-1:0] latched_awaddr;
  logic                      w_latched;
  logic [AXI_DATA_WIDTH-1:0] latched_wdata;
  logic [3:0]                latched_wstrb;

  // Accept AW
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      aw_latched     <= 1'b0;
      latched_awaddr <= '0;
    end else begin
      if (s_axil_awvalid && s_axil_awready) begin
        aw_latched     <= 1'b1;
        latched_awaddr <= s_axil_awaddr;
      end else if (s_axil_bvalid && s_axil_bready) begin
        aw_latched     <= 1'b0;
      end
    end
  end
  assign s_axil_awready = !aw_latched && (!s_axil_bvalid || s_axil_bready);

  // Accept W
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      w_latched     <= 1'b0;
      latched_wdata <= '0;
      latched_wstrb <= '0;
    end else begin
      if (s_axil_wvalid && s_axil_wready) begin
        w_latched     <= 1'b1;
        latched_wdata <= s_axil_wdata;
        latched_wstrb <= s_axil_wstrb;
      end else if (s_axil_bvalid && s_axil_bready) begin
        w_latched     <= 1'b0;
      end
    end
  end
  assign s_axil_wready = !w_latched && (!s_axil_bvalid || s_axil_bready);

  // Execute Write when both AW and W are latched
  logic write_fire;
  assign write_fire = (aw_latched || (s_axil_awvalid && s_axil_awready)) &&
                      (w_latched  || (s_axil_wvalid && s_axil_wready)) &&
                      !s_axil_bvalid;

  logic [AXI_ADDR_WIDTH-1:0] write_addr;
  logic [AXI_DATA_WIDTH-1:0] write_data;
  logic [3:0]                write_strb;

  assign write_addr = aw_latched ? latched_awaddr : s_axil_awaddr;
  assign write_data = w_latched  ? latched_wdata  : s_axil_wdata;
  assign write_strb = w_latched  ? latched_wstrb  : s_axil_wstrb;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      s_axil_bvalid    <= 1'b0;
      s_axil_bresp     <= RESP_OKAY;
      cmd_start        <= 1'b0;
      cmd_soft_reset   <= 1'b0;
      status_done_w1c  <= 1'b0;
      status_error_w1c <= 1'b0;

      reg_k             <= 16'd4;
      reg_m_valid       <= 3'd4;
      reg_n_valid       <= 3'd4;
      reg_mode          <= 2'd0;
      reg_command_seq   <= 32'd0;
      reg_requant_mult  <= 32'd1;
      reg_requant_shift <= 6'd0;
      for (int i = 0; i < 4; i++) reg_bias[i] <= 32'sd0;

      a_host_we <= 1'b0;
      b_host_we <= 1'b0;
    end else begin
      // Self-clearing strobes
      cmd_start        <= 1'b0;
      cmd_soft_reset   <= 1'b0;
      status_done_w1c  <= 1'b0;
      status_error_w1c <= 1'b0;
      a_host_we        <= 1'b0;
      b_host_we        <= 1'b0;

      if (s_axil_bvalid && s_axil_bready) begin
        s_axil_bvalid <= 1'b0;
      end

      if (write_fire) begin
        s_axil_bvalid <= 1'b1;
        s_axil_bresp  <= RESP_OKAY;

        // Decode Address
        if (write_addr[1:0] != 0) begin
          s_axil_bresp <= RESP_SLVERR;
        end else if (write_strb == 0) begin
          // AXI zero-strobe write is an acknowledged no-op.
        /* verilator lint_off CMPCONST */
        end else if (write_addr > 'hffff) begin
        /* verilator lint_on CMPCONST */
          s_axil_bresp <= RESP_SLVERR;
        end else if (write_addr >=  'h1000 && write_addr <= 'h1fff) begin
          // A_BUFFER (0x1000 - 0x1FFF)
          if (!core_status_busy) begin
            a_host_we    <= 1'b1;
            a_host_bank  <= write_addr[11:10];
            a_host_addr  <= write_addr[9:0];
            a_host_wdata <= write_data;
            a_host_wstrb <= write_strb;
          end else begin
            s_axil_bresp <= RESP_SLVERR;
          end
        end else if (write_addr >= 'h2000 && write_addr <= 'h2fff) begin
          // B_BUFFER (0x2000 - 0x2FFF)
          if (!core_status_busy) begin
            b_host_we    <= 1'b1;
            b_host_bank  <= write_addr[11:10];
            b_host_addr  <= write_addr[9:0];
            b_host_wdata <= write_data;
            b_host_wstrb <= write_strb;
          end else begin
            s_axil_bresp <= RESP_SLVERR;
          end
        end else if (write_addr < 'h100) begin
          // Register File (0x0000 - 0x00FF)
          if (core_status_busy && write_addr != 'h0c &&
              !(write_addr == 'h08 && write_strb[0] && write_data[1])) begin
            s_axil_bresp <= RESP_SLVERR;
          end else if (write_strb != 4'hf) begin
            // ABI v1 requires whole-register writes; RAM accepts arbitrary strobes.
            s_axil_bresp <= RESP_SLVERR;
          end else case (write_addr[7:0])
            8'h08: begin // CONTROL
              if (write_data[0]) cmd_start      <= 1'b1;
              if (write_data[1]) cmd_soft_reset <= 1'b1;
            end
            8'h0c: begin // STATUS W1C
              if (write_data[1]) status_done_w1c  <= 1'b1;
              if (write_data[2]) status_error_w1c <= 1'b1;
            end
            8'h10: if (!core_status_busy) reg_k             <= write_data[15:0];
            8'h14: if (!core_status_busy) reg_m_valid       <= write_data[2:0];
            8'h18: if (!core_status_busy) reg_n_valid       <= write_data[2:0];
            8'h1c: if (!core_status_busy) reg_mode          <= write_data[1:0];
            8'h2c: if (!core_status_busy) reg_command_seq   <= write_data;
            8'h34: if (!core_status_busy) reg_requant_mult  <= write_data;
            8'h38: if (!core_status_busy) reg_requant_shift <= write_data[5:0];
            8'h40: if (!core_status_busy) reg_bias[0]       <= int32_t'(write_data);
            8'h44: if (!core_status_busy) reg_bias[1]       <= int32_t'(write_data);
            8'h48: if (!core_status_busy) reg_bias[2]       <= int32_t'(write_data);
            8'h4c: if (!core_status_busy) reg_bias[3]       <= int32_t'(write_data);
            default: s_axil_bresp <= RESP_SLVERR; // Unmapped register write
          endcase
        end else begin
          s_axil_bresp <= RESP_SLVERR; // Unmapped region
        end
      end
    end
  end

  // =========================================================================
  // AXI-Lite Read Transaction Management
  // =========================================================================
  logic read_pending;
  logic [AXI_ADDR_WIDTH-1:0] read_addr;
  always_comb begin
    a_host_rdbank       = s_axil_araddr[11:10];
    a_host_rdaddr       = s_axil_araddr[9:0];
    b_host_rdbank       = s_axil_araddr[11:10];
    b_host_rdaddr       = s_axil_araddr[9:0];
    c_host_rd_word_addr = {2'b00, read_addr[5:2]};
    y_host_rd_word_addr = read_addr[3:2];
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      read_pending <= 1'b0;
      read_addr <= '0;
      s_axil_arready <= 1'b1;
      s_axil_rvalid  <= 1'b0;
      s_axil_rdata   <= '0;
      s_axil_rresp   <= RESP_OKAY;
    end else begin
      if (s_axil_rvalid && s_axil_rready) begin
        s_axil_rvalid  <= 1'b0;
        s_axil_arready <= 1'b1;
      end

      if (s_axil_arvalid && s_axil_arready) begin
        s_axil_arready <= 1'b0;
        read_pending <= 1'b1;
        read_addr <= s_axil_araddr;
      end
      if (read_pending) begin
        read_pending <= 1'b0;
        s_axil_rvalid  <= 1'b1;
        s_axil_rresp   <= RESP_OKAY;

        // Decode Read Address
        /* verilator lint_off CMPCONST */
        if (read_addr[1:0] != 0 || read_addr > 'hffff) begin
        /* verilator lint_on CMPCONST */
          s_axil_rdata <= 0; s_axil_rresp <= RESP_SLVERR;
        end else if (read_addr >= 'h1000 && read_addr <= 'h1fff) begin
          // Read from A Buffer
          s_axil_rdata <= a_host_rdata;
          if (core_status_busy) s_axil_rresp <= RESP_SLVERR;
        end else if (read_addr >= 'h2000 && read_addr <= 'h2fff) begin
          // Read from B Buffer
          s_axil_rdata <= b_host_rdata;
          if (core_status_busy) s_axil_rresp <= RESP_SLVERR;
        end else if (read_addr >= 'h3000 && read_addr <= 'h303f) begin
          // Read from C Result Buffer (0x3000 - 0x303F)
          s_axil_rdata <= c_host_rdata;
          if (core_status_busy) s_axil_rresp <= RESP_SLVERR;
        end else if (read_addr >= 'h3100 && read_addr <= 'h310f) begin
          // Read from Y Result Buffer (0x3100 - 0x310F)
          s_axil_rdata <= y_host_rdata;
          if (core_status_busy) s_axil_rresp <= RESP_SLVERR;
        end else if (read_addr < 'h100) begin
          // Register Map
          case (read_addr[7:0])
            8'h00: s_axil_rdata <= NPU_ID_MAGIC;
            8'h04: s_axil_rdata <= NPU_ABI_VERSION;
            8'h08: s_axil_rdata <= 32'h0;
            8'h0c: s_axil_rdata <= {29'h0, core_status_error, core_status_done, core_status_busy};
            8'h10: s_axil_rdata <= {16'h0, reg_k};
            8'h14: s_axil_rdata <= {29'h0, reg_m_valid};
            8'h18: s_axil_rdata <= {29'h0, reg_n_valid};
            8'h1c: s_axil_rdata <= {30'h0, reg_mode};
            8'h20: s_axil_rdata <= core_cycle_count[31:0];
            8'h24: s_axil_rdata <= core_cycle_count[63:32];
            8'h28: s_axil_rdata <= core_error_code;
            8'h2c: s_axil_rdata <= reg_command_seq;
            8'h30: s_axil_rdata <= core_completed_seq;
            8'h34: s_axil_rdata <= reg_requant_mult;
            8'h38: s_axil_rdata <= {26'h0, reg_requant_shift};
            8'h3c: s_axil_rdata <= NPU_BUILD_ID;
            8'h40: s_axil_rdata <= uint32_t'(reg_bias[0]);
            8'h44: s_axil_rdata <= uint32_t'(reg_bias[1]);
            8'h48: s_axil_rdata <= uint32_t'(reg_bias[2]);
            8'h4c: s_axil_rdata <= uint32_t'(reg_bias[3]);
            default: begin
              s_axil_rdata <= 32'hDEADBEEF;
              s_axil_rresp <= RESP_SLVERR;
            end
          endcase
        end else begin
          s_axil_rdata <= 32'hDEADBEEF;
          s_axil_rresp <= RESP_SLVERR;
        end
      end
    end
  end

  // synthesis translate_off
  initial begin
    assert (AXI_ADDR_WIDTH >= 16 && AXI_DATA_WIDTH == 32)
      else $fatal(1, "NPU requires >=16 address bits and 32 data bits");
  end
  assert property (@(posedge clk) disable iff (!rst_n)
    s_axil_bvalid && !s_axil_bready |=> s_axil_bvalid && $stable(s_axil_bresp));
  assert property (@(posedge clk) disable iff (!rst_n)
    s_axil_rvalid && !s_axil_rready |=> s_axil_rvalid && $stable({s_axil_rdata,s_axil_rresp}));
  assert property (@(posedge clk) disable iff (!rst_n)
    core_status_busy |-> !(a_host_we || b_host_we));
  // synthesis translate_on
endmodule
