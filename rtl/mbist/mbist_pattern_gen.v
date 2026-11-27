// =============================================================================
// File: mbist_pattern_gen.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Algorithmic Data Pattern Generator producing Solid, Checkerboard,
//              Walking-1/0, and Pseudo-Random LFSR test vectors.
// =============================================================================

`timescale 1ns / 1ps
`include "mbist_defines.v"

module mbist_pattern_gen #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // Pattern Selection & Control
    input  wire [2:0]            pattern_sel,     // Base pattern selector
    input  wire                  data_invert,     // Invert output pattern
    input  wire                  lfsr_en,         // Clock LFSR step
    input  wire                  lfsr_seed_load,  // Load seed into LFSR
    input  wire [DATA_WIDTH-1:0] lfsr_seed,       // Seed value
    input  wire [ADDR_WIDTH-1:0] current_addr,    // Current address for spatial checkerboard
    
    // Generated Pattern Output
    output reg  [DATA_WIDTH-1:0] pattern_out
);

    // -------------------------------------------------------------------------
    // LFSR (Linear Feedback Shift Register) for Pseudo-Random Pattern Generation
    // Polynomial: x^8 + x^6 + x^5 + x^4 + 1 (Taps at bits 7, 5, 4, 3)
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] lfsr_reg;
    wire lfsr_feedback;
    
    assign lfsr_feedback = lfsr_reg[7] ^ lfsr_reg[5] ^ lfsr_reg[4] ^ lfsr_reg[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_reg <= {{(DATA_WIDTH-1){1'b0}}, 1'b1}; // Non-zero reset state
        end else if (lfsr_seed_load) begin
            lfsr_reg <= (lfsr_seed == {DATA_WIDTH{1'b0}}) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : lfsr_seed;
        end else if (lfsr_en) begin
            lfsr_reg <= {lfsr_reg[DATA_WIDTH-2:0], lfsr_feedback};
        end
    end

    // -------------------------------------------------------------------------
    // Combinational Pattern Synthesizer
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] raw_pattern;

    always @(*) begin
        case (pattern_sel)
            `PATTERN_ALL_ZEROS: begin
                raw_pattern = {DATA_WIDTH{1'b0}};
            end
            
            `PATTERN_ALL_ONES: begin
                raw_pattern = {DATA_WIDTH{1'b1}};
            end
            
            `PATTERN_CHECKER_55: begin
                // Physical checkerboard: alternates based on address LSB
                if (current_addr[0] == 1'b0)
                    raw_pattern = { (DATA_WIDTH/2){2'b01} };
                else
                    raw_pattern = { (DATA_WIDTH/2){2'b10} };
            end
            
            `PATTERN_CHECKER_AA: begin
                if (current_addr[0] == 1'b0)
                    raw_pattern = { (DATA_WIDTH/2){2'b10} };
                else
                    raw_pattern = { (DATA_WIDTH/2){2'b01} };
            end
            
            `PATTERN_WALKING_ONE: begin
                raw_pattern = (1 << (current_addr % DATA_WIDTH));
            end
            
            `PATTERN_WALKING_ZERO: begin
                raw_pattern = ~(1 << (current_addr % DATA_WIDTH));
            end
            
            `PATTERN_LFSR_PRBS: begin
                raw_pattern = lfsr_reg;
            end
            
            default: begin
                raw_pattern = {DATA_WIDTH{1'b0}};
            end
        endcase
    end

    // Apply inversion modifier
    always @(*) begin
        pattern_out = data_invert ? (~raw_pattern) : raw_pattern;
    end

endmodule
