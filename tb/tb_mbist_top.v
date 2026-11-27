// =============================================================================
// File: tb_mbist_top.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Comprehensive self-checking top-level testbench executing March C-,
//              March A, and MATS+ algorithms across Golden and Fault-Injected runs
//              (SAF, TF, CF, AF), validating diagnostic logging & collar isolation.
// =============================================================================

`timescale 1ns / 1ps
`include "mbist_defines.v"
`include "tb_tasks.vh"

module tb_mbist_top;

    parameter ADDR_WIDTH = 6;              // 64 memory locations for simulation speed
    parameter DATA_WIDTH = 8;
    parameter MEM_DEPTH  = (1 << ADDR_WIDTH);
    parameter MAX_ADDR   = MEM_DEPTH - 1;

    // Clock & Reset
    reg                  clk;
    reg                  rst_n;

    // BIST Control
    reg                  bist_mode;
    reg                  bist_start;
    reg [2:0]            algo_sel;
    reg [2:0]            pattern_sel;
    reg [ADDR_WIDTH-1:0] max_addr;
    reg                  stop_on_fail;

    // Functional Interface
    reg                  func_ce_n;
    reg                  func_we_n;
    reg [ADDR_WIDTH-1:0] func_addr;
    reg [DATA_WIDTH-1:0] func_din;
    wire [DATA_WIDTH-1:0] func_dout;

    // Status & Diagnostics
    wire                  bist_busy;
    wire                  bist_done;
    wire                  bist_pass;
    wire                  bist_fail;
    wire [15:0]           diag_fail_count;
    wire [ADDR_WIDTH-1:0] diag_first_fail_addr;
    wire [DATA_WIDTH-1:0] diag_first_fail_data_actual;
    wire [DATA_WIDTH-1:0] diag_first_fail_data_exp;
    wire [DATA_WIDTH-1:0] diag_first_fail_bitmask;
    wire [3:0]            diag_first_fail_step;
    wire [DATA_WIDTH-1:0] misr_signature;

    // Fault Injection
    reg                  fault_inject_en;
    reg [3:0]            fault_type;
    reg [ADDR_WIDTH-1:0] fault_addr;
    reg [3:0]            fault_bit;
    reg [ADDR_WIDTH-1:0] fault_victim_addr;
    reg [3:0]            fault_victim_bit;
    reg [ADDR_WIDTH-1:0] fault_alias_addr;

    // Test tracking
    integer total_tests = 0;
    integer passed_tests = 0;

    // Clock Generator (100 MHz / 10ns)
    always #5 clk = ~clk;

    // Top-Level DUT Instantiation
    mbist_top #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH (MEM_DEPTH)
    ) dut (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .bist_mode                  (bist_mode),
        .bist_start                 (bist_start),
        .algo_sel                   (algo_sel),
        .pattern_sel                (pattern_sel),
        .max_addr                   (max_addr),
        .stop_on_fail               (stop_on_fail),
        .func_ce_n                  (func_ce_n),
        .func_we_n                  (func_we_n),
        .func_addr                  (func_addr),
        .func_din                   (func_din),
        .func_dout                  (func_dout),
        .bist_busy                  (bist_busy),
        .bist_done                  (bist_done),
        .bist_pass                  (bist_pass),
        .bist_fail                  (bist_fail),
        .diag_fail_count            (diag_fail_count),
        .diag_first_fail_addr       (diag_first_fail_addr),
        .diag_first_fail_data_actual(diag_first_fail_data_actual),
        .diag_first_fail_data_exp   (diag_first_fail_data_exp),
        .diag_first_fail_bitmask    (diag_first_fail_bitmask),
        .diag_first_fail_step       (diag_first_fail_step),
        .misr_signature             (misr_signature),
        .fault_inject_en            (fault_inject_en),
        .fault_type                 (fault_type),
        .fault_addr                 (fault_addr),
        .fault_bit                  (fault_bit),
        .fault_victim_addr          (fault_victim_addr),
        .fault_victim_bit           (fault_victim_bit),
        .fault_alias_addr           (fault_alias_addr)
    );

    // -------------------------------------------------------------------------
    // Helper task to execute a full BIST run and wait for completion
    // -------------------------------------------------------------------------
    task run_bist;
        input [2:0] sel_algo;
        input [2:0] sel_patt;
        begin
            bist_mode    <= 1'b1;
            algo_sel     <= sel_algo;
            pattern_sel  <= sel_patt;
            max_addr     <= MAX_ADDR;
            stop_on_fail <= 1'b0;
            
            @(posedge clk);
            bist_start <= 1'b1;
            @(posedge clk);
            bist_start <= 1'b0;
            
            // Wait for BIST completion
            @(posedge clk);
            wait (bist_done == 1'b1);
            @(posedge clk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Verification Process
    // -------------------------------------------------------------------------
    initial begin
        // Signal Initialization
        clk             = 0;
        rst_n           = 0;
        bist_mode       = 0;
        bist_start      = 0;
        algo_sel        = `ALGO_MARCH_C_MINUS;
        pattern_sel     = `PATTERN_ALL_ZEROS;
        max_addr        = MAX_ADDR;
        stop_on_fail    = 0;
        func_ce_n       = 1;
        func_we_n       = 1;
        func_addr       = 0;
        func_din        = 0;
        fault_inject_en = 0;
        fault_type      = `FAULT_NONE;
        fault_addr      = 0;
        fault_bit       = 0;
        fault_victim_addr = 0;
        fault_victim_bit  = 0;
        fault_alias_addr  = 0;

        print_banner("MEMORY BUILT-IN SELF-TEST (MBIST) 2024 - VERIFICATION SUITE");

        // Apply Power-On Reset
        #20;
        rst_n = 1;
        #20;

        // =====================================================================
        // TEST 1: Golden Run (March C- on Fault-Free RAM)
        // =====================================================================
        total_tests = total_tests + 1;
        print_test_header(1, "Golden Run (March C- on Clean SRAM)", 
                             "Executes 10N March C- algorithm with no faults injected. Expects BIST_PASS = 1.");
        fault_inject_en = 0;
        run_bist(`ALGO_MARCH_C_MINUS, `PATTERN_ALL_ZEROS);

        if (bist_pass == 1'b1 && bist_fail == 1'b0 && diag_fail_count == 16'd0) begin
            passed_tests = passed_tests + 1;
            print_result("Test 1: Golden March C- Run", 1);
            $display("  -> MISR Final Signature: 0x%02h", misr_signature);
        end else begin
            print_result("Test 1: Golden March C- Run", 0);
        end

        #20;

        // =====================================================================
        // TEST 2: Stuck-At-0 Fault (SA0) Detection
        // =====================================================================
        total_tests = total_tests + 1;
        print_test_header(2, "Stuck-At-0 Fault (SA0) Detection", 
                             "Injects SA0 at Address 0x1F, Bit 4. Expects BIST_FAIL = 1 and correct diagnostic latching.");
        fault_inject_en = 1;
        fault_type      = `FAULT_SA0;
        fault_addr      = 6'h1F;
        fault_bit       = 4; // Bit 4 stuck at 0
        run_bist(`ALGO_MARCH_C_MINUS, `PATTERN_ALL_ZEROS);

        if (bist_fail == 1'b1 && diag_first_fail_addr == 6'h1F && diag_first_fail_bitmask == 8'h10) begin
            passed_tests = passed_tests + 1;
            print_result("Test 2: SA0 Fault Detection", 1);
            $display("  -> Diagnosed Fail Addr: 0x%02h | Expected: 0x1F", diag_first_fail_addr);
            $display("  -> Diagnosed Bitmask:   0x%02h | Expected: 0x10", diag_first_fail_bitmask);
            $display("  -> Total Failures Detected: %0d", diag_fail_count);
        end else begin
            print_result("Test 2: SA0 Fault Detection", 0);
            $display("  -> Actual Addr: 0x%02h, Actual Mask: 0x%02h", diag_first_fail_addr, diag_first_fail_bitmask);
        end

        #20;

        // =====================================================================
        // TEST 3: Stuck-At-1 Fault (SA1) Detection
        // =====================================================================
        total_tests = total_tests + 1;
        print_test_header(3, "Stuck-At-1 Fault (SA1) Detection", 
                             "Injects SA1 at Address 0x2B, Bit 2. Expects BIST_FAIL = 1 and bitmask 0x04.");
        fault_inject_en = 1;
        fault_type      = `FAULT_SA1;
        fault_addr      = 6'h2B;
        fault_bit       = 2; // Bit 2 stuck at 1
        run_bist(`ALGO_MARCH_C_MINUS, `PATTERN_ALL_ZEROS);

        if (bist_fail == 1'b1 && diag_first_fail_addr == 6'h2B && diag_first_fail_bitmask == 8'h04) begin
            passed_tests = passed_tests + 1;
            print_result("Test 3: SA1 Fault Detection", 1);
            $display("  -> Diagnosed Fail Addr: 0x%02h | Bitmask: 0x%02h", diag_first_fail_addr, diag_first_fail_bitmask);
        end else begin
            print_result("Test 3: SA1 Fault Detection", 0);
        end

        #20;

        // =====================================================================
        // TEST 4: Transition Fault (Slow-to-Rise 0->1) Detection
        // =====================================================================
        total_tests = total_tests + 1;
        print_test_header(4, "Transition Fault (Slow-to-Rise) Detection", 
                             "Injects TF at Address 0x12, Bit 0. Fails when transitioning 0 -> 1.");
        fault_inject_en = 1;
        fault_type      = `FAULT_TF_SLOW_RISE;
        fault_addr      = 6'h12;
        fault_bit       = 0;
        run_bist(`ALGO_MARCH_C_MINUS, `PATTERN_ALL_ZEROS);

        if (bist_fail == 1'b1 && diag_first_fail_addr == 6'h12 && diag_first_fail_bitmask == 8'h01) begin
            passed_tests = passed_tests + 1;
            print_result("Test 4: Transition Fault Detection", 1);
            $display("  -> Diagnosed Fail Addr: 0x%02h | Failing Step: %0d", diag_first_fail_addr, diag_first_fail_step);
        end else begin
            print_result("Test 4: Transition Fault Detection", 0);
        end

        #20;

        // =====================================================================
        // TEST 5: Coupling Fault (Inversion CFin) Detection
        // =====================================================================
        total_tests = total_tests + 1;
        print_test_header(5, "Coupling Fault (Inversion CFin) Detection", 
                             "Aggressor at Address 0x05 Bit 0 toggles, inverting victim cell at Address 0x06 Bit 3.");
        fault_inject_en   = 1;
        fault_type        = `FAULT_CF_INVERSION;
        fault_addr        = 6'h05; // Aggressor
        fault_bit         = 0;
        fault_victim_addr = 6'h06; // Victim
        fault_victim_bit  = 3;
        run_bist(`ALGO_MARCH_C_MINUS, `PATTERN_ALL_ZEROS);

        if (bist_fail == 1'b1 && diag_first_fail_addr == 6'h06 && diag_first_fail_bitmask == 8'h08) begin
            passed_tests = passed_tests + 1;
            print_result("Test 5: Coupling Fault Detection", 1);
            $display("  -> Diagnosed Victim Fail Addr: 0x%02h | Corrupted Bit: 0x%02h", diag_first_fail_addr, diag_first_fail_bitmask);
        end else begin
            print_result("Test 5: Coupling Fault Detection", 0);
        end

        #20;

        // =====================================================================
        // TEST 6: Address Decoder Fault (Aliasing) Detection
        // =====================================================================
        total_tests = total_tests + 1;
        print_test_header(6, "Address Decoder Fault (Aliasing) Detection", 
                             "Address 0x1E aliases to 0x02. Writes to 0x1E overwrite 0x02.");
        fault_inject_en  = 1;
        fault_type       = `FAULT_ADDR_DECODER;
        fault_addr       = 6'h02;
        fault_alias_addr = 6'h1E;
        run_bist(`ALGO_MARCH_C_MINUS, `PATTERN_ALL_ZEROS);

        if (bist_fail == 1'b1) begin
            passed_tests = passed_tests + 1;
            print_result("Test 6: Address Decoder Fault Detection", 1);
            $display("  -> Aliasing Fault Caught at Address: 0x%02h", diag_first_fail_addr);
        end else begin
            print_result("Test 6: Address Decoder Fault Detection", 0);
        end

        #20;

        // =====================================================================
        // TEST 7: Multi-Algorithm Validation (March A and MATS+)
        // =====================================================================
        total_tests = total_tests + 1;
        print_test_header(7, "Multi-Algorithm Validation (March A & MATS+)", 
                             "Runs clean March A (15N) and MATS+ (5N) to verify multi-algorithm support.");
        fault_inject_en = 0;
        run_bist(`ALGO_MARCH_A, `PATTERN_ALL_ZEROS);
        
        if (bist_pass == 1'b1 && bist_fail == 1'b0) begin
            run_bist(`ALGO_MATS_PLUS, `PATTERN_ALL_ZEROS);
            if (bist_pass == 1'b1 && bist_fail == 1'b0) begin
                passed_tests = passed_tests + 1;
                print_result("Test 7: Multi-Algorithm Verification", 1);
            end else begin
                print_result("Test 7: Multi-Algorithm Verification (MATS+ Failed)", 0);
            end
        end else begin
            print_result("Test 7: Multi-Algorithm Verification (March A Failed)", 0);
        end

        #20;

        // =====================================================================
        // TEST 8: Functional Mode Isolation
        // =====================================================================
        total_tests = total_tests + 1;
        print_test_header(8, "BIST Collar / Functional Mode Isolation", 
                             "Sets bist_mode = 0. Verifies CPU functional read/write access to SRAM.");
        bist_mode       = 0;
        fault_inject_en = 0;
        
        // Write 0xDE to addr 0x10
        @(posedge clk);
        func_ce_n <= 0;
        func_we_n <= 0;
        func_addr <= 6'h10;
        func_din  <= 8'hDE;
        @(posedge clk);
        // Write 0xAD to addr 0x11
        func_addr <= 6'h11;
        func_din  <= 8'hAD;
        @(posedge clk);
        // Read back addr 0x10
        func_we_n <= 1;
        func_addr <= 6'h10;
        @(posedge clk);
        @(posedge clk); // Read latency
        
        if (func_dout == 8'hDE) begin
            // Read back addr 0x11
            func_addr <= 6'h11;
            @(posedge clk);
            @(negedge clk);
            if (func_dout == 8'hAD) begin
                passed_tests = passed_tests + 1;
                print_result("Test 8: Functional Mode Isolation", 1);
            end else begin
                print_result("Test 8: Functional Mode Isolation", 0);
            end
        end else begin
            print_result("Test 8: Functional Mode Isolation", 0);
        end
        func_ce_n <= 1;

        // =====================================================================
        // SUMMARY
        // =====================================================================
        $display("\n================================================================================");
        $display("  ALL VERIFICATION TESTS COMPLETED : %0d / %0d PASSED", passed_tests, total_tests);
        if (passed_tests == total_tests) begin
            $display("  STATUS: \033[1;32mALL MBIST ARCHITECTURE TESTS PASSED SUCCESSFULLY (ALL SUPPLIED SCENARIOS)\033[0m");
        end else begin
            $display("  STATUS: \033[1;31mSOME TESTS FAILED - REVIEW LOGS ABOVE\033[0m");
        end
        $display("================================================================================\n");

        if (passed_tests != total_tests) $fatal(1, "MBIST regression failed");
        $display("PASS tb_mbist_top: %0d of %0d vendor scenarios", passed_tests, total_tests);
        #50;
        $finish;
    end

    initial begin
        repeat (30000) @(posedge clk);
        $fatal(1, "MBIST standalone watchdog");
    end
endmodule
