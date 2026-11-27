// =============================================================================
// File: mbist_defines.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Global parameter definitions, algorithm opcodes, fault injection
//              constants, and controller state encodings for the MBIST system.
// =============================================================================

`ifndef MBIST_DEFINES_V
`define MBIST_DEFINES_V

// -----------------------------------------------------------------------------
// Default Memory Geometry (Can be overridden via top-level parameters)
// -----------------------------------------------------------------------------
`define DEFAULT_ADDR_WIDTH   8       // 256 memory words
`define DEFAULT_DATA_WIDTH   8       // 8 bits per word
`define DEFAULT_MEM_DEPTH    256     // 2^ADDR_WIDTH

// -----------------------------------------------------------------------------
// MBIST Algorithm Selection Opcodes (algo_sel)
// -----------------------------------------------------------------------------
`define ALGO_MARCH_C_MINUS   3'b000  // March C- (10N complexity) - SAF, TF, AF, CFin, CFid
`define ALGO_MARCH_A         3'b001  // March A  (15N complexity) - SAF, TF, AF, Linked CF
`define ALGO_MATS_PLUS       3'b010  // MATS+    (5N complexity)  - SAF, Unlinked AF
`define ALGO_CHECKERBOARD    3'b011  // Checkerboard (55/AA alternating)
`define ALGO_SOLID_RETENTION 3'b100  // Solid 0/1 with programmable pause/retention wait
`define ALGO_CUSTOM_LFSR     3'b101  // Pseudo-random LFSR sequence test

// -----------------------------------------------------------------------------
// Data Pattern Background Types (pattern_sel)
// -----------------------------------------------------------------------------
`define PATTERN_ALL_ZEROS    3'b000  // 8'h00 / All 0s
`define PATTERN_ALL_ONES     3'b001  // 8'hFF / All 1s
`define PATTERN_CHECKER_55   3'b010  // 8'h55 (01010101)
`define PATTERN_CHECKER_AA   3'b011  // 8'hAA (10101010)
`define PATTERN_WALKING_ONE  3'b100  // Walking 1 (00000001, 00000010, ...)
`define PATTERN_WALKING_ZERO 3'b101  // Walking 0 (11111110, 11111101, ...)
`define PATTERN_LFSR_PRBS    3'b110  // PRBS-8 pseudo-random

// -----------------------------------------------------------------------------
// Fault Injection Types for SRAM Simulation Model (fault_type)
// -----------------------------------------------------------------------------
`define FAULT_NONE           4'b0000 // No fault (Golden operation)
`define FAULT_SA0            4'b0001 // Stuck-at-0 (bit stays 0 permanently)
`define FAULT_SA1            4'b0010 // Stuck-at-1 (bit stays 1 permanently)
`define FAULT_TF_SLOW_RISE   4'b0011 // Transition Fault: Cannot transition 0 -> 1
`define FAULT_TF_SLOW_FALL   4'b0100 // Transition Fault: Cannot transition 1 -> 0
`define FAULT_CF_INVERSION   4'b0101 // Coupling Fault Inversion (CFin): Victim inverts on aggressor edge
`define FAULT_CF_IDEMPOTENT  4'b0110 // Coupling Fault Idempotent (CFid): Victim forced to 0/1 on aggressor edge
`define FAULT_ADDR_DECODER   4'b0111 // Address Decoder Fault: Multiple addresses map to same physical cell

// -----------------------------------------------------------------------------
// Controller Major States
// -----------------------------------------------------------------------------
`define BIST_STATE_IDLE      4'b0000 // Standby / Waiting for bist_start
`define BIST_STATE_INIT      4'b0001 // Reset internal counters, latch parameters
`define BIST_STATE_EXECUTE   4'b0010 // Running active March test element
`define BIST_STATE_READ_WAIT 4'b0011 // Memory read access latency cycle
`define BIST_STATE_COMPARE   4'b0100 // Output response comparison & latch
`define BIST_STATE_STEP_NEXT 4'b0101 // Increment/decrement address / advance element
`define BIST_STATE_PAUSE     4'b0110 // Pause for retention or diagnostic hold
`define BIST_STATE_FINISH    4'b0111 // Complete test, set bist_done, assert pass/fail

// -----------------------------------------------------------------------------
// March C- Element Encodings (10N Sequence)
// Element 0: (w0)           - ↕ Up/Down: Write 0 to all cells (1N)
// Element 1: (r0, w1)       - ⇑ Ascending: Read 0, Write 1    (2N)
// Element 2: (r1, w0)       - ⇑ Ascending: Read 1, Write 0    (2N)
// Element 3: (r0, w1)       - ⇓ Descending: Read 0, Write 1   (2N)
// Element 4: (r1, w0)       - ⇓ Descending: Read 1, Write 0   (2N)
// Element 5: (r0)           - ↕ Up/Down: Read 0 from all cells(1N)
// -----------------------------------------------------------------------------
`define MARCH_C_E0_W0        3'd0
`define MARCH_C_E1_R0_W1     3'd1
`define MARCH_C_E2_R1_W0     3'd2
`define MARCH_C_E3_R0_W1     3'd3
`define MARCH_C_E4_R1_W0     3'd4
`define MARCH_C_E5_R0        3'd5

`endif // MBIST_DEFINES_V
