module rv32_pipeline import rv32_pkg::*; #(
    parameter [31:0] RESET_ADDR = 32'h0000_0000
)(
    input wire clk, rst_n, external_irq,
    output wire [31:0] imem_addr, input wire [31:0] imem_data,
    input wire imem_ready, imem_err,
    output wire wb_cyc, wb_stb, wb_we, output wire [3:0] wb_sel,
    output wire [31:0] wb_addr, wb_wdata, input wire [31:0] wb_rdata,
    input wire wb_ack, wb_err,
    output wire trap_event, output wire [31:0] trap_cause
);
    // IF and ID. A redirect invalidates the two younger instructions.
    logic [31:0] fetch_pc, d_pc, d_insn;
    wire [31:0] fetch_pc4;
    logic d_valid, d_fetch_error;
    assign imem_addr=fetch_pc;
    PC_Adder pc_increment(.a(fetch_pc),.b(32'd4),.c(fetch_pc4));

    uop_t decoded, x_ctl;
    rv32_decode decode(.insn(d_insn),.uop(decoded));
    logic x_valid, x_fetch_error;
    logic [31:0] x_pc, x_insn, x_raw_a, x_raw_b;

    typedef struct packed {
        logic valid, write_rd, load_op, store_op, csr_op, csr_write, mret, fault;
        logic [2:0] f3;
        logic [4:0] rd;
        logic [11:0] csr_addr;
        logic [31:0] pc, next_pc, insn, result, store_value, csr_operand;
        logic [31:0] cause, tval;
    } mem_stage_t;
    mem_stage_t m, x_to_m;
    logic w_write;
    logic [4:0] w_rd;
    logic [31:0] w_data;
    wire [31:0] decode_a,decode_b;
    Register_File registers(.clk(clk),.rst(rst_n),.WE3(w_write),.WD3(w_data),
        .A1(d_insn[19:15]),.A2(d_insn[24:20]),.A3(w_rd),.RD1(decode_a),.RD2(decode_b));

    // MEM supplies one in-order Wishbone transaction. Lower address bits remain
    // byte-valued. SEL and write data are positioned in the physical word lanes.
    wire data_access = m.valid && !m.fault && (m.load_op || m.store_op);
    wire wait_mem = data_access && !(wb_ack || wb_err);
    assign wb_cyc=data_access && rst_n;
    assign wb_stb=wb_cyc;
    assign wb_we=m.store_op;
    assign wb_addr=m.result;
    wire [3:0] base_mask = (m.f3[1:0]==0) ? 4'b0001 :
                           (m.f3[1:0]==1) ? 4'b0011 : 4'b1111;
    assign wb_sel=base_mask << wb_addr[1:0];
    assign wb_wdata=m.store_value << {wb_addr[1:0],3'b000};
    wire [31:0] shifted_load = wb_rdata >> {wb_addr[1:0],3'b000};
    logic [31:0] load_value;
    always @* begin
        case (m.f3)
            0: load_value={{24{shifted_load[7]}},shifted_load[7:0]};
            1: load_value={{16{shifted_load[15]}},shifted_load[15:0]};
            4: load_value={24'b0,shifted_load[7:0]};
            5: load_value={16'b0,shifted_load[15:0]};
            default: load_value=shifted_load;
        endcase
    end

    wire [31:0] csr_old, mtvec, mepc;
    wire csr_exists, csr_readonly, irq_enabled;
    wire csr_bad=m.csr_op && (!csr_exists || (m.csr_write && csr_readonly));
    wire data_fault=data_access && wb_err;
    wire sync_fault=m.valid && (m.fault || csr_bad || data_fault);
    wire returning=m.valid && m.mret && !sync_fault;
    // Interrupt after the oldest instruction completes. Its resolved successor
    // is the exact resume PC even when that instruction took a branch.
    wire irq_taken=m.valid && !wait_mem && !sync_fault && !m.mret && !m.csr_op && irq_enabled;
    assign trap_event=sync_fault || irq_taken;
    assign trap_cause=irq_taken ? 32'h8000000b : m.fault ? m.cause :
                      csr_bad ? 32'd2 : (m.store_op ? 32'd7 : 32'd5);
    wire [31:0] fault_value=irq_taken ? 0 : m.fault ? m.tval : csr_bad ? m.insn : m.result;
    wire [31:0] csr_new=(m.f3[1:0]==1) ? m.csr_operand :
                        (m.f3[1:0]==2) ? csr_old | m.csr_operand : csr_old & ~m.csr_operand;
    rv32_machine csr(.clk(clk),.rst_n(rst_n),.external_irq(external_irq),
        .csr_addr(m.csr_addr),.csr_commit(m.valid && m.csr_op && m.csr_write && !sync_fault),
        .csr_wdata(csr_new),.csr_rdata(csr_old),.csr_exists(csr_exists),.csr_readonly(csr_readonly),
        .take_trap(trap_event),.take_mret(returning),.trap_pc(irq_taken ? m.next_pc : m.pc),
        .cause(trap_cause),.trap_value(fault_value),.mtvec(mtvec),.mepc(mepc),.irq_enabled(irq_enabled));

    wire [31:0] m_value=m.csr_op ? csr_old : m.load_op ? load_value : m.result;
    wire [1:0] forward_a, forward_b;
    wire [31:0] x_a,x_b;
    hazard_unit bypass(.rst(rst_n),.RegWriteM(m.valid && m.write_rd && !wait_mem && !sync_fault),
        .RegWriteW(w_write),.RD_M(m.rd),.RD_W(w_rd),.Rs1_E(x_insn[19:15]),.Rs2_E(x_insn[24:20]),
        .ForwardAE(forward_a),.ForwardBE(forward_b));
    Mux_3_by_1 mux_a(.a(x_raw_a),.b(w_data),.c(m_value),.s(forward_a),.d(x_a));
    Mux_3_by_1 mux_b(.a(x_raw_b),.b(w_data),.c(m_value),.s(forward_b),.d(x_b));

    wire [31:0] lhs=x_ctl.pc_operand ? x_pc : x_ctl.zero_operand ? 0 : x_a;
    wire [31:0] rhs=x_ctl.immediate ? x_ctl.imm : x_b;
    wire [31:0] alu_result;
    rv32_alu alu(.fn(x_ctl.alu_fn),.a(lhs),.b(rhs),.result(alu_result));
    logic branch_matches;
    always @* begin
        case (x_ctl.funct3)
            0: branch_matches=(x_a==x_b);
            1: branch_matches=(x_a!=x_b);
            4: branch_matches=($signed(x_a)<$signed(x_b));
            5: branch_matches=($signed(x_a)>=$signed(x_b));
            6: branch_matches=(x_a<x_b);
            7: branch_matches=(x_a>=x_b);
            default: branch_matches=0;
        endcase
    end
    wire x_redirect=x_valid && x_ctl.legal &&
        (x_ctl.jal || x_ctl.jalr || (x_ctl.branch_op && branch_matches));
    wire [31:0] x_target=x_ctl.jalr ? (x_a+x_ctl.imm) & 32'hffff_fffe : x_pc+x_ctl.imm;
    wire unaligned_data=(x_ctl.funct3[1:0]==1 && alu_result[0]) ||
                        (x_ctl.funct3[1:0]==2 && |alu_result[1:0]);
    wire load_hazard=x_valid && x_ctl.load_op && x_insn[11:7]!=0 && d_valid &&
        ((decoded.use_rs1 && d_insn[19:15]==x_insn[11:7]) ||
         (decoded.use_rs2 && d_insn[24:20]==x_insn[11:7]));

    always @* begin
        x_to_m='0;
        x_to_m.valid=x_valid; x_to_m.pc=x_pc; x_to_m.insn=x_insn;
        x_to_m.next_pc=x_redirect ? x_target : x_pc+4;
        x_to_m.rd=x_insn[11:7]; x_to_m.write_rd=x_ctl.write_rd;
        x_to_m.f3=x_ctl.funct3; x_to_m.load_op=x_ctl.load_op; x_to_m.store_op=x_ctl.store_op;
        x_to_m.result=(x_ctl.jal || x_ctl.jalr) ? x_pc+4 : alu_result;
        x_to_m.store_value=x_b; x_to_m.mret=x_ctl.mret;
        x_to_m.csr_op=x_ctl.csr_op; x_to_m.csr_addr=x_insn[31:20];
        x_to_m.csr_operand=x_ctl.csr_imm ? {27'b0,x_insn[19:15]} : x_a;
        x_to_m.csr_write=(x_ctl.funct3[1:0]==1 || x_insn[19:15]!=0);
        x_to_m.fault=1;
        if (|x_pc[1:0]) begin x_to_m.cause=0; x_to_m.tval=x_pc; end
        else if (x_fetch_error) begin x_to_m.cause=1; x_to_m.tval=x_pc; end
        else if (!x_ctl.legal) begin x_to_m.cause=2; x_to_m.tval=x_insn; end
        else if (x_ctl.ebreak_op) begin x_to_m.cause=3; x_to_m.tval=x_pc; end
        else if (x_ctl.ecall) x_to_m.cause=11;
        else if (x_redirect && |x_target[1:0]) begin x_to_m.cause=0; x_to_m.tval=x_target; end
        else if ((x_ctl.load_op || x_ctl.store_op) && unaligned_data) begin
            x_to_m.cause=x_ctl.store_op ? 6 : 4; x_to_m.tval=alu_result;
        end else x_to_m.fault=0;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_pc<=RESET_ADDR; d_valid<=0; x_valid<=0; m<='0; w_write<=0;
            d_pc<=0; d_insn<=0; d_fetch_error<=0; x_ctl<='0; x_pc<=0; x_insn<=0;
            x_fetch_error<=0; x_raw_a<=0; x_raw_b<=0; w_rd<=0; w_data<=0;
        end else begin
            w_write<=m.valid && m.write_rd && !wait_mem && !sync_fault;
            if (!wait_mem) begin w_rd<=m.rd; w_data<=m_value; end
            if (trap_event || returning) begin
                fetch_pc<=returning ? mepc : mtvec;
                m.valid<=0; x_valid<=0; d_valid<=0;
            end else if (wait_mem) begin
                // WB may retire during a stall. Preserve its forwarded operands.
                x_raw_a<=x_a; x_raw_b<=x_b;
            end else begin
                m<=x_to_m;
                if (x_redirect) begin
                    fetch_pc<=x_target; d_valid<=0; x_valid<=0;
                end else if (load_hazard) begin
                    x_valid<=0;
                end else begin
                    x_valid<=d_valid; x_pc<=d_pc; x_ctl<=decoded; x_insn<=d_insn;
                    x_fetch_error<=d_fetch_error; x_raw_a<=decode_a; x_raw_b<=decode_b;
                    d_valid<=imem_ready;
                    if (imem_ready) begin
                        d_pc<=fetch_pc; d_insn<=imem_data; d_fetch_error<=imem_err; fetch_pc<=fetch_pc4;
                    end
                end
            end
        end
    end
endmodule
