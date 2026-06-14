````markdown
# IDDQ-Style Fault Testing — CPU FSM

IDDQ-style stuck-at fault testing implementation for the CPU Finite State Machine (FSM) of the RWU-RV64i RISC-V processor. The design was simulated, synthesized, and implemented on the Zybo Z7-10 FPGA target using Vivado 2024.2.

> Note: This project performs **IDDQ-style RTL fault simulation**. It does not perform real physical IDDQ current measurement. The `iddq_measure_i` signal is used as a freeze/measurement control signal in simulation and FPGA testing.

---

## Project Objective

The objective of this project is to verify whether stuck-at faults in the CPU control FSM can be detected using an IDDQ-style test methodology.

The test focuses on:

- Freezing the FSM in known stable states
- Injecting stuck-at faults on FSM state bits
- Comparing the observed FSM output against the golden fault-free reference
- Calculating stuck-at fault coverage

The current project scope is limited to the **CPU FSM fault test**. Standalone ALU fault-testing files that were added earlier have been removed because they did not test the original RISC-V ALU module.

---

## IDDQ-Style Testing Methodology

Traditional IDDQ testing works by driving a CMOS circuit into a known static state and measuring the quiescent VDD supply current. A fault-free circuit draws only leakage current, while physical defects such as bridging faults may create abnormal current paths.

In this RTL-level project, actual current is not measured. Instead, the IDDQ concept is modeled by holding the FSM state stable during an observation window.

Test flow:

1. Reset the DUT.
2. Drive the FSM into a known target state using normal clock cycles.
3. Assert `iddq_measure_i = 1` to freeze the FSM state.
4. Observe FSM outputs.
5. Compare the observed outputs with the expected golden reference.
6. Inject stuck-at faults using `fault_sel_i`.
7. Repeat the same observation sequence.
8. Count detected faults and calculate fault coverage.

---

## CPU FSM Overview

The CPU FSM contains four states encoded using two flip-flops:

| State | Encoding | Description |
|------|----------|-------------|
| `FETCH0_ST` | `2'b00` | First instruction fetch phase |
| `FETCH1_ST` | `2'b01` | Second instruction fetch phase |
| `EXEC_ST` | `2'b10` | Instruction execution phase |
| `EXECLD_ST` | `2'b11` | Load execution/wait phase |

Expected golden sequence:

```text
FETCH0_ST → FETCH1_ST → EXEC_ST → EXECLD_ST
````

The transition to `EXECLD_ST` is controlled using `load_pending_i`.

---

## Fault Model

The project uses a stuck-at fault model on the FSM state register bits.

| Fault Select | Injected Fault          |
| ------------ | ----------------------- |
| `3'd0`       | No fault                |
| `3'd1`       | `state_s[0]` stuck-at-0 |
| `3'd2`       | `state_s[0]` stuck-at-1 |
| `3'd3`       | `state_s[1]` stuck-at-0 |
| `3'd4`       | `state_s[1]` stuck-at-1 |

The fault selector input is:

```verilog
fault_sel_i[2:0]
```

---

## Main Design Files

```text
RWU_RV/RV_NoPipeline/
└── RV_NoPipeline.srcs/
    ├── sources_1/new/
    │   └── iddq_cpu_fsm_fault_top.sv
    ├── sim_1/new/
    │   └── tb_iddq_cpu_fsm_fault.sv
    └── constrs_1/new/
        └── iddq_cpu_fsm_fault_top.xdc
```

### Important Modules

| File                         | Purpose                                       |
| ---------------------------- | --------------------------------------------- |
| `iddq_cpu_fsm_fault_top.sv`  | Synthesizable CPU FSM fault-injection wrapper |
| `tb_iddq_cpu_fsm_fault.sv`   | Testbench for FSM stuck-at fault simulation   |
| `iddq_cpu_fsm_fault_top.xdc` | Zybo Z7-10 pin and clock constraints          |

---

## FSM Fault Simulation Result

The FSM fault test was run using Vivado behavioral simulation.

### Golden No-Fault Run

| Vector   | Expected State | Result |
| -------- | -------------- | ------ |
| `FETCH0` | `00`           | PASS   |
| `FETCH1` | `01`           | PASS   |
| `EXEC`   | `10`           | PASS   |
| `EXECLD` | `11`           | PASS   |

Golden run result:

```text
Golden run failures: 0
```

This confirms that the fault-free FSM behavior is correct.

---

## Fault Injection Simulation Result

