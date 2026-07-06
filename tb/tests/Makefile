# =============================================================================
# tb/tests/Makefile - RVP Test Firmware Compilation
# =============================================================================
# Compiles RISC-V assembly test programs (.S) into Verilog hex files (.hex)
# using the riscv-gnu-toolchain.
#
# Test programs follow the riscv-tests convention (see picorv32/tests/):
#   - riscv_test.h   : test environment macros (RVTEST_PASS / RVTEST_FAIL)
#   - test_macros.h  : test case macros (TEST_RR_OP, TEST_IMM_OP, etc.)
#
# Targets:
#   make all          - Compile all tests
#   make test_<name>  - Compile a single test (e.g., make test_add)
#   make list         - List all available tests
#   make clean        - Remove build artifacts
#
# Prerequisites:
#   - riscv-gnu-toolchain installed (riscv32-unknown-elf-gcc)
#   - Set RISCV_PREFIX if using a different toolchain variant
#
# Usage:
#   make all
#   make test_add
#   make clean
# =============================================================================

# --- Toolchain ---
RISCV_PREFIX  ?= riscv32-unknown-elf-
RISCV_GCC      := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY  := $(RISCV_PREFIX)objcopy
RISCV_OBJDUMP  := $(RISCV_PREFIX)objdump
RISCV_SIZE     := $(RISCV_PREFIX)size

# --- Compilation flags ---
# -march=rv32im  : RV32I + M extension (adjust if testing RV32I only)
# -mabi=ilp32    : 32-bit integer ABI
# -nostdlib      : No standard library (bare metal)
# -nostartfiles  : No default startup files
# -ffreestanding : Freestanding environment
# -Wl,--gc-sections : Remove unused sections
ARCH    ?= rv32im
ABI     ?= ilp32
CFLAGS  := -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -ffreestanding \
           -O2 -Wall -Wextra -g \
           -static -Wl,--gc-sections

# --- Directories ---
TESTS_DIR     := $(CURDIR)
BUILD_DIR     := $(TESTS_DIR)/build
OBJ_DIR       := $(BUILD_DIR)/obj

# --- Reference test files (from picorv32 tests/) ---
# If local .S files are not found, fall back to picorv32 reference tests.
PICORV32_TESTS := $(CURDIR)/../../document/references/picorv32/tests

# --- Linker script ---
# Use picorv32 firmware linker script or a custom one
LINK_SCRIPT   ?= $(TESTS_DIR)/link.ld

# --- Memory configuration ---
MEM_SIZE     ?= 8192    # 8K words = 32KB
HEX_FORMAT   ?= verilog  # verilog | binary

# --- makehex script (for binary -> hex conversion) ---
MAKEHEX      := $(TESTS_DIR)/makehex.py

