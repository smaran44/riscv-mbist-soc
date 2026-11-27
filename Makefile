PYTHON ?= python3
CROSS ?= riscv64-unknown-elf-

.PHONY: test waves firmware synth
test:
	$(PYTHON) tools/run_tests.py
waves:
	$(PYTHON) tools/run_tests.py --case soc --waves
firmware:
	$(PYTHON) tools/build_firmware.py --prefix $(CROSS)
synth:
	$(PYTHON) tools/check_synthesis.py
