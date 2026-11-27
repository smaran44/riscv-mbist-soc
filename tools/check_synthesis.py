"""Board-independent structural synthesis check. Requires sv2v and Yosys."""
import os
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
out = root / "build"
out.mkdir(exist_ok=True)
sources = (root/"rtl/files.f").read_text().splitlines()
with (out/"fpga_synth.v").open("w") as generated:
    subprocess.run([os.environ.get("SV2V","sv2v"), "--top=fpga_top", "-Irtl/mbist", *sources],
                   cwd=root,stdout=generated,check=True)
script = ("read_verilog build/fpga_synth.v; hierarchy -check -top fpga_top; "
          "proc; opt; memory -nomap; opt; check -assert; stat")
subprocess.run([os.environ.get("YOSYS","yosys"), "-Q", "-q", "-l", "build/synthesis.log",
                "-p",script], cwd=root,check=True)
print("PASS fpga_top structural synthesis. See build/synthesis.log for the design hierarchy and warnings.")
