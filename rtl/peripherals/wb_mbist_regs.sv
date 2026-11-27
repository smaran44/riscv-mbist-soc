// Software sees a stable result even though bist_done lasts one core clock.
// The same in-order bus services the bank window, so accepting START means
// all preceding functional bank transfers have already terminated.
module wb_mbist_regs #(parameter AW=8)(
    input wire clk,rst_n,req,we, input wire [5:0] addr, input wire [3:0] sel,
    input wire [31:0] wdata, output reg [31:0] rdata, output wire ack,err,
    output reg bist_owned,bist_start, output wire [2:0] algo_sel,pattern_sel,
    output wire stop_on_fail, output reg [AW-1:0] max_addr, output wire irq,status_pass,status_fail,
    input wire bist_done,bist_pass,bist_fail,
    input wire [15:0] fail_count, input wire [AW-1:0] first_addr,
    input wire [7:0] first_expected,first_actual,first_mask,signature,
    input wire [3:0] first_step
);
    reg [8:0] config_reg;
    reg done,pass_flag,fail_flag;
    reg [15:0] saved_count;
    reg [AW-1:0] saved_addr;
    reg [7:0] saved_expected,saved_actual,saved_mask,saved_signature;
    reg [3:0] saved_step;
    localparam [5:0] CTRL=0, CFG=4, LIMIT=8, STATUS=12, FIRST_ADDR=16,
        FIRST_DATA=20, FIRST_DETAIL=24, FAIL_COUNT=28, SIGNATURE=32;
    assign algo_sel=config_reg[2:0];
    assign pattern_sel=config_reg[6:4];
    assign stop_on_fail=config_reg[8];
    assign irq=done;
    assign status_pass=pass_flag;
    assign status_fail=fail_flag;
    reg legal;
    always @* begin
        legal=0; rdata=0;
        case(addr)
            CTRL: legal=we && ((wdata==1 && !bist_owned) || wdata==2);
            CFG: begin
                legal=!we || (!bist_owned && (wdata & ~32'h177)==0 &&
                               wdata[2:0]<=3 && wdata[6:4]<=5);
                rdata={23'b0,config_reg};
            end
            LIMIT: begin legal=!we || (!bist_owned && (wdata>>AW)==0);
                rdata={{(32-AW){1'b0}},max_addr}; end
            STATUS: begin legal=!we;rdata={28'b0,fail_flag,pass_flag,done,bist_owned};end
            FIRST_ADDR: begin legal=!we;rdata={{(32-AW){1'b0}},saved_addr};end
            FIRST_DATA: begin legal=!we;rdata={16'b0,saved_expected,saved_actual};end
            FIRST_DETAIL: begin legal=!we;rdata={20'b0,saved_step,saved_mask};end
            FAIL_COUNT: begin legal=!we;rdata={16'b0,saved_count};end
            SIGNATURE: begin legal=!we;rdata={24'b0,saved_signature};end
            default: ;
        endcase
    end
    assign ack=req && legal && sel==4'hf;
    assign err=req && !(legal && sel==4'hf);
    wire start_write=ack && we && addr==CTRL && wdata==1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            config_reg<=0; max_addr<={AW{1'b1}}; bist_owned<=0; bist_start<=0;
            done<=0;pass_flag<=0;fail_flag<=0; saved_count<=0;saved_addr<=0;
            saved_expected<=0;saved_actual<=0;saved_mask<=0;saved_step<=0;saved_signature<=0;
        end else begin
            bist_start<=start_write;
            if (ack && we && addr==CFG) config_reg<=wdata[8:0];
            if (ack && we && addr==LIMIT) max_addr<=wdata[AW-1:0];
            if (ack && we && addr==CTRL && wdata==2) done<=0;
            if (start_write) begin
                bist_owned<=1;done<=0;pass_flag<=0;fail_flag<=0;
                saved_count<=0;saved_addr<=0;saved_expected<=0;saved_actual<=0;
                saved_mask<=0;saved_step<=0;saved_signature<=0;
            end else if (bist_owned && bist_done) begin
                bist_owned<=0;done<=1;pass_flag<=bist_pass;fail_flag<=bist_fail;
                saved_count<=fail_count;saved_addr<=first_addr;saved_expected<=first_expected;
                saved_actual<=first_actual;saved_mask<=first_mask;saved_step<=first_step;
                saved_signature<=signature;
            end
        end
    end
endmodule
