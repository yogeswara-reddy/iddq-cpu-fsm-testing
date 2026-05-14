`timescale 1ns/1ps
/* verilator lint_off INITIALDLY  */
/* verilator lint_off UNUSEDSIGNAL */

import as_pack::*;

// Testbench for asScratch (64-bit × 1024 synchronous scratchpad SRAM).
//
// TC01  ld    : write + read 64-bit doubleword
// TC02  lw/lwu: sign- and zero-extend 32-bit word at offset 0
// TC03  lw/lwu: sign- and zero-extend 32-bit word at offset 4
// TC04  lb/lbu: sign- and zero-extend byte at offset 0
// TC05  lh/lhu: sign- and zero-extend halfword at offset 0
// TC06  lh/lhu: sign- and zero-extend halfword at offset 4
// TC07  lb/lbu: sign- and zero-extend byte at offset 7
// TC08  wstrb : byte-enable partial write, read back full word
// TC09  bound : last address in scratchpad
// TC10  base  : first address (addr 0)
// TC11  burst : back-to-back reads (two distinct words)
// TC12  lb+   : lb positive (no sign-extend) and lb negative (sign-extend)

module tb_asScratch;

  // -------------------------------------------------------------------------
  // Clock / reset
  // -------------------------------------------------------------------------
  localparam int CLK_HALF = 5;   // 100 MHz

  logic clk_s = 0;
  logic rst_s = 1;
  always #CLK_HALF clk_s = ~clk_s;

  // -------------------------------------------------------------------------
  // Interface
  // -------------------------------------------------------------------------
  as_dcache_if cpu_if (.clk_i(clk_s), .rst_i(rst_s));

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  asScratch #(.SP_DEPTH(1024), .PA_WIDTH(32)) dut (
    .clk_i  (clk_s),
    .rst_i  (rst_s),
    .cpu_if (cpu_if)
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

  task automatic chk_eq64(
    input logic [63:0] got, exp,
    input string msg
  );
    if (got === exp) pass_cnt++;
    else begin
      $display("  FAIL [%0t ps] %s: got=0x%016X exp=0x%016X", $time, msg, got, exp);
      fail_cnt++;
    end
  endtask

  // -------------------------------------------------------------------------
  // Signal initialisation
  // -------------------------------------------------------------------------
  task automatic init_signals();
    cpu_if.dc_req   = 0; cpu_if.dc_addr  = '0; cpu_if.dc_wr   = 0;
    cpu_if.dc_size  = 0; cpu_if.dc_wdata = '0; cpu_if.dc_wstrb = 0;
    cpu_if.dc_flush = 0;
  endtask

  // -------------------------------------------------------------------------
  // CPU read BFM: one-cycle dc_req pulse, wait for dc_rvalid (1-cycle stall)
  // -------------------------------------------------------------------------
  task automatic cpu_read(
    input  logic [31:0] addr,
    input  logic [2:0]  size,
    output logic [63:0] rdata_out
  );
    cpu_if.dc_addr = 64'(addr);
    cpu_if.dc_req  = 1;
    cpu_if.dc_wr   = 0;
    cpu_if.dc_size = size;
    @(posedge clk_s); #1;
    cpu_if.dc_req  = 0;
    cpu_if.dc_addr = '0;
    forever begin @(posedge clk_s); if (cpu_if.dc_rvalid) break; end
    #1;
    rdata_out = cpu_if.dc_rdata;
  endtask

  // -------------------------------------------------------------------------
  // CPU write BFM: one-cycle dc_req pulse (writes never stall)
  // -------------------------------------------------------------------------
  task automatic cpu_write(
    input logic [31:0] addr,
    input logic [2:0]  size,
    input logic [63:0] wdata,
    input logic [7:0]  wstrb
  );
    cpu_if.dc_addr  = 64'(addr);
    cpu_if.dc_req   = 1;
    cpu_if.dc_wr    = 1;
    cpu_if.dc_size  = size;
    cpu_if.dc_wdata = wdata;
    cpu_if.dc_wstrb = wstrb;
    @(posedge clk_s); #1;
    cpu_if.dc_req   = 0;
    cpu_if.dc_wr    = 0;
    cpu_if.dc_addr  = '0;
    cpu_if.dc_wdata = '0;
    cpu_if.dc_wstrb = '0;
    @(posedge clk_s); #1;   // one idle cycle between operations
  endtask

  // =========================================================================
  // MAIN
  // =========================================================================
  initial begin
    logic [63:0] rdata;

    $display("=== tb_asScratch start ===");
    init_signals();

    rst_s = 1; repeat (4) @(posedge clk_s); #1;
    rst_s = 0; repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC01 – ld: write 64-bit word and read back
    // ================================================================
    $display("TC01: ld write+read, addr 0x0000_0008");
    cpu_write(32'h0000_0008, 3'b011, 64'hDEAD_BEEF_CAFE_BABE, 8'hFF);
    cpu_read (32'h0000_0008, 3'b011, rdata);
    chk_eq64(rdata, 64'hDEAD_BEEF_CAFE_BABE, "TC01: ld rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC02 – lw / lwu at byte offset 0  (lower 32 bits = 0xCAFE_BABE)
    // ================================================================
    $display("TC02: lw/lwu sign/zero-extend, offset 0");
    cpu_read(32'h0000_0008, 3'b010, rdata);   // lw  (bit31=1 → sign-ext)
    chk_eq64(rdata, 64'hFFFF_FFFF_CAFE_BABE, "TC02: lw rdata");
    cpu_read(32'h0000_0008, 3'b110, rdata);   // lwu
    chk_eq64(rdata, 64'h0000_0000_CAFE_BABE, "TC02: lwu rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC03 – lw / lwu at byte offset 4  (upper 32 bits = 0xDEAD_BEEF)
    // ================================================================
    $display("TC03: lw/lwu sign/zero-extend, offset 4");
    cpu_read(32'h0000_000C, 3'b010, rdata);   // lw  (bit31=1 → sign-ext)
    chk_eq64(rdata, 64'hFFFF_FFFF_DEAD_BEEF, "TC03: lw rdata");
    cpu_read(32'h0000_000C, 3'b110, rdata);   // lwu
    chk_eq64(rdata, 64'h0000_0000_DEAD_BEEF, "TC03: lwu rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC04 – lb / lbu at byte offset 0  (byte = 0xFE, bit7=1)
    // ================================================================
    $display("TC04: lb/lbu sign/zero-extend, byte offset 0");
    // wdata[7:0] = 0xFE; wstrb = 0x01 (byte 0 only)
    cpu_write(32'h0000_0010, 3'b000, 64'h0000_0000_0000_00FE, 8'h01);
    cpu_read (32'h0000_0010, 3'b000, rdata);   // lb
    chk_eq64(rdata, 64'hFFFF_FFFF_FFFF_FFFE, "TC04: lb rdata");
    cpu_read (32'h0000_0010, 3'b100, rdata);   // lbu
    chk_eq64(rdata, 64'h0000_0000_0000_00FE, "TC04: lbu rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC05 – lh / lhu at byte offset 0  (halfword = 0xBEEF, bit15=1)
    // ================================================================
    $display("TC05: lh/lhu sign/zero-extend, halfword offset 0");
    // Write 0xBEEF at bytes 0,1: wdata[15:0]=0xBEEF, wstrb=0x03
    cpu_write(32'h0000_0018, 3'b001, 64'h0000_0000_0000_BEEF, 8'h03);
    cpu_read (32'h0000_0018, 3'b001, rdata);   // lh  (bit15=1 → sign-ext)
    chk_eq64(rdata, 64'hFFFF_FFFF_FFFF_BEEF, "TC05: lh rdata");
    cpu_read (32'h0000_0018, 3'b101, rdata);   // lhu
    chk_eq64(rdata, 64'h0000_0000_0000_BEEF, "TC05: lhu rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC06 – lh / lhu at byte offset 4  (halfword = 0xCAFE, bit15=1)
    // ================================================================
    $display("TC06: lh/lhu sign/zero-extend, halfword offset 4");
    // Write 0xCAFE at bytes 4,5: wdata[47:32]=0xCAFE; byte4=0xFE, byte5=0xCA
    // wdata = 64'h0000_CAFE_0000_0000, wstrb=0x30
    cpu_write(32'h0000_0020, 3'b001, 64'h0000_CAFE_0000_0000, 8'h30);
    cpu_read (32'h0000_0024, 3'b001, rdata);   // lh from addr+4 (boff=4)
    chk_eq64(rdata, 64'hFFFF_FFFF_FFFF_CAFE, "TC06: lh rdata");
    cpu_read (32'h0000_0024, 3'b101, rdata);   // lhu
    chk_eq64(rdata, 64'h0000_0000_0000_CAFE, "TC06: lhu rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC07 – lb / lbu at byte offset 7  (byte = 0x81, bit7=1)
    // ================================================================
    $display("TC07: lb/lbu sign/zero-extend, byte offset 7");
    // wdata[63:56] = 0x81; wstrb = 0x80 (byte 7)
    cpu_write(32'h0000_0028, 3'b000, 64'h8100_0000_0000_0000, 8'h80);
    cpu_read (32'h0000_002F, 3'b000, rdata);   // lb (boff=7, bit63=1)
    chk_eq64(rdata, 64'hFFFF_FFFF_FFFF_FF81, "TC07: lb rdata");
    cpu_read (32'h0000_002F, 3'b100, rdata);   // lbu
    chk_eq64(rdata, 64'h0000_0000_0000_0081, "TC07: lbu rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC08 – byte-enable partial write: wstrb=0xAA (bytes 1,3,5,7)
    // ================================================================
    $display("TC08: byte-enable partial write, wstrb=0xAA");
    // Fresh word at 0x30; initial = 0 (from DUT init)
    cpu_write(32'h0000_0030, 3'b011, 64'hFFFF_FFFF_FFFF_FFFF, 8'hAA);
    cpu_read (32'h0000_0030, 3'b011, rdata);
    // bytes 0,2,4,6 = 0x00; bytes 1,3,5,7 = 0xFF → 0xFF00_FF00_FF00_FF00
    chk_eq64(rdata, 64'hFF00_FF00_FF00_FF00, "TC08: partial-write rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC09 – boundary: last word in scratchpad (addr 0x1FF8 = 1023×8)
    // ================================================================
    $display("TC09: last-word boundary, addr 0x0000_1FF8");
    cpu_write(32'h0000_1FF8, 3'b011, 64'h1234_5678_9ABC_DEF0, 8'hFF);
    cpu_read (32'h0000_1FF8, 3'b011, rdata);
    chk_eq64(rdata, 64'h1234_5678_9ABC_DEF0, "TC09: boundary rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC10 – first word (addr 0)
    // ================================================================
    $display("TC10: first word, addr 0x0000_0000");
    cpu_write(32'h0000_0000, 3'b011, 64'hA5A5_A5A5_A5A5_A5A5, 8'hFF);
    cpu_read (32'h0000_0000, 3'b011, rdata);
    chk_eq64(rdata, 64'hA5A5_A5A5_A5A5_A5A5, "TC10: first-word rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC11 – back-to-back reads of two distinct words
    // ================================================================
    $display("TC11: back-to-back reads");
    cpu_write(32'h0000_0038, 3'b011, 64'h1111_1111_1111_1111, 8'hFF);
    cpu_write(32'h0000_0040, 3'b011, 64'h2222_2222_2222_2222, 8'hFF);
    cpu_read (32'h0000_0038, 3'b011, rdata);
    chk_eq64(rdata, 64'h1111_1111_1111_1111, "TC11: word A rdata");
    cpu_read (32'h0000_0040, 3'b011, rdata);
    chk_eq64(rdata, 64'h2222_2222_2222_2222, "TC11: word B rdata");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // TC12 – lb positive (no sign-ext) and lb negative (sign-ext)
    // ================================================================
    $display("TC12: lb positive (byte=0x01) and negative (byte=0x80)");
    // Write 0x8000_0000_0000_0001: byte0=0x01 (positive), byte7=0x80 (negative)
    cpu_write(32'h0000_0048, 3'b011, 64'h8000_0000_0000_0001, 8'hFF);
    cpu_read (32'h0000_0048, 3'b000, rdata);   // lb  byte0 = 0x01, bit7=0
    chk_eq64(rdata, 64'h0000_0000_0000_0001, "TC12: lb positive");
    cpu_read (32'h0000_004F, 3'b000, rdata);   // lb  byte7 = 0x80, bit7=1
    chk_eq64(rdata, 64'hFFFF_FFFF_FFFF_FF80, "TC12: lb negative");
    repeat (2) @(posedge clk_s); #1;

    // ================================================================
    // Done
    // ================================================================
    if (fail_cnt == 0)
      $display("PASS: all %0d checks passed.", pass_cnt);
    else
      $display("FAIL: %0d/%0d checks failed.", fail_cnt, pass_cnt+fail_cnt);

    $finish;
  end

  // ── Timeout watchdog ─────────────────────────────────────────────────────
  initial begin
    #2_000_000;
    $fatal(1, "TIMEOUT: tb_asScratch exceeded 2 ms");
  end

endmodule
