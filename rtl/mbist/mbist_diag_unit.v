// =============================================================================
// File: mbist_diag_unit.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Diagnostic Register Unit capturing first-fail address, bitmask,
//              expected vs actual data, failing March element, and total error count.
// =============================================================================

`timescale 1ns / 1ps

module mbist_diag_unit #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // Control & Reset
    input  wire                  diag_reset,                  // Clear diagnostic latches
    input  wire                  mismatch_strobe,             // High when comparator detects error
    
    // Input Context
    input  wire [ADDR_WIDTH-1:0] current_addr,
    input  wire [DATA_WIDTH-1:0] data_actual,
    input  wire [DATA_WIDTH-1:0] data_expected,
    input  wire [DATA_WIDTH-1:0] error_bitmap,
    input  wire [3:0]            current_step,
    
    // Diagnostic Readout Outputs
    output reg                   diag_has_failed,             // Sticky failure flag
    output reg  [15:0]           diag_fail_count,             // Total mismatch count
    output reg  [ADDR_WIDTH-1:0] diag_first_fail_addr,        // Address of 1st failure
    output reg  [DATA_WIDTH-1:0] diag_first_fail_data_actual, // Read data on 1st fail
    output reg  [DATA_WIDTH-1:0] diag_first_fail_data_exp,    // Expected data on 1st fail
    output reg  [DATA_WIDTH-1:0] diag_first_fail_bitmask,     // Error bitmask on 1st fail
    output reg  [3:0]            diag_first_fail_step         // March step of 1st fail
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diag_has_failed             <= 1'b0;
            diag_fail_count             <= 16'd0;
            diag_first_fail_addr        <= {ADDR_WIDTH{1'b0}};
            diag_first_fail_data_actual <= {DATA_WIDTH{1'b0}};
            diag_first_fail_data_exp    <= {DATA_WIDTH{1'b0}};
            diag_first_fail_bitmask     <= {DATA_WIDTH{1'b0}};
            diag_first_fail_step        <= 4'd0;
        end else if (diag_reset) begin
            diag_has_failed             <= 1'b0;
            diag_fail_count             <= 16'd0;
            diag_first_fail_addr        <= {ADDR_WIDTH{1'b0}};
            diag_first_fail_data_actual <= {DATA_WIDTH{1'b0}};
            diag_first_fail_data_exp    <= {DATA_WIDTH{1'b0}};
            diag_first_fail_bitmask     <= {DATA_WIDTH{1'b0}};
            diag_first_fail_step        <= 4'd0;
        end else if (mismatch_strobe) begin
            // Increment cumulative failure count
            diag_fail_count <= diag_fail_count + 1'b1;
            
            // Latch first failure details
            if (!diag_has_failed) begin
                diag_has_failed             <= 1'b1;
                diag_first_fail_addr        <= current_addr;
                diag_first_fail_data_actual <= data_actual;
                diag_first_fail_data_exp    <= data_expected;
                diag_first_fail_bitmask     <= error_bitmap;
                diag_first_fail_step        <= current_step;
            end
        end
    end

endmodule
