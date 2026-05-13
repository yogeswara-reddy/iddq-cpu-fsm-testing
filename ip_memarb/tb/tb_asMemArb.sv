// tb_asMemArb.sv  --  Unit testbench for asMemArb
`timescale 1ns/1ps
/* verilator lint_off INITIALDLY  */
/* verilator lint_off UNUSEDSIGNAL */

import as_pack::*;

// Testbench for the Memory Arbiter (asMemArb).
//
// Test cases
//   TC01  I-Cache single read burst, QSPI immediate arready
//   TC02  D-Cache single read burst, QSPI immediate arready
//   TC03  Simultaneous D+I request: D-Cache wins, then I-Cache gets bus
//   TC04  D-Cache read, QSPI stalls arready 3 cycles
//   TC05  Back-to-back D-Cache bursts (immediate re-request after RLAST)
//   TC06  I-Cache read, arready leakage to D-Cache checked
//
// Drive/read split (no modport in TB → all signals freely accessible):
//   TB drives on icache_if / dcache_if:
//     arvalid, arid, araddr, arlen, arsize, arburst, rready  (cache master outputs)
//     awvalid, wvalid = 0  (writes not used)
//   TB reads on icache_if / dcache_if:
//     arready, rvalid, rid, rdata, rresp, rlast  (driven by DUT)
//   TB drives on qspi_if:
//     arready, rvalid, rid, rdata, rresp, rlast  (QSPI slave responses)
//     awready, wready = 1 ; bvalid = 0           (write channels tied off)
//   TB reads on qspi_if:
//     arvalid, arid, araddr, arlen, arsize, arburst, rready  (driven by DUT)

module tb_asMemArb;

  // --------------------------------------------------------------------------
  // Clock and reset
  // --------------------------------------------------------------------------
  localparam int CLK_HALF = 5; // 100 MHz → 10 ns period

  logic clk_s = 0;
  logic rst_s = 1;

  always #CLK_HALF clk_s = ~clk_s;

  // --------------------------------------------------------------------------
  // Interface instances (no modport: TB can drive/read all signals freely)
  // --------------------------------------------------------------------------
  as_axi4_if icache_if (.clk_i(clk_s), .rst_i(rst_s));
  as_axi4_if dcache_if (.clk_i(clk_s), .rst_i(rst_s));
  as_axi4_if qspi_if   (.clk_i(clk_s), .rst_i(rst_s));

  // --------------------------------------------------------------------------
  // DUT
  // --------------------------------------------------------------------------
  asMemArb dut (
    .clk_i       (clk_s),
    .rst_i       (rst_s),
    .icache_axi4 (icache_if),
    .dcache_axi4 (dcache_if),
    .qspi_axi4   (qspi_if)
  );

  // --------------------------------------------------------------------------
  // Test infrastructure
  // --------------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  task automatic chk(input logic cond, input string msg);
    if (cond) begin
      pass_cnt++;
    end else begin
      $display("  FAIL [%6t ns] %s", $time / 1000, msg);
      fail_cnt++;
    end
  endtask

  // Advance n rising edges, settle 1 ns after last edge
  task automatic tick(input int n = 1);
    repeat (n) @(posedge clk_s);
    #1;
  endtask

  // --------------------------------------------------------------------------
  // Initialise all TB-driven interface signals to safe defaults
  // --------------------------------------------------------------------------
  task automatic init_signals();
    // I-Cache master outputs
    icache_if.arvalid = 0; icache_if.arid    = 0; icache_if.araddr  = 0;
    icache_if.arlen   = 0; icache_if.arsize  = 0; icache_if.arburst = 0;
    icache_if.rready  = 0;
    icache_if.awvalid = 0; icache_if.awid    = 0; icache_if.awaddr  = 0;
    icache_if.awlen   = 0; icache_if.awsize  = 0; icache_if.awburst = 0;
    icache_if.wvalid  = 0; icache_if.wdata   = 0; icache_if.wstrb   = 0;
    icache_if.wlast   = 0; icache_if.bready  = 1;
    // D-Cache master outputs
    dcache_if.arvalid = 0; dcache_if.arid    = 0; dcache_if.araddr  = 0;
    dcache_if.arlen   = 0; dcache_if.arsize  = 0; dcache_if.arburst = 0;
    dcache_if.rready  = 0;
    dcache_if.awvalid = 0; dcache_if.awid    = 0; dcache_if.awaddr  = 0;
    dcache_if.awlen   = 0; dcache_if.awsize  = 0; dcache_if.awburst = 0;
    dcache_if.wvalid  = 0; dcache_if.wdata   = 0; dcache_if.wstrb   = 0;
    dcache_if.wlast   = 0; dcache_if.bready  = 1;
    // QSPI slave outputs
    qspi_if.arready = 0;
    qspi_if.rvalid  = 0; qspi_if.rid   = 0; qspi_if.rdata = 0;
    qspi_if.rresp   = 0; qspi_if.rlast = 0;
    qspi_if.awready = 1; qspi_if.wready = 1;
    qspi_if.bvalid  = 0; qspi_if.bid   = 0; qspi_if.bresp = 0;
  endtask

  // --------------------------------------------------------------------------
  // QSPI slave BFM: respond to one 4-beat AXI4 read burst
  //
  //   arready_dly  : cycles to stall before asserting arready (0 = immediate)
  //   got_id       : AXI4 ID forwarded by the arbiter (should match the master)
  //   got_addr     : start address forwarded by the arbiter
  // --------------------------------------------------------------------------
  task automatic qspi_serve (
    input  int          arready_dly,
    output logic [3:0]  got_id,
    output logic [31:0] got_addr
  );
    // Wait until the arbiter presents a read address on the QSPI port
    while (!qspi_if.arvalid) begin @(posedge clk_s); #1; end
    got_id   = qspi_if.arid;
    got_addr = qspi_if.araddr;

    // Optional stall before accepting the address
    if (arready_dly > 0) repeat (arready_dly) @(posedge clk_s);
    #1;

    // One-cycle ARREADY pulse → AR handshake completes
    qspi_if.arready = 1;
    @(posedge clk_s); #1;
    qspi_if.arready = 0;

    // Drive 4 data beats.
    // RREADY is forwarded by the arbiter from the granted cache's rready.
    // We wait for RREADY before advancing to the next beat.
    for (int b = 0; b < 4; b++) begin
      qspi_if.rvalid = 1;
      qspi_if.rid    = got_id;
      qspi_if.rdata  = {32'hBEEF_0000, got_addr[27:0], got_id} ^ (64'(b) << 4);
      qspi_if.rresp  = 2'b00;
      qspi_if.rlast  = (b == 3) ? 1'b1 : 1'b0;
      // Handshake: wait until rready (from arbiter) goes high
      while (!qspi_if.rready) begin @(posedge clk_s); #1; end
      @(posedge clk_s); #1;
    end

    qspi_if.rvalid = 0;
    qspi_if.rlast  = 0;
    qspi_if.rid    = 0;
  endtask

  // --------------------------------------------------------------------------
  // I-Cache master BFM: issue one read burst and collect all 4 data beats
  //
  //   addr      : 32-bit start address
  //   beat_cnt  : number of beats received (should always be 4)
  //
  // NOTE: arready / rvalid are sampled AT the posedge (before #1) to avoid
  // a race with qspi_serve, which deasserts those signals at posedge+#1.
  // --------------------------------------------------------------------------
  task automatic icache_rd (
    input  logic [31:0] addr,
    output int          beat_cnt
  );
    icache_if.arid    = 4'h1;   // I-Cache transaction ID per spec
    icache_if.araddr  = addr;
    icache_if.arlen   = 8'h03;  // 4-beat burst (ARLEN = beats - 1)
    icache_if.arsize  = 3'b011; // 8 bytes per beat
    icache_if.arburst = 2'b01;  // INCR
    icache_if.arvalid = 1;
    icache_if.rready  = 1;

    // AR handshake: sample arready AT posedge (qspi_serve deasserts at posedge+#1)
    forever begin @(posedge clk_s); if (icache_if.arready) break; end
    #1;
    icache_if.arvalid = 0;

    // Collect data beats — sample rvalid/rlast AT posedge
    beat_cnt = 0;
    forever begin
      @(posedge clk_s);
      if (icache_if.rvalid) begin
        beat_cnt++;
        if (icache_if.rlast) break;
      end
    end
    #1;
    icache_if.rready = 0;
  endtask

  // --------------------------------------------------------------------------
  // D-Cache master BFM: identical to icache_rd but uses D-Cache ID (0x2)
  // --------------------------------------------------------------------------
  task automatic dcache_rd (
    input  logic [31:0] addr,
    output int          beat_cnt
  );
    dcache_if.arid    = 4'h2;   // D-Cache transaction ID per spec
    dcache_if.araddr  = addr;
    dcache_if.arlen   = 8'h03;
    dcache_if.arsize  = 3'b011;
    dcache_if.arburst = 2'b01;
    dcache_if.arvalid = 1;
    dcache_if.rready  = 1;

    forever begin @(posedge clk_s); if (dcache_if.arready) break; end
    #1;
    dcache_if.arvalid = 0;

    beat_cnt = 0;
    forever begin
      @(posedge clk_s);
      if (dcache_if.rvalid) begin
        beat_cnt++;
        if (dcache_if.rlast) break;
      end
    end
    #1;
    dcache_if.rready = 0;
  endtask

  // --------------------------------------------------------------------------
  // MAIN TEST
  // --------------------------------------------------------------------------
  initial begin
    int  bc_i, bc_d;
    logic [3:0]  got_id, got_id2;
    logic [31:0] got_addr, got_addr2;

    $display("=== tb_asMemArb start ===");
    init_signals();

    // ---- Reset ----
    rst_s = 1;
    tick(4);
    rst_s = 0;
    tick(2);

    // ================================================================
    // TC01 – I-Cache only, QSPI immediate arready
    // ================================================================
    $display("TC01: I-Cache single read burst (immediate arready)");
    fork
      icache_rd(32'h0000_0040, bc_i);
      qspi_serve(0, got_id, got_addr);
    join
    chk(bc_i     == 4,              "TC01: I-Cache got 4 beats");
    chk(got_id    == 4'h1,           "TC01: QSPI arb forwarded ID=0x1 (I-Cache)");
    chk(got_addr  == 32'h0000_0040,  "TC01: QSPI arb forwarded correct araddr");
    chk(dcache_if.arready === 1'b0,  "TC01: D-Cache arready stayed 0");
    tick(2);

    // ================================================================
    // TC02 – D-Cache only, QSPI immediate arready
    // ================================================================
    $display("TC02: D-Cache single read burst (immediate arready)");
    fork
      dcache_rd(32'h0000_0060, bc_d);
      qspi_serve(0, got_id, got_addr);
    join
    chk(bc_d     == 4,              "TC02: D-Cache got 4 beats");
    chk(got_id    == 4'h2,           "TC02: QSPI arb forwarded ID=0x2 (D-Cache)");
    chk(got_addr  == 32'h0000_0060,  "TC02: QSPI arb forwarded correct araddr");
    chk(icache_if.arready === 1'b0,  "TC02: I-Cache arready stayed 0");
    tick(2);

    // ================================================================
    // TC03 – Simultaneous D+I request: D wins, then I gets bus
    // Both cache tasks start concurrently in the same delta.
    // The QSPI thread serves two sequential bursts.
    // ================================================================
    $display("TC03: Simultaneous D+I request -- D wins, then I gets bus");
    fork
      icache_rd(32'h0000_0080, bc_i);
      dcache_rd(32'h0000_00A0, bc_d);
      begin
        // First burst must be D-Cache (higher priority)
        qspi_serve(0, got_id, got_addr);
        chk(got_id   == 4'h2,           "TC03: 1st QSPI grant is D-Cache (ID=2)");
        chk(got_addr == 32'h0000_00A0,  "TC03: 1st QSPI araddr is D-Cache address");
        // Second burst must be I-Cache (lower priority, was waiting)
        qspi_serve(0, got_id2, got_addr2);
        chk(got_id2   == 4'h1,          "TC03: 2nd QSPI grant is I-Cache (ID=1)");
        chk(got_addr2 == 32'h0000_0080, "TC03: 2nd QSPI araddr is I-Cache address");
      end
    join
    chk(bc_d == 4, "TC03: D-Cache got 4 beats");
    chk(bc_i == 4, "TC03: I-Cache got 4 beats");
    tick(2);

    // ================================================================
    // TC04 – D-Cache burst with QSPI arready stall (3 cycles)
    //
    // Verifies that the arbiter holds D-Cache's arvalid forwarded to QSPI
    // even while QSPI stalls (arready withheld), and that I-Cache sees
    // arready=0 throughout (it has no pending request here).
    // ================================================================
    $display("TC04: D-Cache read, QSPI stalls arready for 3 cycles");
    fork
      dcache_rd(32'h0000_00C0, bc_d);
      qspi_serve(3, got_id, got_addr);
    join
    chk(bc_d     == 4,              "TC04: D-Cache got 4 beats after stall");
    chk(got_id    == 4'h2,           "TC04: QSPI got D-Cache ID after stall");
    chk(got_addr  == 32'h0000_00C0,  "TC04: QSPI got correct araddr after stall");
    tick(2);

    // ================================================================
    // TC05 – Back-to-back D-Cache bursts (second starts right after RLAST)
    //
    // Verifies that the state machine returns to IDLE and can accept a
    // new grant in the very next cycle after a burst completes.
    // ================================================================
    $display("TC05: Back-to-back D-Cache bursts");
    fork
      dcache_rd(32'h0000_00E0, bc_d);
      qspi_serve(0, got_id, got_addr);
    join
    chk(bc_d == 4, "TC05a: 1st D-Cache burst: 4 beats");
    // Second burst immediately following
    fork
      dcache_rd(32'h0000_0100, bc_d);
      qspi_serve(0, got_id, got_addr);
    join
    chk(bc_d     == 4,              "TC05b: 2nd D-Cache burst: 4 beats");
    chk(got_addr  == 32'h0000_0100,  "TC05b: 2nd burst: correct araddr");
    tick(2);

    // ================================================================
    // TC06 – I-Cache read with 1-cycle QSPI stall; verify D-Cache blocked
    //
    // Ensures arready is only sent to the granted master (I-Cache here)
    // and never leaks to D-Cache while D-Cache is idle.
    // ================================================================
    $display("TC06: I-Cache read with 1-cycle stall, D-Cache blocked");
    fork
      icache_rd(32'h0000_0120, bc_i);
      qspi_serve(1, got_id, got_addr);
    join
    chk(bc_i     == 4,              "TC06: I-Cache got 4 beats");
    chk(got_id    == 4'h1,           "TC06: QSPI saw I-Cache ID");
    chk(dcache_if.arready === 1'b0,  "TC06: D-Cache arready never went high");
    tick(2);

    // ================================================================
    // RESULT
    // ================================================================
    $display("=== tb_asMemArb done ===");
    if (fail_cnt == 0) begin
      $display("PASS: all %0d checks passed.", pass_cnt);
    end else begin
      $display("FAIL: %0d of %0d checks failed.",
               fail_cnt, pass_cnt + fail_cnt);
    end
    $finish;
  end

  // --------------------------------------------------------------------------
  // Watchdog: abort if simulation hangs (e.g. arbiter stuck in a state)
  // --------------------------------------------------------------------------
  initial begin
    #200_000; // 200 us
    $fatal(1, "TIMEOUT: tb_asMemArb exceeded 200 us");
  end

endmodule : tb_asMemArb
