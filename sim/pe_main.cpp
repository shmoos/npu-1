#include "Vmac_pe.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>

int main(int argc, char** argv) {
    if (argc < 2 || argc > 3) {
        std::cerr << "Usage: Vmac_pe vectors.txt [waveform.vcd]\n";
        return 2;
    }
    std::ifstream vectors(argv[1]);
    if (!vectors) { std::cerr << "Cannot read vectors\n"; return 2; }
    auto context = std::make_unique<VerilatedContext>();
    context->commandArgs(argc, argv);
    context->traceEverOn(argc == 3);
    auto dut = std::make_unique<Vmac_pe>(context.get());
    std::unique_ptr<VerilatedVcdC> trace;
    if (argc == 3) {
        trace = std::make_unique<VerilatedVcdC>();
        dut->trace(trace.get(), 99);
        trace->open(argv[2]);
    }
    auto evaluate = [&]() {
        dut->eval();
        if (trace) trace->dump(context->time());
        context->timeInc(5);
    };
    std::string line;
    std::string case_label;
    std::uint64_t cycle = 0;
    while (std::getline(vectors, line)) {
        if (line.empty()) continue;
        if (line[0] == '#') { case_label = line; continue; }
        int reset, clear, step, av, bv, a, b;
        std::int64_t expected_acc;
        unsigned expected_a, expected_b, expected_av, expected_bv;
        std::istringstream row(line);
        if (!(row >> reset >> clear >> step >> av >> bv >> a >> b
                  >> expected_acc >> expected_a >> expected_b >> expected_av >> expected_bv)) {
            std::cerr << "Malformed vector at cycle " << cycle << '\n';
            return 2;
        }
        dut->clk = 0;
        dut->reset = reset;
        dut->clear = clear;
        dut->step = step;
        dut->a_valid = av;
        dut->b_valid = bv;
        dut->a_in = static_cast<std::uint8_t>(a);
        dut->b_in = static_cast<std::uint8_t>(b);
        evaluate();
        dut->clk = 1;
        evaluate();
        std::int64_t actual_acc = dut->acc;
        if (actual_acc >= (1LL << 31)) actual_acc -= (1LL << 32);
        if (actual_acc != expected_acc || dut->a_out != expected_a ||
            dut->b_out != expected_b || dut->a_valid_out != expected_av ||
            dut->b_valid_out != expected_bv) {
            std::cerr << case_label << '\n' << "PE_MISMATCH cycle=" << cycle << " inputs="
                      << reset << ',' << clear << ',' << step << ',' << av << ',' << bv
                      << ',' << a << ',' << b << " expected="
                      << expected_acc << ',' << expected_a << ',' << expected_b << ','
                      << expected_av << ',' << expected_bv << " actual="
                      << actual_acc << ',' << unsigned(dut->a_out) << ',' << unsigned(dut->b_out)
                      << ',' << unsigned(dut->a_valid_out) << ',' << unsigned(dut->b_valid_out) << '\n';
            return 1;
        }
        dut->clk = 0;
        evaluate();
        ++cycle;
    }
    if (cycle == 0) { std::cerr << "Empty vector set\n"; return 2; }
    dut->final();
    if (trace) trace->close();
    std::cout << "PASS: " << cycle << " cycles checked, accumulator and all forwarding outputs\n";
    return 0;
}
