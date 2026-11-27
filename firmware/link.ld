OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    ROM (rx) : ORIGIN = 0, LENGTH = 16K
}
SECTIONS {
    .text : { *(.text.start) *(.text .text.*) *(.rodata .rodata.*) } > ROM
    /DISCARD/ : { *(.riscv.attributes) *(.comment) }
}
