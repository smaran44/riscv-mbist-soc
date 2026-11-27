`timescale 1ns/1ps
module tb_legacy;
    reg clk=0,rst=0; always #5 clk=~clk;
    Pipeline_top dut(.clk(clk),.rst(rst));
    initial begin
        repeat(4) @(negedge clk);rst=1;
        repeat(24) @(negedge clk);
        if(dut.cpu.registers.Register[7]!==8 || dut.cpu.registers.Register[10]!==1)
            $fatal(1,"Original six-instruction signature failed");
        $display("PASS tb_legacy: original program x7=8 x10=1");
        $finish;
    end
endmodule
