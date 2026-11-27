# RISC-V SoC for SRAM built-in self-test

The five-stage CPU boots from ROM, checks that it can read and write the dedicated test SRAM, then instructs the MBIST controller to run March C−. The hardware sweeps the bank and compares the returned bytes. Firmware reports PASS or FAIL on GPIO and logs the first failing address, expected byte, actual byte, failing bits, March element, comparison-error count and signature. Program instructions, stack and result records live outside the SRAM being overwritten.

## Run the project

Extract the ZIP and open a terminal in the `RISCV_MBIST_SoC` folder. Install Python 3 and Icarus Verilog (both `iverilog` and `vvp` on PATH). The project includes assembled ROM images. The regression was run with Icarus Verilog 12.

```sh
python3 tools/run_tests.py --waves
```

On Windows use `py -3 tools/run_tests.py --waves` if that is your Python launcher. Expect the final line **6/6 simulation configurations passed**. A failed assertion, timeout or missing success marker produces a nonzero exit code. Individual simulator logs and the summary appear under `build/`. For the integrated 64-byte case alone, use `python3 tools/run_tests.py --case soc --waves`.

To see an already captured run, open the included waveform and GTKWave layout from the project folder. Replace the first path with `build/mbist_soc.vcd` to view your own run.

```sh
gtkwave verification/mbist_soc.vcd verification/mbist_soc.gtkw
```

## Find the modules

| Directory or entry | What to open |
|---|---|
| `rtl/top/soc_top.sv` | Complete SoC. Connects CPU, bus, ROM, scratch RAM, SRAM window, GPIO, register wrapper, interrupt and MBIST engine. |
| `rtl/top/fpga_top.sv` | Board-facing top. One clock, synchronized reset release, eight bidirectional GPIOs and four test-status pins. Selects the synthesizable SRAM. |
| `rtl/top/Pipeline_top.sv` | Two-pin compatibility wrapper for the provided processor's original program. |
| `rtl/cpu/` | Five-stage datapath, instruction decoder, ALU, forwarding, register file, package and machine-mode CSRs. |
| `rtl/bus/` | `wb_interconnect.sv` decodes data requests. `wb_byte_bank.sv` connects one CPU byte lane to the single-port test SRAM and enforces ownership. |
| `rtl/memory/` | `boot_rom.sv`, `scratch_ram.sv` and `mbist_sram_sp.sv` implement the three memories. |
| `rtl/peripherals/` | `wb_gpio.sv` implements synchronized inputs, output data and output enables. `wb_mbist_regs.sv` captures completion, errors and first-failure diagnostics for software. |
| `rtl/mbist/` | The chosen repository's algorithm controller, address and pattern generators, comparator, diagnostic unit, SRAM collar, top, definitions and simulation fault model. |
| `firmware/` | `mbist_demo.S` drives the actual application. `cpu_checks.S` exercises instructions, traps and peripheral error paths. Each has a prebuilt word-hex image. |
| `tb/` | `tb_soc.sv` is the main end-to-end self-check. Separate benches cover the CPU, FPGA top, original CPU program and standalone MBIST core. |
| `verification/` | Captured SoC waveform, GTKWave signal layout, simulation transcript and generic synthesis summary. |
| `docs/` | Opening flowchart in PNG and editable draw.io formats, nine-page design and verification PDF, and the register-level programming reference. |
| `rtl/files.f` | Compile order for the synthesizable design plus the selectable simulation model. Provide `rtl/mbist` as a Verilog include directory. |

## What changed in the CPU

The upgrade retains the five-stage organization, original PC adder, forwarding selector and ALU input multiplexers. The register file keeps its upstream interface and adds hardwired x0 and write-through reads. The new pipelined datapath connects fetch to a ROM port and loads/stores to a 32-bit Wishbone Classic master. It inserts load-use bubbles, forwards result and store operands, holds transfers through wait states and flushes younger instructions on a redirect or precise trap.

The decoder handles RV32I integer arithmetic, shifts, comparisons, branches, jumps, upper immediates, byte/halfword/word accesses, FENCE, ECALL and EBREAK. The core implements the six Zicsr operations, direct machine trap entry and MRET. A machine-external interrupt conveys MBIST completion. The reference system uses one hart, machine mode, a fixed instruction ROM and ordered, uncached data accesses. The instruction-set checks are directed simulations.

