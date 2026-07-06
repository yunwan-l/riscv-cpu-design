# =============================================================================
# Makefile - RVP (RISC-V Pipeline) Processor Build System
# =============================================================================
# Targets:
#   make sim      - Run simulation (iverilog or verilator)
#   make synth    - Run Vivado synthesis
#   make test     - Run test suite
#   make configs  - List all available named configurations
#   make clean    - Clean build artifacts
#
# Usage examples:
#   make sim                                  # Default config (phase2_full_rv32i)
#   make sim CONFIG=phase3_icache_lru          # Use specific config
#   make sim SIMULATOR=verilator               # Use Verilator instead of iverilog
#   make synth CONFIG=phase3_full BOARD=nexys4 # Synthesize with full config
#   make test                                  - Run all tests
#   make configs                               # List available configs
# =============================================================================

# --- Project paths ---
PROJECT_ROOT := $(CURDIR)
RTL_DIR      := $(PROJECT_ROOT)/rtl
CONFIG_DIR   := $(PROJECT_ROOT)/config
TB_DIR       := $(PROJECT_ROOT)/tb
SYNTH_DIR    := $(PROJECT_ROOT)/synth/vivado
BUILD_DIR    := $(PROJECT_ROOT)/build

# --- Configuration selection ---
CONFIG       ?= phase2_full_rv32i
SIMULATOR    ?= iverilog
BOARD        ?= nexys4
TOP_MODULE   ?= rvp_core
TB_MODULE    ?= tb_rvp_core

# --- File lists ---
FILELIST     := $(CONFIG_DIR)/rvp_core.f
CONFIGS_YAML := $(CONFIG_DIR)/rvp_configs.yaml
CONFIG_SVH   := $(CONFIG_DIR)/rvp_config.svh

# --- Toolchain paths ---
RISCV_PREFIX  ?= riscv32-unknown-elf-
RISCV_GCC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy

# --- Vivado ---
VIVADO       ?= vivado

# --- Simulation parameters ---
SIM_TIME     ?= 1000ns
VCD_FILE     ?= $(BUILD_DIR)/sim/wave.vcd
SIM_LOG       := $(BUILD_DIR)/sim/sim.log

# =============================================================================
# Helper: Parse YAML config to generate Verilog defines
# =============================================================================
# This extracts the config parameters from rvp_configs.yaml and converts them
# to +define+ flags for the simulator.
define parse_config
$(eval CONFIG_PARAMS := $(shell \
	python3 -c "\
import yaml, sys; \
c = yaml.safe_load(open('$(CONFIGS_YAML)')); \
cfg = c.get('$(CONFIG)'); \
exit(1) if not cfg else None; \
print(' '.join('+define+RVP_{}={}'.format(k,v) for k,v in cfg.items()))" 2>/dev/null || \
	python3 -c "\
import sys; \
lines = open('$(CONFIGS_YAML)').read().split('\n'); \
in_cfg = False; \
params = []; \
for line in lines: \
    t = line.strip(); \
    if not t or t[0] == '#': continue; \
    if not line[0].isspace() and t.endswith(':'): \
        in_cfg = (t[:-1] == '$(CONFIG)'); continue; \
    if in_cfg and ':' in t: \
        k,_,v = t.partition(':'); \
        params.append('+define+RVP_{}={}'.format(k.strip(),v.strip())); \
print(' '.join(params))" \
))
endef

$(eval $(call parse_config))

# Get all RTL source files from the file list (excluding comments)
RTL_FILES := $(shell grep -v '^\s*//' $(FILELIST) | grep -v '^\s*$$' | grep -v '^\s*#' | sed 's|^\s*||;s|\s*$$||')

# =============================================================================
# Phony targets
# =============================================================================
.PHONY: all sim synth test configs clean help

all: help

# =============================================================================
# help - Show available targets
# =============================================================================
help:
	@echo "==================================================================="
	@echo " RVP (RISC-V Pipeline) Build System"
	@echo "==================================================================="
	@echo ""
	@echo "Targets:"
	@echo "  sim      Run simulation (SIMULATOR=iverilog|verilator)"
	@echo "  synth    Run Vivado synthesis"
	@echo "  test     Run test suite"
	@echo "  configs  List all available named configurations"
	@echo "  clean    Clean build artifacts"
	@echo "  help     Show this help message"
	@echo ""
	@echo "Variables:"
	@echo "  CONFIG       Named config (default: $(CONFIG))"
	@echo "  SIMULATOR    Simulator: iverilog|verilator (default: $(SIMULATOR))"
	@echo "  BOARD        Target board: nexys4|zybo (default: $(BOARD))"
	@echo "  TOP_MODULE   Top-level RTL module (default: $(TOP_MODULE))"
	@echo "  SIM_TIME     Simulation time (default: $(SIM_TIME))"
	@echo ""
	@echo "Examples:"
	@echo "  make sim CONFIG=phase3_icache_lru"
	@echo "  make sim SIMULATOR=verilator CONFIG=phase3_full"
	@echo "  make synth CONFIG=phase3_full BOARD=nexys4"
	@echo "  make test"
	@echo "==================================================================="

