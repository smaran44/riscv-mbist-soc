    .option norvc
    .section .text.start,"ax"
    .global _start
    .org 0x100                    # Exercise the configurable reset vector.
    .macro check reg, value
    li t5,\value
    bne \reg,t5,failed
    .endm
    # s6 holds the expected mtval. Verify that the fault occurred at this
    # precise instruction. A failed trap falls through to a deliberate failure.
    .macro expect_trap reason, action:vararg
    li s5,\reason
    la s7,.Lresume\@
    la s8,.Lfault\@
.Lfault\@:
    \action
    j failed
.Lresume\@:
    .endm

_start:
    li s0,0x10000
    li s1,0x40000000
    li s2,0x40000100
    li s3,0x20000
    li s4,0                     # Synchronous traps taken
    la t0,handler
    csrw mtvec,t0
    sw zero,0(s0)
    li t0,15
    sw t0,8(s2)
    li t6,1                     # Diagnostic group number on failure
    li t0,-8
    li t1,3
    add t2,t0,t1
    check t2,-5
    sub t2,t1,t0
    check t2,11
    sll t2,t1,t1
    check t2,24
    slt t2,t0,t1
    check t2,1
    sltu t2,t0,t1
    check t2,0
    xor t2,t0,t1
    check t2,-5
    srl t2,t0,t1
    check t2,0x1fffffff
    sra t2,t0,t1
    check t2,-1
    or t2,t0,t1
    check t2,-5
    and t2,t0,t1
    check t2,0
    addi t2,t0,-1
    check t2,-9
    slti t2,t0,-1
    check t2,1
    sltiu t2,t0,-1
    check t2,1
    xori t2,t0,-1
    check t2,7
    ori t2,t0,3
    check t2,-5
    andi t2,t0,15
    check t2,8
    slli t2,t1,31
    check t2,0x80000000
    srli t2,t0,31
    check t2,1
    srai t2,t0,31
    check t2,-1
    addi zero,t1,11
    check zero,0

    li t6,2
    li t0,0x80000000
    li t1,1
    beq t0,t1,failed
    bne t0,t0,failed
    bge t0,t1,failed
    blt t1,t0,failed
    bltu t0,t1,failed
    bgeu t1,t0,failed
    blt t0,t1,1f
    j failed
1:  bge t1,t0,1f
    j failed
1:  bltu t1,t0,1f
    j failed
1:  bgeu t0,t1,1f
    j failed
1:  beq t0,t0,1f
    sw t1,0(s0)                  # A wrong-path store must be squashed.
1:  bne t0,t1,1f
    sw t1,0(s0)
1:  lw t2,0(s0)
    check t2,0
pc_here:
    auipc t2,0
    la t0,pc_here
    bne t0,t2,failed
    jal t2,jump_ok
return_pc:
    j failed
jump_ok:
    la t0,return_pc
    bne t0,t2,failed
    la t0,jalr_ok
    ori t0,t0,1
    jalr t2,0(t0)               # The low target bit is ignored.
jalr_link:
    j failed
jalr_ok:
    la t0,jalr_link
    bne t2,t0,failed

    li t6,3
    li t0,0x80237f81
    sw t0,32(s0)
    lb t1,32(s0)
    check t1,-127
    lbu t1,35(s0)
    check t1,128
    lh t1,34(s0)
    check t1,0xffff8023
    lhu t1,34(s0)
    check t1,0x8023
    li t0,0xab
    sb t0,33(s0)
    li t0,0xcdef
    sh t0,34(s0)
    lw t1,32(s0)
    sw t1,36(s0)                 # Immediate load-to-store dependency
    lw t1,36(s0)
    add t1,t1,zero
    check t1,0xcdefab81
    fence rw,rw

    li t6,4
    li t0,0x120
    csrrw t1,mscratch,t0
    check t1,0
    li t0,1
    csrrs t1,mscratch,t0
    check t1,0x120
    csrrc t1,mscratch,t0
    check t1,0x121
    csrrwi t1,mscratch,3
    check t1,0x120
    csrrsi t1,mscratch,4
    check t1,3
    csrrci t1,mscratch,2
    check t1,7
    csrr t1,mscratch
    check t1,5
    csrrs t1,mhartid,zero       # Read-only CSR, zero source suppresses write.
    check t1,0
    li s6,-1
    expect_trap 2,.word 0xffffffff
    li s6,0
    expect_trap 11,ecall
    la s6,breakpoint
    li s5,3
    la s7,break_return
    la s8,breakpoint