## Reproduce the demonstration

1. Reset the SoC. Firmware installs its trap handler, sets GPIO output-enable to `0x0F` and writes then reads `0xDE` and `0xAD` through the CPU's test-bank window.
2. With GPIO input bit 6 low, firmware starts March C− and polls STATUS. With bit 6 high, it enables the machine-external interrupt. Both modes execute the same ROM image.
3. Observe the GPIO low nibble. `0x1` means functional preflight, `0x2` means testing, `0x4` means PASS and `0x8` means FAIL. `0xF` records an unexpected trap. After the result, present a low then a high on input bit 7 to start another run.
4. In `tb_soc.sv`, the testbench sets bit 4 stuck at zero at local SRAM offset `0x1F`. Firmware captures `STATUS=0x0A`, expected `0xFF`, actual `0xEF`, mask `0x10`, element E2 and two mismatching comparisons. The two comparisons revisit the same faulty bit. With injection cleared, a new run passes and clears the old diagnostic record.

| Self-check configuration | Observed result |
|---|---|
| Original processor program | x7 = 8 and x10 = 1 |
| Directed CPU and MMIO firmware | 40 RV32I mnemonic bins, all six CSR operations, 20 synchronous trap returns, busy-bank rejection and early stop |
| Integrated 64-byte bank, two bus wait clocks | Independent March scoreboard compared 320 reads and checked 320 writes per full run. Clean, two injected stuck-bit cases, clean retest, interrupts and reset recovery passed. |
| Integrated 256-byte bank, zero added wait clocks | Same scenarios passed. Each full sweep had 1,280 comparisons and 1,280 writes. |
| Board-facing top in RTL simulation | Synchronized reset, inferred SRAM path, GPIO `0x04` and signature `0x06` |
| Standalone MBIST RTL | All eight supplied scenarios passed after the sequencing and sampling fixes. |

As a check on the testbench, forcing the captured failure mask to zero in a temporary copy triggered a mismatch in the second firmware result and a nonzero simulator exit. The diagnostic is in `verification/mutation_check.txt`.

For a presentation, zoom the included **64-byte SoC waveform** to **24.955–24.965 µs**. The comparator raises `mismatch`, then the diagnostic unit latches offset `0x1F`. At **34.945 µs** the raw completion pulse rises. At **34.975 µs** the CPU takes the external interrupt. The register window keeps the result available for firmware. Page 8 of the PDF plots this same comparison from the included SoC waveform.

## Firmware rebuild and FPGA entry point

To rebuild after editing assembly, install GNU RISC-V binutils and run the following. A matching 32-bit-target toolchain prefix can be supplied with `--prefix`.

```sh
python3 tools/build_firmware.py --prefix riscv64-unknown-elf-
python3 tools/run_tests.py
```

For generic structural synthesis, install sv2v and Yosys and run `python3 tools/check_synthesis.py`. The check elaborates `fpga_top`, simplifies processes and memories, and runs `check -assert`. For an FPGA build, make `firmware/mbist_demo.hex` available at the configured ROM initialization path and assign the clock, reset, GPIO and status ports to pins on the selected board. Board-specific constraints, timing closure and a physical board demonstration remain device-dependent.

From a make-enabled environment the equivalent shortcuts are `make test`, `make waves`, `make firmware` and `make synth`. Detailed register semantics, the firmware log format and the optional fault-injection interface are in [the programming reference](docs/interfaces.md).

## Source provenance

The CPU base is revision `e9a5690` of smaran44's five-stage processor. The original program and reusable RTL primitives are retained in the distribution. [CPU revision](https://github.com/smaran44/riscv-5stage-pipelined-cpu/tree/e9a5690b736651c06ce95e18ecefdbe30bd05782)

The MBIST base is revision `127164b` of kndkrakhil's Memory-Built-In-Self-Test. The local controller initializes its March element once per start. The local bench samples synchronous data after the read edge, uses a timeout and fails its process on a failed check. The top selects the simulation fault model or a synthesizable SRAM. The upstream MIT notice is in `licenses/MBIST-MIT.txt`. [MBIST revision](https://github.com/kndkrakhil/Memory-Built-In-Self-Test/tree/127164b8540d74155b2bc4ab9d91ccb03df26298)
