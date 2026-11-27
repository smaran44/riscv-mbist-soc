// Port-compatible upgrade of the original Register_File. Register x0 is wired
// to zero. Writeback-to-decode bypass makes same-cycle RAW behavior explicit.
module Register_File(input clk, rst, WE3, input [31:0] WD3,
    input [4:0] A1,A2,A3, output [31:0] RD1,RD2);
    reg [31:0] Register [1:31];
    wire write_enable = rst && WE3 && (A3 != 0);
    always @(posedge clk)
        if (write_enable) Register[A3] <= WD3;
    assign RD1 = !rst || A1==0 ? 0 : (write_enable && A1==A3 ? WD3 : Register[A1]);
    assign RD2 = !rst || A2==0 ? 0 : (write_enable && A2==A3 ? WD3 : Register[A2]);
endmodule
