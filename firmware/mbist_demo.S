    .option norvc
    .section .text.start,"ax"
    .global _start
    .equ CTRL,0
    .equ CONFIG,4
    .equ LIMIT,8
    .equ STATUS,12
    .equ FIRST_ADDR,16
    .equ FIRST_DATA,20
    .equ FIRST_DETAIL,24
    .equ FAIL_COUNT,28
    .equ SIGNATURE,32
    .equ GPIO_IN,0
    .equ GPIO_OUT,4
    .equ GPIO_OE,8
    .equ RUNS,0
    .equ PREFLIGHT,4
    .equ IRQ_RESULT,8
    .equ IRQ_COUNT,12
    .equ TRAP_CAUSE,16
    .equ TRAP_PC,20
    .equ TRAP_VALUE,24

_start:
    li      sp,0x14000             # Stack grows down into private scratch RAM.
    li      s0,0x40000000          # MBIST register bank
    li      s1,0x40000100          # GPIO
    li      s2,0x00010000          # Scratch and result log
    li      s3,0x00020000          # SRAM being tested
    la      t0,trap_handler
    csrw    mtvec,t0
    sw      zero,RUNS(s2)
    sw      zero,PREFLIGHT(s2)
    sw      zero,IRQ_RESULT(s2)
    sw      zero,IRQ_COUNT(s2)
    sw      zero,TRAP_CAUSE(s2)
    sw      zero,TRAP_PC(s2)
    sw      zero,TRAP_VALUE(s2)
    li      t0,15
    sw      t0,GPIO_OE(s1)         # Drive pins 0..3. Pins 6 and 7 are inputs.
    li      t0,1
    sw      t0,GPIO_OUT(s1)
    lw      t2,LIMIT(s0)
    li      t0,0x11
    mv      s6,s3
    bltu    t2,t0,smoke_addr_ready
    addi    s6,s3,0x10
smoke_addr_ready:
    li      t0,0xde
    li      t1,0xad
    sb      t0,0(s6)
    sb      t1,1(s6)
    lbu     t2,0(s6)
    bne     t2,t0,run_test
    lbu     t2,1(s6)
    bne     t2,t1,run_test
    li      t0,1
    sw      t0,PREFLIGHT(s2)       # Still run MBIST if the functional check fails.

run_test:
    csrci   mstatus,8
    sw      zero,IRQ_RESULT(s2)
    sw      zero,CONFIG(s0)        # March C-, zero background, continue on failure.
    lw      t0,LIMIT(s0)           # Use the implemented bank size.
    sw      t0,LIMIT(s0)
    lw      t0,GPIO_IN(s1)
    andi    s4,t0,64
    li      t0,2
    sw      t0,GPIO_OUT(s1)
    li      t0,1
    sw      t0,CTRL(s0)
    beqz    s4,poll
    li      t0,0x800
    csrs    mie,t0
    csrsi   mstatus,8
wait_irq:
    lw      t1,IRQ_RESULT(s2)
    beqz    t1,wait_irq
    csrci   mstatus,8
    j       record
poll:
    lw      t1,STATUS(s0)
    andi    t0,t1,2
    beqz    t0,poll
record:
    # Eight 32-byte records in a circular buffer. Publish RUNS last.
    lw      t2,RUNS(s2)
    andi    t0,t2,7
    slli    t0,t0,5
    add     s5,s2,t0
    addi    s5,s5,0x40
    sw      t1,0(s5)
    lw      t0,FIRST_ADDR(s0)
    sw      t0,4(s5)
    lw      t0,FIRST_DATA(s0)
    sw      t0,8(s5)
    lw      t0,FIRST_DETAIL(s0)
    sw      t0,12(s5)
    lw      t0,FAIL_COUNT(s0)
    sw      t0,16(s5)
    lw      t0,SIGNATURE(s0)
    sw      t0,20(s5)
    sltu    t0,zero,s4
    sw      t0,24(s5)
    addi    t2,t2,1
    sw      t2,28(s5)
    andi    t0,t1,12
    sw      t0,GPIO_OUT(s1)        # 0x04 = pass, 0x08 = fail.
    sw      t2,RUNS(s2)
wait_low:
    lw      t0,GPIO_IN(s1)
    andi    t0,t0,128
    bnez    t0,wait_low
wait_high:
    lw      t0,GPIO_IN(s1)
    andi    t0,t0,128
    beqz    t0,wait_high
    j       run_test

    .balign 4
trap_handler:
    addi    sp,sp,-8
    sw      t0,0(sp)
    sw      t1,4(sp)
    csrr    t0,mcause
    li      t1,0x8000000b
    bne     t0,t1,unexpected
    lw      t0,STATUS(s0)
    sw      t0,IRQ_RESULT(s2)
    li      t0,2
    sw      t0,CTRL(s0)            # Drop the level interrupt before MRET.
    lw      t0,IRQ_COUNT(s2)
    addi    t0,t0,1
    sw      t0,IRQ_COUNT(s2)
    lw      t1,4(sp)
    lw      t0,0(sp)
    addi    sp,sp,8
    mret
unexpected:
    sw      t0,TRAP_CAUSE(s2)
    csrr    t0,mepc
    sw      t0,TRAP_PC(s2)
    csrr    t0,mtval
    sw      t0,TRAP_VALUE(s2)
    li      t0,15
    sw      t0,GPIO_OUT(s1)
stopped:
    j       stopped
