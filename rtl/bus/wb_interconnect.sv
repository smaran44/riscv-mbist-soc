// Single-initiator Wishbone Classic. ADR is the full byte address. At most
// one target sees req. Optional registered wait clocks exercise backpressure.
module wb_interconnect #(
    parameter integer BANK_AW=8, WAIT_CYCLES=0
)(
    input wire clk,rst_n,cyc,stb, input wire [31:0] addr,
    output wire rom_req, ram_req, bank_req, mbist_req, gpio_req,
    input wire [4:0] slave_ack,slave_err,
    input wire [31:0] rom_data,ram_data,bank_data,mbist_data,gpio_data,
    output wire ack,err, output logic [31:0] rdata
);
    wire active=cyc && stb && rst_n;
    wire [4:0] hit={
        addr[31:4]==28'h4000010,            // GPIO    0x40000100..0x4000010f
        addr[31:6]==26'h1000000,            // MBIST   0x40000000..0x4000003f
        (addr >> BANK_AW)==(32'h00020000 >> BANK_AW),
        addr[31:14]==18'h00004,             // scratch 0x00010000..0x00013fff
        addr[31:14]==18'h00000              // ROM     0x00000000..0x00003fff
    };
    wire enabled;
    generate if (WAIT_CYCLES==0) begin : no_wait
        assign enabled=active;
    end else begin : with_wait
        localparam W=$clog2(WAIT_CYCLES+1);
        reg [W-1:0] elapsed;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) elapsed<=0;
            else if (!active || ack || err) elapsed<=0;
            else if (elapsed<W'(WAIT_CYCLES)) elapsed<=elapsed+1'b1;
        end
        assign enabled=active && elapsed==W'(WAIT_CYCLES);
    end endgenerate
    assign {gpio_req,mbist_req,bank_req,ram_req,rom_req}=hit & {5{enabled}};
    assign ack=enabled && |(hit & slave_ack);
    assign err=enabled && ((hit==0) || |(hit & slave_err));
    always @* begin
        case (hit)
            5'b00001:rdata=rom_data;
            5'b00010:rdata=ram_data;
            5'b00100:rdata=bank_data;
            5'b01000:rdata=mbist_data;
            5'b10000:rdata=gpio_data;
            default:rdata=0;
        endcase
    end
endmodule
