`timescale 1ns/1ps
module tb_fpga;
    reg clk=0,reset_n=0;always #5 clk=~clk;
    tri [7:0] gpio;
    // Model board straps on the input pins; observe the pins actually driven.
    assign gpio[7:4]=4'b0;
    wire busy,done,pas,fail_sig;
    fpga_top board(.clk(clk),.reset_n(reset_n),.gpio(gpio),.test_busy(busy),.test_done(done),
        .test_pass(pas),.test_fail(fail_sig));
    reg saw_busy=0;
    initial begin
        repeat(4) @(negedge clk);reset_n=1;
        repeat(16000) begin
            @(negedge clk);
            if(busy) saw_busy=1;
            if(gpio[3:0]===4'hf || fail_sig) $fatal(1,"Physical SRAM path reported FAIL");
            if(gpio[3:0]===4'h4 && done) begin
                if(!saw_busy || !pas || busy || board.soc.signature!==8'h06)
                    $fatal(1,"Board path signature/status mismatch");
                $display("PASS tb_fpga: synchronized reset, inferred 256-byte SRAM, physical GPIO=04, signature=06");
                $finish;
            end
        end
        $fatal(1,"Board watchdog");
    end
endmodule
