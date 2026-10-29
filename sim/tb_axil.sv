`timescale 1ns/1ps

module tb_axil;
  import npu_pkg::*;

  logic        clk;
  logic        rst_n;

  // AXI4-Lite Signals
  logic [15:0] s_axil_awaddr;
  logic [2:0]  s_axil_awprot;
  logic        s_axil_awvalid;
  logic        s_axil_awready;

  logic [31:0] s_axil_wdata;
  logic [3:0]  s_axil_wstrb;
  logic        s_axil_wvalid;
  logic        s_axil_wready;

  /* verilator lint_off UNUSEDSIGNAL */
  logic [1:0]  s_axil_bresp;
  /* verilator lint_on UNUSEDSIGNAL */
  logic        s_axil_bvalid;
  logic        s_axil_bready;

  logic [15:0] s_axil_araddr;
  logic [2:0]  s_axil_arprot;
  logic        s_axil_arvalid;
  logic        s_axil_arready;

  logic [31:0] s_axil_rdata;
  logic [1:0]  s_axil_rresp;
  logic        s_axil_rvalid;
  logic        s_axil_rready;

  // Instantiate DUT (npu_axil)
  npu_axil dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axil_awaddr (s_axil_awaddr),
    .s_axil_awprot (s_axil_awprot),
    .s_axil_awvalid(s_axil_awvalid),
    .s_axil_awready(s_axil_awready),
    .s_axil_wdata  (s_axil_wdata),
    .s_axil_wstrb  (s_axil_wstrb),
    .s_axil_wvalid (s_axil_wvalid),
    .s_axil_wready (s_axil_wready),
    .s_axil_bresp  (s_axil_bresp),
    .s_axil_bvalid (s_axil_bvalid),
    .s_axil_bready (s_axil_bready),
    .s_axil_araddr (s_axil_araddr),
    .s_axil_arprot (s_axil_arprot),
    .s_axil_arvalid(s_axil_arvalid),
    .s_axil_arready(s_axil_arready),
    .s_axil_rdata  (s_axil_rdata),
    .s_axil_rresp  (s_axil_rresp),
    .s_axil_rvalid (s_axil_rvalid),
    .s_axil_rready (s_axil_rready)
  );

  // Clock Generation (100MHz / 10ns period)
  always #5 clk = ~clk;

  int errors = 0;

  // Bus Master Helper Tasks
  task automatic do_reset();
    @(negedge clk);
    rst_n          = 0;
    s_axil_awaddr  = '0;
    s_axil_awprot  = '0;
    s_axil_awvalid = 0;
    s_axil_wdata   = '0;
    s_axil_wstrb   = '0;
    s_axil_wvalid  = 0;
    s_axil_bready  = 1;
    s_axil_araddr  = '0;
    s_axil_arprot  = '0;
    s_axil_arvalid = 0;
    s_axil_rready  = 1;
    repeat (2) @(negedge clk);
    rst_n = 1;
    @(negedge clk);
  endtask

  // Checked AXI-Lite Write
  task automatic axil_write(
    input logic [15:0] addr,
    input logic [31:0] data,
    input logic [3:0]  strb = 4'b1111,
    input int          aw_delay = 0,
    input int          w_delay = 0,
    input int          bready_delay = 0
  );
    fork
      begin
        repeat (aw_delay) @(negedge clk);
        s_axil_awaddr  <= addr;
        s_axil_awvalid <= 1'b1;
        do @(posedge clk); while (!s_axil_awready);
        @(negedge clk);
        s_axil_awvalid <= 1'b0;
      end
      begin
        repeat (w_delay) @(negedge clk);
        s_axil_wdata  <= data;
        s_axil_wstrb  <= strb;
        s_axil_wvalid <= 1'b1;
        do @(posedge clk); while (!s_axil_wready);
        @(negedge clk);
        s_axil_wvalid <= 1'b0;
      end
    join

    // Handle B channel response
    if (bready_delay > 0) begin
      s_axil_bready <= 1'b0;
      repeat (bready_delay) @(posedge clk);
      @(negedge clk);
      s_axil_bready <= 1'b1;
    end else begin
      s_axil_bready <= 1'b1;
    end

    do @(posedge clk); while (!s_axil_bvalid);
    @(negedge clk);
  endtask

  // Checked AXI-Lite Read
  task automatic axil_read(
    input  logic [15:0] addr,
    output logic [31:0] data,
    output logic [1:0]  resp,
    input  int          rready_delay = 0
  );
    @(negedge clk);
    s_axil_araddr  <= addr;
    s_axil_arvalid <= 1'b1;
    do @(posedge clk); while (!s_axil_arready);
    @(negedge clk);
    s_axil_arvalid <= 1'b0;

    if (rready_delay > 0) begin
      s_axil_rready <= 1'b0;
      repeat (rready_delay) @(posedge clk);
      @(negedge clk);
      s_axil_rready <= 1'b1;
    end else begin
      s_axil_rready <= 1'b1;
    end

    do @(posedge clk); while (!s_axil_rvalid);
    data = s_axil_rdata;
    resp = s_axil_rresp;
    @(negedge clk);
  endtask

  initial begin
    logic [31:0] rdata;
    logic [1:0]  rresp;

    $dumpfile("artifacts/tb_axil.fst");
    $dumpvars(0, tb_axil);

    clk = 0;
    do_reset();

    $display("--- Step 1: Read Fixed Identifiers (ID, ABI_VERSION, BUILD_ID) ---");
    // 1. Read ID
    axil_read(16'h0000, rdata, rresp);
    if (rdata !== NPU_ID_MAGIC || rresp !== 2'b00) begin
      $display("ERROR: ID register read failed! Expected %08x, got %08x", NPU_ID_MAGIC, rdata);
      errors++;
    end

    // 2. Read ABI_VERSION
    axil_read(16'h0004, rdata, rresp);
    if (rdata !== NPU_ABI_VERSION || rresp !== 2'b00) begin
      $display("ERROR: ABI_VERSION read failed! Expected %08x, got %08x", NPU_ABI_VERSION, rdata);
      errors++;
    end

    // 3. Read BUILD_ID
    axil_read(16'h003c, rdata, rresp);
    if (rdata !== NPU_BUILD_ID || rresp !== 2'b00) begin
      $display("ERROR: BUILD_ID read failed! Expected %08x, got %08x", NPU_BUILD_ID, rdata);
      errors++;
    end

    $display("--- Step 2: Register Write / Readback Verification ---");
    // Write K = 64
    axil_write(16'h0010, 32'd64);
    axil_read(16'h0010, rdata, rresp);
    if (rdata !== 32'd64) begin
      $display("ERROR: K readback failed! Expected 64, got %0d", rdata);
      errors++;
    end

    // Write M_VALID = 2, N_VALID = 3
    axil_write(16'h0014, 32'd2);
    axil_write(16'h0018, 32'd3);
    axil_read(16'h0014, rdata, rresp);
    if (rdata !== 32'd2) errors++;
    axil_read(16'h0018, rdata, rresp);
    if (rdata !== 32'd3) errors++;

    // Write BIAS_0 = 1234, BIAS_1 = -5678
    axil_write(16'h0040, 32'd1234);
    axil_write(16'h0044, uint32_t'(-32'sd5678));
    axil_read(16'h0040, rdata, rresp);
    if (rdata !== 32'd1234) errors++;
    axil_read(16'h0044, rdata, rresp);
    if (rdata !== uint32_t'(-32'sd5678)) errors++;

    $display("--- Step 3: Decoupled AW / W Timing Channel Delays ---");
    // AW arrives 3 cycles before W
    axil_write(16'h002c, 32'hBEEF, 4'b1111, 0, 3, 0);
    axil_read(16'h002c, rdata, rresp);
    if (rdata !== 32'hBEEF) begin
      $display("ERROR: Decoupled AW-first write failed!");
      errors++;
    end

    // W arrives 3 cycles before AW
    axil_write(16'h002c, 32'hCAFE, 4'b1111, 3, 0, 0);
    axil_read(16'h002c, rdata, rresp);
    if (rdata !== 32'hCAFE) begin
      $display("ERROR: Decoupled W-first write failed!");
      errors++;
    end

    $display("--- Step 4: Backpressure Testing on B and R Channels ---");
    // Delayed BREADY (5 cycles)
    axil_write(16'h0010, 32'd16, 4'b1111, 0, 0, 5);
    // Delayed RREADY (5 cycles)
    axil_read(16'h0010, rdata, rresp, 5);
    if (rdata !== 32'd16) begin
      $display("ERROR: Backpressure read failed!");
      errors++;
    end

    $display("--- Step 5: Unmapped Address Error Handling ---");
    axil_read(16'h0500, rdata, rresp);
    if (rresp !== 2'b10) begin // RESP_SLVERR
      $display("ERROR: Expected SLVERR for unmapped address 0x0500, got %b", rresp);
      errors++;
    end

    $display("--- Step 6: Full Tile GEMM Execution via AXI-Lite MMIO ---");
    // Write 4x4 matrix into A buffer (0x1000 - 0x1FFF)
    for (int row = 0; row < 4; row++) begin
      logic [15:0] addr;
      addr = 16'h1000 | (16'(row) << 10);
      axil_write(addr, 32'h04030201); // 4 consecutive bytes
    end

    // Write 4x4 matrix into B buffer (0x2000 - 0x2FFF)
    for (int col = 0; col < 4; col++) begin
      logic [15:0] addr;
      addr = 16'h2000 | (16'(col) << 10);
      axil_write(addr, 32'h01010101); // 4 consecutive bytes
    end

    // Configure Tile: K=4, M=4, N=4, MODE=0 (Raw GEMM), SEQ=0x42
    axil_write(16'h0010, 32'd4);
    axil_write(16'h0014, 32'd4);
    axil_write(16'h0018, 32'd4);
    axil_write(16'h001c, 32'd0);
    axil_write(16'h002c, 32'h0042);

    // Issue START (CONTROL = 0x01)
    axil_write(16'h0008, 32'h0001);

    // Poll STATUS register until DONE (bit 1) is asserted
    rdata = 32'h0;
    while (!rdata[1]) begin
      axil_read(16'h000c, rdata, rresp);
    end

    // Verify COMPLETED_SEQ
    axil_read(16'h0030, rdata, rresp);
    if (rdata !== 32'h0042) begin
      $display("ERROR: Completed seq mismatch! Expected 0x42, got %08x", rdata);
      errors++;
    end

    // Read C Result Buffer (0x3000 - 0x303C)
    // Row elements [1, 2, 3, 4] . [1, 1, 1, 1] = 10
    for (int i = 0; i < 4; i++) begin
      for (int j = 0; j < 4; j++) begin
        logic [15:0] c_addr;
        c_addr = 16'h3000 | (16'(i * 4 + j) << 2);
        axil_read(c_addr, rdata, rresp);
        if (rdata !== 32'd10) begin
          $display("ERROR: C[%0d,%0d] MMIO mismatch! Expected 10, got %0d", i, j, rdata);
          errors++;
        end
      end
    end

    // Clear DONE using W1C
    axil_write(16'h000c, 32'h0002);
    axil_read(16'h000c, rdata, rresp);
    if (rdata[1] !== 1'b0) begin
      $display("ERROR: DONE bit not cleared by W1C! STATUS = %08x", rdata);
      errors++;
    end

    if (errors == 0) begin
      $display("=================================================");
      $display("  ALL AXI4-LITE SUBORDINATE & ABI TESTS PASSED!");
      $display("  Milestone M5 Gate G5: SUCCESS");
      $display("=================================================");
      $finish;
    end else begin
      $fatal(1, "AXI4-Lite Verification FAILED with %0d errors!", errors);
    end
  end

endmodule
