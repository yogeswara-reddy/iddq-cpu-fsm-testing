`timescale 1ns/1ps

module tb_iddq_cpu_fsm;

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

  localparam [1:0] FETCH0_ST = 2'b00,
                   FETCH1_ST = 2'b01,
                   EXEC_ST   = 2'b10,
                   EXECLD_ST = 2'b11;

  reg [1:0] state_s;
  reg [1:0] nextstate_s;

  always @(*) begin
    nextstate_s = state_s;
    case (state_s)
      FETCH0_ST : nextstate_s = FETCH1_ST;
      FETCH1_ST : nextstate_s = EXEC_ST;
      EXEC_ST   : nextstate_s = load_pending_s ? EXECLD_ST : FETCH0_ST;
      EXECLD_ST : nextstate_s = FETCH0_ST;
      default   : nextstate_s = FETCH0_ST;
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

  task iddq_freeze_and_check;
    input [63:0] vec_name;
    input [1:0]  exp_st;
    input        exp_f0, exp_f1, exp_ex, exp_exld;
    begin
      iddq_measure = 1'b1;
      #1;

      $display("[IDDQ] %s | state_s=%02b | f0=%b f1=%b ex=%b exld=%b",
               vec_name, state_s,
               fetch0_phase_o, fetch1_phase_o,
               exec_phase_o,   execld_phase_o);

      if (state_s !== exp_st) begin
        $display("  FAIL state : got 2'b%02b  expected 2'b%02b", state_s, exp_st);
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS state");
        pass_count = pass_count + 1;
      end

      if ({fetch0_phase_o, fetch1_phase_o, exec_phase_o, execld_phase_o} !==
          {exp_f0, exp_f1, exp_ex, exp_exld}) begin
        $display("  FAIL phase : got %b%b%b%b  expected %b%b%b%b",
                 fetch0_phase_o, fetch1_phase_o, exec_phase_o, execld_phase_o,
                 exp_f0, exp_f1, exp_ex, exp_exld);
        fail_count = fail_count + 1;
      end else begin
        $display("  PASS phase decode");
        pass_count = pass_count + 1;
      end

      $display("  >>> Quiescent measurement window open - probe VDD now <<<");
      $display("");
      iddq_measure = 1'b0;
    end
  endtask

  task one_cycle;
    begin
      @(posedge clk_free);
      @(negedge clk_free);
    end
  endtask

  initial begin
    pass_count     = 0;
    fail_count     = 0;
    rst_i          = 1'b1;
    load_pending_s = 1'b0;
    iddq_measure   = 1'b0;

    $display("========================================");
    $display("  IDDQ TEST : CPU FSM  (asCPUx.sv)");
    $display("========================================");
    $display("");

    repeat(3) @(posedge clk_free);
    @(negedge clk_free);
    rst_i = 1'b0;

    // V1: FETCH0_ST (async reset, state already here)
    $display("--- V1 : FETCH0_ST ---");
    iddq_freeze_and_check("FETCH0  ", FETCH0_ST, 1'b1, 1'b0, 1'b0, 1'b0);

    one_cycle;
    $display("--- V2 : FETCH1_ST ---");
    iddq_freeze_and_check("FETCH1  ", FETCH1_ST, 1'b0, 1'b1, 1'b0, 1'b0);

    load_pending_s = 1'b0;
    one_cycle;
    $display("--- V3 : EXEC_ST (load_pending=0) ---");
    iddq_freeze_and_check("EXEC    ", EXEC_ST,   1'b0, 1'b0, 1'b1, 1'b0);

    // Reach EXECLD: EXEC->FETCH0->FETCH1, set load_pending, FETCH1->EXEC->EXECLD
    one_cycle;             // EXEC->FETCH0
    one_cycle;             // FETCH0->FETCH1
    load_pending_s = 1'b1; // stable before next posedge
    one_cycle;             // FETCH1->EXEC (load_pending=1, next=EXECLD)
    one_cycle;             // EXEC->EXECLD latched
    $display("--- V4 : EXECLD_ST ---");
    iddq_freeze_and_check("EXECLD  ", EXECLD_ST, 1'b0, 1'b0, 1'b0, 1'b1);
    load_pending_s = 1'b0;

    one_cycle;             // EXECLD->FETCH0
    one_cycle;             // FETCH0->FETCH1
    load_pending_s = 1'b0;
    one_cycle;             // FETCH1->EXEC
    $display("--- Extra : EXEC_ST (load_pending=0) ---");
    iddq_freeze_and_check("EXEC_NL ", EXEC_ST,   1'b0, 1'b0, 1'b1, 1'b0);

    $display("========================================");
    $display("  RESULT : PASS=%0d  FAIL=%0d", pass_count, fail_count);
    if (fail_count == 0)
      $display("  ALL IDDQ VECTORS PASSED");
    else
      $display("  *** FAILURES - check log above ***");
    $display("========================================");

    $finish;
  end

  initial begin
    #5000;
    $display("WATCHDOG: timeout at 5000 ns");
    $finish;
  end

endmodule