// Board-neutral single-clock top. Expose GPIO as bidirectional pins. Connect
// useful board pins and add clock/I/O constraints for the selected FPGA.
module fpga_top #(parameter ROM_FILE="firmware/mbist_demo.hex")(
    input wire clk, reset_n, inout wire [7:0] gpio,
    output wire test_busy,test_done,test_pass,test_fail
);
    (* ASYNC_REG="TRUE" *) reg [1:0] release_sync;
    always @(posedge clk or negedge reset_n)
        if (!reset_n) release_sync<=0;
        else release_sync<={release_sync[0],1'b1};
    wire [7:0] gpio_o,oe;
    genvar i;
    for (i=0;i<8;i=i+1) assign gpio[i]=oe[i] ? gpio_o[i] : 1'bz;
    soc_top #(.ROM_FILE(ROM_FILE),.FAULT_MODEL(0)) soc(
        .clk(clk),.rst_n(release_sync[1]),.gpio_in(gpio),.gpio_out(gpio_o),.gpio_oe(oe),
        .fault_en(1'b0),.fault_type(4'b0),.fault_addr(8'b0),.fault_bit(4'b0),
        .fault_victim_addr(8'b0),.fault_victim_bit(4'b0),.fault_alias_addr(8'b0),
        .mbist_busy(test_busy),.mbist_done(test_done),.mbist_pass(test_pass),.mbist_fail(test_fail));
endmodule
