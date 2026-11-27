// Byte-only functional window into the test bank. Synchronous reads take
// one SRAM cycle. Only the accepted byte is returned in its selected lane.
module wb_byte_bank #(parameter AW=8)(
    input wire clk,rst_n,req,we,bist_owned, input wire [31:0] addr,wdata,
    input wire [3:0] sel, output wire [31:0] rdata, output wire ack,err,
    output wire func_ce_n,func_we_n, output wire [AW-1:0] func_addr,
    output wire [7:0] func_din, input wire [7:0] func_dout
);
    reg read_pending;
    wire valid_byte=(sel==(4'b0001<<addr[1:0]));
    wire allowed=req && !bist_owned && valid_byte;
    wire issue=allowed && !read_pending;
    assign func_ce_n=!issue;
    assign func_we_n=!(issue && we);
    assign func_addr=addr[AW-1:0];
    assign func_din=wdata[8*addr[1:0]+:8];
    assign rdata={24'b0,func_dout} << {addr[1:0],3'b000};
    assign ack=allowed && (we || read_pending);
    assign err=req && (!valid_byte || bist_owned);
    always @(posedge clk or negedge rst_n)
        if (!rst_n) read_pending<=0;
        else read_pending<=issue && !we;
endmodule
