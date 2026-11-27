"""Rebuild the RV32I word-hex images with GNU RISC-V binutils."""
import argparse
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("images", nargs="*", default=["mbist_demo", "cpu_checks"])
parser.add_argument("--prefix", default="riscv64-unknown-elf-")
args = parser.parse_args()
build = root / "build" / "firmware"
build.mkdir(parents=True, exist_ok=True)
for name in args.images:
    asm = root / "firmware" / (name + ".S")
    obj, elf, binary = [build / (name + suffix) for suffix in (".o", ".elf", ".bin")]
    subprocess.run([args.prefix+"as", "-march=rv32i_zicsr", "-mabi=ilp32", "-mno-relax",
                    "-o", obj, asm], check=True)
    subprocess.run([args.prefix+"ld", "-m", "elf32lriscv", "--no-relax", "-T",
                    root/"firmware/link.ld", "-o", elf, obj], check=True)
    subprocess.run([args.prefix+"objcopy", "-O", "binary", elf, binary], check=True)
    data = binary.read_bytes()
    data += bytes((-len(data)) % 4)
    words = [f"{int.from_bytes(data[i:i+4], 'little'):08x}" for i in range(0, len(data), 4)]
    if len(words) < 4096:
        words += ["@00000fff", "00000013"]
    (root/"firmware"/(name+".hex")).write_text("\n".join(words)+"\n", encoding="ascii")
    print(f"{name}: {len(data)//4} words assembled")
