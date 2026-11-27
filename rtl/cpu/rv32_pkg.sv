package rv32_pkg;
    typedef enum logic [3:0] {
        ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
        ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR, ALU_AND
    } alu_fn_t;
    typedef struct packed {
        logic legal, use_rs1, use_rs2, write_rd;
        logic immediate, pc_operand, zero_operand;
        logic branch_op, jal, jalr, load_op, store_op;
        logic csr_op, csr_imm, mret, ecall, ebreak_op;
        logic [2:0] funct3;
        alu_fn_t alu_fn;
        logic [31:0] imm;
    } uop_t;
endpackage
