// sim_main.cpp — Verilator custom main mit FST-Tracing
// Replaces Verilator's default --binary main (verilated_main.cpp).
// Enables FST waveform output without modifying the SystemVerilog testbenches.

#include <memory>
#include "verilated.h"
#include "verilated_fst_c.h"
#include "Vtb_rv64i.h"

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    contextp->traceEverOn(true);

    const std::unique_ptr<Vtb_rv64i> top{new Vtb_rv64i{contextp.get()}};

    VerilatedFstC* tfp = new VerilatedFstC;
    top->trace(tfp, 99);
    tfp->open("dump.fst");

    while (!contextp->gotFinish()) {
        contextp->timeInc(1);
        top->eval();
        tfp->dump(contextp->time());
    }

    tfp->close();
    delete tfp;
    top->final();
    return 0;
}
