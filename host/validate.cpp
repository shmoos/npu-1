#include "workload.hpp"
#include <chrono>
int main(int argc,char**argv) {
 if(argc!=4 || std::string(argv[1])!="--aws") {
   std::cerr<<"Usage: npu_validate --aws fixtures.bin SLOT (runs on an already loaded F2)\n";return 2;
 }
 npu_transport_t*t=nullptr;npu_t*n=nullptr;
 try {
   int slot=std::stoi(argv[3]);require(slot>=0,"invalid slot");
   t=npu_transport_create_aws();require(t!=nullptr,"AWS transport unavailable");
   n=npu_init(t,slot);require(n!=nullptr,"attach/ID/ABI/reset failed");
   auto start=std::chrono::steady_clock::now();auto cycles=run_workload(n,argv[2]);
   auto seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
   std::cout<<"Hardware validation complete. core_cycles="<<cycles<<" host_seconds="<<seconds<<"\n";
   npu_close(n);npu_transport_destroy(t);return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<'\n';if(n)npu_close(n);npu_transport_destroy(t);return 1;}
}
