// =============================================================================
// File: mbist_top.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Top-level integration uniting MBIST Controller, Address Generator,
//              Data Pattern Synthesizer, BIST Collar, Output Response Analyzer,
//              Diagnostic Unit, and Synchronous SRAM under test.
// =============================================================================

`timescale 1ns / 1ps
`include "mbist_defines.v"

module mbist_top #(
    parameter ADDR_WIDTH = `DEFAULT_ADDR_WIDTH,
    parameter DATA_WIDTH = `DEFAULT_DATA_WIDTH,
    parameter MEM_DEPTH  = (1 << ADDR_WIDTH),
    parameter FAULT_MODEL = 1
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // -------------------------------------------------------------------------
    // BIST Control & Configuration
    // -------------------------------------------------------------------------
    input  wire                  bist_mode,       // 0 = Normal/Functional, 1 = BIST Mode
    input  wire                  bist_start,      // Start BIST execution
    input  wire [2:0]            algo_sel,        // Algorithm selection
    input  wire [2:0]            pattern_sel,     // Base data pattern selection
    input  wire [ADDR_WIDTH-1:0] max_addr,        // Test address boundary (typically MEM_DEPTH-1)
    input  wire                  stop_on_fail,    // Halt test on first detected mismatch
    
    // -------------------------------------------------------------------------
    // Functional System Interface (CPU / DMA / System Bus)
    // -------------------------------------------------------------------------
    input  wire                  func_ce_n,
    input  wire                  func_we_n,
    input  wire [ADDR_WIDTH-1:0] func_addr,
    input  wire [DATA_WIDTH-1:0] func_din,
    output wire [DATA_WIDTH-1:0] func_dout,
    
    // -------------------------------------------------------------------------
    // BIST Status & Diagnostic Outputs
    // -------------------------------------------------------------------------
    output wire                  bist_busy,
    output wire                  bist_done,
    output wire                  bist_pass,
    output wire                  bist_fail,
    output wire [15:0]           diag_fail_count,
    output wire [ADDR_WIDTH-1:0] diag_first_fail_addr,
    output wire [DATA_WIDTH-1:0] diag_first_fail_data_actual,
    output wire [DATA_WIDTH-1:0] diag_first_fail_data_exp,
    output wire [DATA_WIDTH-1:0] diag_first_fail_bitmask,
    output wire [3:0]            diag_first_fail_step,
    output wire [DATA_WIDTH-1:0] misr_signature,
    
    // -------------------------------------------------------------------------
    // Fault Injection Interface (For Verification & Testbench Control)
    // -------------------------------------------------------------------------
    input  wire                  fault_inject_en,
    input  wire [3:0]            fault_type,
    input  wire [ADDR_WIDTH-1:0] fault_addr,
    input  wire [3:0]            fault_bit,
    input  wire [ADDR_WIDTH-1:0] fault_victim_addr,
    input  wire [3:0]            fault_victim_bit,
    input  wire [ADDR_WIDTH-1:0] fault_alias_addr
);

    // -------------------------------------------------------------------------
    // Internal Interconnect Signals
    // -------------------------------------------------------------------------
    // Address Generator
    wire                  addr_en;
    wire                  addr_dir;
    wire                  addr_init;
    wire                  sweep_done;
    wire [ADDR_WIDTH-1:0] bist_addr;
    
    // Pattern Generator
    wire                  data_invert;
    wire                  lfsr_en;
    wire [DATA_WIDTH-1:0] bist_din;
    
    // Controller & Memory
    wire                  bist_ce_n;
    wire                  bist_we_n;
    wire [DATA_WIDTH-1:0] bist_dout;
    
    // Target SRAM Physical Interface (Collar -> RAM)
    wire                  mem_ce_n;
    wire                  mem_we_n;
    wire [ADDR_WIDTH-1:0] mem_addr;
    wire [DATA_WIDTH-1:0] mem_din;
    wire [DATA_WIDTH-1:0] mem_dout;
    
    // Comparator & Diagnostics
    wire                  compare_en;
    wire                  diag_reset;
    wire [3:0]            current_step;
    wire                  match;
    wire                  mismatch;
    wire [DATA_WIDTH-1:0] error_bitmap;
    wire                  diag_has_failed;

    // -------------------------------------------------------------------------
    // Sub-Module Instantiations
    // -------------------------------------------------------------------------

    // 1. Programmable Address Generator
    mbist_addr_gen #(
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_addr_gen (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr_en       (addr_en),
        .addr_dir      (addr_dir),
        .addr_init     (addr_init),
        .addr_load     (1'b0),
        .addr_load_val ({ADDR_WIDTH{1'b0}}),
        .max_addr      (max_addr),
        .addr_out      (bist_addr),
        .addr_is_first (),
        .addr_is_last  (),
        .sweep_done    (sweep_done)
    );

    // 2. Algorithmic Data Pattern Generator
    mbist_pattern_gen #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_pattern_gen (
        .clk           (clk),
        .rst_n         (rst_n),
        .pattern_sel   (pattern_sel),
        .data_invert   (data_invert),
        .lfsr_en       (lfsr_en),
        .lfsr_seed_load(1'b0),
        .lfsr_seed     ({DATA_WIDTH{1'b0}}),
        .current_addr  (bist_addr),
        .pattern_out   (bist_din)
    );

    // 3. Multi-Algorithm MBIST Controller FSM
    mbist_fsm_controller #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_fsm_controller (
        .clk            (clk),
        .rst_n          (rst_n),
        .bist_start     (bist_start),
        .algo_sel       (algo_sel),
        .pattern_sel    (pattern_sel),
        .max_addr       (max_addr),
        .stop_on_fail   (stop_on_fail),
        .addr_en        (addr_en),
        .addr_dir       (addr_dir),
        .addr_init      (addr_init),
        .sweep_done     (sweep_done),
        .current_addr   (bist_addr),
        .data_invert    (data_invert),
        .lfsr_en        (lfsr_en),
        .bist_ce_n      (bist_ce_n),
        .bist_we_n      (bist_we_n),
        .compare_en     (compare_en),
        .diag_reset     (diag_reset),
        .current_step   (current_step),
        .mismatch_strobe(mismatch),
        .bist_busy      (bist_busy),
        .bist_done      (bist_done),
        .bist_pass      (bist_pass),
        .bist_fail      (bist_fail)
    );

    // 4. BIST Collar (Functional / Test Multiplexer)
    mbist_collar #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_collar (
        .bist_mode(bist_mode),
        .func_ce_n(func_ce_n),
        .func_we_n(func_we_n),
        .func_addr(func_addr),
        .func_din (func_din),
        .func_dout(func_dout),
        .bist_ce_n(bist_ce_n),
        .bist_we_n(bist_we_n),
        .bist_addr(bist_addr),
        .bist_din (bist_din),
        .bist_dout(bist_dout),
        .mem_ce_n (mem_ce_n),
        .mem_we_n (mem_we_n),
        .mem_addr (mem_addr),
        .mem_din  (mem_din),
        .mem_dout (mem_dout)
    );

    // 5. Target Synchronous SRAM Model with Dynamic Fault Injection
    generate if (FAULT_MODEL) begin : sim_bank
    ram_sp_fault_model #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH (MEM_DEPTH)
    ) u_ram_under_test (
        .clk             (clk),
        .rst_n           (rst_n),
        .ce_n            (mem_ce_n),
        .we_n            (mem_we_n),
        .addr            (mem_addr),
        .din             (mem_din),
        .dout            (mem_dout),
        .fault_inject_en (fault_inject_en),
        .fault_type      (fault_type),
        .fault_addr      (fault_addr),
        .fault_bit       (fault_bit),
        .fault_victim_addr(fault_victim_addr),
        .fault_victim_bit(fault_victim_bit),
        .fault_alias_addr(fault_alias_addr)
    );
    end else begin : physical_bank
        mbist_sram_sp #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) ram (
            .clk(clk), .ce_n(mem_ce_n), .we_n(mem_we_n),
            .addr(mem_addr), .din(mem_din), .dout(mem_dout)
        );
    end endgenerate

    // 6. Output Response Analyzer (Comparator & MISR)
    mbist_comparator #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_comparator (
        .clk           (clk),
        .rst_n         (rst_n),
        .compare_en    (compare_en),
        .misr_reset    (diag_reset),
        .data_actual   (bist_dout),
        .data_expected (bist_din),
        .match         (match),
        .mismatch      (mismatch),
        .error_bitmap  (error_bitmap),
        .misr_signature(misr_signature)
    );

    // 7. Diagnostic Capture Unit
    mbist_diag_unit #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_diag_unit (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .diag_reset                 (diag_reset),
        .mismatch_strobe            (mismatch),
        .current_addr               (bist_addr),
        .data_actual                (bist_dout),
        .data_expected              (bist_din),
        .error_bitmap               (error_bitmap),
        .current_step               (current_step),
        .diag_has_failed            (diag_has_failed),
        .diag_fail_count            (diag_fail_count),
        .diag_first_fail_addr       (diag_first_fail_addr),
        .diag_first_fail_data_actual(diag_first_fail_data_actual),
        .diag_first_fail_data_exp   (diag_first_fail_data_exp),
        .diag_first_fail_bitmask    (diag_first_fail_bitmask),
        .diag_first_fail_step       (diag_first_fail_step)
    );

endmodule
