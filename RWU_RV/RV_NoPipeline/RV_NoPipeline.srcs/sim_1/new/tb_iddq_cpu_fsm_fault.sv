`timescale 1ns/1ps

module tb_iddq_cpu_fsm_fault;

  reg         clk_free;
  reg         clk_i;
  reg         rst_i;
  reg         load_pending_s;
  reg         iddq_measure;

  wire        fetch0_phase_o;
  wire        fetch1_phase_o;
  wire        exec_phase_o;
  wire        execld_phase_o;
  wire [1:0]  state_obs;

  localparam [1:0] FETCH0_ST    = 2'b00,
                   FETCH1_ST    = 2'b01,
                   EXEC_ST      = 2'b10,
                   EXECLD_ST    = 2'b11;

  localparam [2:0] FAULT_NONE   = 3'd0,
                   FAULT_SA0_B0 = 3'd1,
                   FAULT_SA1_B0 = 3'd2,
                   FAULT_SA0_B1 = 3'd3,
                   FAULT_SA1_B1 = 3'd4;

  reg [1:0] state_s;
  reg [1:0] nextstate_s;
  reg [2:0] active_fault;

  always @(*) begin
    nextstate_s = state_s;
    case (state_s)
      FETCH0_ST : nextstate_s = FETCH1_ST;
      FETCH1_ST : nextstate_s = EXEC_ST;
      EXEC_ST   : nextstate_s = load_pending_s ? EXECLD_ST : FETCH0_ST;
      EXECLD_ST : nextstate_s = FETCH0_ST;
      default   : nextstate_s = FETCH0_ST;
    endcase
    case (active_fault)
      FAULT_SA0_B0 : nextstate_s[0] = 1'b0;
      FAULT_SA1_B0 : nextstate_s[0] = 1'b1;
      FAULT_SA0_B1 : nextstate_s[1] = 1'b0;
      FAULT_SA1_B1 : nextstate_s[1] = 1'b1;
      default      : nextstate_s = nextstate_s;
    endcase
  end

  always @(posedge clk_i or posedge rst_i) begin
    if (rst_i)
      state_s <= FETCH0_ST;
    else
      state_s <= nextstate_s;
  end

  assign fetch0_phase_o = (state_s == FETCH0_ST) ? 1'b1 : 1'b0;
  assign fetch1_phase_o = (state_s == FETCH1_ST) ? 1'b1 : 1'b0;
  assign exec_phase_o   = (state_s == EXEC_ST)   ? 1'b1 : 1'b0;
  assign execld_phase_o = (state_s == EXECLD_ST)  ? 1'b1 : 1'b0;
  assign state_obs      = state_s;

  initial clk_free = 1'b0;
  always #5 clk_free = ~clk_free;
  always @(*) clk_i = clk_free & ~iddq_measure;

  integer pass_count;
  integer fail_count;
  integer fault_detected;
  integer total_faults_detected;

  task iddq_freeze_and_check;
    input [63:0] vec_name;
    input [1:0]  exp_st;
    input        exp_f0, exp_f1, exp_ex, exp_exld;
    begin
      iddq_measure = 1'b1;
      #1;
      $display("  [IDDQ] %s | state=%02b | f0=%b f1=%b ex=%b exld=%b",
               vec_name, state_s,
               fetch0_phase_o, fetch1_phase_o,
               exec_phase_o, execld_phase_o);
      if (state_s !== exp_st ||
          {fetch0_phase_o,fetch1_phase_o,exec_phase_o,execld_phase_o} !==
          {exp_f0,exp_f1,exp_ex,exp_exld}) begin
        $display("  *** FAULT DETECTED at %s : got=%02b expected=%02b ***",
                 vec_name, state_s, exp_st);
        fault_detected = fault_detected + 1;
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS (no fault effect)");
        pass_count = pass_count + 1;
      end
      iddq_measure = 1'b0;
    end
  endtask

  task one_cycle;
    begin
      @(posedge clk_free);
      @(negedge clk_free);
    end
  endtask

  task run_iddq_vectors;
    begin
      rst_i = 1'b1;
      load_pending_s = 1'b0;
      repeat(3) @(posedge clk_free);
      @(negedge clk_free);
      rst_i = 1'b0;

      iddq_freeze_and_check("FETCH0  ", FETCH0_ST, 1'b1, 1'b0, 1'b0, 1'b0);
      one_cycle;
      iddq_freeze_and_check("FETCH1  ", FETCH1_ST, 1'b0, 1'b1, 1'b0, 1'b0);
      load_pending_s = 1'b0;
      one_cycle;
      iddq_freeze_and_check("EXEC    ", EXEC_ST,   1'b0, 1'b0, 1'b1, 1'b0);
      one_cycle;
      one_cycle;
      load_pending_s = 1'b1;
      one_cycle;
      one_cycle;
      iddq_freeze_and_check("EXECLD  ", EXECLD_ST, 1'b0, 1'b0, 1'b0, 1'b1);
      load_pending_s = 1'b0;
    end
  endtask

  initial begin
    pass_count            = 0;
    fail_count            = 0;
    total_faults_detected = 0;
    active_fault          = FAULT_NONE;
    iddq_measure          = 1'b0;
    rst_i                 = 1'b1;
    load_pending_s        = 1'b0;

    $display("==============================================");
    $display("  IDDQ FAULT INJECTION TEST : CPU FSM");
    $display("==============================================");
    $display("");

    $display("--- RUN 1: No Fault (Golden Reference) ---");
    active_fault   = FAULT_NONE;
    fault_detected = 0;
    run_iddq_vectors;
    $display("  Result: %0d faults detected", fault_detected);
    $display("");

    $display("--- RUN 2: SA0 on state_s[0] ---");
    $display("  Injected: bit0 stuck-at-0");
    active_fault   = FAULT_SA0_B0;
    fault_detected = 0;
    run_iddq_vectors;
    if (fault_detected > 0) begin
      $display("  FAULT DETECTED (%0d vectors caught it)", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else
      $display("  FAULT NOT DETECTED");
    $display("");

    $display("--- RUN 3: SA1 on state_s[0] ---");
    $display("  Injected: bit0 stuck-at-1");
    active_fault   = FAULT_SA1_B0;
    fault_detected = 0;
    run_iddq_vectors;
    if (fault_detected > 0) begin
      $display("  FAULT DETECTED (%0d vectors caught it)", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else
      $display("  FAULT NOT DETECTED");
    $display("");

    $display("--- RUN 4: SA0 on state_s[1] ---");
    $display("  Injected: bit1 stuck-at-0");
    active_fault   = FAULT_SA0_B1;
    fault_detected = 0;
    run_iddq_vectors;
    if (fault_detected > 0) begin
      $display("  FAULT DETECTED (%0d vectors caught it)", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else
      $display("  FAULT NOT DETECTED");
    $display("");

    $display("--- RUN 5: SA1 on state_s[1] ---");
    $display("  Injected: bit1 stuck-at-1");
    active_fault   = FAULT_SA1_B1;
    fault_detected = 0;
    run_iddq_vectors;
    if (fault_detected > 0) begin
      $display("  FAULT DETECTED (%0d vectors caught it)", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else
      $display("  FAULT NOT DETECTED");
    $display("");

    $display("==============================================");
    $display("  FAULT COVERAGE SUMMARY");
    $display("  Total faults injected : 4");
    $display("  Faults detected       : %0d", total_faults_detected);
    $display("  Fault coverage        : %0d%%", total_faults_detected * 25);
    $display("==============================================");

    $finish;
  end

  initial begin
    #20000;
    $display("WATCHDOG: timeout");
    $finish;
  end

endmodule