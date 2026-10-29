`timescale 1ns/1ps
module test_npu;
 logic [63:0] value;
 initial begin
   tb.power_up();
   tb.peek_ocl(.addr(0),.data(value));
   if(value[31:0] !== 32'h4e505531) $fatal(1,"NPU ID mismatch");
   for(int bank=0;bank<4;bank++) begin
     tb.poke_ocl(.addr(64'h1000+64'(bank)*1024),.data(32'h04030201));
     tb.poke_ocl(.addr(64'h2000+64'(bank)*1024),.data(32'h01010101));
   end
   tb.poke_ocl(.addr('h10),.data(4));
   tb.poke_ocl(.addr('h14),.data(4));
   tb.poke_ocl(.addr('h18),.data(4));
   tb.poke_ocl(.addr('h1c),.data(0));
   tb.poke_ocl(.addr('h2c),.data(42));
   tb.poke_ocl(.addr(8),.data(1));
   for(int i=0;i<2000;i++) begin
     tb.peek_ocl(.addr(12),.data(value));
     if(value[2])$fatal(1,"NPU command error");
     if(value[1])break;
     if(i==1999)$fatal(1,"NPU completion timeout");
   end
   tb.peek_ocl(.addr('h30),.data(value));
   if(value[31:0] !== 42)$fatal(1,"sequence mismatch");
   for(int i=0;i<16;i++) begin
     tb.peek_ocl(.addr(64'h3000+64'(i)*4),.data(value));
     if(value[31:0] !== 10)$fatal(1,"result mismatch");
   end
   tb.power_down();$display("PASS NPU official HDK shell test");$finish;
 end
 initial begin #100000000;$fatal(1,"HDK test watchdog");end
endmodule
