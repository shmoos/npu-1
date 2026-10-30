`timescale 1ns/1ps
module tb_timing;
 import npu_pkg::*;
 parameter int R=3,C=5;
 logic clk,rst_n,clear,step;
 int8_t a[R],b[C],as[R],bs[C];logic av[R],bv[C],avs[R],bvs[C];int32_t acc[R][C];
 int ah[160][R],bh[160][C];bit avh[160][R],bvh[160][C];int expected[R][C];
 skew_feeder #(.ROWS(R),.COLS(C)) feeder(clk,rst_n,clear,step,a,av,b,bv,as,avs,bs,bvs);
 systolic_array_4x4 #(.ROWS(R),.COLS(C)) array_dut(clk,rst_n,clear,step,as,avs,bs,bvs,acc);
  // Behavioral testbench clock; blocking assignment is intentional.
  /* verilator lint_off BLKSEQ */
 always #5 clk=~clk;
  /* verilator lint_on BLKSEQ */
 initial begin
   clk=0;rst_n=0;clear=0;step=0;
   repeat(2) @(negedge clk);rst_n=1;
   for(int trial=0;trial<5;trial++) begin
     clear=1;step=0;@(negedge clk);clear=0;
     for(int r=0;r<R;r++)for(int c=0;c<C;c++)expected[r][c]=0;
     for(int t=0;t<100+R+C;t++) begin
       for(int r=0;r<R;r++)begin
         ah[t][r]=int'($signed(8'($urandom)));avh[t][r]=(t<100 && $urandom_range(0,4)!=0);a[r]=8'(ah[t][r]);av[r]=avh[t][r];
       end
       for(int c=0;c<C;c++)begin
         bh[t][c]=int'($signed(8'($urandom)));bvh[t][c]=(t<100 && $urandom_range(0,4)!=0);b[c]=8'(bh[t][c]);bv[c]=bvh[t][c];
       end
       step=0;
       repeat($urandom_range(0,2)) begin
         @(negedge clk);
         for(int r=0;r<R;r++)for(int c=0;c<C;c++)assert(acc[r][c]==expected[r][c])else $fatal(1,"hold timing");
       end
       step=1;
       for(int r=0;r<R;r++)for(int c=0;c<C;c++)begin
         int token; token=t-r-c;
         if(token>=0 && avh[token][r] && bvh[token][c])expected[r][c]+=ah[token][r]*bh[token][c];
       end
       @(negedge clk);
       for(int r=0;r<R;r++)for(int c=0;c<C;c++)assert(acc[r][c]==expected[r][c])else $fatal(1,"cycle mismatch t=%0d row=%0d col=%0d actual=%0d expected=%0d",t,r,c,acc[r][c],expected[r][c]);
     end
   end
   $display("PASS every-cycle skew/valid/hold oracle R=%0d C=%0d",R,C);$finish;
 end
 initial begin #1000000;$fatal(1,"timing timeout");end
endmodule
