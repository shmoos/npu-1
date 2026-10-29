#include "Vsystolic_array_4x4.h"
#include "verilated.h"
#include "verilated_vcd_c.h"
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>

int main(int argc, char** argv) {
    if (argc < 2 || argc > 3) return 2;
    std::ifstream vectors(argv[1]);
    if (!vectors) return 2;
    auto context = std::make_unique<VerilatedContext>();
    context->commandArgs(argc, argv);
    context->traceEverOn(argc == 3);
    auto dut = std::make_unique<Vsystolic_array_4x4>(context.get());
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
    std::string line, label;
    std::uint64_t cycle = 0;
    while (std::getline(vectors, line)) {
        if (line.empty()) continue;
        if (line[0] == '#') { label = line; continue; }
        unsigned reset, clear, step, av, bv;
        std::uint32_t a, b, expected_a, expected_b;
        unsigned expected_av, expected_bv;
        std::array<std::int64_t, 16> expected;
        std::istringstream row(line);
        if (!(row >> reset >> clear >> step >> av >> bv >> a >> b)) return 2;
        for (auto& value : expected) if (!(row >> value)) return 2;
        if (!(row >> expected_a >> expected_b >> expected_av >> expected_bv)) return 2;
        dut->clk = 0;
        dut->reset = reset; dut->clear = clear; dut->step = step;
        dut->a_valid = av; dut->b_valid = bv; dut->a_in = a; dut->b_in = b;
        evaluate();
        dut->clk = 1;
        evaluate();
        for (unsigned pe = 0; pe < 16; ++pe) {
            std::int64_t actual = dut->accumulators[pe];
            if (actual >= (1LL << 31)) actual -= (1LL << 32);
            if (actual != expected[pe]) {
                std::cerr << label << "\nARRAY_MISMATCH cycle=" << cycle
                          << " row=" << pe/4 << " col=" << pe%4
                          << " expected=" << expected[pe] << " actual=" << actual << '\n';
                return 1;
            }
        }
        if (dut->a_out != expected_a || dut->b_out != expected_b ||
            dut->a_valid_out != expected_av || dut->b_valid_out != expected_bv) {
            std::cerr << label << "\nARRAY_FORWARD_MISMATCH cycle=" << cycle
                      << " expected=" << expected_a << ',' << expected_b << ',' << expected_av << ',' << expected_bv
                      << " actual=" << dut->a_out << ',' << dut->b_out << ',' << unsigned(dut->a_valid_out)
                      << ',' << unsigned(dut->b_valid_out) << '\n';
            return 1;
        }
        dut->clk = 0;
        evaluate();
        ++cycle;
    }
    if (!cycle) return 2;
    dut->final();
    if (trace) trace->close();
    std::cout << "PASS: " << cycle << " array cycles checked, all 16 accumulators and edge forwarding\n";
    return 0;
}
