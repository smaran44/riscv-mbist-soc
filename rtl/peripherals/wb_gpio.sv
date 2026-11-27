// GPIO input is synchronized in the SoC clock domain. OUT and OE are
// independent 8-bit registers; writes to the input register return ERR.
module wb_gpio (
    input wire clk,rst_n,req,we, input wire [3:0] addr,sel,
    input wire [31:0] wdata, output reg [31:0] rdata, output wire ack,err,
    input wire [7:0] gpio_in, output reg [7:0] gpio_out,gpio_oe
);
    (* ASYNC_REG="TRUE" *) reg [7:0] sync1,sync2;
    wire valid=(sel==4'hf) && (addr==4 || addr==8 || (addr==0 && !we));
    assign ack=req && valid;
    assign err=req && !valid;
    always @* case(addr)
        0:rdata={24'b0,sync2};
        4:rdata={24'b0,gpio_out};
        8:rdata={24'b0,gpio_oe};
        default:rdata=0;
    endcase
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sync1<=0;sync2<=0;gpio_out<=0;gpio_oe<=0;end
        else begin
            sync1<=gpio_in; sync2<=sync1;
            if (ack && we && addr==4) gpio_out<=wdata[7:0];
            if (ack && we && addr==8) gpio_oe<=wdata[7:0];
        end
    end
endmodule
