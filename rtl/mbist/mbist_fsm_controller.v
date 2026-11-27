// =============================================================================
// File: mbist_fsm_controller.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Multi-Algorithm Finite State Machine (FSM) Controller executing
//              March C- (10N), March A (15N), MATS+ (5N), and Checkerboard tests
//              with synchronous SRAM read/write pipeline timing.
// =============================================================================

`timescale 1ns / 1ps
`include "mbist_defines.v"

module mbist_fsm_controller #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // Control & Configuration
    input  wire                  bist_start,      // Start BIST execution pulse
    input  wire [2:0]            algo_sel,        // Selected algorithm (March C-, March A, MATS+, etc.)
    input  wire [2:0]            pattern_sel,     // Background data pattern
    input  wire [ADDR_WIDTH-1:0] max_addr,        // Max address bound
    input  wire                  stop_on_fail,    // If high, halt BIST immediately upon first mismatch
    
    // Address Generator Controls
    output reg                   addr_en,
    output reg                   addr_dir,        // 0 = Ascending, 1 = Descending
    output reg                   addr_init,
    input  wire                  sweep_done,      // Address generator finished current pass
    input  wire [ADDR_WIDTH-1:0] current_addr,
    
    // Pattern Generator Controls
    output reg                   data_invert,     // Invert pattern polarity
    output reg                   lfsr_en,
    
    // Memory Interface (via BIST Collar)
    output reg                   bist_ce_n,
    output reg                   bist_we_n,
    
    // Comparator & Diagnostic Controls
    output reg                   compare_en,      // Compare strobe when read data is ready
    output reg                   diag_reset,      // Reset diagnostics at test start
    output reg  [3:0]            current_step,    // Active March element identifier
    input  wire                  mismatch_strobe, // From comparator
    
    // Top-Level Status Flags
    output reg                   bist_busy,
    output reg                   bist_done,
    output reg                   bist_pass,
    output reg                   bist_fail
);

    // -------------------------------------------------------------------------
    // Major FSM States
    // -------------------------------------------------------------------------
    localparam S_IDLE        = 4'd0;
    localparam S_INIT        = 4'd1;
    localparam S_READ_REQ    = 4'd2; // Issue read address & strobe
    localparam S_READ_EVAL   = 4'd3; // Strobe comparison & latch response
    localparam S_WRITE_ACT   = 4'd4; // Issue write cycle
    localparam S_ADVANCE     = 4'd5; // Advance address or advance element
    localparam S_DONE        = 4'd6;

    reg [3:0] state, next_state;
    
    // Sub-operation tracking within a March element
    reg [2:0] march_elem;     // Which March element in the algorithm
    reg [2:0] micro_op_idx;   // Which operation in the current element (0, 1, 2...)
    reg       has_error_reg;

    // Total elements per algorithm
    reg [2:0] max_elements;
    always @(*) begin
        case (algo_sel)
            `ALGO_MARCH_C_MINUS:   max_elements = 3'd6; // 6 elements (E0..E5)
            `ALGO_MARCH_A:         max_elements = 3'd5; // 5 elements (E0..E4)
            `ALGO_MATS_PLUS:       max_elements = 3'd3; // 3 elements (E0..E2)
            `ALGO_CHECKERBOARD:    max_elements = 3'd4; // 4 elements (E0..E3)
            default:               max_elements = 3'd6;
        endcase
    end

    // -------------------------------------------------------------------------
    // Micro-Operation Decoder for Active March Element
    // Identifies whether current sub-operation is Read (0) or Write (1),
    // what polarity is expected/written, and traversal direction.
    // -------------------------------------------------------------------------
    reg       current_is_write;
    reg       current_polarity; // 0 = standard background, 1 = inverted background
    reg       elem_dir;         // 0 = Ascending, 1 = Descending
    reg [2:0] num_micro_ops;    // Number of operations at each address

    always @(*) begin
        current_step = {1'b0, march_elem};
        
        // Defaults
        current_is_write = 1'b0;
        current_polarity = 1'b0;
        elem_dir         = 1'b0;
        num_micro_ops    = 3'd1;

        case (algo_sel)
            // =================================================================
            // MARCH C- (10N) Sequence:
            // E0: ↕ (w0)
            // E1: ⇑ (r0, w1)
            // E2: ⇑ (r1, w0)
            // E3: ⇓ (r0, w1)
            // E4: ⇓ (r1, w0)
            // E5: ↕ (r0)
            // =================================================================
            `ALGO_MARCH_C_MINUS: begin
                case (march_elem)
                    `MARCH_C_E0_W0: begin // ↕ (w0)
                        elem_dir         = 1'b0;
                        num_micro_ops    = 3'd1;
                        current_is_write = 1'b1;
                        current_polarity = 1'b0;
                    end
                    `MARCH_C_E1_R0_W1: begin // ⇑ (r0, w1)
                        elem_dir         = 1'b0;
                        num_micro_ops    = 3'd2;
                        if (micro_op_idx == 3'd0) begin
                            current_is_write = 1'b0; // r0
                            current_polarity = 1'b0;
                        end else begin
                            current_is_write = 1'b1; // w1
                            current_polarity = 1'b1;
                        end
                    end
                    `MARCH_C_E2_R1_W0: begin // ⇑ (r1, w0)
                        elem_dir         = 1'b0;
                        num_micro_ops    = 3'd2;
                        if (micro_op_idx == 3'd0) begin
                            current_is_write = 1'b0; // r1
                            current_polarity = 1'b1;
                        end else begin
                            current_is_write = 1'b1; // w0
                            current_polarity = 1'b0;
                        end
                    end
                    `MARCH_C_E3_R0_W1: begin // ⇓ (r0, w1)
                        elem_dir         = 1'b1;
                        num_micro_ops    = 3'd2;
                        if (micro_op_idx == 3'd0) begin
                            current_is_write = 1'b0; // r0
                            current_polarity = 1'b0;
                        end else begin
                            current_is_write = 1'b1; // w1
                            current_polarity = 1'b1;
                        end
                    end
                    `MARCH_C_E4_R1_W0: begin // ⇓ (r1, w0)
                        elem_dir         = 1'b1;
                        num_micro_ops    = 3'd2;
                        if (micro_op_idx == 3'd0) begin
                            current_is_write = 1'b0; // r1
                            current_polarity = 1'b1;
                        end else begin
                            current_is_write = 1'b1; // w0
                            current_polarity = 1'b0;
                        end
                    end
                    `MARCH_C_E5_R0: begin // ↕ (r0)
                        elem_dir         = 1'b0;
                        num_micro_ops    = 3'd1;
                        current_is_write = 1'b0; // r0
                        current_polarity = 1'b0;
                    end
                endcase
            end

            // =================================================================
            // MARCH A (15N) Sequence:
            // E0: ↕ (w0)
            // E1: ⇑ (r0, w1, w0, w1)
            // E2: ⇑ (r1, w0, w1)
            // E3: ⇓ (r1, w0, w1, w0)
            // E4: ⇓ (r0, w1, w0)
            // =================================================================
            `ALGO_MARCH_A: begin
                case (march_elem)
                    3'd0: begin // ↕ (w0)
                        elem_dir = 1'b0; num_micro_ops = 3'd1;
                        current_is_write = 1'b1; current_polarity = 1'b0;
                    end
                    3'd1: begin // ⇑ (r0, w1, w0, w1)
                        elem_dir = 1'b0; num_micro_ops = 3'd4;
                        case (micro_op_idx)
                            3'd0: begin current_is_write = 1'b0; current_polarity = 1'b0; end // r0
                            3'd1: begin current_is_write = 1'b1; current_polarity = 1'b1; end // w1
                            3'd2: begin current_is_write = 1'b1; current_polarity = 1'b0; end // w0
                            3'd3: begin current_is_write = 1'b1; current_polarity = 1'b1; end // w1
                        endcase
                    end
                    3'd2: begin // ⇑ (r1, w0, w1)
                        elem_dir = 1'b0; num_micro_ops = 3'd3;
                        case (micro_op_idx)
                            3'd0: begin current_is_write = 1'b0; current_polarity = 1'b1; end // r1
                            3'd1: begin current_is_write = 1'b1; current_polarity = 1'b0; end // w0
                            3'd2: begin current_is_write = 1'b1; current_polarity = 1'b1; end // w1
                        endcase
                    end
                    3'd3: begin // ⇓ (r1, w0, w1, w0)
                        elem_dir = 1'b1; num_micro_ops = 3'd4;
                        case (micro_op_idx)
                            3'd0: begin current_is_write = 1'b0; current_polarity = 1'b1; end // r1
                            3'd1: begin current_is_write = 1'b1; current_polarity = 1'b0; end // w0
                            3'd2: begin current_is_write = 1'b1; current_polarity = 1'b1; end // w1
                            3'd3: begin current_is_write = 1'b1; current_polarity = 1'b0; end // w0
                        endcase
                    end
                    3'd4: begin // ⇓ (r0, w1, w0)
                        elem_dir = 1'b1; num_micro_ops = 3'd3;
                        case (micro_op_idx)
                            3'd0: begin current_is_write = 1'b0; current_polarity = 1'b0; end // r0
                            3'd1: begin current_is_write = 1'b1; current_polarity = 1'b1; end // w1
                            3'd2: begin current_is_write = 1'b1; current_polarity = 1'b0; end // w0
                        endcase
                    end
                endcase
            end

            // =================================================================
            // MATS+ (5N) Sequence:
            // E0: ↕ (w0)
            // E1: ⇑ (r0, w1)
            // E2: ⇓ (r1, w0)
            // =================================================================
            `ALGO_MATS_PLUS: begin
                case (march_elem)
                    3'd0: begin // ↕ (w0)
                        elem_dir = 1'b0; num_micro_ops = 3'd1;
                        current_is_write = 1'b1; current_polarity = 1'b0;
                    end
                    3'd1: begin // ⇑ (r0, w1)
                        elem_dir = 1'b0; num_micro_ops = 3'd2;
                        if (micro_op_idx == 3'd0) begin
                            current_is_write = 1'b0; current_polarity = 1'b0; // r0
                        end else begin
                            current_is_write = 1'b1; current_polarity = 1'b1; // w1
                        end
                    end
                    3'd2: begin // ⇓ (r1, w0)
                        elem_dir = 1'b1; num_micro_ops = 3'd2;
                        if (micro_op_idx == 3'd0) begin
                            current_is_write = 1'b0; current_polarity = 1'b1; // r1
                        end else begin
                            current_is_write = 1'b1; current_polarity = 1'b0; // w0
                        end
                    end
                endcase
            end

            // =================================================================
            // CHECKERBOARD Sequence:
            // E0: ↕ (w_pattern)
            // E1: ↕ (r_pattern)
            // E2: ↕ (w_inv_pattern)
            // E3: ↕ (r_inv_pattern)
            // =================================================================
            `ALGO_CHECKERBOARD: begin
                case (march_elem)
                    3'd0: begin elem_dir = 1'b0; num_micro_ops = 3'd1; current_is_write = 1'b1; current_polarity = 1'b0; end
                    3'd1: begin elem_dir = 1'b0; num_micro_ops = 3'd1; current_is_write = 1'b0; current_polarity = 1'b0; end
                    3'd2: begin elem_dir = 1'b0; num_micro_ops = 3'd1; current_is_write = 1'b1; current_polarity = 1'b1; end
                    3'd3: begin elem_dir = 1'b0; num_micro_ops = 3'd1; current_is_write = 1'b0; current_polarity = 1'b1; end
                endcase
            end

            default: begin
                elem_dir         = 1'b0;
                num_micro_ops    = 3'd1;
                current_is_write = 1'b1;
                current_polarity = 1'b0;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Synchronous FSM State Transitions
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            march_elem    <= 3'd0;
            micro_op_idx  <= 3'd0;
            has_error_reg <= 1'b0;
        end else begin
            state <= next_state;
            
            if (state == S_IDLE && bist_start) begin
                march_elem    <= 3'd0;
                micro_op_idx  <= 3'd0;
                has_error_reg <= 1'b0;
            end else if (mismatch_strobe) begin
                has_error_reg <= 1'b1;
            end
            
            // Advance micro-ops and March elements in ADVANCE state
            if (state == S_ADVANCE) begin
                if (stop_on_fail && has_error_reg) begin
                    // Halting due to fail
                end else if (micro_op_idx + 1'b1 < num_micro_ops) begin
                    // Advance to next micro-operation at the same memory address
                    micro_op_idx <= micro_op_idx + 1'b1;
                end else begin
                    // Completed all micro-ops at this address
                    micro_op_idx <= 3'd0;
                    if (sweep_done) begin
                        // Completed full address sweep for this element
                        march_elem <= march_elem + 1'b1;
                    end
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Next State Logic
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = state;
        
        case (state)
            S_IDLE: begin
                if (bist_start)
                    next_state = S_INIT;
            end

            S_INIT: begin
                // Initialize address and jump to first operation
                if (current_is_write)
                    next_state = S_WRITE_ACT;
                else
                    next_state = S_READ_REQ;
            end

            S_READ_REQ: begin
                // Memory needs 1 cycle to present synchronous read data
                next_state = S_READ_EVAL;
            end

            S_READ_EVAL: begin
                // Strobe comparator evaluation
                next_state = S_ADVANCE;
            end

            S_WRITE_ACT: begin
                // Write completes in 1 cycle
                next_state = S_ADVANCE;
            end

            S_ADVANCE: begin
                if (stop_on_fail && has_error_reg) begin
                    next_state = S_DONE;
                end else if (micro_op_idx + 1'b1 < num_micro_ops) begin
                    // Next micro-op on SAME address
                    if (march_elem < max_elements) begin
                        // Check if upcoming micro-op is write or read
                        // Peek at next micro-op
                        // If current was read (idx 0) and next is write (idx 1), go to WRITE
                        next_state = S_WRITE_ACT; // In March sequences, reads precede writes
                    end else begin
                        next_state = S_DONE;
                    end
                end else begin
                    // Next address or next element
                    if (sweep_done) begin
                        if (march_elem + 1'b1 >= max_elements) begin
                            // All March elements finished!
                            next_state = S_DONE;
                        end else begin
                            // Start new element, initialize address
                            next_state = S_INIT;
                        end
                    end else begin
                        // Step address and continue current element
                        // Look at first micro-op of current element
                        // If it's a write (like E0), go to WRITE_ACT, else READ_REQ
                        if (num_micro_ops > 3'd1 || !current_is_write)
                            next_state = S_READ_REQ;
                        else
                            next_state = S_WRITE_ACT;
                    end
                end
            end

            S_DONE: begin
                if (!bist_start)
                    next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Output Generation Logic
    // -------------------------------------------------------------------------
    always @(*) begin
        // Defaults
        bist_busy   = 1'b1;
        bist_done   = 1'b0;
        bist_pass   = 1'b0;
        bist_fail   = 1'b0;
        bist_ce_n   = 1'b1;
        bist_we_n   = 1'b1;
        compare_en  = 1'b0;
        diag_reset  = 1'b0;
        addr_en     = 1'b0;
        addr_init   = 1'b0;
        addr_dir    = elem_dir;
        data_invert = current_polarity;
        lfsr_en     = 1'b0;

        case (state)
            S_IDLE: begin
                bist_busy = 1'b0;
            end

            S_INIT: begin
                addr_init  = 1'b1;
                addr_dir   = elem_dir;
                diag_reset = (march_elem == 3'd0) ? 1'b1 : 1'b0;
            end

            S_READ_REQ: begin
                bist_ce_n = 1'b0;
                bist_we_n = 1'b1; // Read mode
            end

            S_READ_EVAL: begin
                bist_ce_n  = 1'b0;
                bist_we_n  = 1'b1;
                compare_en = 1'b1; // Strobe comparator
            end

            S_WRITE_ACT: begin
                bist_ce_n = 1'b0;
                bist_we_n = 1'b0; // Write mode
            end

            S_ADVANCE: begin
                // Step address counter only when all micro-ops at current address are done
                if (micro_op_idx + 1'b1 >= num_micro_ops && !sweep_done) begin
                    addr_en = 1'b1;
                end
            end

            S_DONE: begin
                bist_busy = 1'b0;
                bist_done = 1'b1;
                bist_pass = ~has_error_reg;
                bist_fail = has_error_reg;
            end
        endcase
    end

endmodule
