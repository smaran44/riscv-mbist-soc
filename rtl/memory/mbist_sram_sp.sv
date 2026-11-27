// FPGA/synthesis memory. The initial March write initializes the test range.
module mbist_sram_sp #(parameter ADDR_WIDTH=8, DATA_WIDTH=8)(
    input wire clk,ce_n,we_n, input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] din, output reg [DATA_WIDTH-1:0] dout
);
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
    always @(posedge clk) if (!ce_n) begin
        if (!we_n) mem[addr]<=din;
        else dout<=mem[addr];
    end
endmodule
