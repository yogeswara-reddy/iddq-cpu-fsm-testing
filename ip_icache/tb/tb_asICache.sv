`timescale 1ns/1ps
/* verilator lint_off INITIALDLY  */
/* verilator lint_off UNUSEDSIGNAL */

import as_pack::*;

// Testbench for asICache.
//
// Memory model: rdata[beat] = { araddr + beat*8 + 4, araddr + beat*8 }
//   → every 32-bit instruction word equals its byte address (ic_addr & ~32'h3).
//
// Test cases:
//   TC01  Cold miss: fetch instr at 0x0000_0000, check fill + rdata
//   TC02  Hit: same address again (no AXI4 transaction)
//   TC03  Hit: different instruction offset in same cache line
//   TC04  Miss: different set (different index bits)
//   TC05  4-way fill: 4 conflict misses to set 0 → all 4 ways filled
//   TC06  Flush → re-miss: lines invalidated after flush
//   TC07  AXI4 error: RRESP != OKAY → ic_err pulse, no valid data written

module tb_asICache;

  // -------------------------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------------------------
  localparam int CLK_HALF = 5;   // 100 MHz

  logic clk_s = 0;
  logic rst_s = 1;
  always #CLK_HALF clk_s = ~clk_s;

  // -------------------------------------------------------------------------
  // Interfaces
  // -------------------------------------------------------------------------
  as_icache_if cpu_if (.clk_i(clk_s), .rst_i(rst_s));
  as_axi4_if   axi_if (.clk_i(clk_s), .rst_i(rst_s));

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  asICache dut (
    .clk_i   (clk_s),
    .rst_i   (rst_s),
    .cpu_if  (cpu_if),
    .axi_if  (axi_if)
  );

  // -------------------------------------------------------------------------
  // Test infrastructure
  // -------------------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  task automatic chk(input logic cond, input string msg);
    if (cond) pass_cnt++;
    else begin
      $display("  FAIL [%0t ps] %s", $time, msg);
      fail_cnt++;
    end
  endtask

  task automatic chk_eq32(
    input logic [31:0] got, exp,
    input string msg
  );
    if (got === exp) pass_cnt++;
    else begin
      $display("  FAIL [%0t ps] %s: got=0x%08X exp=0x%08X", $time, msg, got, exp);
      fail_cnt++;
    end
  endtask

  // -------------------------------------------------------------------------
  // Initialise all TB-driven signals
  // -------------------------------------------------------------------------
  task automatic init_signals();
    cpu_if.ic_req   = 0; cpu_if.ic_addr  = '0; cpu_if.ic_flush = 0;
    axi_if.arready  = 0;
    axi_if.rvalid   = 0; axi_if.rid      = 0;  axi_if.rdata   = '0;
    axi_if.rresp    = 0; axi_if.rlast    = 0;
    axi_if.awready  = 1; axi_if.wready   = 1;
    axi_if.bvalid   = 0; axi_if.bid      = 0;  axi_if.bresp   = 0;
  endtask

  // -------------------------------------------------------------------------
  // AXI4 memory model: serves one 4-beat read burst.
  //
  //   arready_dly : cycles to stall before asserting arready (0 = immediate)
  //   err_beat    : beat index on which to inject RRESP error (-1 = no error)
  //   got_araddr  : forwarded AXI4 ARADDR (cache-line aligned)
  //
  //   rdata model: rdata[b] = { araddr+b*8+4, araddr+b*8 }
  //   → every 32-bit word in the line equals its byte address
  // -------------------------------------------------------------------------
  task automatic qspi_serve(
    input  int          arready_dly,
    input  int          err_beat,
    output logic [31:0] got_araddr
  );
    // Wait for DUT to present ARVALID
    forever begin @(posedge clk_s); if (axi_if.arvalid) break; end
    got_araddr = axi_if.araddr[31:0];

    // Optional AR stall
    if (arready_dly > 0) repeat (arready_dly) @(posedge clk_s);
    #1;
    axi_if.arready = 1;
    @(posedge clk_s); #1;
    axi_if.arready = 0;

    // Drive up to 4 data beats; stop after err_beat (terminate burst there)
    for (int b = 0; b < 4; b++) begin
      axi_if.rvalid = 1;
      axi_if.rid    = 4'h1;
      axi_if.rdata  = {32'(got_araddr + b*8 + 4), 32'(got_araddr + b*8)};
      axi_if.rresp  = (b == err_beat) ? 2'b10 : 2'b00;  // SLVERR on err_beat
      axi_if.rlast  = (b == 3) || (b == err_beat);       // rlast on last or error beat
      // Wait for DUT rready at posedge (DUT asserts rready in FILL state)
      forever begin @(posedge clk_s); if (axi_if.rready) break; end
      #1;
      if (b == err_beat) break;   // DUT has exited FILL; stop here
    end
    axi_if.rvalid = 0; axi_if.rlast = 0;
    axi_if.rid = 0; axi_if.rdata = '0; axi_if.rresp = 0;
  endtask

  // -------------------------------------------------------------------------
  // CPU BFM: issue one fetch and wait for rvalid.
  //
  //   addr      : instruction byte address (4-byte aligned)
  //   rdata_out : 32-bit instruction received
  //
  //   rvalid is a registered signal; sample it AT posedge to avoid race
  //   with RESPOND/LOOKUP states that set it at posedge+#1.
  // -------------------------------------------------------------------------
  task automatic cpu_fetch(
    input  logic [31:0] addr,
    output logic [31:0] rdata_out
  );
    cpu_if.ic_addr = addr;
    cpu_if.ic_req  = 1;
    @(posedge clk_s); #1;    // one-cycle pulse: DUT captures request
    cpu_if.ic_req  = 0;
    cpu_if.ic_addr = '0;
    forever begin @(posedge clk_s); if (cpu_if.ic_rvalid) break; end
    #1;                       // rdata_r (set in FILL, one cycle before rvalid) is stable
    rdata_out = cpu_if.ic_rdata;
  endtask

  // Expected instruction word for a given address (see memory model comment)
  function automatic logic [31:0] expected_instr(input logic [31:0] addr);
    return addr & ~32'h3;  // byte address of instruction (4-byte aligned)
  endfunction

  // Compute the cache-line aligned address
  function automatic logic [31:0] line_addr(input logic [31:0] addr);
    return addr & ~32'h1F;
  endfunction

  // -------------------------------------------------------------------------
  // MAIN
  // -------------------------------------------------------------------------
  initial begin
    logic [31:0] rdata, got_addr;
    $display("=== tb_asICache start ===");
    init_signals();

    rst_s = 1; repeat (4) @(posedge clk_s); #1;
    rst_s = 0; repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC01 – Cold miss: fetch first instruction
    // ================================================================
    $display("TC01: cold miss, fetch 0x0000_0000");
    fork
      cpu_fetch(32'h0000_0000, rdata);
      qspi_serve(0, -1, got_addr);
    join
    chk_eq32(rdata,    expected_instr(32'h0000_0000), "TC01: correct rdata");
    chk_eq32(got_addr, line_addr(32'h0000_0000),      "TC01: correct ARADDR");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC02 – Hit: same address (no AXI4 transaction expected)
    // ================================================================
    $display("TC02: hit, same address");
    cpu_fetch(32'h0000_0000, rdata);
    chk_eq32(rdata, expected_instr(32'h0000_0000), "TC02: correct rdata on hit");
    // Verify AXI4 ARVALID never went high: check it is 0 now
    chk(axi_if.arvalid === 1'b0, "TC02: no AXI4 transaction on hit");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC03 – Hit: different instruction offset in same cache line
    // ================================================================
    $display("TC03: hit, instr offset 7 of same line (addr 0x0000_001C)");
    cpu_fetch(32'h0000_001C, rdata);
    chk_eq32(rdata, expected_instr(32'h0000_001C), "TC03: correct rdata");
    chk(axi_if.arvalid === 1'b0,                "TC03: no AXI4 transaction");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC04 – Miss: different set (addr 0x0000_0020, index=1)
    // ================================================================
    $display("TC04: miss, set 1 (addr 0x0000_0020)");
    fork
      cpu_fetch(32'h0000_0020, rdata);
      qspi_serve(0, -1, got_addr);
    join
    chk_eq32(rdata,    expected_instr(32'h0000_0020), "TC04: correct rdata");
    chk_eq32(got_addr, line_addr(32'h0000_0020),      "TC04: correct ARADDR");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC05 – Fill all 4 ways of set 0 (4 conflict misses)
    //        Addresses with index=0 and different tags:
    //          tag N = addr[31:10] → step = 0x400 (1024 B)
    //          way 0 was filled in TC01 (0x0000_0000)
    //          now fill 3 more: 0x0000_0400, 0x0000_0800, 0x0000_0C00
    // ================================================================
    $display("TC05: fill 3 more ways of set 0");
    // Way 1 – addr 0x0000_0400
    fork cpu_fetch(32'h0000_0400, rdata); qspi_serve(0, -1, got_addr); join
    chk_eq32(rdata,    expected_instr(32'h0000_0400), "TC05[0]: rdata");
    chk_eq32(got_addr, line_addr(32'h0000_0400),      "TC05[0]: ARADDR");
    repeat (1) @(posedge clk_s); #1;
    // Way 2 – addr 0x0000_0800
    fork cpu_fetch(32'h0000_0800, rdata); qspi_serve(0, -1, got_addr); join
    chk_eq32(rdata,    expected_instr(32'h0000_0800), "TC05[1]: rdata");
    chk_eq32(got_addr, line_addr(32'h0000_0800),      "TC05[1]: ARADDR");
    repeat (1) @(posedge clk_s); #1;
    // Way 3 – addr 0x0000_0C00
    fork cpu_fetch(32'h0000_0C00, rdata); qspi_serve(0, -1, got_addr); join
    chk_eq32(rdata,    expected_instr(32'h0000_0C00), "TC05[2]: rdata");
    chk_eq32(got_addr, line_addr(32'h0000_0C00),      "TC05[2]: ARADDR");
    repeat (1) @(posedge clk_s); #1;

    // All 4 ways filled; verify hits on all 4 lines (no AXI4 expected)
    $display("TC05: verify hits on all 4 ways");
    cpu_fetch(32'h0000_0000, rdata);
    chk_eq32(rdata, expected_instr(32'h0000_0000), "TC05 hit way0");
    chk(axi_if.arvalid === 1'b0, "TC05 hit way0: no AXI4");
    repeat (1) @(posedge clk_s); #1;
    cpu_fetch(32'h0000_0400, rdata);
    chk_eq32(rdata, expected_instr(32'h0000_0400), "TC05 hit way1");
    chk(axi_if.arvalid === 1'b0, "TC05 hit way1: no AXI4");
    repeat (1) @(posedge clk_s); #1;
    cpu_fetch(32'h0000_0800, rdata);
    chk_eq32(rdata, expected_instr(32'h0000_0800), "TC05 hit way2");
    chk(axi_if.arvalid === 1'b0, "TC05 hit way2: no AXI4");
    repeat (1) @(posedge clk_s); #1;
    cpu_fetch(32'h0000_0C00, rdata);
    chk_eq32(rdata, expected_instr(32'h0000_0C00), "TC05 hit way3");
    chk(axi_if.arvalid === 1'b0, "TC05 hit way3: no AXI4");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC06 – Flush: all ways invalidated, re-fetch misses again
    // ================================================================
    $display("TC06: flush");
    cpu_if.ic_flush = 1;
    @(posedge clk_s); #1;
    cpu_if.ic_flush = 0;
    // Wait for flush_done (single-cycle pulse; sample PRE-NBA at the posedge it appears)
    forever begin @(posedge clk_s); if (cpu_if.ic_flush_done) break; end
    chk(cpu_if.ic_flush_done === 1'b1, "TC06: flush_done asserted");
    repeat (2) @(posedge clk_s); #1;

    // Re-fetch TC01 address – must miss
    $display("TC06: re-fetch after flush (expect miss)");
    fork
      cpu_fetch(32'h0000_0000, rdata);
      qspi_serve(0, -1, got_addr);
    join
    chk_eq32(rdata,    expected_instr(32'h0000_0000), "TC06: correct rdata after flush");
    chk_eq32(got_addr, line_addr(32'h0000_0000),      "TC06: AXI4 issued after flush");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC07 – AXI4 error on beat 0 → ic_err pulse, no valid data
    // ================================================================
    $display("TC07: AXI4 RRESP error");
    // Need a fresh address so we get a miss (use a new set)
    fork
      begin
        cpu_if.ic_addr = 32'h0000_0040;  // set 2
        cpu_if.ic_req  = 1;
        @(posedge clk_s); #1;   // one-cycle pulse
        cpu_if.ic_req  = 0;
        cpu_if.ic_addr = '0;
        // ic_err is a single-cycle pulse; sample PRE-NBA at the posedge it appears
        forever begin @(posedge clk_s); if (cpu_if.ic_err) break; end
      end
      qspi_serve(0, 0, got_addr);  // err on beat 0
    join
    chk(cpu_if.ic_err    === 1'b1, "TC07: ic_err pulsed");
    chk(cpu_if.ic_rvalid === 1'b0, "TC07: no rvalid on error");
    repeat (4) @(posedge clk_s); #1;

    // ================================================================
    // RESULT
    // ================================================================
    $display("=== tb_asICache done ===");
    if (fail_cnt == 0)
      $display("PASS: all %0d checks passed.", pass_cnt);
    else
      $display("FAIL: %0d of %0d checks failed.", fail_cnt, pass_cnt + fail_cnt);
    $finish;
  end

  // Watchdog
  initial begin
    #500_000;
    $fatal(1, "TIMEOUT: tb_asICache exceeded 500 us");
  end

endmodule : tb_asICache
