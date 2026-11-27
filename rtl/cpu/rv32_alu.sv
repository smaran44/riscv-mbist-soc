module rv32_alu import rv32_pkg::*; (
    input alu_fn_t fn, input logic [31:0] a, b, output logic [31:0] result
);
    always @* begin
        case (fn)
            ALU_ADD:  result=a+b;
            ALU_SUB:  result=a-b;
            ALU_SLL:  result=a << b[4:0];
            ALU_SLT:  result={31'b0,$signed(a)<$signed(b)};
            ALU_SLTU: result={31'b0,a<b};
            ALU_XOR:  result=a^b;
            ALU_SRL:  result=a >> b[4:0];
            ALU_SRA:  result=$signed(a) >>> b[4:0];
            ALU_OR:   result=a|b;
            ALU_AND:  result=a&b;
            default:  result=0;
        endcase
    end
endmodule
