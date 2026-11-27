"""Compile and run the self-checking simulations from any working directory."""
import argparse
from pathlib import Path
import os
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CASES = {
    "legacy": ("tb_legacy", [], "original six-instruction program"),
    "cpu": ("tb_cpu", [], "instruction, exception and integration checks"),
    "soc": ("tb_soc", [], "64-byte SRAM, two bus wait clocks"),
    "fullbank": ("tb_soc", ["-Ptb_soc.BANK_AW=8","-Ptb_soc.BUS_WAIT=0"],
                 "256-byte SRAM, zero bus wait clocks"),
    "fpga": ("tb_fpga", [], "physical SRAM path and board-facing pins"),
    "mbist": ("tb_mbist_top", [], "eight standalone MBIST cases"),
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--case", choices=CASES, action="append", help="run only this case, repeatable")
parser.add_argument("--waves", action="store_true", help="capture the 64-byte SoC run into build/mbist_soc.vcd")
args = parser.parse_args()
selected = args.case or list(CASES)
if args.waves and "soc" not in selected:
    parser.error("--waves needs the soc case")
build = ROOT / "build"
build.mkdir(exist_ok=True)
compiler = os.environ.get("IVERILOG", "iverilog")
runtime = os.environ.get("VVP", "vvp")
# Optional flags only for installations with nonstandard simulator library paths.
compile_flags = shlex.split(os.environ.get("IVERILOG_FLAGS", ""))
run_flags = shlex.split(os.environ.get("VVP_FLAGS", ""))

def run(cmd):
    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, encoding="utf-8", errors="replace",
                       timeout=90)
    if p.returncode:
        raise RuntimeError(p.stdout + p.stderr)
    return p.stdout + p.stderr

failures = 0
transcript = []
for name in selected:
    module, params, description = CASES[name]
    source = ROOT / "tb" / (module + (".v" if name=="mbist" else ".sv"))
    product = build / (name+".vvp")
    heading = f"[{name}] {description}"
    print(heading, flush=True)
    try:
        compile_output = run([compiler, *compile_flags, "-g2012", "-Irtl/mbist", "-Itb", "-s",
                              module, *params, "-o", str(product), "-f", "rtl/files.f", str(source)])
        output = run([runtime, *run_flags, str(product)] + (["+vcd"] if name=="soc" and args.waves else []))
        (build / (name+".log")).write_text(compile_output+output, encoding="utf-8")
        summary = [line for line in output.splitlines() if line.startswith(("RUN ", "PASS "))]
        if not any(line.startswith("PASS "+module) for line in summary):
            raise RuntimeError("Missing self-check success marker.\n"+output)
        print("\n".join(summary))
        transcript.extend([heading, *summary, ""])
    except (FileNotFoundError, RuntimeError, subprocess.TimeoutExpired) as err:
        failures += 1
        detail = f"FAIL {name}: {err}"
        print(detail, file=sys.stderr)
        transcript.extend([heading, detail, ""])
verdict = f"{len(selected)-failures}/{len(selected)} simulation configurations passed"
print(verdict)
(build/"regression.txt").write_text("\n".join([*transcript,verdict,""]), encoding="utf-8")
sys.exit(bool(failures))
