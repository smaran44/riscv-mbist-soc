// =============================================================================
// File: ram_sp_fault_model.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Synchronous Single-Port SRAM Behavioral Model with Dynamic Fault
//              Injection Capabilities (Stuck-At, Transition, Coupling, and
//              Address Aliasing Faults) for MBIST verification.
// =============================================================================

`timescale 1ns / 1ps
`include "mbist_defines.v"

module ram_sp_fault_model #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 8,
    parameter MEM_DEPTH  = (1 << ADDR_WIDTH)
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // Memory Interface
    input  wire                  ce_n,      // Active-low Chip Enable
    input  wire                  we_n,      // Active-low Write Enable (0 = Write, 1 = Read)
    input  wire [ADDR_WIDTH-1:0] addr,      // Memory Address
    input  wire [DATA_WIDTH-1:0] din,       // Write Data In
    output reg  [DATA_WIDTH-1:0] dout,      // Read Data Out
    
    // Fault Injection Interface (For Verification & Simulation)
    input  wire                  fault_inject_en,
    input  wire [3:0]            fault_type,
    input  wire [ADDR_WIDTH-1:0] fault_addr,
    input  wire [3:0]            fault_bit,
    input  wire [ADDR_WIDTH-1:0] fault_victim_addr,
    input  wire [3:0]            fault_victim_bit,
    input  wire [ADDR_WIDTH-1:0] fault_alias_addr
);

    // -------------------------------------------------------------------------
    // Core Memory Array
    // -------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    
    integer i;

    // -------------------------------------------------------------------------
    // Synchronous Read / Write and Fault Emulation Logic
    // -------------------------------------------------------------------------
    wire [ADDR_WIDTH-1:0] effective_addr;
    
    // Address Aliasing Fault Emulation: If fault is active and accessing alias_addr, map to fault_addr
    assign effective_addr = (fault_inject_en && (fault_type == `FAULT_ADDR_DECODER) && (addr == fault_alias_addr)) 
                            ? fault_addr 
                            : addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout <= {DATA_WIDTH{1'b0}};
            // Initialize memory contents to deterministic zeros upon reset
            for (i = 0; i < MEM_DEPTH; i = i + 1) begin
                mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end else if (!ce_n) begin
            if (!we_n) begin
                // -------------------------------------------------------------
                // WRITE OPERATION
                // -------------------------------------------------------------
                if (fault_inject_en && (effective_addr == fault_addr)) begin
                    case (fault_type)
                        `FAULT_SA0: begin
                            // Target bit forced to 0 regardless of din
                            mem[effective_addr] <= (din & ~(1 << fault_bit));
                        end
                        
                        `FAULT_SA1: begin
                            // Target bit forced to 1 regardless of din
                            mem[effective_addr] <= (din | (1 << fault_bit));
                        end
                        
                        `FAULT_TF_SLOW_RISE: begin
                            // 0 -> 1 transition fails (stays 0)
                            if (mem[effective_addr][fault_bit] == 1'b0 && din[fault_bit] == 1'b1) begin
                                mem[effective_addr] <= (din & ~(1 << fault_bit));
                            end else begin
                                mem[effective_addr] <= din;
                            end
                        end
                        
                        `FAULT_TF_SLOW_FALL: begin
                            // 1 -> 0 transition fails (stays 1)
                            if (mem[effective_addr][fault_bit] == 1'b1 && din[fault_bit] == 1'b0) begin
                                mem[effective_addr] <= (din | (1 << fault_bit));
                            end else begin
                                mem[effective_addr] <= din;
                            end
                        end
                        
                        `FAULT_CF_INVERSION: begin
                            // Invert victim cell when aggressor cell undergoes transition
                            if (mem[effective_addr][fault_bit] != din[fault_bit]) begin
                                mem[fault_victim_addr] <= mem[fault_victim_addr] ^ (1 << fault_victim_bit);
                            end
                            mem[effective_addr] <= din;
                        end
                        
                        `FAULT_CF_IDEMPOTENT: begin
                            // Force victim cell to 1 on rising transition of aggressor
                            if (mem[effective_addr][fault_bit] == 1'b0 && din[fault_bit] == 1'b1) begin
                                mem[fault_victim_addr] <= mem[fault_victim_addr] | (1 << fault_victim_bit);
                            end
                            mem[effective_addr] <= din;
                        end
                        
                        default: begin
                            mem[effective_addr] <= din;
                        end
                    endcase
                end else begin
                    mem[effective_addr] <= din;
                end
            end else begin
                // -------------------------------------------------------------
                // READ OPERATION
                // -------------------------------------------------------------
                if (fault_inject_en && (effective_addr == fault_addr)) begin
                    case (fault_type)
                        `FAULT_SA0: begin
                            dout <= (mem[effective_addr] & ~(1 << fault_bit));
                        end
                        `FAULT_SA1: begin
                            dout <= (mem[effective_addr] | (1 << fault_bit));
                        end
                        default: begin
                            dout <= mem[effective_addr];
                        end
                    endcase
                end else begin
                    dout <= mem[effective_addr];
                end
            end
        end
    end

endmodule
