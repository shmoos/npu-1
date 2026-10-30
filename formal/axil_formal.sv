module axil_formal(
  input logic clk, rst_n,
  input logic [31:0] s_axil_awaddr, s_axil_araddr, s_axil_wdata,
  input logic [3:0] s_axil_wstrb,
  input logic [2:0] s_axil_awprot, s_axil_arprot,
  input logic s_axil_awvalid, s_axil_wvalid, s_axil_arvalid,
  input logic s_axil_bready, s_axil_rready
);
  wire s_axil_awready, s_axil_wready, s_axil_arready;
  wire s_axil_bvalid, s_axil_rvalid;
  wire [1:0] s_axil_bresp, s_axil_rresp;
  wire [31:0] s_axil_rdata;
  npu_axil #(.AXI_ADDR_WIDTH(32)) dut(.*);
  logic past_valid=0;
  logic aw_seen=0, w_seen=0, ar_seen=0;
  wire aw=s_axil_awvalid && s_axil_awready;
  wire w=s_axil_wvalid && s_axil_wready;
  wire ar=s_axil_arvalid && s_axil_arready;
  wire b=s_axil_bvalid && s_axil_bready;
  wire r=s_axil_rvalid && s_axil_rready;
  always @(posedge clk) begin
    past_valid<=1;
    if(!past_valid) assume(!rst_n);
    // A legal AXI master holds each request until its handshake. Responses
    // may be stalled forever: no fairness assumption hides a stability bug.
    if(past_valid && rst_n && $past(rst_n)) begin
      if($past(s_axil_awvalid && !s_axil_awready))
        assume(s_axil_awvalid && $stable({s_axil_awaddr,s_axil_awprot}));
      if($past(s_axil_wvalid && !s_axil_wready))
        assume(s_axil_wvalid && $stable({s_axil_wdata,s_axil_wstrb}));
      if($past(s_axil_arvalid && !s_axil_arready))
        assume(s_axil_arvalid && $stable({s_axil_araddr,s_axil_arprot}));
    end
    if(!rst_n) begin
      aw_seen<=0;w_seen<=0;ar_seen<=0;
    end else begin
      if(aw) aw_seen<=1;
      if(w) w_seen<=1;
      if(ar) ar_seen<=1;
      if(b) begin aw_seen<=0;w_seen<=0;end
      if(r) ar_seen<=0;
    end
    if(past_valid) begin
      if(!$past(rst_n)) begin
        assert(!s_axil_bvalid && !s_axil_rvalid);
      end else begin
        if($past(s_axil_bvalid && !s_axil_bready))
          assert(s_axil_bvalid && $stable(s_axil_bresp));
        if($past(s_axil_rvalid && !s_axil_rready))
          assert(s_axil_rvalid && $stable({s_axil_rdata,s_axil_rresp}));
      end
      // Strengthening invariants tie the independent transaction scoreboard
      // to reachable adapter states; these are assertions, never assumptions.
      assert(aw_seen == dut.aw_latched);
      assert(w_seen == dut.w_latched);
      assert(ar_seen == (dut.read_pending || s_axil_rvalid));
      assert(s_axil_arready == !ar_seen);
      // One outstanding request per direction, and no unsolicited response.
      assert(!s_axil_bvalid || (aw_seen && w_seen));
      assert(!s_axil_rvalid || ar_seen);
      if(rst_n) begin
        assert(!aw || !aw_seen); assert(!w || !w_seen); assert(!ar || !ar_seen);
      end
      cover(rst_n && aw_seen && !w_seen && ar_seen);
      cover(rst_n && w_seen && !aw_seen && s_axil_rvalid);
      cover(rst_n && s_axil_bvalid && !s_axil_bready && s_axil_rvalid && !s_axil_rready);
      cover(rst_n && b && r);
    end
  end
endmodule
