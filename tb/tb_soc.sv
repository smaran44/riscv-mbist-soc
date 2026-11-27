`timescale 1ns/1ps
module tb_soc #(parameter BANK_AW=6, BUS_WAIT=2);
    localparam DEPTH=1<<BANK_AW;
    reg clk=0, rst_n=0; always #5 clk=~clk;
    reg [7:0] pins=0;
    reg inject=0; reg [3:0] kind=0, bitno=0; reg [BANK_AW-1:0] bad_addr=0;
    wire [7:0] leds,oe; wire busy,done,pas,fail_sig;
    soc_top #(.BANK_AW(BANK_AW),.BUS_WAIT(BUS_WAIT),.FAULT_MODEL(1)) dut(
        .clk(clk),.rst_n(rst_n),.gpio_in(pins),.gpio_out(leds),.gpio_oe(oe),
        .fault_en(inject),.fault_type(kind),.fault_addr(bad_addr),.fault_bit(bitno),
        .fault_victim_addr({BANK_AW{1'b0}}),.fault_victim_bit(4'b0),.fault_alias_addr({BANK_AW{1'b0}}),
        .mbist_busy(busy),.mbist_done(done),.mbist_pass(pas),.mbist_fail(fail_sig));

    integer elem,location,phase,writes,reads,errors,completions,irq_seen,starts,cycles,last_compares;
    reg [7:0] sig_ref,last_signature,expected_read,expected_byte;
    reg should_write;
    reg held;
    reg [68:0] held_bus;
    wire [68:0] bus_payload={dut.we,dut.sel,dut.addr,dut.wdata};
    // This scoreboard derives the entire March C- sequence from the specified
    // algorithm. The address, direction, compare data and signature all come
    // from independent reference state, never from the DUT's internal counter.
    always @(posedge clk) begin
        if (!rst_n) begin
            elem=0; location=0; phase=0; writes=0; reads=0; errors=0;
            completions=0; irq_seen=0; starts=0; cycles=0; held=0; sig_ref=0;
            last_signature=0;last_compares=0;
        end else begin
            cycles=cycles+1;
            if(held && ((!dut.cyc || !dut.stb) || bus_payload!==held_bus))
                $fatal(1,"Bus request changed during wait at %0t",$time);
            held=dut.cyc && dut.stb && !dut.ack && !dut.err; held_bus=bus_payload;
            if(dut.ack && dut.err) $fatal(1,"ACK and ERR together");
            if(dut.err) $fatal(1,"Unexpected bus error at %h",dut.addr);
            if(dut.trap_event) begin
                if(dut.trap_cause!==32'h8000000b) $fatal(1,"Unexpected trap %h PC %h",dut.trap_cause,dut.cpu.m.pc);
                irq_seen=irq_seen+1;
            end
            if(dut.start) begin
                if(!busy || done || pas || fail_sig) $fatal(1,"Stale result on START");
                starts=starts+1;elem=0;location=0;phase=0;writes=0;reads=0;errors=0;sig_ref=0;
            end
            if(busy && (!dut.mbist.mem_ce_n && !dut.mbist.mem_we_n || dut.mbist.compare_en)) begin
                should_write=elem==0 || (elem>=1 && elem<=4 && phase==1);
                case(elem)
                    0,5: expected_byte=0;
                    1,3: expected_byte=(phase==0 ? 8'h00 : 8'hff);
                    2,4: expected_byte=(phase==0 ? 8'hff : 8'h00);
                    default:$fatal(1,"Extra logical operation after E5");
                endcase
                if(dut.mbist.current_step!==elem[3:0] || dut.mbist.mem_addr!==location[BANK_AW-1:0])
                    $fatal(1,"March step/address: expected E%0d %h, got E%0d %h",elem,location,dut.mbist.current_step,dut.mbist.mem_addr);
                if(dut.mbist.bist_din!==expected_byte ||
                    (!dut.mbist.mem_we_n)!==should_write || dut.mbist.compare_en===should_write)
                    $fatal(1,"Wrong March operation at E%0d/%h",elem,location);
                if(should_write) writes=writes+1;
                else begin
                    reads=reads+1; expected_read=expected_byte;
                    if(inject && location==bad_addr) begin
                        if(kind==1) expected_read[bitno]=0;
                        if(kind==2) expected_read[bitno]=1;
                    end
                    if(dut.mbist.bist_dout!==expected_read ||
                       dut.mbist.error_bitmap!==(expected_byte^expected_read) ||
                       dut.mbist.mismatch!==(expected_byte!=expected_read))
                        $fatal(1,"Read/compare error E%0d addr=%0h",elem,location);
                    if(expected_byte!=expected_read) errors=errors+1;
                    sig_ref={sig_ref[6:0],sig_ref[7]^sig_ref[5]^sig_ref[4]^sig_ref[3]} ^ expected_read;
                end
                if(elem>=1 && elem<=4 && phase==0) phase=1;
                else begin
                    phase=0;
                    if((elem==3 || elem==4) ? location==0 : location==DEPTH-1) begin
                        elem=elem+1; location=(elem==3 || elem==4) ? DEPTH-1 : 0;
                    end else if(elem==3 || elem==4) location=location-1;
                    else location=location+1;
                end
            end
            if(busy && !dut.func_ce_n) $fatal(1,"Functional SRAM port enabled during MBIST");
            if(dut.raw_done) begin
                if(elem!=6 || reads!=5*DEPTH || writes!=5*DEPTH ||
                   dut.fail_count!==errors[15:0] || dut.signature!==sig_ref ||
                   dut.raw_pass!==(errors==0) || dut.raw_fail!==(errors!=0))
                    $fatal(1,"Bad completion E=%0d R=%0d W=%0d mismatches=%0d",elem,reads,writes,errors);
                completions=completions+1;last_signature=sig_ref;last_compares=reads;
            end
        end
    end
    task automatic check_record(input integer seqnum, input [31:0] status,first,bytes,detail,count,
                                input integer irqmode,input integer expected_irqs);
        integer timeout,base;
        begin
            timeout=0;
            while(dut.scratch.mem[0]!==seqnum && timeout<DEPTH*60+1500) begin
                @(negedge clk);timeout=timeout+1;
            end
            if(timeout>=DEPTH*60+1500) $fatal(1,"Firmware timeout seq=%0d fetch=%h leds=%h",seqnum,dut.iaddr,leds);
            base=16+8*((seqnum-1)%8);
            if(dut.scratch.mem[1]!==1 || oe!==8'h0f || leds!==status[3:2]*4 ||
               starts!=seqnum || completions!=seqnum || irq_seen!=expected_irqs ||
               dut.scratch.mem[3]!==expected_irqs ||
               dut.scratch.mem[base]!==status || dut.scratch.mem[base+1]!==first ||
               dut.scratch.mem[base+2]!==bytes || dut.scratch.mem[base+3]!==detail ||
               dut.scratch.mem[base+4]!==count || dut.scratch.mem[base+5]!=={24'b0,last_signature} ||
               dut.scratch.mem[base+6]!==irqmode || dut.scratch.mem[base+7]!==seqnum ||
               busy!==0 || done!==!irqmode || pas!==(count==0) || fail_sig!==(count!=0))
                $fatal(1,"Firmware result seq=%0d status=%h addr=%h data=%h detail=%h count=%0d GPIO=%h IRQ=%0d",
                    seqnum,dut.scratch.mem[base],dut.scratch.mem[base+1],dut.scratch.mem[base+2],
                    dut.scratch.mem[base+3],dut.scratch.mem[base+4],leds,irq_seen);
            $display("RUN %0d  irq_mode=%0d  status=%02h addr=%02h expected/actual=%04h step/mask=%04h count=%0d sig=%02h gpio=%02h comparisons=%0d",
               seqnum,irqmode,status[7:0],first[7:0],bytes[15:0],detail[15:0],count,last_signature,leds,last_compares);
        end
    endtask
    task automatic retrigger(input [3:0] ft, input [BANK_AW-1:0] fa,input [3:0] bit_index,input irqmode);
        begin
            repeat(40+BUS_WAIT*10) @(negedge clk);
            inject=(ft!=0); kind=ft;bad_addr=fa;bitno=bit_index;pins[6]=irqmode;
            repeat(5) @(negedge clk);
            pins[7]=1;
            while(!busy) @(negedge clk);
            pins[7]=0;
        end
    endtask
    initial begin
        if($test$plusargs("vcd")) begin
            $dumpfile("build/mbist_soc.vcd");
            $dumpvars(1,tb_soc);$dumpvars(1,dut);$dumpvars(1,dut.mbist);
            $dumpvars(1,dut.regs);$dumpvars(1,dut.cpu.csr);
        end
        repeat(5) @(negedge clk);rst_n=1;
        check_record(1,6,0,0,0,0,0,0);
        if(BANK_AW==6 && last_signature!==8'h13) $fatal(1,"Wrong golden signature");
        retrigger(1,'h1f,4,1);
        check_record(2,10,'h1f,'hffef,'h210,2,1,1);
        retrigger(0,0,0,1);
        check_record(3,6,0,0,0,0,1,2);
        retrigger(2,'h2b,2,0);
        check_record(4,10,'h2b,'h0004,'h104,3,0,2);
        retrigger(1,'h1f,4,0);
        repeat(40) @(negedge clk);
        rst_n=0;inject=0;pins=0;
        repeat(5) @(negedge clk);
        if(busy || done || pas || fail_sig) $fatal(1,"Reset did not cancel test");
        rst_n=1;
        check_record(1,6,0,0,0,0,0,0);
        $display("PASS tb_soc BANK_AW=%0d BUS_WAIT=%0d: CPU logs, IRQ, isolation, March scoreboard and reset recovery",BANK_AW,BUS_WAIT);
        $finish;
    end
    initial begin repeat(DEPTH*240+15000) @(posedge clk);$fatal(1,"Global SoC watchdog");end
endmodule
