// Integrated top. Set FAULT_MODEL=1 only for simulation fault campaigns.
// BANK_AW=8 selects 256 bytes. The reference regression uses BANK_AW=6.
module soc_top #(
    parameter ROM_FILE="firmware/mbist_demo.hex",
    parameter [31:0] RESET_ADDR=0,
    parameter integer BANK_AW=8, BUS_WAIT=0, FAULT_MODEL=0
)(
    input wire clk,rst_n, input wire [7:0] gpio_in,
    output wire [7:0] gpio_out,gpio_oe,
    input wire fault_en, input wire [3:0] fault_type,
    input wire [BANK_AW-1:0] fault_addr,fault_victim_addr,fault_alias_addr,
    input wire [3:0] fault_bit,fault_victim_bit,
    output wire mbist_busy,mbist_done,mbist_pass,mbist_fail
);
    wire [31:0] iaddr,idata,addr,wdata,rdata;
    wire iferr,cyc,stb,we,ack,err;
    wire [3:0] sel;
    wire irq, trap_event;
    wire [31:0] trap_cause;
    rv32_pipeline #(.RESET_ADDR(RESET_ADDR)) cpu (
        .clk(clk),.rst_n(rst_n),.external_irq(irq),.imem_addr(iaddr),
        .imem_data(idata),.imem_ready(1'b1),.imem_err(iferr),
        .wb_cyc(cyc),.wb_stb(stb),.wb_we(we),.wb_sel(sel),.wb_addr(addr),
        .wb_wdata(wdata),.wb_rdata(rdata),.wb_ack(ack),.wb_err(err),
        .trap_event(trap_event),.trap_cause(trap_cause)
    );

    wire rom_req,ram_req,bank_req,reg_req,gpio_req;
    wire rom_ack,rom_err,ram_ack,bank_ack,bank_err,reg_ack,reg_err,gpio_ack,gpio_err;
    wire [31:0] rom_rdata,ram_rdata,bank_rdata,reg_rdata,gpio_rdata;
    wb_interconnect #(.BANK_AW(BANK_AW),.WAIT_CYCLES(BUS_WAIT)) bus(
        .clk(clk),.rst_n(rst_n),.cyc(cyc),.stb(stb),.addr(addr),
        .rom_req(rom_req),.ram_req(ram_req),.bank_req(bank_req),.mbist_req(reg_req),.gpio_req(gpio_req),
        .slave_ack({gpio_ack,reg_ack,bank_ack,ram_ack,rom_ack}),
        .slave_err({gpio_err,reg_err,bank_err,1'b0,rom_err}),.ack(ack),.err(err),
        .rom_data(rom_rdata),.ram_data(ram_rdata),.bank_data(bank_rdata),.mbist_data(reg_rdata),
        .gpio_data(gpio_rdata),.rdata(rdata)
    );
    boot_rom #(.INIT_FILE(ROM_FILE)) rom(.fetch_addr(iaddr),.insn(idata),.fetch_err(iferr),
        .data_req(rom_req),.data_we(we),.data_addr(addr),.data_ack(rom_ack),.data_err(rom_err),.data_rdata(rom_rdata));
    scratch_ram scratch(.clk(clk),.req(ram_req),.we(we),.addr(addr),.wdata(wdata),
        .sel(sel),.rdata(ram_rdata),.ack(ram_ack));
    wb_gpio gpio(.clk(clk),.rst_n(rst_n),.req(gpio_req),.we(we),.addr(addr[3:0]),.sel(sel),
        .wdata(wdata),.rdata(gpio_rdata),.ack(gpio_ack),.err(gpio_err),
        .gpio_in(gpio_in),.gpio_out(gpio_out),.gpio_oe(gpio_oe));

    wire start,owned,raw_done,raw_pass,raw_fail,raw_busy,stop_on_fail;
    wire [2:0] algo_sel,pattern_sel;
    wire [BANK_AW-1:0] limit,first_addr,func_addr;
    wire [15:0] fail_count;
    wire [7:0] actual,expected,bitmask,signature,func_din,func_dout;
    wire [3:0] first_step;
    wire func_ce_n,func_we_n;
    wb_byte_bank #(.AW(BANK_AW)) bank_window(.clk(clk),.rst_n(rst_n),.req(bank_req),
        .we(we),.bist_owned(owned),.addr(addr),.wdata(wdata),.sel(sel),.rdata(bank_rdata),
        .ack(bank_ack),.err(bank_err),.func_ce_n(func_ce_n),.func_we_n(func_we_n),
        .func_addr(func_addr),.func_din(func_din),.func_dout(func_dout));
    wb_mbist_regs #(.AW(BANK_AW)) regs(.clk(clk),.rst_n(rst_n),.req(reg_req),.we(we),
        .addr(addr[5:0]),.sel(sel),.wdata(wdata),.rdata(reg_rdata),.ack(reg_ack),.err(reg_err),
        .bist_owned(owned),.bist_start(start),.algo_sel(algo_sel),.pattern_sel(pattern_sel),
        .stop_on_fail(stop_on_fail),.max_addr(limit),.irq(irq),
        .bist_done(raw_done),.bist_pass(raw_pass),.bist_fail(raw_fail),.fail_count(fail_count),
        .first_addr(first_addr),.first_expected(expected),.first_actual(actual),
        .first_mask(bitmask),.first_step(first_step),.signature(signature),
        .status_pass(mbist_pass),.status_fail(mbist_fail)
    );
    assign mbist_busy=owned;
    assign mbist_done=irq;
    mbist_top #(.ADDR_WIDTH(BANK_AW),.DATA_WIDTH(8),.MEM_DEPTH(1<<BANK_AW),.FAULT_MODEL(FAULT_MODEL))
    mbist(.clk(clk),.rst_n(rst_n),.bist_mode(owned),.bist_start(start),.algo_sel(algo_sel),
        .pattern_sel(pattern_sel),.max_addr(limit),.stop_on_fail(stop_on_fail),
        .func_ce_n(func_ce_n),.func_we_n(func_we_n),.func_addr(func_addr),.func_din(func_din),.func_dout(func_dout),
        .bist_busy(raw_busy),.bist_done(raw_done),.bist_pass(raw_pass),.bist_fail(raw_fail),
        .diag_fail_count(fail_count),.diag_first_fail_addr(first_addr),.diag_first_fail_data_actual(actual),
        .diag_first_fail_data_exp(expected),.diag_first_fail_bitmask(bitmask),.diag_first_fail_step(first_step),
        .misr_signature(signature),.fault_inject_en(fault_en),.fault_type(fault_type),.fault_addr(fault_addr),
        .fault_bit(fault_bit),.fault_victim_addr(fault_victim_addr),.fault_victim_bit(fault_victim_bit),
        .fault_alias_addr(fault_alias_addr));
endmodule
