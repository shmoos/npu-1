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
#include "axi_sim.hpp"
#include "protocol_stress.hpp"
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
   require(argc==3,"usage: host_sim fixtures.bin seed");Verilated::commandArgs(argc,argv);Sim sim(unsigned(std::stoul(argv[2])));protocol(sim);stress_protocol(sim);
   npu_transport_t transport{attach,detach,poke,peek,&sim};npu_t*npu=npu_init(&transport,0);require(npu!=nullptr,"host init");
   // Fault injection proves the C driver propagates failed MMIO.
   auto original=transport.poke;transport.poke=[](npu_transport_t*,uint32_t,uint32_t){return -99;};
   require(npu_set_config(npu,4,4,4,0,1,0,nullptr)!=0,"lost write failure");transport.poke=original;
   run_workload(npu,argv[1]); npu_close(npu);
   std::cout<<"PASS seed="<<argv[2]<<" simulated_bus_cycles="<<sim.ticks<<" (no FPGA performance claim)\n";return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}
}
