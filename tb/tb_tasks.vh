// =============================================================================
// File: tb_tasks.vh
// Project: Memory Built-In Self-Test (MBIST) 2024
// Description: Testbench logging utilities, banner displays, and assertion tasks.
// =============================================================================

`ifndef TB_TASKS_VH
`define TB_TASKS_VH

task print_banner;
    input [1023:0] title;
    begin
        $display("\n================================================================================");
        $display("  %0s", title);
        $display("================================================================================");
    end
endtask

task print_test_header;
    input integer test_num;
    input [1023:0] test_name;
    input [1023:0] test_desc;
    begin
        $display("\n--------------------------------------------------------------------------------");
        $display(" [TEST %0d] : %0s", test_num, test_name);
        $display(" Description: %0s", test_desc);
        $display("--------------------------------------------------------------------------------");
    end
endtask

task print_result;
    input [1023:0] test_name;
    input         passed;
    begin
        if (passed) begin
            $display(" [RESULT] : %0s -> \033[1;32m[ PASSED ]\033[0m", test_name);
        end else begin
            $display(" [RESULT] : %0s -> \033[1;31m[ FAILED ]\033[0m", test_name);
        end
    end
endtask

`endif // TB_TASKS_VH
