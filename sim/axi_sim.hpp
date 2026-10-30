#pragma once
#include "Vnpu_axil.h"
#include "verilated.h"
#include "npu_runtime.h"
#include "workload.hpp"
#include <random>
class Sim {
public:
 Vnpu_axil d; std::mt19937 rng; uint64_t ticks=0, commands=0;
 explicit Sim(unsigned seed):rng(seed) {d.rst_n=0; for(int i=0;i<4;i++) tick();d.rst_n=1;tick();}
 void low(){d.clk=0;d.eval();}
 void tick(){low();d.clk=1;d.eval();++ticks;low();}
 int write(uint32_t addr,uint32_t data,uint8_t strb=15) {
   unsigned ad=rng()%4,wd=rng()%4,stall=rng()%6;bool aw=false,w=false;
   d.s_axil_awaddr=addr;d.s_axil_wdata=data;d.s_axil_wstrb=strb;d.s_axil_bready=0;
   for(unsigned c=0;c<100;c++) {
     d.s_axil_awvalid=!aw && c>=ad;d.s_axil_wvalid=!w && c>=wd;low();
     bool ah=d.s_axil_awvalid && d.s_axil_awready,wh=d.s_axil_wvalid && d.s_axil_wready;
     tick();aw|=ah;w|=wh;if(aw && w) break;
   }
   require(aw && w,"write handshake timeout");d.s_axil_awvalid=0;d.s_axil_wvalid=0;low();
   for(int c=0;!d.s_axil_bvalid;c++){require(c<100,"write response timeout");tick();}
   auto response=d.s_axil_bresp;
   for(unsigned c=0;c<stall;c++){tick();require(d.s_axil_bvalid && d.s_axil_bresp==response,"unstable B response");}
   d.s_axil_bready=1;tick();d.s_axil_bready=0;return response==0 ? 0:-1;
 }
 int read(uint32_t addr,uint32_t* data) {
   d.s_axil_araddr=addr;d.s_axil_arvalid=1;d.s_axil_rready=0;low();
   for(int c=0;;c++){require(c<100,"read address timeout");bool ready=d.s_axil_arready;tick();if(ready) break;}
   d.s_axil_arvalid=0;d.s_axil_araddr=0xfedcba98;low(); // address changes immediately after handshake
   for(int c=0;!d.s_axil_rvalid;c++){require(c<100,"read response timeout");tick();}
   auto value=d.s_axil_rdata;auto response=d.s_axil_rresp;
   for(unsigned c=0,n=rng()%6;c<n;c++){tick();require(d.s_axil_rvalid && d.s_axil_rdata==value && d.s_axil_rresp==response,"unstable R response");}
   *data=value;d.s_axil_rready=1;tick();d.s_axil_rready=0;return response==0?0:-1;
 }
};
static int attach(npu_transport_t*,int){return 0;}
static void detach(npu_transport_t*){}
static int poke(npu_transport_t*t,uint32_t a,uint32_t v){return static_cast<Sim*>(t->priv)->write(a,v);}
static int peek(npu_transport_t*t,uint32_t a,uint32_t*v){return static_cast<Sim*>(t->priv)->read(a,v);}
