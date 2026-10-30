module pe_formal(
  input logic clk, rst_n, clear, step, a_valid, b_valid,
  input logic signed [7:0] a_in, b_in
);
  wire signed [7:0] a_out,b_out;
  wire a_valid_out,b_valid_out;
  wire signed [31:0] acc_out;
  logic past_valid=0;
  mac_pe dut(.*);
  always @(posedge clk) begin
    past_valid<=1;
    if(!past_valid) assume(!rst_n);
    if(past_valid) begin
      if($past(!rst_n || clear)) begin
        assert(acc_out==0);
        assert({a_out,b_out,a_valid_out,b_valid_out}==0);
      end else if(!$past(step)) begin
        assert($stable({acc_out,a_out,b_out,a_valid_out,b_valid_out}));
      end else begin
        assert(a_out==$past(a_in) && b_out==$past(b_in));
        assert(a_valid_out==$past(a_valid) && b_valid_out==$past(b_valid));
        if(!$past(a_valid && b_valid)) assert($stable(acc_out));
      end
      cover(rst_n && $past(rst_n && step && a_valid && b_valid) && acc_out!=0);
      cover(rst_n && $past(rst_n && !clear && !step) && acc_out!=0);
    end
  end
endmodule
