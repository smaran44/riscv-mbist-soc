// Standalone entry with the original CPU's two pins and Harvard baseline
// address map. In this wrapper the first data word is RAM initialized to zero.
module Pipeline_top #(parameter ROM_FILE="firmware/original.hex",parameter [31:0] RESET_ADDR=0)
    (input wire clk,rst);
    wire [31:0] ia,insn,addr,wd,rd; wire [3:0] sel;
    wire cyc,stb,we,ack,iferr;
    boot_rom #(.INIT_FILE(ROM_FILE)) rom(.fetch_addr(ia),.insn(insn),.fetch_err(iferr),
        .data_req(1'b0),.data_we(1'b0),.data_addr(32'b0),.data_ack(),.data_err(),.data_rdata());
    wire valid_addr=addr<32'h4000;
    scratch_ram #(.INIT_WORD0(1)) ram(.clk(clk),.req(cyc && stb && valid_addr),.we(we),.addr(addr),
        .wdata(wd),.sel(sel),.rdata(rd),.ack(ack));
    rv32_pipeline #(.RESET_ADDR(RESET_ADDR)) cpu(.clk(clk),.rst_n(rst),.external_irq(1'b0),
        .imem_addr(ia),.imem_data(insn),.imem_ready(1'b1),.imem_err(iferr),
        .wb_cyc(cyc),.wb_stb(stb),.wb_we(we),.wb_sel(sel),.wb_addr(addr),.wb_wdata(wd),
        .wb_rdata(rd),.wb_ack(ack),.wb_err(cyc && stb && !valid_addr),.trap_event(),.trap_cause());
endmodule
