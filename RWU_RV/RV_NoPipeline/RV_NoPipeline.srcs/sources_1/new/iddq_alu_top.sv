`timescale 1ns/1ps

// ============================================================
// iddq_alu_top.sv
// 8-bit IDDQ-style ALU stuck-at fault injection wrapper
//
// Reduced from 32-bit to 8-bit so FPGA implementation can pass.
// Same fault-injection concept is preserved.
// ============================================================

module iddq_alu_fault_top (
  input  wire [7:0] a_i,
  input  wire [7:0] b_i,
  input  wire [2:0] alu_op_i,
  input  wire       iddq_measure_i,
  input  wire [3:0] fault_sel_i,

  output wire [7:0] result_o,
  output wire       zero_o,
  output wire       fault_active_o
);

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

  reg [7:0] result_golden;
  reg [7:0] result_faulty;

  wire zero_golden;
  reg  zero_faulty;

  // ---------- Golden ALU ----------
  always @(*) begin
    case (alu_op_i)
      ALU_ADD : result_golden = a_i + b_i;
      ALU_SUB : result_golden = a_i - b_i;
      ALU_AND : result_golden = a_i & b_i;
      ALU_OR  : result_golden = a_i | b_i;
      ALU_XOR : result_golden = a_i ^ b_i;
      ALU_SLT : result_golden = ($signed(a_i) < $signed(b_i)) ? 8'd1 : 8'd0;
      ALU_SLL : result_golden = a_i << b_i[2:0];
      ALU_SRL : result_golden = a_i >> b_i[2:0];
      default : result_golden = 8'd0;
    endcase
  end

  assign zero_golden = (result_golden == 8'd0);

  // ---------- Fault injection ----------
  always @(*) begin
    result_faulty = result_golden;
    zero_faulty   = zero_golden;

    case (fault_sel_i)

      FAULT_NONE : begin
        result_faulty = result_golden;
        zero_faulty   = zero_golden;
      end

      // Stuck-at faults on result bit 0
      FAULT_RES0_SA0 : result_faulty[0] = 1'b0;
      FAULT_RES0_SA1 : result_faulty[0] = 1'b1;

      // Stuck-at faults on result bit 1
      FAULT_RES1_SA0 : result_faulty[1] = 1'b0;
      FAULT_RES1_SA1 : result_faulty[1] = 1'b1;

      // Stuck-at faults on result bit 2
      FAULT_RES2_SA0 : result_faulty[2] = 1'b0;
      FAULT_RES2_SA1 : result_faulty[2] = 1'b1;

      // Stuck-at faults on zero flag
      FAULT_ZERO_SA0 : zero_faulty = 1'b0;
      FAULT_ZERO_SA1 : zero_faulty = 1'b1;

      default : begin
        result_faulty = result_golden;
        zero_faulty   = zero_golden;
      end

    endcase
  end

  // ---------- Observable outputs ----------
  assign result_o       = result_faulty;
  assign zero_o         = zero_faulty;
  assign fault_active_o = (fault_sel_i != FAULT_NONE);

endmodule