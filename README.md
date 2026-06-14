# IDDQ Fault Testing — CPU FSM and ALU

IDDQ (Quiescent Current) fault testing implementation for the CPU Finite State Machine and Arithmetic Logic Unit of the RWU-RV64i RISC-V processor. Simulated and synthesized on the Zybo Z7-10 FPGA board using Vivado 2024.2.

---

## IDDQ Testing Methodology

IDDQ testing works by driving the circuit into a known static state, then freezing all switching activity and measuring the quiescent VDD supply current. A fault-free circuit draws only leakage current. A stuck-at or bridging fault causes an anomalous current path, which shows up as elevated IDDQ.

In simulation, the freeze is modeled by a clock-enable signal (`iddq_measure_i = 1`). On hardware, a `BUFGCE` primitive gates the clock directly.

Test flow per vector:
1. Drive the DUT into the target state using normal clock cycles
2. Assert `iddq_measure_i = 1` — all flip-flops hold state
3. Observe outputs and compare against golden reference
4. Release `iddq_measure_i = 0` before the next transition

---

## Part 1 — CPU FSM

### FSM Overview

The CPU FSM has 4 states encoded in 2 flip-flops:

| State | Encoding | Description |
|-------|----------|-------------|
| FETCH0_ST | 2'b00 | PC driven to instruction memory address |
| FETCH1_ST | 2'b01 | Instruction register latched from memory |
| EXEC_ST   | 2'b10 | Instruction execution |
| EXECLD_ST | 2'b11 | Wait for load data (load instructions only) |

### Fault Model

Stuck-at faults on both bits of the 2-bit state register `state_s[1:0]`:

| Fault ID | Description |
|----------|-------------|
| SA0_B0 | state_s[0] stuck-at-0 |
| SA1_B0 | state_s[0] stuck-at-1 |
| SA0_B1 | state_s[1] stuck-at-0 |
| SA1_B1 | state_s[1] stuck-at-1 |

### Test Results

#### Normal IDDQ Simulation

