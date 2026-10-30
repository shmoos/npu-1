#pragma once
#include "axi_sim.hpp"
#include <array>

inline void reset_bus(Sim& sim) {
    auto& d=sim.d;
    d.s_axil_awvalid=0; d.s_axil_wvalid=0; d.s_axil_arvalid=0;
    d.s_axil_bready=0; d.s_axil_rready=0; d.rst_n=0;
    sim.tick(); sim.tick();
    require(!d.s_axil_bvalid && !d.s_axil_rvalid,"reset retained response");
    d.rst_n=1; sim.tick();
}

// Launch independent read and write transactions with overlapping outstanding
// requests. Read and write addresses differ; same-address collision is excluded.
inline uint32_t concurrent_transaction(Sim& sim, uint32_t wa, uint32_t wd,
                                       uint8_t strb, uint32_t ra) {
    auto& d=sim.d;
    unsigned ad=sim.rng()%8, dd=sim.rng()%8, rd=sim.rng()%8;
    unsigned bs=8+sim.rng()%16, rs=8+sim.rng()%16;
    bool aw=false,w=false,ar=false,br=false,rr=false;
    uint32_t value=0;
    for(unsigned cycle=0;cycle<256;cycle++) {
        d.s_axil_awaddr=wa; d.s_axil_wdata=wd; d.s_axil_wstrb=strb;
        d.s_axil_araddr=ra;
        d.s_axil_awvalid=!aw && cycle>=ad;
        d.s_axil_wvalid=!w && cycle>=dd;
        d.s_axil_arvalid=!ar && cycle>=rd;
        d.s_axil_bready=cycle>=bs; d.s_axil_rready=cycle>=rs;
        sim.low();
        aw|=d.s_axil_awvalid && d.s_axil_awready;
        w|=d.s_axil_wvalid && d.s_axil_wready;
        ar|=d.s_axil_arvalid && d.s_axil_arready;
        if(d.s_axil_bvalid && d.s_axil_bready) {
            require(!br && d.s_axil_bresp==0,"duplicate/error concurrent write");br=true;
        }
        if(d.s_axil_rvalid && d.s_axil_rready) {
            require(!rr && d.s_axil_rresp==0,"duplicate/error concurrent read");rr=true;value=d.s_axil_rdata;
        }
        sim.tick();
        if(aw && w && ar && br && rr) {
            d.s_axil_awvalid=0;d.s_axil_wvalid=0;d.s_axil_arvalid=0;
            d.s_axil_bready=0;d.s_axil_rready=0;sim.low();return value;
        }
    }
    throw std::runtime_error("concurrent bus timeout");
}

inline void stress_protocol(Sim& sim) {
    // Exercise synchronous operand reads while writes use the other RAM port.
    std::array<uint32_t,32> mirror{};
    for(unsigned i=0;i<mirror.size();i++) {
        mirror[i]=sim.rng();require(sim.write(0x1000+4*i,mirror[i])==0,"stress init");
    }
    for(unsigned i=0;i<1000;i++) {
        unsigned w=sim.rng()%mirror.size(),r=sim.rng()%mirror.size();
        if(r==w) r=(r+1)%mirror.size();
        uint32_t data=sim.rng();uint8_t mask=sim.rng()%16;
        auto got=concurrent_transaction(sim,0x1000+4*w,data,mask,0x1000+4*r);
        require(got==mirror[r],"concurrent RAM scoreboard mismatch");
        for(unsigned b=0;b<4;b++) if(mask&(1u<<b)) {
            uint32_t m=255u<<(8*b);mirror[w]=(mirror[w]&~m)|(data&m);
        }
        uint32_t check;require(sim.read(0x1000+4*w,&check)==0 && check==mirror[w],"concurrent write lost");
    }
    // Hard reset with AW-only, W-only, both captured, B held, AR pending,
    // R held, and overlapping held read/write responses. Aborted requests
    // must not combine with post-reset requests or produce ghost responses.
    for(unsigned scenario=0;scenario<7;scenario++) {
        reset_bus(sim);auto& d=sim.d;
        d.s_axil_awaddr=0x40;d.s_axil_wdata=0x5a5a5a5a;d.s_axil_wstrb=15;
        d.s_axil_araddr=0;d.s_axil_bready=0;d.s_axil_rready=0;
        d.s_axil_awvalid=(scenario==0 || scenario==2 || scenario==3 || scenario==6);
        d.s_axil_wvalid=(scenario==1 || scenario==2 || scenario==3 || scenario==6);
        d.s_axil_arvalid=(scenario==4 || scenario==5 || scenario==6);
        sim.tick();d.s_axil_awvalid=0;d.s_axil_wvalid=0;d.s_axil_arvalid=0;
        if(scenario==3 || scenario==5 || scenario==6)for(int i=0;i<4;i++)sim.tick();
        sim.low();
        if(scenario==0) require(!d.s_axil_awready && d.s_axil_wready && !d.s_axil_bvalid,"AW-only setup");
        if(scenario==1) require(d.s_axil_awready && !d.s_axil_wready && !d.s_axil_bvalid,"W-only setup");
        if(scenario==2 || scenario==3) require(d.s_axil_bvalid,"pending B setup");
        if(scenario==4) require(!d.s_axil_arready && !d.s_axil_rvalid,"AR-pending setup");
        if(scenario==5) require(d.s_axil_rvalid,"pending R setup");
        if(scenario==6) require(d.s_axil_bvalid && d.s_axil_rvalid,"overlapping responses setup");
        reset_bus(sim);
        d.s_axil_bready=1;d.s_axil_rready=1;
        for(int i=0;i<8;i++) {sim.tick();require(!d.s_axil_bvalid && !d.s_axil_rvalid,"ghost response after reset");}
        d.s_axil_bready=0;d.s_axil_rready=0;
        uint32_t value;
        require(sim.read(0x40,&value)==0 && value==0,"aborted write leaked across reset");
        require(sim.write(0x40,scenario+11)==0,"write recovery");
        require(sim.read(0x40,&value)==0 && value==scenario+11,"read recovery");
    }
    reset_bus(sim);
    std::cout<<"PASS 1000 concurrent AXI read/write transactions and 7 reset phases\n";
}
