// =============================================================================
// File: mbist_comparator.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Output Response Analyzer (ORA) performing real-time data
//              comparison, bit-slice error masking, and MISR signature compaction.
// =============================================================================

`timescale 1ns / 1ps

module mbist_comparator #(
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // Control & Synchronization
    input  wire                  compare_en,      // Compare strobe when read data is valid
    input  wire                  misr_reset,      // Reset signature accumulator
    
    // Data Interfaces
    input  wire [DATA_WIDTH-1:0] data_actual,     // Data read from SRAM
    input  wire [DATA_WIDTH-1:0] data_expected,   // Reference pattern
    
    // Evaluation Results
    output wire                  match,           // Data matched perfectly
    output wire                  mismatch,        // Data mismatch detected
    output wire [DATA_WIDTH-1:0] error_bitmap,    // '1' indicates error at that bit position
    output reg  [DATA_WIDTH-1:0] misr_signature   // Compacted MISR signature
);

    // -------------------------------------------------------------------------
    // Bit-Wise XOR Comparison
    // -------------------------------------------------------------------------
    assign error_bitmap = compare_en ? (data_actual ^ data_expected) : {DATA_WIDTH{1'b0}};
    assign mismatch     = compare_en && (|error_bitmap);
    assign match        = compare_en && (~|error_bitmap);

    // -------------------------------------------------------------------------
    // MISR (Multiple Input Signature Register) Compactor
    // Linear feedback polynomial: x^8 + x^6 + x^5 + x^4 + 1
    // -------------------------------------------------------------------------
    wire misr_feedback;
    assign misr_feedback = misr_signature[7] ^ misr_signature[5] ^ misr_signature[4] ^ misr_signature[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            misr_signature <= {DATA_WIDTH{1'b0}};
        end else if (misr_reset) begin
            misr_signature <= {DATA_WIDTH{1'b0}};
        end else if (compare_en) begin
            // Shift with feedback XORed with incoming RAM data
            misr_signature <= {misr_signature[DATA_WIDTH-2:0], misr_feedback} ^ data_actual;
        end
    end

endmodule