breakpoint:
    ebreak
    j failed
break_return:
    li s6,0x10001
    expect_trap 4,lw t0,1(s0)
    li s6,0x10003
    expect_trap 6,sh zero,3(s0)
    li t0,0x60000000
    mv s6,t0
    expect_trap 5,lw t2,0(t0)
    li s6,0
    expect_trap 7,sw zero,0(zero)
    li s6,0xf1109073            # CSRRW x0, mvendorid, x1 (read-only).
    expect_trap 2,.word 0xf1109073
    la t0,aligned_dest
    addi t0,t0,2
    mv s6,t0
    expect_trap 0,jalr zero,0(t0)
aligned_dest:
    # An aligned jump can succeed and then encounter an instruction access fault.
    li s5,1
    li s6,0x8000
    mv s8,s6
    la s7,after_bad_fetch
    jalr zero,0(s6)
    j failed
after_bad_fetch:
    li t6,5
    li s6,0x40000024
    expect_trap 5,lw t0,36(s1)   # Unmapped MMIO offset
    li s6,0x40000004
    li t0,4
    expect_trap 7,sw t0,4(s1)   # Unsupported retention opcode
    li s6,0x40000008
    li t0,256
    expect_trap 7,sw t0,8(s1)   # Beyond the 64-byte test configuration
    li s6,0x4000000c
    expect_trap 7,sb zero,12(s1)
    li s6,0x20000
    expect_trap 5,lw t0,0(s3)   # Bank window permits only byte accesses
    li s6,0x40000100
    expect_trap 7,sw zero,0(s2) # GPIO input is read-only

    li t6,6
    li t0,0x100                 # Stop at the first fault.
    sw t0,4(s1)
    li t0,1
    sw t0,0(s1)
    li s6,0x20011
    expect_trap 7,sb zero,17(s3)
    expect_trap 5,lbu t2,17(s3)
    li s6,0x40000000
    li t0,1
    expect_trap 7,sw t0,0(s1)   # Duplicate START
    li s6,0x40000004
    expect_trap 7,sw zero,4(s1) # Change active configuration
wait_stop:
    lw t0,12(s1)
    andi t1,t0,2
    beqz t1,wait_stop
    check t0,10
    lw t1,16(s1)
    check t1,0x1f
    lw t1,28(s1)
    check t1,1
    lw t1,24(s1)
    check t1,0x210
    li t0,2
    sw t0,0(s1)
    lw t1,12(s1)
    check t1,8                  # ACK clears only DONE, not the verdict.

    li t6,7
    li t0,3
    sw t0,8(s1)                 # Inclusive limit covers bytes 0..3.
    li t0,0x23                  # Checkerboard, 55/AA background.
    sw t0,4(s1)
    li t0,1
    sw t0,0(s1)
wait_checker:
    lw t0,12(s1)
    andi t1,t0,2
    beqz t1,wait_checker
    check t0,6
    lw t1,28(s1)
    check t1,0
    lbu t1,0(s3)                # Final checkerboard is inverted.
    check t1,0xaa
    lbu t1,1(s3)
    check t1,0x55
    la t0,rom_constant
    lw t0,0(t0)
    check t0,0x51234567
    check s4,20
    sw s4,4(s0)
    li t0,0x600dcafe
    sw t0,0(s0)
    li t0,4
    sw t0,4(s2)
done:
    j done

handler:
    csrr t3,mcause
    bne t3,s5,failed
    csrr t3,mtval
    bne t3,s6,failed
    csrr t3,mepc
    bne t3,s8,failed
    addi s4,s4,1
    csrw mepc,s7
    mret

failed:
    sw t6,8(s0)
    sw s4,12(s0)
    csrr t3,mcause
    sw t3,16(s0)
    csrr t3,mepc
    sw t3,20(s0)
    csrr t3,mtval
    sw t3,24(s0)
    li t0,15
    sw t0,4(s2)
    j done
.section .rodata
.balign 4
rom_constant:
    .word 0x51234567
