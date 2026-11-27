`timescale 1ns/1ps
module tb_cpu;
    reg clk=0,rst_n=0;always #5 clk=~clk;
    wire [7:0] leds;
    soc_top #(.BANK_AW(6),.BUS_WAIT(3),.ROM_FILE("firmware/cpu_checks.hex"),
              .RESET_ADDR(32'h100),.FAULT_MODEL(1)) dut(
        .clk(clk),.rst_n(rst_n),.gpio_in(8'b0),.gpio_out(leds),.gpio_oe(),
        .fault_en(1'b1),.fault_type(4'd1),.fault_addr(6'h1f),.fault_bit(4'd4),
        .fault_victim_addr(6'b0),.fault_victim_bit(4'b0),.fault_alias_addr(6'b0),
        .mbist_busy(),.mbist_done(),.mbist_pass(),.mbist_fail());
    reg [39:0] isa_seen=0;
    reg [5:0] csr_seen=0;
    integer traps=0,returns=0,starts=0,stalls=0,busy_bank_errors=0;
    reg held=0;
    reg [68:0] last_payload;
    wire [68:0] bus_payload={dut.we,dut.sel,dut.addr,dut.wdata};
    wire [31:0] insn=dut.cpu.m.insn;
    wire [2:0] f=insn[14:12];
    integer index;
    always @(posedge clk) if(rst_n) begin
        if(held && (!dut.cyc || !dut.stb || bus_payload!==last_payload))
            $fatal(1,"Wishbone changed while waiting");
        held=dut.cyc && dut.stb && !dut.ack && !dut.err;
        last_payload=bus_payload;
        if(dut.trap_event) traps=traps+1;
        if(dut.cpu.returning) returns=returns+1;
        if(dut.start) starts=starts+1;
        if(dut.cpu.load_hazard && !dut.cpu.wait_mem) stalls=stalls+1;
        if(dut.bank_err && dut.owned) begin
            busy_bank_errors=busy_bank_errors+1;
            if(!dut.func_ce_n) $fatal(1,"Blocked request reached SRAM");
        end
        if(dut.cpu.m.valid && !dut.cpu.wait_mem) begin
            index=-1;
            case(insn[6:0])
                7'h33: index=insn[30] && f==0 ? 8 : insn[30] && f==5 ? 9 : int'(f);
                7'h13: index=insn[30] && f==5 ? 18 : 10+int'(f);
                7'h37: index=19;
                7'h17: index=20;
                7'h6f: index=21;
                7'h67: index=22;
                7'h63: index=(f<2 ? 23+int'(f) : 21+int'(f));
                7'h03: index=(f<3 ? 29+int'(f) : 28+int'(f));
                7'h23: index=34+int'(f);
                7'h0f: index=37;
                7'h73: begin
                    if(insn==32'h00000073) index=38;
                    if(insn==32'h00100073) index=39;
                    if(f[1:0]!=0 && !dut.cpu.sync_fault)
                        csr_seen[(f[2] ? 3 : 0)+int'(f[1:0])-1]=1;
                end
                default: ;
            endcase
            if(index>=0 && index<40) isa_seen[index]=1;
        end
    end
    initial begin
        repeat(5) @(negedge clk);
        if(dut.iaddr!==32'h100) $fatal(1,"Wrong reset PC");
        rst_n=1;
        repeat(20000) begin
            @(negedge clk);
            if(leds==15) $fatal(1,"Firmware group %d failed after %d traps, cause=%h mepc=%h mtval=%h",
                dut.scratch.mem[2],dut.scratch.mem[3],dut.scratch.mem[4],dut.scratch.mem[5],dut.scratch.mem[6]);
            if(leds==4) begin
                if(dut.scratch.mem[0]!==32'h600dcafe || dut.scratch.mem[1]!==20 ||
                   traps!=20 || returns!=20 || starts!=2 || busy_bank_errors!=2 || stalls==0 ||
                   isa_seen!==40'hffffffffff || csr_seen!==6'h3f)
                    $fatal(1,"Coverage/architectural mismatch ISA=%h CSR=%h traps=%0d MRET=%0d starts=%0d busy bank errors=%0d",
                        isa_seen,csr_seen,traps,returns,starts,busy_bank_errors);
                $display("PASS tb_cpu: 40 RV32I mnemonic bins, six Zicsr operations, 20 precise trap returns, %0d load-use bubbles, busy-bank ERR, early stop and checkerboard",stalls);
                $finish;
            end
        end
        $fatal(1,"CPU watchdog fetch=%h pc=%h exception=%h",dut.iaddr,dut.cpu.m.pc,dut.trap_cause);
    end
endmodule