| Fault                 | Description      | Detected By                | Result   |
| --------------------- | ---------------- | -------------------------- | -------- |
| `SA0` on `state_s[0]` | Bit 0 stuck-at-0 | `FETCH1`, `EXEC`, `EXECLD` | Detected |
| `SA1` on `state_s[0]` | Bit 0 stuck-at-1 | `EXEC`, `EXECLD`           | Detected |
| `SA0` on `state_s[1]` | Bit 1 stuck-at-0 | `EXEC`, `EXECLD`           | Detected |
| `SA1` on `state_s[1]` | Bit 1 stuck-at-1 | `FETCH1`                   | Detected |

Final simulation summary:

```text
Golden run failures   : 0
Total faults injected : 4
Faults detected       : 4
Fault coverage        : 100%
```

Therefore, all targeted FSM stuck-at faults were detected.

---

## Synthesis and Implementation

The FSM fault-injection wrapper was synthesized and implemented for the Zybo Z7-10 FPGA target.

| Item             | Value              |
| ---------------- | ------------------ |
| FPGA Device      | `xc7z010clg400-1`  |
| Tool             | Vivado 2024.2      |
| Clock Constraint | 8 ns               |
| Clock Name       | `sys_clk`          |
| Fault Coverage   | 100% in simulation |

The implemented design uses the board switches/buttons to control reset, load-pending, IDDQ measurement, and fault selection. FSM state outputs are mapped to LEDs/PMOD pins for observation.

---

## Zybo Z7-10 Hardware Mapping

| Signal           | Pin   | Board Connection    |
| ---------------- | ----- | ------------------- |
| `clk_i`          | `L16` | 125 MHz board clock |
| `rst_i`          | `R18` | BTN0                |
| `load_pending_i` | `G15` | SW0                 |
| `iddq_measure_i` | `P15` | SW1                 |
| `fault_sel_i[0]` | `W13` | SW2                 |
| `fault_sel_i[1]` | `T16` | SW3                 |
| `fault_sel_i[2]` | `P16` | BTN1                |
| `fetch0_o`       | `M14` | LED0                |
| `fetch1_o`       | `M15` | LED1                |
| `exec_o`         | `G14` | LED2                |
| `execld_o`       | `D18` | LED3                |
| `state_obs_o[0]` | `N15` | PMOD JA[0]          |
| `state_obs_o[1]` | `L14` | PMOD JA[1]          |
| `fault_active_o` | `K16` | PMOD JA[2]          |

---

## Timing and Methodology Notes

A clock constraint is applied to `clk_i`:

```tcl
create_clock -period 8.000 -name sys_clk [get_ports clk_i]
```

The FSM clock is therefore constrained for implementation timing analysis.

Some methodology warnings may remain related to missing external input/output delay constraints on switch, button, LED, and PMOD signals. These I/O signals are used only for manual control and observation in this test setup, not as a synchronous external interface.

False paths are applied to manual/static control inputs:

```tcl
set_false_path -from [get_ports rst_i]
set_false_path -from [get_ports load_pending_i]
set_false_path -from [get_ports iddq_measure_i]
set_false_path -from [get_ports {fault_sel_i[*]}]
```

---

## How to Run

### 1. Open the Project

Open the Vivado project:

```text
RWU_RV/RV_NoPipeline/RV_NoPipeline.xpr
```

### 2. Run FSM Fault Simulation

Set simulation top:

```text
tb_iddq_cpu_fsm_fault
```

Run:

```text
Run Behavioral Simulation
```

Expected final result:

```text
Golden run failures   : 0
Total faults injected : 4
Faults detected       : 4
Fault coverage        : 100%
```

### 3. Run FSM Synthesis and Implementation

Set synthesis top:

```text
iddq_cpu_fsm_fault_top
```

Then run:

```text
Run Synthesis
Run Implementation
Open Implemented Design
```

### 4. Generate Reports

Recommended reports:

```text
Report Utilization
Report Timing Summary
Report Methodology
```

---



## Base Project

This work is built on top of the RWU-RV64i RISC-V processor project:

```text
https://github.com/asiggel/rwu-rv64iV2.0
```

---

## Final Result

The CPU FSM IDDQ-style stuck-at fault test was successfully completed.

```text
Golden run failures   : 0
Total faults injected : 4
Faults detected       : 4
Fault coverage        : 100%
```

The project demonstrates RTL-level IDDQ-style fault testing on the CPU control FSM and verifies that all targeted state-register stuck-at faults are observable through the selected test vectors.

```
```
