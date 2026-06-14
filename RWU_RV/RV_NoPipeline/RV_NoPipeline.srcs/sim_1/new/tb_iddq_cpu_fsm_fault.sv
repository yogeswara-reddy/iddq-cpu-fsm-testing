`timescale 1ns/1ps

// ============================================================
// tb_iddq_cpu_fsm_fault.sv
// IDDQ fault-injection testbench - DUT based
//
// Rule used here:
// 1. Let FSM run to the required state with iddq_measure_i = 0
// 2. Assert iddq_measure_i = 1 to freeze clock
// 3. Observe state/output
// 4. Release iddq_measure_i = 0 before next transition
// ============================================================

module tb_iddq_cpu_fsm_fault;

  // ---------- DUT I/O ----------
  reg         clk_i;
  reg         rst_i;
  reg         load_pending_i;
  reg         iddq_measure_i;
  reg  [2:0]  fault_sel_i;

  wire [1:0]  state_obs_o;
  wire        fetch0_o;
  wire        fetch1_o;
  wire        exec_o;
  wire        execld_o;
  wire        fault_active_o;

  // ---------- Fault encoding ----------
  localparam [2:0] FAULT_NONE   = 3'd0,
                   FAULT_SA0_B0 = 3'd1,
                   FAULT_SA1_B0 = 3'd2,
                   FAULT_SA0_B1 = 3'd3,
                   FAULT_SA1_B1 = 3'd4;

  // ---------- State encoding ----------
  localparam [1:0] FETCH0_ST = 2'b00,
                   FETCH1_ST = 2'b01,
                   EXEC_ST   = 2'b10,
                   EXECLD_ST = 2'b11;

  // ---------- DUT instantiation ----------
  iddq_cpu_fsm_fault_top u_dut (
    .clk_i           (clk_i),
    .rst_i           (rst_i),
    .load_pending_i  (load_pending_i),
    .iddq_measure_i  (iddq_measure_i),
    .fault_sel_i     (fault_sel_i),
    .state_obs_o     (state_obs_o),
    .fetch0_o        (fetch0_o),
    .fetch1_o        (fetch1_o),
    .exec_o          (exec_o),
    .execld_o        (execld_o),
    .fault_active_o  (fault_active_o)
  );

  // ---------- 100 MHz clock ----------
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  // ---------- Counters ----------
  integer pass_count;
  integer fail_count;
  integer fault_detected;
  integer total_faults_detected;
  integer golden_fail_count;

  // ============================================================
  // Advance DUT by one active clock edge
  // ============================================================
 task automatic advance_one_cycle;
  begin
    // Keep DUT frozen until we are ready to intentionally advance one clock
    @(negedge clk_i);
    iddq_measure_i = 1'b0;   // release freeze before active clock edge

    @(posedge clk_i);        // FSM advances exactly once here
    #1;

    iddq_measure_i = 1'b1;   // keep frozen after checking
    #1;
  end
endtask

  // ============================================================
  // Reset DUT
  // ============================================================
  task automatic reset_dut;
    begin
      iddq_measure_i = 1'b0;
      load_pending_i = 1'b0;
      rst_i          = 1'b1;

      repeat (3) begin
        @(posedge clk_i);
      end

      @(negedge clk_i);
      rst_i = 1'b0;
      #1;
    end
  endtask

  // ============================================================
  // IDDQ freeze and check state/output
  // ============================================================
  task automatic iddq_freeze_and_check;
    input string vec_name;
    input [1:0]  exp_st;
    input        exp_f0;
    input        exp_f1;
    input        exp_ex;
    input        exp_exld;

    begin
      iddq_measure_i = 1'b1;   // freeze DUT gated clock
      #2;

      $display("  [IDDQ] %-8s | state=%02b | f0=%b f1=%b ex=%b exld=%b",
               vec_name,
               state_obs_o,
               fetch0_o,
               fetch1_o,
               exec_o,
               execld_o);

      if (state_obs_o !== exp_st ||
          {fetch0_o, fetch1_o, exec_o, execld_o} !==
          {exp_f0, exp_f1, exp_ex, exp_exld}) begin

        $display("  *** FAULT DETECTED at %-8s : got=%02b expected=%02b ***",
                 vec_name, state_obs_o, exp_st);

        fault_detected = fault_detected + 1;
        fail_count     = fail_count + 1;

      end else begin

        $display("  PASS (no fault effect)");
        pass_count = pass_count + 1;

      end

      iddq_measure_i = 1'b1;   // keep frozen after checking
      #1;
    end
  endtask

  // ============================================================
  // Apply all four IDDQ vectors
  // Expected golden FSM path:
  // FETCH0 -> FETCH1 -> EXEC -> EXECLD
  // For EXECLD, load_pending_i is asserted while FSM is in EXEC.
  // ============================================================
  task automatic run_iddq_vectors;
    begin
      reset_dut;

      // V1: FETCH0 after reset
      iddq_freeze_and_check("FETCH0", FETCH0_ST,
                            1'b1, 1'b0, 1'b0, 1'b0);

      // V2: FETCH1
      advance_one_cycle;
      iddq_freeze_and_check("FETCH1", FETCH1_ST,
                            1'b0, 1'b1, 1'b0, 1'b0);

      // V3: EXEC
      load_pending_i = 1'b0;
      advance_one_cycle;
      iddq_freeze_and_check("EXEC", EXEC_ST,
                            1'b0, 1'b0, 1'b1, 1'b0);

      // V4: EXECLD
      // We are currently in EXEC. Make load_pending_i = 1 before next clock.
      load_pending_i = 1'b1;
      advance_one_cycle;
      iddq_freeze_and_check("EXECLD", EXECLD_ST,
                            1'b0, 1'b0, 1'b0, 1'b1);

      load_pending_i = 1'b0;
    end
  endtask

  // ============================================================
  // Main test
  // ============================================================
  initial begin
    pass_count            = 0;
    fail_count            = 0;
    fault_detected        = 0;
    total_faults_detected = 0;
    golden_fail_count     = 0;

    fault_sel_i      = FAULT_NONE;
    iddq_measure_i   = 1'b0;
    rst_i            = 1'b1;
    load_pending_i   = 1'b0;

    $display("==============================================");
    $display("  IDDQ FAULT INJECTION TEST : CPU FSM DUT-based");
    $display("==============================================");
    $display("");

    // ---------------- Golden reference ----------------
    $display("--- RUN 1: No Fault Golden Reference ---");
    fault_sel_i    = FAULT_NONE;
    fault_detected = 0;

    run_iddq_vectors;

    golden_fail_count = fault_detected;

    $display("  Result: %0d faults detected expected: 0", fault_detected);

    if (golden_fail_count != 0) begin
      $display("");
      $display("  ERROR: Golden run failed.");
      $display("  Fault coverage result is not valid until golden run gives 0 faults.");
      $display("");
    end

    $display("");

    // ---------------- Fault 1 ----------------
    $display("--- RUN 2: SA0 on state_s[0] ---");
    fault_sel_i    = FAULT_SA0_B0;
    fault_detected = 0;

    run_iddq_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end

    $display("");

    // ---------------- Fault 2 ----------------
    $display("--- RUN 3: SA1 on state_s[0] ---");
    fault_sel_i    = FAULT_SA1_B0;
    fault_detected = 0;

    run_iddq_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end

    $display("");

    // ---------------- Fault 3 ----------------
    $display("--- RUN 4: SA0 on state_s[1] ---");
    fault_sel_i    = FAULT_SA0_B1;
    fault_detected = 0;

    run_iddq_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end

    $display("");

    // ---------------- Fault 4 ----------------
    $display("--- RUN 5: SA1 on state_s[1] ---");
    fault_sel_i    = FAULT_SA1_B1;
    fault_detected = 0;

    run_iddq_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end

    $display("");

    $display("==============================================");
    $display("  FAULT COVERAGE SUMMARY");
    $display("  Golden run failures   : %0d", golden_fail_count);
    $display("  Total faults injected : 4");
    $display("  Faults detected       : %0d", total_faults_detected);

    if (golden_fail_count == 0) begin
      $display("  Fault coverage        : %0d%%", total_faults_detected * 25);
    end else begin
      $display("  Fault coverage        : INVALID because golden run failed");
    end

    $display("==============================================");

    $finish;
  end

  // ---------- Watchdog ----------
  initial begin
    #50000;
    $display("WATCHDOG: timeout");
    $finish;
  end

endmodule