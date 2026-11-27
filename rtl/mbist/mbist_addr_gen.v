// =============================================================================
// File: mbist_addr_gen.v
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Programmable Address Generator supporting Ascending (⇑),
//              Descending (⇓), and arbitrary bounds for March test traversals.
// =============================================================================

`timescale 1ns / 1ps

module mbist_addr_gen #(
    parameter ADDR_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,
    
    // Control Interface
    input  wire                  addr_en,         // Step address to next value
    input  wire                  addr_dir,        // 0 = Ascending (0 -> Max), 1 = Descending (Max -> 0)
    input  wire                  addr_init,       // Initialize address counter according to direction
    input  wire                  addr_load,       // Force load custom address
    input  wire [ADDR_WIDTH-1:0] addr_load_val,   // Value for manual load
    input  wire [ADDR_WIDTH-1:0] max_addr,        // Upper address boundary (e.g., 255 for 256 words)
    
    // Status & Outputs
    output reg  [ADDR_WIDTH-1:0] addr_out,        // Current address output
    output wire                  addr_is_first,   // High when at 0 (ascending start / descending end)
    output wire                  addr_is_last,    // High when at max_addr (ascending end / descending start)
    output wire                  sweep_done       // High when current direction traversal reached final address
);

    assign addr_is_first = (addr_out == {ADDR_WIDTH{1'b0}});
    assign addr_is_last  = (addr_out == max_addr);
    
    // Traversal is complete if ascending and reached max, or descending and reached 0
    assign sweep_done    = (addr_dir == 1'b0) ? addr_is_last : addr_is_first;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_out <= {ADDR_WIDTH{1'b0}};
        end else if (addr_load) begin
            addr_out <= addr_load_val;
        end else if (addr_init) begin
            if (addr_dir == 1'b0) begin
                addr_out <= {ADDR_WIDTH{1'b0}}; // Ascending start
            end else begin
                addr_out <= max_addr;           // Descending start
            end
        end else if (addr_en) begin
            if (addr_dir == 1'b0) begin
                // Ascending traversal
                if (addr_out < max_addr) begin
                    addr_out <= addr_out + 1'b1;
                end else begin
                    addr_out <= {ADDR_WIDTH{1'b0}}; // Wrap around
                end
            end else begin
                // Descending traversal
                if (addr_out > {ADDR_WIDTH{1'b0}}) begin
                    addr_out <= addr_out - 1'b1;
                end else begin
                    addr_out <= max_addr;           // Wrap around
                end
            end
        end
    end

endmodule
