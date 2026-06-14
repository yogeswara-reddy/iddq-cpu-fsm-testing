`timescale 1ns/1ps

// ============================================================
// tb_iddq_alu_fault.sv
// 8-bit IDDQ-style ALU stuck-at fault injection testbench
//
// This testbench matches the 8-bit iddq_alu_fault_top.
// Golden run must produce 0 failures.
// Eight stuck-at faults are injected and checked.
// ============================================================

module tb_iddq_alu_fault;

  // ---------- DUT inputs ----------
  reg  [7:0] a_i;
  reg  [7:0] b_i;
  reg  [2:0] alu_op_i;
  reg        iddq_measure_i;
  reg  [3:0] fault_sel_i;

  // ---------- DUT outputs ----------
  wire [7:0] result_o;
  wire       zero_o;
  wire       fault_active_o;

  // ---------- ALU operation encoding ----------
  localparam [2:0] ALU_ADD = 3'd0,
                   ALU_SUB = 3'd1,
                   ALU_AND = 3'd2,
                   ALU_OR  = 3'd3,
                   ALU_XOR = 3'd4,
                   ALU_SLT = 3'd5,
                   ALU_SLL = 3'd6,
                   ALU_SRL = 3'd7;

  // ---------- Fault encoding ----------
  localparam [3:0] FAULT_NONE     = 4'd0,
                   FAULT_RES0_SA0 = 4'd1,
                   FAULT_RES0_SA1 = 4'd2,
                   FAULT_RES1_SA0 = 4'd3,
                   FAULT_RES1_SA1 = 4'd4,
                   FAULT_RES2_SA0 = 4'd5,
                   FAULT_RES2_SA1 = 4'd6,
                   FAULT_ZERO_SA0 = 4'd7,
                   FAULT_ZERO_SA1 = 4'd8;

  // ---------- Counters ----------
  integer pass_count;
  integer fail_count;
  integer fault_detected;
  integer total_faults_detected;
  integer golden_fail_count;

  // ---------- DUT instantiation ----------
  iddq_alu_fault_top u_dut (
    .a_i            (a_i),
    .b_i            (b_i),
    .alu_op_i       (alu_op_i),
    .iddq_measure_i (iddq_measure_i),
    .fault_sel_i    (fault_sel_i),
    .result_o       (result_o),
    .zero_o         (zero_o),
    .fault_active_o (fault_active_o)
  );

  // ============================================================
  // Golden ALU calculation inside testbench
  // ============================================================
  function automatic [7:0] golden_result;
    input [7:0] a;
    input [7:0] b;
    input [2:0] op;
    begin
      case (op)
        ALU_ADD : golden_result = a + b;
        ALU_SUB : golden_result = a - b;
        ALU_AND : golden_result = a & b;
        ALU_OR  : golden_result = a | b;
        ALU_XOR : golden_result = a ^ b;
        ALU_SLT : golden_result = ($signed(a) < $signed(b)) ? 8'd1 : 8'd0;
        ALU_SLL : golden_result = a << b[2:0];
        ALU_SRL : golden_result = a >> b[2:0];
        default : golden_result = 8'd0;
      endcase
    end
  endfunction

  // ============================================================
  // Apply one static IDDQ vector and check output
  // ============================================================
  task automatic apply_iddq_vector;
    input string vec_name;
    input [7:0]  a_val;
    input [7:0]  b_val;
    input [2:0]  op_val;

    reg [7:0] exp_result;
    reg       exp_zero;

    begin
      // Apply static vector
      iddq_measure_i = 1'b0;
      a_i            = a_val;
      b_i            = b_val;
      alu_op_i       = op_val;

      #5;

      // IDDQ measurement window: inputs are stable
      iddq_measure_i = 1'b1;
      #5;

      exp_result = golden_result(a_val, b_val, op_val);
      exp_zero   = (exp_result == 8'd0);

      $display("  [IDDQ] %-12s | A=%02h B=%02h op=%0d | result=%02h zero=%b | expected=%02h zero=%b",
               vec_name,
               a_i,
               b_i,
               alu_op_i,
               result_o,
               zero_o,
               exp_result,
               exp_zero);

      if ((result_o !== exp_result) || (zero_o !== exp_zero)) begin
        $display("  *** FAULT DETECTED at %-12s ***", vec_name);
        fault_detected = fault_detected + 1;
        fail_count     = fail_count + 1;
      end
      else begin
        $display("  PASS (no fault effect)");
        pass_count = pass_count + 1;
      end

      iddq_measure_i = 1'b0;
      #5;
    end
  endtask

  // ============================================================
  // Apply ALU vector set
  // These vectors excite result[0], result[1], result[2],
  // and zero flag.
  // ============================================================
  task automatic run_alu_vectors;
    begin
      // result = 01, detects result[0] SA0
      apply_iddq_vector("ADD_RES1", 8'd0, 8'd1, ALU_ADD);

      // result = 00, detects result[0] SA1 and zero SA0
      apply_iddq_vector("SUB_ZERO", 8'd5, 8'd5, ALU_SUB);

      // result = 02, detects result[1] SA0
      apply_iddq_vector("ADD_RES2", 8'd1, 8'd1, ALU_ADD);

      // result = 04, detects result[2] SA0
      apply_iddq_vector("SLL_RES4", 8'd1, 8'd2, ALU_SLL);

      // result = FF, detects zero SA1 and SA0 effects
      apply_iddq_vector("XOR_ALL1", 8'hAA, 8'h55, ALU_XOR);

      // result = 06, extra check for bit1 and bit2
      apply_iddq_vector("OR_RES6", 8'd2, 8'd4, ALU_OR);

      // result = 01, SLT operation check
      apply_iddq_vector("SLT_RES1", 8'd3, 8'd7, ALU_SLT);

      // result = 00, AND operation zero check
      apply_iddq_vector("AND_ZERO", 8'hAA, 8'h55, ALU_AND);
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

    a_i            = 8'd0;
    b_i            = 8'd0;
    alu_op_i       = ALU_ADD;
    iddq_measure_i = 1'b0;
    fault_sel_i    = FAULT_NONE;

    $display("==============================================");
    $display("  IDDQ FAULT INJECTION TEST : 8-bit ALU DUT-based");
    $display("==============================================");
    $display("");

    // ---------------- Golden reference ----------------
    $display("--- RUN 1: No Fault Golden Reference ---");
    fault_sel_i    = FAULT_NONE;
    fault_detected = 0;

    run_alu_vectors;

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
    $display("--- RUN 2: SA0 on result_o[0] ---");
    fault_sel_i    = FAULT_RES0_SA0;
    fault_detected = 0;
    run_alu_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end
    $display("");

    // ---------------- Fault 2 ----------------
    $display("--- RUN 3: SA1 on result_o[0] ---");
    fault_sel_i    = FAULT_RES0_SA1;
    fault_detected = 0;
    run_alu_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end
    $display("");

    // ---------------- Fault 3 ----------------
    $display("--- RUN 4: SA0 on result_o[1] ---");
    fault_sel_i    = FAULT_RES1_SA0;
    fault_detected = 0;
    run_alu_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end
    $display("");

    // ---------------- Fault 4 ----------------
    $display("--- RUN 5: SA1 on result_o[1] ---");
    fault_sel_i    = FAULT_RES1_SA1;
    fault_detected = 0;
    run_alu_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end
    $display("");

    // ---------------- Fault 5 ----------------
    $display("--- RUN 6: SA0 on result_o[2] ---");
    fault_sel_i    = FAULT_RES2_SA0;
    fault_detected = 0;
    run_alu_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end
    $display("");

    // ---------------- Fault 6 ----------------
    $display("--- RUN 7: SA1 on result_o[2] ---");
    fault_sel_i    = FAULT_RES2_SA1;
    fault_detected = 0;
    run_alu_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end
    $display("");

    // ---------------- Fault 7 ----------------
    $display("--- RUN 8: SA0 on zero_o ---");
    fault_sel_i    = FAULT_ZERO_SA0;
    fault_detected = 0;
    run_alu_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end
    $display("");

    // ---------------- Fault 8 ----------------
    $display("--- RUN 9: SA1 on zero_o ---");
    fault_sel_i    = FAULT_ZERO_SA1;
    fault_detected = 0;
    run_alu_vectors;

    if (fault_detected > 0) begin
      $display("  FAULT DETECTED %0d vectors caught it", fault_detected);
      total_faults_detected = total_faults_detected + 1;
    end else begin
      $display("  FAULT NOT DETECTED");
    end
    $display("");

    $display("==============================================");
    $display("  ALU FAULT COVERAGE SUMMARY");
    $display("  Golden run failures   : %0d", golden_fail_count);
    $display("  Total faults injected : 8");
    $display("  Faults detected       : %0d", total_faults_detected);

    if (golden_fail_count == 0) begin
      $display("  Fault coverage        : %0d%%", total_faults_detected * 100 / 8);
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