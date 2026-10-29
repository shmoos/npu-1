#include "Vnpu_axil.h"
#include "verilated.h"
#include "npu_runtime.h"
#include <algorithm>
#include <fstream>
#include <iostream>
#include <random>
#include <stdexcept>
#include <vector>
#include "workload.hpp"
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
static void protocol(Sim&s){
 uint32_t v;
 require(s.write(0x1000,0x12345678)==0,"ram write");require(s.write(0x1004,0xdeadbeef)==0,"ram write2");
 require(s.read(0x1000,&v)==0 && v==0x12345678,"RAM read latency");
 require(s.read(0x1004,&v)==0 && v==0xdeadbeef,"RAM sequential reads");
 for(unsigned mask=0;mask<16;mask++){
   s.write(0x1000,0x12345678);s.write(0x1000,0xaabbccdd,mask);uint32_t expected=0x12345678;
   for(unsigned b=0;b<4;b++)if(mask&(1u<<b))expected=(expected&~(255u<<(8*b)))|(0xaabbccddu&(255u<<(8*b)));
   require(s.read(0x1000,&v)==0 && v==expected,"byte strobes");
 }
 require(s.write(0x10,17)==0,"cfg write");require(s.write(0x10,99,0)==0,"zero strobe");
 require(s.read(0x10,&v)==0 && v==17,"zero strobe changed register");require(s.write(0x10,99,1)!=0,"partial cfg must reject");
 require(s.write(8,1,0)==0,"zero-strobe START");s.read(0xc,&v);require(v==0,"zero-strobe start ran");
 for(auto addr:{0x1001u,0x3040u,0x3110u,0x10000u,0xffff0000u})require(s.read(addr,&v)!=0,"unmapped/unaligned read");
 require(s.write(0x11000,1)!=0,"high-address alias");require(s.write(0x1001,1)!=0,"unaligned write");
 // Illegal commands and W1C errors, including unsupported multiplier high bit.
 const uint32_t bad[][3]={{0x10,0,1},{0x10,1025,1},{0x14,0,2},{0x18,5,3},{0x1c,3,4},{0x34,0,7},{0x34,0x80000000,7},{0x38,63,7}};
 for(const auto& b:bad){s.write(0x10,4);s.write(0x14,4);s.write(0x18,4);s.write(0x1c,2);s.write(0x34,1);s.write(0x38,0);s.write(b[0],b[1]);s.write(8,1);
   for(int i=0;i<10;i++)s.tick();s.read(0xc,&v);require((v&5)==4,"illegal command state");s.read(0x28,&v);require(v==b[2],"wrong error code");s.write(0xc,4);s.read(0xc,&v);require(!(v&4),"W1C error");}
 // Busy ownership and abort with no stale completion.
 s.write(0x10,1024);s.write(0x1c,0);s.write(8,1);
 require(s.write(0x1000,0)!=0,"busy RAM write accepted");require(s.write(0x10,1)!=0,"busy cfg write accepted");require(s.write(8,1)!=0,"busy start accepted");require(s.read(0x1000,&v)!=0,"busy RAM read accepted");
 s.write(8,2);for(int i=0;i<50;i++)s.tick();s.read(0xc,&v);require(v==0,"abort left busy/done");
 // Abort at each core phase, including postprocess; subsequent inference checks recovery.
 for(unsigned delay=0;delay<50;delay++) {s.write(0x10,1);s.write(8,1);for(unsigned i=0;i<delay;i++)s.tick();s.write(8,2);for(int i=0;i<40;i++)s.tick();s.read(0xc,&v);require(v==0,"abort pipeline leak");}
}
int main(int argc,char**argv){
 try{
   require(argc==3,"usage: host_sim fixtures.bin seed");Verilated::commandArgs(argc,argv);Sim sim(unsigned(std::stoul(argv[2])));protocol(sim);
   npu_transport_t transport{attach,detach,poke,peek,&sim};npu_t*npu=npu_init(&transport,0);require(npu!=nullptr,"host init");
   // Fault injection proves the C driver propagates failed MMIO.
   auto original=transport.poke;transport.poke=[](npu_transport_t*,uint32_t,uint32_t){return -99;};
   require(npu_set_config(npu,4,4,4,0,1,0,nullptr)!=0,"lost write failure");transport.poke=original;
   run_workload(npu,argv[1]); npu_close(npu);
   std::cout<<"PASS seed="<<argv[2]<<" simulated_bus_cycles="<<sim.ticks<<" (no FPGA performance claim)\n";return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}
}
