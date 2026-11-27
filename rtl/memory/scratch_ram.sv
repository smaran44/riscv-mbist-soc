module scratch_ram #(parameter WORDS=4096, parameter INIT_WORD0=0)(
    input wire clk,req,we, input wire [31:0] addr,wdata, input wire [3:0] sel,
    output wire [31:0] rdata, output wire ack
);
    localparam AW=$clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    wire [AW-1:0] index=addr[AW+1:2];
    generate if (INIT_WORD0) begin : legacy_init
        initial mem[0]=0;
    end endgenerate
    integer lane;
    always @(posedge clk) if (req && we)
        for(lane=0;lane<4;lane=lane+1)
            if(sel[lane]) mem[index][8*lane+:8]<=wdata[8*lane+:8];
    assign rdata=mem[index];
    assign ack=req;
endmodule
