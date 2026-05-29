# IDDQ Fault Testing for CPU FSM

IDDQ (Quiescent Current) fault testing implementation for the CPU Finite State Machine of the RWU-RV64i RISC-V processor. Tested on Zybo FPGA board using Vivado 2024.2.

## FSM Overview

The CPU FSM has 4 states encoded in 2 flip-flops:

| State | Encoding | Description |
|-------|----------|-------------|
| FETCH0_ST | 2'b00 | PC driven to instruction memory address |
| FETCH1_ST | 2'b01 | Instruction register latched from memory |
| EXEC_ST   | 2'b10 | Instruction execution |
| EXECLD_ST | 2'b11 | Wait for load data (load instructions only) |

## IDDQ Testing Methodology

IDDQ testing works by:
1. Driving the FSM into a specific state using normal clock cycles
2. **Freezing the clock** (`iddq_measure = 1`) — all flip-flops hold state
3. Measuring quiescent VDD supply current at each frozen state
4. Anomalous leakage current indicates a stuck-at or bridging fault

## Project Structure

RWU_RV/RV_NoPipeline/
├── src/
│   └── asCPUx.sv                    # Original CPU FSM (RWU-RV64i)
├── tb/
│   └── tb_iddq_cpu_fsm.sv           # IDDQ testbench (normal)
└── RV_NoPipeline.srcs/
├── sources_1/new/
│   ├── iddq_cpu_fsm_top.sv          # Synthesizable IDDQ wrapper
│   ├── iddq_cpu_fsm_fault_top.sv    # Fault injection RTL
└── sim_1/new/
└── tb_iddq_cpu_fsm_fault.sv     # Fault injection testbench

## Test Results

### Normal IDDQ Simulation
| Vector | State | Result |
|--------|-------|--------|
| V1 | FETCH0_ST (2'b00) | ✅ PASS |
| V2 | FETCH1_ST (2'b01) | ✅ PASS |
| V3 | EXEC_ST   (2'b10) | ✅ PASS |
| V4 | EXECLD_ST (2'b11) | ✅ PASS |

**Result: PASS=10, FAIL=0**

### Fault Injection Simulation

| Fault | Description | Vectors Detected | Result |
|-------|-------------|-----------------|--------|
| SA0 on state_s[0] | bit0 stuck-at-0 | FETCH1, EXEC, EXECLD | ✅ Detected |
| SA1 on state_s[0] | bit0 stuck-at-1 | EXEC | ✅ Detected |
| SA0 on state_s[1] | bit1 stuck-at-0 | EXEC, EXECLD | ✅ Detected |
| SA1 on state_s[1] | bit1 stuck-at-1 | FETCH1, EXECLD | ✅ Detected |

**Fault Coverage: 100% (4/4 faults detected)**

### Synthesis & Implementation
- Target: Zybo (xc7z010clg400-1)
- Tool: Vivado 2024.2
- WNS: 5.939 ns ✅
- Failing Endpoints: 0 ✅
- All timing constraints met ✅

## Hardware Mapping (Zybo)

| Signal | Pin | Physical |
|--------|-----|----------|
| clk_i | L16 | 125 MHz clock |
| rst_i | R18 | BTN0 |
| load_pending_i | G15 | SW0 |
| iddq_measure_i | P15 | SW1 |
| fault_sel_i[0] | W13 | SW2 |
| fault_sel_i[1] | P16 | SW3 |
| fetch0_o | M14 | LED0 |
| fetch1_o | M15 | LED1 |
| exec_o | G14 | LED2 |
| execld_o | D18 | LED3 |

## How to Run

### Normal IDDQ Simulation
1. Open `RV_NoPipeline.xpr` in Vivado 2024.2
2. Set `tb_iddq_cpu_fsm` as simulation top
3. Run Behavioral Simulation

### Fault Injection Simulation
1. Set `tb_iddq_cpu_fsm_fault` as simulation top
2. Run Behavioral Simulation

### Synthesis & Implementation
1. Set `iddq_cpu_fsm_top` as design top
2. Run Synthesis → Implementation

### Fault Injection Synthesis
1. Set `iddq_cpu_fsm_fault_top` as design top
2. Run Synthesis → Implementation

## Base Project

This work is built on top of the RWU-RV64i RISC-V processor:
[https://github.com/asiggel/rwu-rv64iV2.0](https://github.com/asiggel/rwu-rv64iV2.0)
