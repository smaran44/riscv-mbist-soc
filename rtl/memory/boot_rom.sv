// Harvard instruction port and a second read-only data port for constants.
module boot_rom #(parameter INIT_FILE="firmware/mbist_demo.hex", parameter WORDS=4096)(
    input wire [31:0] fetch_addr, output wire [31:0] insn, output wire fetch_err,
    input wire data_req, data_we, input wire [31:0] data_addr,
    output wire data_ack,data_err, output wire [31:0] data_rdata
);
    localparam AW=$clog2(WORDS);
    reg [31:0] mem [0:WORDS-1];
    integer i;
    initial begin
        for(i=0;i<WORDS;i=i+1) mem[i]=32'h00000013;
        if (INIT_FILE!="") $readmemh(INIT_FILE,mem);
    end
    assign fetch_err=fetch_addr>=WORDS*4;
    assign insn=fetch_err ? 32'b0 : mem[fetch_addr[AW+1:2]];
    assign data_rdata=mem[data_addr[AW+1:2]];
    assign data_ack=data_req && !data_we;
    assign data_err=data_req && data_we;
endmodule
