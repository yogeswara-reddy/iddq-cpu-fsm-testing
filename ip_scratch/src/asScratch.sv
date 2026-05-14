`timescale 1ns/1ps

module asScratch #(
    parameter int SP_DEPTH = 1024,   // entries (64-bit words); must be power of 2
    parameter int PA_WIDTH = 32      // physical address width (unused; for doc)
) (
    input  logic clk_i,
    input  logic rst_i,
    as_dcache_if.cache cpu_if
);

    localparam int ADDR_W = $clog2(SP_DEPTH);   // 10 for default SP_DEPTH=1024

    // ── SRAM array ───────────────────────────────────────────────
    logic [63:0] mem_r [0:SP_DEPTH-1];

    initial
        for (int i = 0; i < SP_DEPTH; i++) mem_r[i] = '0;

    // ── Internal state ───────────────────────────────────────────
    logic              busy_r;    // 1 = read result pending
    logic [63:0]       mem_rd_r;  // registered SRAM output
    logic [2:0]        size_r;    // dc_size latched for extension
    logic [2:0]        boff_r;    // dc_addr[2:0] latched for sub-word extract

    // Word address: dc_addr[ADDR_W+2 : 3]  (bits 3..ADDR_W+2)
    logic [ADDR_W-1:0] waddr_s;
    assign waddr_s = cpu_if.dc_addr[ADDR_W+2:3];

    // ── FSM (IDLE / BUSY) ────────────────────────────────────────
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            busy_r <= 1'b0;
        end else begin
            busy_r <= 1'b0;          // default: clear busy
            if (!busy_r && cpu_if.dc_req) begin
                if (cpu_if.dc_wr) begin
                    // Byte-enable write; dc_stall stays 0
                    for (int i = 0; i < 8; i++)
                        if (cpu_if.dc_wstrb[i])
                            mem_r[waddr_s][i*8 +: 8] <= cpu_if.dc_wdata[i*8 +: 8];
                end else begin
                    // Read: latch address info and issue SRAM read; stall CPU for 1 cycle
                    mem_rd_r <= mem_r[waddr_s];
                    size_r   <= cpu_if.dc_size;
                    boff_r   <= cpu_if.dc_addr[2:0];
                    busy_r   <= 1'b1;
                end
            end
        end
    end

    // ── CPU interface outputs ────────────────────────────────────
    // dc_stall: high for exactly 1 cycle on a read request
    assign cpu_if.dc_stall      = cpu_if.dc_req & ~cpu_if.dc_wr & ~busy_r;
    assign cpu_if.dc_rvalid     = busy_r;
    assign cpu_if.dc_flush_done = 1'b0;
    assign cpu_if.dc_err        = 1'b0;

    // ── Sign / zero extension (RISC-V dc_size encoding) ─────────
    always_comb begin
        // Bit position of the sub-word within the 64-bit SRAM word
        automatic logic [5:0] bsel = {boff_r,        3'b000};     // byte start bit
        automatic logic [5:0] hsel = {boff_r[2:1], 4'b0000};     // half start bit
        automatic logic [5:0] wsel = {boff_r[2],  5'b00000};     // word start bit
        case (size_r)
            3'b000: cpu_if.dc_rdata = {{56{mem_rd_r[bsel+7]}},  mem_rd_r[bsel +: 8 ]};  // lb
            3'b001: cpu_if.dc_rdata = {{48{mem_rd_r[hsel+15]}}, mem_rd_r[hsel +: 16]};  // lh
            3'b010: cpu_if.dc_rdata = {{32{mem_rd_r[wsel+31]}}, mem_rd_r[wsel +: 32]};  // lw
            3'b011: cpu_if.dc_rdata = mem_rd_r;                                          // ld
            3'b100: cpu_if.dc_rdata = {56'h0, mem_rd_r[bsel +: 8 ]};                    // lbu
            3'b101: cpu_if.dc_rdata = {48'h0, mem_rd_r[hsel +: 16]};                    // lhu
            3'b110: cpu_if.dc_rdata = {32'h0, mem_rd_r[wsel +: 32]};                    // lwu
            default: cpu_if.dc_rdata = mem_rd_r;
        endcase
    end

endmodule
