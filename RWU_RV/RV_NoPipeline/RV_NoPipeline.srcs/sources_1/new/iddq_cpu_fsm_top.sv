// ============================================================
// iddq_cpu_fsm_top.sv
// Synthesizable IDDQ wrapper for CPU FSM
// Target: Zybo (xc7z010clg400-1)
// ============================================================

module iddq_cpu_fsm_top (
  input  wire        clk_i,
  input  wire        rst_i,
  input  wire        load_pending_i,
  input  wire        iddq_measure_i,

  output wire [1:0]  state_obs_o,
  output wire        fetch0_o,
  output wire        fetch1_o,
  output wire        exec_o,
  output wire        execld_o
);

  wire clk_gated;

  BUFGCE clk_gate_inst (
    .I  (clk_i),
    .CE (~iddq_measure_i),
    .O  (clk_gated)
  );

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
      EXEC_ST   : nextstate_s = load_pending_i ? EXECLD_ST : FETCH0_ST;
      EXECLD_ST : nextstate_s = FETCH0_ST;
      default   : nextstate_s = FETCH0_ST;
    endcase
  end

  always @(posedge clk_gated or posedge rst_i) begin
    if (rst_i)
      state_s <= FETCH0_ST;
    else
      state_s <= nextstate_s;
  end

  assign fetch0_o    = (state_s == FETCH0_ST) ? 1'b1 : 1'b0;
  assign fetch1_o    = (state_s == FETCH1_ST) ? 1'b1 : 1'b0;
  assign exec_o      = (state_s == EXEC_ST)   ? 1'b1 : 1'b0;
  assign execld_o    = (state_s == EXECLD_ST)  ? 1'b1 : 1'b0;
  assign state_obs_o = state_s;

endmodule