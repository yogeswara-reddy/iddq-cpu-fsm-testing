#include <memory>
#include "verilated.h"
#include "verilated_fst_c.h"
#include "Vtb_asScratch.h"

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};
    contextp->commandArgs(argc, argv);
    contextp->traceEverOn(true);
    const std::unique_ptr<Vtb_asScratch> top{new Vtb_asScratch{contextp.get()}};
    VerilatedFstC* tfp = new VerilatedFstC;
    top->trace(tfp, 99);
    tfp->open("dump_scratch.fst");
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
