`timescale 1ns/1ps
module skew_feeder import npu_pkg::*;
#(parameter int ROWS = 4, COLS = 4)(
 input logic clk, rst_n, clear, step,
 input int8_t a_unskewed [ROWS], input logic a_valid_raw [ROWS],
 input int8_t b_unskewed [COLS], input logic b_valid_raw [COLS],
 output int8_t a_skewed [ROWS], output logic a_valid_skewed [ROWS],
 output int8_t b_skewed [COLS], output logic b_valid_skewed [COLS]
);
 for (genvar r=0;r<ROWS;r++) begin: a_lane
   if (r==0) begin: direct_lane
     assign a_skewed[r]=a_unskewed[r];
     assign a_valid_skewed[r]=a_valid_raw[r] && rst_n && !clear;
   end else begin: delay_lane
     int8_t data_pipe[r]; logic valid_pipe[r];
     always_ff @(posedge clk) begin
       if (!rst_n || clear) begin
         for (int d=0;d<r;d++) begin data_pipe[d]<='0; valid_pipe[d]<=0; end
       end else if(step) begin
         data_pipe[0]<=a_unskewed[r]; valid_pipe[0]<=a_valid_raw[r];
         for(int d=1;d<r;d++) begin data_pipe[d]<=data_pipe[d-1]; valid_pipe[d]<=valid_pipe[d-1]; end
       end
     end
     assign a_skewed[r]=data_pipe[r-1];
     assign a_valid_skewed[r]=valid_pipe[r-1] && rst_n && !clear;
   end
 end
 for (genvar c=0;c<COLS;c++) begin: b_lane
   if (c==0) begin: direct_lane
     assign b_skewed[c]=b_unskewed[c];
     assign b_valid_skewed[c]=b_valid_raw[c] && rst_n && !clear;
   end else begin: delay_lane
     int8_t data_pipe[c]; logic valid_pipe[c];
     always_ff @(posedge clk) begin
       if (!rst_n || clear) begin
         for (int d=0;d<c;d++) begin data_pipe[d]<='0; valid_pipe[d]<=0; end
       end else if(step) begin
         data_pipe[0]<=b_unskewed[c]; valid_pipe[0]<=b_valid_raw[c];
         for(int d=1;d<c;d++) begin data_pipe[d]<=data_pipe[d-1]; valid_pipe[d]<=valid_pipe[d-1]; end
       end
     end
     assign b_skewed[c]=data_pipe[c-1];
     assign b_valid_skewed[c]=valid_pipe[c-1] && rst_n && !clear;
   end
 end
endmodule
