#include "axi_sim.hpp"
#include <memory>

template<class T> void array_json(std::ostream& out, const std::vector<T>& values) {
    out << '[';
    for(size_t i=0;i<values.size();i++) { if(i) out << ',';out << int64_t(values[i]); }
    out << ']';
}
int main(int argc, char** argv) {
    try {
        require(argc==3,"usage: predict_sim request.bin result.json");
        Verilated::commandArgs(argc,argv);
        std::ifstream f(argv[1],std::ios::binary);
        require(u32(f)==0x4e505532,"prediction request magic");
        auto input=vec<int8_t>(f,64),w1=vec<int8_t>(f,64*32);
        auto b1=vec<int32_t>(f,32);auto mult=u32(f),shift=u32(f);
        auto w2=vec<int8_t>(f,32*10);auto b2=vec<int32_t>(f,10);
        require(f.peek()==std::ifstream::traits_type::eof(),"trailing request data");
        Sim sim(42);npu_transport_t transport{attach,detach,poke,peek,&sim};
        std::unique_ptr<npu_t,decltype(&npu_close)> npu(npu_init(&transport,0),npu_close);
        require(bool(npu),"host attach");
        std::vector<int8_t> hidden(32);std::vector<int32_t> biased(32),logits(10);
        npu_perf_t p1{},p2{};auto before=sim.ticks;
        require(npu_gemm(npu.get(),input.data(),w1.data(),biased.data(),hidden.data(),1,32,64,2,mult,shift,b1.data(),&p1)==0,"hidden layer");
        auto after_l1=sim.ticks;
        // Only the RTL's actual hidden outputs are fed to the second layer.
        require(npu_gemm(npu.get(),hidden.data(),w2.data(),logits.data(),nullptr,1,10,32,1,1,0,b2.data(),&p2)==0,"output layer");
        unsigned prediction=std::max_element(logits.begin(),logits.end())-logits.begin();
        std::ofstream out(argv[2]);require(bool(out),"open output JSON");
        out << "{\"prediction\":" << prediction << ",\"hidden_i8\":";array_json(out,hidden);
        out << ",\"biased_1_i32\":";array_json(out,biased);
        out << ",\"logits_i32\":";array_json(out,logits);
        out << ",\"layer_core_cycles\":[" << p1.core_cycles << ',' << p2.core_cycles
            << "],\"layer_bus_cycles\":[" << after_l1-before << ',' << sim.ticks-after_l1
            << "],\"core_cycles\":" << p1.core_cycles+p2.core_cycles
            << ",\"bus_cycles\":" << sim.ticks-before << "}\n";
        out.close();require(bool(out),"write output JSON");
        std::cout << "PASS RTL prediction=" << prediction << " core_cycles=" << p1.core_cycles+p2.core_cycles << '\n';
        return 0;
    } catch(const std::exception& e) {std::cerr << "FAIL: " << e.what() << '\n';return 1;}
}