# =============================================================================
# Test source files
# =============================================================================
# Local test files (in tb/tests/)
TEST_SRCS_LOCAL := $(wildcard $(TESTS_DIR)/*.S)

# Reference test files from picorv32 (used if local copies don't exist)
TEST_SRCS_REF := \
	$(PICORV32_TESTS)/add.S \
	$(PICORV32_TESTS)/addi.S \
	$(PICORV32_TESTS)/sub.S \
	$(PICORV32_TESTS)/and.S \
	$(PICORV32_TESTS)/andi.S \
	$(PICORV32_TESTS)/or.S \
	$(PICORV32_TESTS)/ori.S \
	$(PICORV32_TESTS)/xor.S \
	$(PICORV32_TESTS)/xori.S \
	$(PICORV32_TESTS)/sll.S \
	$(PICORV32_TESTS)/slli.S \
	$(PICORV32_TESTS)/sra.S \
	$(PICORV32_TESTS)/srai.S \
	$(PICORV32_TESTS)/srl.S \
	$(PICORV32_TESTS)/srli.S \
	$(PICORV32_TESTS)/slt.S \
	$(PICORV32_TESTS)/slti.S \
	$(PICORV32_TESTS)/lui.S \
	$(PICORV32_TESTS)/auipc.S \
	$(PICORV32_TESTS)/j.S \
	$(PICORV32_TESTS)/jal.S \
	$(PICORV32_TESTS)/jalr.S \
	$(PICORV32_TESTS)/beq.S \
	$(PICORV32_TESTS)/bne.S \
	$(PICORV32_TESTS)/blt.S \
	$(PICORV32_TESTS)/bltu.S \
	$(PICORV32_TESTS)/bge.S \
	$(PICORV32_TESTS)/bgeu.S \
	$(PICORV32_TESTS)/lb.S \
	$(PICORV32_TESTS)/lbu.S \
	$(PICORV32_TESTS)/lh.S \
	$(PICORV32_TESTS)/lhu.S \
	$(PICORV32_TESTS)/lw.S \
	$(PICORV32_TESTS)/sb.S \
	$(PICORV32_TESTS)/sh.S \
	$(PICORV32_TESTS)/sw.S \
	$(PICORV32_TESTS)/mul.S \
	$(PICORV32_TESTS)/mulh.S \
	$(PICORV32_TESTS)/mulhsu.S \
	$(PICORV32_TESTS)/mulhu.S \
	$(PICORV32_TESTS)/div.S \
	$(PICORV32_TESTS)/divu.S \
	$(PICORV32_TESTS)/rem.S \
	$(PICORV32_TESTS)/remu.S \
	$(PICORV32_TESTS)/simple.S

# Use local tests if available, otherwise reference
ifeq ($(strip $(TEST_SRCS_LOCAL)),)
  TEST_SRCS := $(TEST_SRCS_REF)
else
  TEST_SRCS := $(TEST_SRCS_LOCAL)
endif

# Extract test names (basename without extension)
TEST_NAMES := $(notdir $(basename $(TEST_SRCS)))

# Output hex files
TEST_HEXES := $(addprefix $(BUILD_DIR)/, $(addsuffix .hex, $(TEST_NAMES)))

# =============================================================================
# Phony targets
# =============================================================================
.PHONY: all clean list help copy-tests

all: $(BUILD_DIR) $(TEST_HEXES)
	@echo "==================================================================="
	@echo " All tests compiled successfully"
	@echo "==================================================================="
	@echo " Output directory: $(BUILD_DIR)"
	@echo " Tests compiled:   $(words $(TEST_HEXES))"
	@ls -1 $(BUILD_DIR)/*.hex 2>/dev/null | xargs -I{} basename {} | column
	@echo "==================================================================="

# =============================================================================
# Build directory creation
# =============================================================================
$(BUILD_DIR):
	mkdir -p $@
	mkdir -p $(OBJ_DIR)

# =============================================================================
# Linker script (generate if not provided)
# =============================================================================
$(LINK_SCRIPT):
	@echo "Generating default linker script: $@"
	@echo "/* Auto-generated linker script for RVP tests */" > $@
	@echo "OUTPUT_ARCH(riscv)" >> $@
	@echo "ENTRY(_start)" >> $@
	@echo "MEMORY { ROM (rx) : ORIGIN = 0x00000000, LENGTH = 32K }" >> $@
	@echo "SECTIONS { .text : { *(.text.init) *(.text) } > ROM" >> $@
	@echo "  .data : { *(.data) } > ROM" >> $@
	@echo "  .rodata : { *(.rodata) } > ROM" >> $@
	@echo "  .bss : { *(.bss) } > ROM" >> $@
	@echo "}" >> $@

# =============================================================================
# Compile a single test: .S -> .elf -> .hex
# =============================================================================
# Pattern rule for compiling .S -> .elf
$(BUILD_DIR)/%.elf: %.S | $(BUILD_DIR)
	@echo "Compiling: $(notdir $<) -> $(notdir $@)"
	$(RISCV_GCC) $(CFLAGS) -T $(LINK_SCRIPT) $< -o $@
	@echo "  Size: $$($(RISCV_SIZE) $@ | tail -1)"

# Pattern rule for picorv32 reference tests
$(BUILD_DIR)/%.elf: $(PICORV32_TESTS)/%.S | $(BUILD_DIR)
	@echo "Compiling (ref): $(notdir $<) -> $(notdir $@)"
	$(RISCV_GCC) $(CFLAGS) \
		-I $(PICORV32_TESTS) \
		-DTEST_FUNC_NAME=$(notdir $(basename $<)) \
		-DTEST_FUNC_TXT="\"$(notdir $(basename $<))\"" \
		-T $(LINK_SCRIPT) $< -o $@
	@echo "  Size: $$($(RISCV_SIZE) $@ | tail -1)"

# Pattern rule: .elf -> .hex (Verilog hex format)
$(BUILD_DIR)/%.hex: $(BUILD_DIR)/%.elf
	@echo "Generating hex: $(notdir $@)"
	$(RISCV_OBJCOPY) -O verilog $< $@
	@# Also generate a disassembly for debugging
	$(RISCV_OBJDUMP) -d $< > $(BUILD_DIR)/$(basename $(notdir $@)).dis
	@echo "  Hex words: $$(wc -l < $@)"

# =============================================================================
# Individual test targets: make test_<name>
# =============================================================================
define TEST_TARGET
test_$(1): | $(BUILD_DIR)
	$$(MAKE) $(BUILD_DIR)/$(1).hex LINK_SCRIPT=$(LINK_SCRIPT)
	@echo "Test '$(1)' compiled: $(BUILD_DIR)/$(1).hex"
endef

$(foreach name,$(TEST_NAMES),$(eval $(call TEST_TARGET,$(name))))

# =============================================================================
# list - List all available tests
# =============================================================================
list:
	@echo "Available tests:"
	@echo "-------------------------------------------------------------------"
	@for name in $(TEST_NAMES); do \
		printf "  %-15s (make test_%s)\n" $$name $$name; \
	done
	@echo "-------------------------------------------------------------------"
	@echo "Total: $(words $(TEST_NAMES)) tests"
	@echo ""
	@echo "Compile all: make all"
	@echo "Clean:       make clean"

# =============================================================================
# copy-tests - Copy reference tests to local directory
# =============================================================================
copy-tests:
	@echo "Copying test files from picorv32 reference..."
	@if [ -d "$(PICORV32_TESTS)" ]; then \
		cp -n $(PICORV32_TESTS)/*.S $(TESTS_DIR)/ 2>/dev/null; \
		cp -n $(PICORV32_TESTS)/riscv_test.h $(TESTS_DIR)/ 2>/dev/null; \
		cp -n $(PICORV32_TESTS)/test_macros.h $(TESTS_DIR)/ 2>/dev/null; \
		echo "Copied test files to $(TESTS_DIR)"; \
	else \
		echo "ERROR: picorv32 tests directory not found: $(PICORV32_TESTS)"; \
		exit 1; \
	fi

# =============================================================================
# help - Show usage
# =============================================================================
help:
	@echo "==================================================================="
	@echo " RVP Test Firmware Compilation"
	@echo "==================================================================="
	@echo ""
	@echo "Targets:"
	@echo "  all          Compile all tests"
	@echo "  test_<name>  Compile a single test (e.g., make test_add)"
	@echo "  list         List all available tests"
	@echo "  copy-tests   Copy reference tests from picorv32"
	@echo "  clean        Remove build artifacts"
	@echo "  help         Show this help"
	@echo ""
	@echo "Variables:"
	@echo "  ARCH         Target architecture (default: $(ARCH))"
	@echo "  RISCV_PREFIX Toolchain prefix (default: $(RISCV_PREFIX))"
	@echo "  MEM_SIZE     Memory size in words (default: $(MEM_SIZE))"
	@echo ""
	@echo "Output:"
	@echo "  build/*.hex        - Verilog hex files (for $readmemh)"
	@echo "  build/*.elf        - ELF executables"
	@echo "  build/*.dis        - Disassembly listings"
	@echo "==================================================================="

# =============================================================================
# clean - Remove build artifacts
# =============================================================================
clean:
	@echo "Cleaning test build artifacts..."
	rm -rf $(BUILD_DIR)
	@echo "Done."
