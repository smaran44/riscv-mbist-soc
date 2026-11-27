module rv32_decode import rv32_pkg::*; (
    input  logic [31:0] insn,
    output uop_t uop
);
    wire [6:0] opcode = insn[6:0];
    wire [2:0] f3 = insn[14:12];
    wire [6:0] f7 = insn[31:25];
    wire [31:0] imm_i = {{20{insn[31]}},insn[31:20]};
    wire [31:0] imm_s = {{20{insn[31]}},insn[31:25],insn[11:7]};
    wire [31:0] imm_b = {{19{insn[31]}},insn[31],insn[7],insn[30:25],insn[11:8],1'b0};
    wire [31:0] imm_u = {insn[31:12],12'b0};
    wire [31:0] imm_j = {{11{insn[31]}},insn[31],insn[19:12],insn[20],insn[30:21],1'b0};

    always @* begin
        uop = '0;
        uop.alu_fn = ALU_ADD;
        uop.funct3 = f3;
        case (opcode)
            7'b0110111, 7'b0010111: begin // LUI, AUIPC
                uop.legal=1; uop.write_rd=1; uop.immediate=1; uop.imm=imm_u;
                uop.zero_operand=(opcode==7'b0110111);
                uop.pc_operand=(opcode==7'b0010111);
            end
            7'b1101111: begin // JAL
                uop.legal=1; uop.jal=1; uop.imm=imm_j; uop.write_rd=1;
            end
            7'b1100111: begin // JALR
                uop.legal=(f3==0); uop.jalr=1; uop.use_rs1=1;
                uop.write_rd=1; uop.imm=imm_i;
            end
            7'b1100011: begin
                uop.legal=(f3==0 || f3==1 || f3>=4); uop.branch_op=1;
                uop.use_rs1=1; uop.use_rs2=1; uop.imm=imm_b;
            end
            7'b0000011: begin
                uop.legal=(f3==0 || f3==1 || f3==2 || f3==4 || f3==5);
                uop.use_rs1=1; uop.immediate=1; uop.write_rd=1;
                uop.load_op=1; uop.imm=imm_i;
            end
            7'b0100011: begin
                uop.legal=(f3<=2); uop.use_rs1=1; uop.use_rs2=1;
                uop.immediate=1; uop.store_op=1; uop.imm=imm_s;
            end
            7'b0010011, 7'b0110011: begin
                uop.immediate=(opcode==7'b0010011); uop.imm=imm_i;
                uop.legal=uop.immediate || f7==0 || (f7==7'h20 && (f3==0 || f3==5));
                uop.use_rs1=1; uop.use_rs2=!uop.immediate; uop.write_rd=1;
                case (f3)
                    0: if (!uop.immediate && f7==7'h20) uop.alu_fn=ALU_SUB;
                    1: begin uop.alu_fn=ALU_SLL; uop.legal=(f7==0); end
                    2: uop.alu_fn=ALU_SLT;
                    3: uop.alu_fn=ALU_SLTU;
                    4: uop.alu_fn=ALU_XOR;
                    5: begin
                        if (f7==7'h20) uop.alu_fn=ALU_SRA;
                        else uop.alu_fn=ALU_SRL;
                        uop.legal=(f7==0 || f7==7'h20);
                    end
                    6: uop.alu_fn=ALU_OR;
                    7: uop.alu_fn=ALU_AND;
                endcase
            end
            7'b0001111: uop.legal=(f3==0); // FENCE: data bus is strictly ordered.
            7'b1110011: begin
                if (f3==0) begin
                    case (insn)
                        32'h00000073: begin uop.legal=1; uop.ecall=1; end
                        32'h00100073: begin uop.legal=1; uop.ebreak_op=1; end
                        32'h30200073: begin uop.legal=1; uop.mret=1; end
                        default: ;
                    endcase
                end else if (f3[1:0]!=0) begin
                    uop.legal=1; uop.write_rd=1; uop.csr_op=1;
                    uop.csr_imm=f3[2]; uop.use_rs1=!f3[2];
                end
            end
            default: ;
        endcase
    end
endmodule
