#pragma once
#include "npu_runtime.h"
#include <algorithm>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <vector>
inline void require(bool x,const char*message){if(!x)throw std::runtime_error(message);}
static uint32_t u32(std::ifstream&f){uint32_t x;f.read(reinterpret_cast<char*>(&x),4);require(bool(f),"truncated fixture");return x;}
template<class T> static std::vector<T> vec(std::ifstream&f,size_t n){std::vector<T> v(n);f.read(reinterpret_cast<char*>(v.data()),n*sizeof(T));require(bool(f),"truncated vector");return v;}

inline uint64_t run_workload(npu_t*npu,const char*fixture) {
   std::ifstream f(fixture,std::ios::binary);require(u32(f)==0x4e505531,"fixture magic");unsigned cases=u32(f);uint64_t cycles=0;
   for(unsigned ci=0;ci<cases;ci++){
     unsigned m=u32(f),n=u32(f),k=u32(f),mode=u32(f),mult=u32(f),shift=u32(f);
     auto a=vec<int8_t>(f,m*k),b=vec<int8_t>(f,k*n);auto bias=vec<int32_t>(f,n),ec=vec<int32_t>(f,m*n);auto ey=vec<int8_t>(f,m*n);
     std::vector<int32_t> c(m*n);std::vector<int8_t> y(m*n);npu_perf_t perf{};
     require(npu_gemm(npu,a.data(),b.data(),c.data(),y.data(),m,n,k,mode,mult,shift,bias.data(),&perf)==0,"host GEMM failed");
     if(c!=ec || y!=ey) {std::cerr<<"case "<<ci<<" shape "<<m<<','<<n<<','<<k<<" mode "<<mode<<'\n';throw std::runtime_error("RTL / NumPy mismatch");}cycles+=perf.core_cycles;
   }
   // Entire two-layer network uses actual hardware hidden outputs for layer two.
   auto w1=vec<int8_t>(f,64*32);auto b1=vec<int32_t>(f,32);auto mult=u32(f),shift=u32(f);
   auto w2=vec<int8_t>(f,32*10);auto b2=vec<int32_t>(f,10);unsigned samples=u32(f);
   auto inputs=vec<int8_t>(f,samples*64),hidden_ref=vec<int8_t>(f,samples*32);auto logits_ref=vec<int32_t>(f,samples*10);auto labels=vec<uint8_t>(f,samples);
   unsigned correct=0;
   for(unsigned batch:{1u,4u}){
     unsigned hits=0;
     for(unsigned r=0;r<samples;r+=batch){unsigned m=std::min(batch,samples-r);std::vector<int8_t> hidden(m*32);std::vector<int32_t> logits(m*10);npu_perf_t p1{},p2{};
       require(npu_gemm(npu,&inputs[r*64],w1.data(),nullptr,hidden.data(),m,32,64,2,mult,shift,b1.data(),&p1)==0,"layer1");
       require(std::equal(hidden.begin(),hidden.end(),hidden_ref.begin()+r*32),"hidden mismatch");
       require(npu_gemm(npu,hidden.data(),w2.data(),logits.data(),nullptr,m,10,32,1,1,0,b2.data(),&p2)==0,"layer2");
       require(std::equal(logits.begin(),logits.end(),logits_ref.begin()+r*10),"logit mismatch");
       for(unsigned i=0;i<m;i++)hits+=std::max_element(logits.begin()+i*10,logits.begin()+(i+1)*10)-(logits.begin()+i*10)==labels[r+i];
       cycles+=p1.core_cycles+p2.core_cycles;
     }correct=hits;std::cout<<"digits batch="<<batch<<" correct="<<hits<<"/"<<samples<<" hidden and logits bit-exact\n";
   }
   require(correct>=340,"accuracy regression");
   std::cout << "PASS random_cases=" << cases << " core_cycles=" << cycles << '\n';
   return cycles;
}
