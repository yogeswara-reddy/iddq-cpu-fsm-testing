`timescale 1ns/1ps
// ============================================================
// iddq_cpu_fsm_fault_top.sv
// IDDQ-style FSM freeze + stuck-at fault injection
//
// Simulation-safe version:
// No gated clock is created.
// iddq_measure_i freezes the state register using clock enable.
// ============================================================

module iddq_cpu_fsm_fault_top (
  input  wire        clk_i,
  input  wire        rst_i,
  input  wire        load_pending_i,
  input  wire        iddq_measure_i,
  input  wire [2:0]  fault_sel_i,

  output wire [1:0]  state_obs_o,
  output wire        fetch0_o,
  output wire        fetch1_o,
  output wire        exec_o,
  output wire        execld_o,
  output wire        fault_active_o
);

  // ---------- State encoding ----------
  localparam [1:0] FETCH0_ST = 2'b00,
                   FETCH1_ST = 2'b01,
                   EXEC_ST   = 2'b10,
                   EXECLD_ST = 2'b11;

  // ---------- Fault encoding ----------
  localparam [2:0] FAULT_NONE   = 3'd0,
                   FAULT_SA0_B0 = 3'd1,
                   FAULT_SA1_B0 = 3'd2,
                   FAULT_SA0_B1 = 3'd3,
                   FAULT_SA1_B1 = 3'd4;

  reg [1:0] state_s;
  reg [1:0] nextstate_s;
  reg [1:0] nextstate_faulty;

  // ---------- Next-state logic ----------
  always @(*) begin
    nextstate_s = state_s;

    case (state_s)
      FETCH0_ST : nextstate_s = FETCH1_ST;
      FETCH1_ST : nextstate_s = EXEC_ST;
      EXEC_ST   : nextstate_s = load_pending_i ? EXECLD_ST : FETCH0_ST;
      EXECLD_ST : nextstate_s = FETCH0_ST;
      default   : nextstate_s = FETCH0_ST;
    endcase
  end

  // ---------- Fault injection ----------
  always @(*) begin
    nextstate_faulty = nextstate_s;

    case (fault_sel_i)
      FAULT_NONE   : nextstate_faulty    = nextstate_s;
      FAULT_SA0_B0 : nextstate_faulty[0] = 1'b0;
      FAULT_SA1_B0 : nextstate_faulty[0] = 1'b1;
      FAULT_SA0_B1 : nextstate_faulty[1] = 1'b0;
      FAULT_SA1_B1 : nextstate_faulty[1] = 1'b1;
      default      : nextstate_faulty    = nextstate_s;
    endcase
  end

  // ---------- State register ----------
  // iddq_measure_i = 1 means freeze state for IDDQ observation.
  // iddq_measure_i = 0 means FSM advances normally.
  always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      state_s <= FETCH0_ST;
    end
    else if (!iddq_measure_i) begin
      state_s <= nextstate_faulty;
    end
    else begin
      state_s <= state_s;
    end
  end

  // ---------- Observable outputs ----------
  assign fetch0_o       = (state_s == FETCH0_ST);
  assign fetch1_o       = (state_s == FETCH1_ST);
  assign exec_o         = (state_s == EXEC_ST);
  assign execld_o       = (state_s == EXECLD_ST);
  assign state_obs_o    = state_s;
  assign fault_active_o = (fault_sel_i != FAULT_NONE);

endmodule