# =============================================================================
# configs - List all available named configurations
# =============================================================================
configs:
	@echo "Available RVP configurations (from config/rvp_configs.yaml):"
	@echo "-------------------------------------------------------------------"
	@grep -E '^\w' $(CONFIGS_YAML) | grep -v '^#' | sed 's/:.*//' | \
		awk '{printf "  %-25s (config #%d)\n", $$1, NR}'
	@echo "-------------------------------------------------------------------"
	@echo "Usage: make sim CONFIG=<name>"
	@echo "       make synth CONFIG=<name>"

# =============================================================================
# sim - Run simulation
# =============================================================================
# Uses iverilog or verilator based on SIMULATOR variable.
# The config parameters from rvp_configs.yaml are passed as +define+ flags.
sim: $(BUILD_DIR)/sim
	@echo "==================================================================="
	@echo " Running simulation"
	@echo "==================================================================="
	@echo " Config:     $(CONFIG)"
	@echo " Simulator:  $(SIMULATOR)"
	@echo " Top module: $(TOP_MODULE)"
	@echo " Sim time:   $(SIM_TIME)"
	@echo "==================================================================="
	@if [ $(SIMULATOR) = iverilog ]; then \
		echo "Compiling with iverilog..."; \
		iverilog -g2012 \
			-I $(CONFIG_DIR) \
			$(CONFIG_PARAMS) \
			-f $(FILELIST) \
			$(TB_DIR)/$(TB_MODULE).sv \
			-o $(BUILD_DIR)/sim/$(TOP_MODULE)_sim; \
		echo "Running simulation..."; \
		vvp $(BUILD_DIR)/sim/$(TOP_MODULE)_sim; \
	elif [ $(SIMULATOR) = verilator ]; then \
		echo "Compiling with Verilator..."; \
		verilator --binary --top-module $(TOP_MODULE) \
			+define+RVP_CONFIG_SVH=1 \
			-I $(CONFIG_DIR) \
			$(CONFIG_PARAMS) \
			-f $(FILELIST) \
			$(TB_DIR)/$(TB_MODULE).sv \
			--Mdir $(BUILD_DIR)/sim/obj_dir; \
		echo "Running simulation..."; \
		$(BUILD_DIR)/sim/obj_dir/V$(TOP_MODULE); \
	else \
		echo "ERROR: Unknown simulator '$(SIMULATOR)'. Use 'iverilog' or 'verilator'."; \
		exit 1; \
	fi
	@echo "==================================================================="
	@echo " Simulation complete"
	@echo "==================================================================="

# =============================================================================
# synth - Run Vivado synthesis
# =============================================================================
synth:
	@echo "==================================================================="
	@echo " Running Vivado synthesis"
	@echo "==================================================================="
	@echo " Config: $(CONFIG)"
	@echo " Board:  $(BOARD)"
	@echo "==================================================================="
	$(VIVADO) -mode batch -source $(SYNTH_DIR)/run_synth.tcl \
		-tclargs -board $(BOARD) -config $(CONFIG) \
		-top $(TOP_MODULE) -project_dir build/vivado \
		-project_name rvp_$(BOARD)

# =============================================================================
# test - Run the test suite
# =============================================================================
test: test-fw sim-test
	@echo "==================================================================="
	@echo " Running test suite"
	@echo "==================================================================="

# Compile test firmware
test-fw:
	@$(MAKE) -C $(TB_DIR)/tests all

# Run simulation with all test programs
sim-test: test-fw
	@echo "Running simulation with test programs..."
	@for hexfile in $(TB_DIR)/tests/build/*.hex; do \
		echo "--- Running test: $$(basename $$hexfile) ---"; \
		$(MAKE) sim CONFIG=$(CONFIG) SIM_TIME=$(SIM_TIME) || \
			echo "FAILED: $$hexfile"; \
	done

# =============================================================================
# clean - Remove build artifacts
# =============================================================================
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	@$(MAKE) -C $(TB_DIR)/tests clean 2>/dev/null || true
	@echo "Done."

# =============================================================================
# Build directories
# =============================================================================
$(BUILD_DIR)/sim:
	mkdir -p $@

# =============================================================================
# Utility targets
# =============================================================================

# Lint check with verilator
.PHONY: lint
lint:
	@echo "Running Verilator lint..."
	verilator --lint-only -Wno-fatal \
		-I $(CONFIG_DIR) \
		$(CONFIG_PARAMS) \
		-f $(FILELIST)

# Show RTL file list
.PHONY: files
files:
	@echo "RTL source files (from $(FILELIST)):"
	@echo "-------------------------------------------------------------------"
	@cat $(FILELIST) | grep -v '^\s*//' | grep -v '^\s*$$' | grep -v '^\s*#'
	@echo "-------------------------------------------------------------------"

# Show current config parameters
.PHONY: show-config
show-config:
	@echo "Current configuration: $(CONFIG)"
	@echo "Parameters:"
	@echo "  $(CONFIG_PARAMS)" | tr ' ' '\n' | sed 's/^/  /'
