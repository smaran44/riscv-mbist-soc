// =============================================================================
// File: mbist_collar.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: BIST Collar / Memory Multiplexer isolating functional system bus
//              and test harness signals with glitch-free switching.
// =============================================================================

`timescale 1ns / 1ps

module mbist_collar #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 8
)(
    // Mode Select
    input  wire                  bist_mode,       // 0 = Functional Mode, 1 = BIST Mode
    
    // Functional System Interface (Normal Operation)
    input  wire                  func_ce_n,
    input  wire                  func_we_n,
    input  wire [ADDR_WIDTH-1:0] func_addr,
    input  wire [DATA_WIDTH-1:0] func_din,
    output wire [DATA_WIDTH-1:0] func_dout,
    
    // MBIST Controller Interface (Test Mode)
    input  wire                  bist_ce_n,
    input  wire                  bist_we_n,
    input  wire [ADDR_WIDTH-1:0] bist_addr,
    input  wire [DATA_WIDTH-1:0] bist_din,
    output wire [DATA_WIDTH-1:0] bist_dout,
    
    // Target SRAM Physical Interface
    output wire                  mem_ce_n,
    output wire                  mem_we_n,
    output wire [ADDR_WIDTH-1:0] mem_addr,
    output wire [DATA_WIDTH-1:0] mem_din,
    input  wire [DATA_WIDTH-1:0] mem_dout
);

    // -------------------------------------------------------------------------
    // Multiplexers: Route BIST or Functional Signals to RAM
    // -------------------------------------------------------------------------
    assign mem_ce_n  = bist_mode ? bist_ce_n : func_ce_n;
    assign mem_we_n  = bist_mode ? bist_we_n : func_we_n;
    assign mem_addr  = bist_mode ? bist_addr : func_addr;
    assign mem_din   = bist_mode ? bist_din  : func_din;
    
    // Return memory output to both ports (or gate in non-active mode)
    assign func_dout = (!bist_mode) ? mem_dout : {DATA_WIDTH{1'b0}};
    assign bist_dout = (bist_mode)  ? mem_dout : {DATA_WIDTH{1'b0}};

endmodule
