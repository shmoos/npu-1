#include "axi_sim.hpp"
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    try {
        Sim sim(42);
        uint32_t value=0;
        npu_transport_t transport{attach,detach,poke,peek,&sim};
        npu_t* npu=npu_init(&transport,0);
        require(npu!=nullptr,"initial attach");
        require(sim.write(NPU_REG_K,1024)==0,"configure long job");
        require(sim.write(NPU_REG_COMMAND_SEQ,17)==0,"sequence write");
        require(sim.write(NPU_REG_CONTROL,1)==0,"start long job");
        // Compiled with a 64-cycle limit; require error AND return to idle.
        bool stopped=false;
        for(int i=0;i<40;i++) {
            require(sim.read(NPU_REG_STATUS,&value)==0,"read status");
            if((value & 5)==4) { stopped=true; break; }
        }
        require(stopped,"watchdog error failed to release BUSY");
        require(!(value & NPU_STATUS_DONE),"timeout incorrectly reported DONE");
        require(sim.read(NPU_REG_ERROR_CODE,&value)==0 && value==6,"watchdog error code");
        require(sim.read(NPU_REG_COMPLETED_SEQ,&value)==0 && value!=17,"timeout completed sequence");
        require(sim.read(NPU_REG_CYCLES_LO,&value)==0 && value>=64 && value<70,"timeout cycles");
        // Recover with W1C only, without resetting away the controller state.
        require(sim.write(NPU_REG_STATUS,4)==0,"clear error");
        const int8_t a[4]={1,-2,3,-4}, b[4]={4,3,2,2};
        int32_t c=0; npu_perf_t perf{};
        require(npu_gemm(npu,a,b,&c,nullptr,1,1,4,0,1,0,nullptr,&perf)==0,"recovery GEMM");
        require(c==-4,"recovery result");
        npu_close(npu);
        std::cout<<"PASS watchdog timeout/error/idle/cycles/recovery (limit=64)\n";
        return 0;
    }catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<'\n';return 1;}
}
