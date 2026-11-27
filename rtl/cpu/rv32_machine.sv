// Single-hart machine-mode CSR bank. mtvec supports direct mode, and the
// single machine-external pending bit follows the peripheral interrupt line.
module rv32_machine (
    input wire clk, rst_n, external_irq,
    input wire [11:0] csr_addr, input wire csr_commit, input wire [31:0] csr_wdata,
    output logic [31:0] csr_rdata, output logic csr_exists, csr_readonly,
    input wire take_trap, take_mret, input wire [31:0] trap_pc, cause, trap_value,
    output logic [31:0] mtvec, mepc, output wire irq_enabled
);
    logic mie_global, previous_mie, meie;
    logic [31:0] mscratch, mcause, mtval;
    assign irq_enabled = mie_global && meie && external_irq;
    always @* begin
        csr_exists=1; csr_readonly=0; csr_rdata=0;
        case (csr_addr)
            12'h300: csr_rdata=32'h1800 | ({31'b0,previous_mie} << 7) | ({31'b0,mie_global} << 3);
            12'h301: csr_rdata=32'h40000100; // RV32, extension I. Fixed WARL value.
            12'h304: csr_rdata={20'b0,meie,11'b0};
            12'h305: csr_rdata=mtvec;
            12'h340: csr_rdata=mscratch;
            12'h341: csr_rdata=mepc;
            12'h342: csr_rdata=mcause;
            12'h343: csr_rdata=mtval;
            12'h344: csr_rdata={20'b0,external_irq,11'b0};
            12'hf11,12'hf12,12'hf13,12'hf14: csr_readonly=1;
            default: csr_exists=0;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtvec<=0; mepc<=0; mcause<=0; mtval<=0; mscratch<=0;
            mie_global<=0; previous_mie<=0; meie<=0;
        end else if (take_trap) begin
            mepc<={trap_pc[31:2],2'b0}; mcause<=cause; mtval<=trap_value;
            previous_mie<=mie_global; mie_global<=0;
        end else if (take_mret) begin
            mie_global<=previous_mie; previous_mie<=1;
        end else if (csr_commit) begin
            case (csr_addr)
                12'h300: begin mie_global<=csr_wdata[3]; previous_mie<=csr_wdata[7]; end
                12'h304: meie<=csr_wdata[11];
                12'h305: mtvec<={csr_wdata[31:2],2'b0};
                12'h340: mscratch<=csr_wdata;
                12'h341: mepc<={csr_wdata[31:2],2'b0};
                12'h342: mcause<=csr_wdata;
                12'h343: mtval<=csr_wdata;
                default: ;
            endcase
        end
    end
endmodule