| Vector | State | Result |
|--------|-------|--------|
| V1 | FETCH0_ST (2'b00) | ✅ PASS |
| V2 | FETCH1_ST (2'b01) | ✅ PASS |
| V3 | EXEC_ST   (2'b10) | ✅ PASS |
| V4 | EXECLD_ST (2'b11) | ✅ PASS |

**Result: PASS=10, FAIL=0**

#### Fault Injection Simulation

| Fault | Description | Vectors Detected | Result |
|-------|-------------|-----------------|--------|
| SA0 on state_s[0] | bit0 stuck-at-0 | FETCH1, EXEC, EXECLD | ✅ Detected |
| SA1 on state_s[0] | bit0 stuck-at-1 | EXEC | ✅ Detected |
| SA0 on state_s[1] | bit1 stuck-at-0 | EXEC, EXECLD | ✅ Detected |
| SA1 on state_s[1] | bit1 stuck-at-1 | FETCH1, EXECLD | ✅ Detected |

**Fault Coverage: 100% (4/4 faults detected)**

#### Synthesis & Implementation

| Metric | Value |
|--------|-------|
| Target | Zybo (xc7z010clg400-1) |
| Tool | Vivado 2024.2 |
| WNS | 5.939 ns ✅ |
| Failing Endpoints | 0 ✅ |

### Hardware Mapping (Zybo)

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

> Note: `iddq_cpu_fsm_top.sv` (hardware target) uses a `BUFGCE` primitive for real clock gating. `iddq_cpu_fsm_fault_top.sv` (fault injection) uses a clock-enable register instead — simulation-safe and avoids gated-clock CDC warnings.

---

## Part 2 — ALU

### ALU Overview

8-bit combinational ALU (reduced from 32-bit to fit FPGA resources while preserving the fault injection concept). Supports 8 operations:

| Encoding | Operation |
|----------|-----------|
| 3'd0 | ADD |
| 3'd1 | SUB |
| 3'd2 | AND |
| 3'd3 | OR  |
| 3'd4 | XOR |
| 3'd5 | SLT (signed less-than) |
| 3'd6 | SLL (shift left logical) |
| 3'd7 | SRL (shift right logical) |

### Fault Model

Stuck-at faults on the lower result bits and zero flag — chosen to be observable with compact test vectors:

| Fault ID | Description |
|----------|-------------|
| FAULT_RES0_SA0 | result_o[0] stuck-at-0 |
| FAULT_RES0_SA1 | result_o[0] stuck-at-1 |
| FAULT_RES1_SA0 | result_o[1] stuck-at-0 |
| FAULT_RES1_SA1 | result_o[1] stuck-at-1 |
| FAULT_RES2_SA0 | result_o[2] stuck-at-0 |
| FAULT_RES2_SA1 | result_o[2] stuck-at-1 |
| FAULT_ZERO_SA0 | zero_o stuck-at-0 |
| FAULT_ZERO_SA1 | zero_o stuck-at-1 |

### Test Vectors

Each vector is chosen to sensitise a specific bit position:

| Vector | Inputs | Operation | Golden Result | Targets |
|--------|--------|-----------|---------------|---------|
| ADD_RES1 | 0x00 + 0x01 | ADD | 0x01, zero=0 | result[0] SA0 |
| SUB_ZERO | 0x05 − 0x05 | SUB | 0x00, zero=1 | result[0] SA1, zero SA0 |
| ADD_RES2 | 0x01 + 0x01 | ADD | 0x02, zero=0 | result[1] SA0 |
| SLL_RES4 | 0x01 << 2   | SLL | 0x04, zero=0 | result[2] SA0 |
| XOR_ALL1 | 0xAA ^ 0x55 | XOR | 0xFF, zero=0 | result[0/1/2] SA1, zero SA1 |
| OR_RES6  | 0x02 \| 0x04 | OR | 0x06, zero=0 | result[1/2] cross-check |
| SLT_RES1 | 3 < 7       | SLT | 0x01, zero=0 | result[0] SA0 (SLT path) |
| AND_ZERO | 0xAA & 0x55 | AND | 0x00, zero=1 | zero SA1 |

### Test Results

#### Normal IDDQ Simulation

| Vector | Result | zero | Pass/Fail |
|--------|--------|------|-----------|
| ADD_RES1 | 0x01 | 0 | ✅ PASS |
| SUB_ZERO | 0x00 | 1 | ✅ PASS |
| ADD_RES2 | 0x02 | 0 | ✅ PASS |
| SLL_RES4 | 0x04 | 0 | ✅ PASS |
| XOR_ALL1 | 0xFF | 0 | ✅ PASS |
| OR_RES6  | 0x06 | 0 | ✅ PASS |
| SLT_RES1 | 0x01 | 0 | ✅ PASS |
| AND_ZERO | 0x00 | 1 | ✅ PASS |

**Result: PASS=8, FAIL=0**

#### Fault Injection Simulation

| Fault | Description | Detected By | Result |
|-------|-------------|-------------|--------|
| FAULT_RES0_SA0 | result[0] stuck-at-0 | ADD_RES1, XOR_ALL1, SLT_RES1 | ✅ Detected |
| FAULT_RES0_SA1 | result[0] stuck-at-1 | SUB_ZERO, ADD_RES2, SLL_RES4, OR_RES6, AND_ZERO | ✅ Detected |
| FAULT_RES1_SA0 | result[1] stuck-at-0 | ADD_RES2, XOR_ALL1, OR_RES6 | ✅ Detected |
| FAULT_RES1_SA1 | result[1] stuck-at-1 | ADD_RES1, SUB_ZERO, SLL_RES4, SLT_RES1, AND_ZERO | ✅ Detected |
| FAULT_RES2_SA0 | result[2] stuck-at-0 | SLL_RES4, XOR_ALL1, OR_RES6 | ✅ Detected |
| FAULT_RES2_SA1 | result[2] stuck-at-1 | ADD_RES1, SUB_ZERO, ADD_RES2, SLT_RES1, AND_ZERO | ✅ Detected |
| FAULT_ZERO_SA0 | zero_o stuck-at-0   | SUB_ZERO, AND_ZERO | ✅ Detected |
| FAULT_ZERO_SA1 | zero_o stuck-at-1   | ADD_RES1, ADD_RES2, SLL_RES4, XOR_ALL1, OR_RES6, SLT_RES1 | ✅ Detected |

**Fault Coverage: 100% (8/8 faults detected)**

> The ALU is simulation-only in this project (no XDC provided). IDDQ freeze is modeled by applying stable static input vectors — no clock gating is needed for a combinational block.

---

## Project Structure

```
RWU_RV/RV_NoPipeline/
├── src/
│   └── asCPUx.sv                        # Original CPU FSM (RWU-RV64i)
├── tb/
│   └── tb_iddq_cpu_fsm.sv               # FSM IDDQ testbench (no fault injection)
└── RV_NoPipeline.srcs/
    ├── sources_1/new/
    │   ├── iddq_cpu_fsm_top.sv           # Synthesizable FSM IDDQ wrapper (BUFGCE)
    │   ├── iddq_cpu_fsm_fault_top.sv     # FSM fault injection RTL (clock-enable)
    │   └── iddq_alu_top.sv               # ALU fault injection RTL
    ├── sim_1/new/
    │   ├── tb_iddq_cpu_fsm_fault.sv      # FSM fault injection testbench
    │   └── tb_iddq_alu_fault.sv          # ALU fault injection testbench
    └── constrs_1/new/
        ├── iddq_cpu_fsm_top.xdc          # Pin constraints (normal FSM)
        └── iddq_cpu_fsm_fault_top.xdc    # Pin constraints (fault injection FSM)
```

---

## How to Run

### FSM — Normal IDDQ Simulation
1. Open `RV_NoPipeline.xpr` in Vivado 2024.2
2. Set `tb_iddq_cpu_fsm` as simulation top
3. Run Behavioral Simulation

### FSM — Fault Injection Simulation
1. Set `tb_iddq_cpu_fsm_fault` as simulation top
2. Run Behavioral Simulation

### ALU — Fault Injection Simulation
1. Set `tb_iddq_alu_fault` as simulation top
2. Run Behavioral Simulation

### FSM — Synthesis & Implementation (no fault injection)
1. Set `iddq_cpu_fsm_top` as design top
2. Run Synthesis → Implementation

### FSM — Synthesis & Implementation (with fault injection)
1. Set `iddq_cpu_fsm_fault_top` as design top
2. Run Synthesis → Implementation

---

## Base Project

This work is built on top of the RWU-RV64i RISC-V processor:
[https://github.com/asiggel/rwu-rv64iV2.0](https://github.com/asiggel/rwu-rv64iV2.0)
