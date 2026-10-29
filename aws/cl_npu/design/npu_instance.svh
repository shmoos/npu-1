// Included by the staged official F2 AXI-Lite example, after its register slice.
// Full 32-bit addresses are decoded: no high-address aliasing into NPU registers.
npu_axil #(.AXI_ADDR_WIDTH(32)) npu (
 .clk(clk_main_a0), .rst_n(npu_rst_n),
 .s_axil_awaddr(sh_ocl_awaddr_q), .s_axil_awprot(3'b0),
 .s_axil_awvalid(sh_ocl_awvalid_q), .s_axil_awready(ocl_sh_awready_q),
 .s_axil_wdata(sh_ocl_wdata_q), .s_axil_wstrb(sh_ocl_wstrb_q),
 .s_axil_wvalid(sh_ocl_wvalid_q), .s_axil_wready(ocl_sh_wready_q),
 .s_axil_bresp(ocl_sh_bresp_q), .s_axil_bvalid(ocl_sh_bvalid_q), .s_axil_bready(sh_ocl_bready_q),
 .s_axil_araddr(sh_ocl_araddr_q), .s_axil_arprot(3'b0),
 .s_axil_arvalid(sh_ocl_arvalid_q), .s_axil_arready(ocl_sh_arready_q),
 .s_axil_rdata(ocl_sh_rdata_q), .s_axil_rresp(ocl_sh_rresp_q),
 .s_axil_rvalid(ocl_sh_rvalid_q), .s_axil_rready(sh_ocl_rready_q)
);
