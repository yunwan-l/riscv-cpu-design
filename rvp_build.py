"""
rvp_build.py - RVP (RISC-V Pipeline) Build Script
===================================================
Python-based build system replacing Makefile for Windows compatibility.
Uses ModelSim for simulation.

Usage:
  py rvp_build.py sim                   # Run simulation (default config)
  py rvp_build.py sim -c phase3_icache_lru  # Specific config
  py rvp_build.py sim -f tb/tests/build/add.hex  # With firmware
  py rvp_build.py configs               # List all available configs
  py rvp_build.py wave                  # Open ModelSim GUI with waveforms
  py rvp_build.py clean                 # Clean build artifacts
  py rvp_build.py files                 # List RTL source files
  py rvp_build.py lint                  # Show config parameters
"""

import os
import sys
import subprocess
import argparse
import re
from pathlib import Path

# =============================================================================
# Configuration
# =============================================================================

PROJECT_ROOT = Path(__file__).parent.resolve()
RTL_DIR      = PROJECT_ROOT / "rtl"
CONFIG_DIR   = PROJECT_ROOT / "config"
TB_DIR       = PROJECT_ROOT / "tb"
BUILD_DIR    = PROJECT_ROOT / "build"
SIM_LIB_DIR  = BUILD_DIR / "sim" / "work"
SIM_LIB_NAME  = "work"  # Logical library name (must not contain path separators)

FILELIST     = CONFIG_DIR / "rvp_core.f"
CONFIGS_YAML = CONFIG_DIR / "rvp_configs.yaml"

# Defaults
DEFAULT_CONFIG   = "phase2_full_rv32i"
TB_MODULE        = "rvp_tb"
SIM_TOP          = "rvp_tb"

# ModelSim paths
MODELSIM_DIR = Path("C:/modeltech64_10.7/win64")
VLIB = MODELSIM_DIR / "vlib.exe"
VLOG = MODELSIM_DIR / "vlog.exe"
VSIM = MODELSIM_DIR / "vsim.exe"


def parse_config_yaml(config_name: str) -> list[str]:
    """Parse rvp_configs.yaml and return +define+ flags including all defaults."""
    # Default values for parameters not in YAML (from rvp_config.svh)
    config_params = []

    try:
        import yaml
        with open(CONFIGS_YAML, 'r') as f:
            configs = yaml.safe_load(f)
        cfg = configs.get(config_name)
        if not cfg:
            print(f"ERROR: Config '{config_name}' not found in {CONFIGS_YAML}")
            sys.exit(1)
        # Map YAML CamelCase keys to RVP_ UPPER_SNAKE_CASE macros
        KEY_MAP = {
            'RV32E':               'RVP_RV32E',
            'RV32M':               'RVP_RV32M',
            'RV32C':               'RVP_RV32C',
            'ICacheEnable':        'RVP_ICACHE_ENABLE',
            'DCacheEnable':        'RVP_DCACHE_ENABLE',
            'ICacheReplacePolicy': 'RVP_ICACHE_REPLACE_POLICY',
            'DCacheReplacePolicy': 'RVP_DCACHE_REPLACE_POLICY',
            'Forwarding':          'RVP_FORWARDING',
            'BranchPredict':       'RVP_BRANCH_PREDICT',
            'CacheStatsEnable':    'RVP_CACHE_STATS_ENABLE',
        }
        # Phase 2: no forwarding (stall-only hazard handling)
        # Remove RVP_FORWARDING define — let rvp_config.svh default to 0
        # The `ifdef RVP_FORWARDING check in Verilog will be FALSE,
        # so the forward unit is not instantiated, avoiding conflicts.
        for k, v in cfg.items():
            if k == 'Forwarding':
                continue  # Skip — use default from rvp_config.svh
            macro_name = KEY_MAP.get(k, f"RVP_{k}")
            config_params.append(f"+define+{macro_name}={v}")
    except ImportError:
        print("ERROR: PyYAML not installed. Run: pip install pyyaml")
        sys.exit(1)

    # Add all default macros from rvp_config.svh that aren't in the YAML
    # These are compile-time constants needed by all modules
    extra_defines = {
        'RVP_PIPELINE_STAGES': 5,
        'RVP_WRITEBACK_STAGE': 1,
        'RVP_BRANCH_TARGET_ALU': 0,
        'RVP_INSTR_MEM_SIZE': 32768,
        'RVP_DATA_MEM_SIZE': 32768,
        'RVP_ICACHE_SIZE_BYTES': 4096,
        'RVP_ICACHE_NUM_WAYS': 2,
        'RVP_ICACHE_LINE_SIZE': 64,
        'RVP_DCACHE_SIZE_BYTES': 4096,
        'RVP_DCACHE_NUM_WAYS': 2,
        'RVP_DCACHE_LINE_SIZE': 64,
        'RVP_UART_ENABLE': 1,
        'RVP_UART_BAUD': 115200,
        'RVP_GPIO_ENABLE': 1,
        'RVP_GPIO_WIDTH': 16,
        'RVP_DATA_WIDTH': 32,
        'RVP_ADDR_WIDTH': 32,
        'RVP_DEBUG': 0,
        'RVP_RVFI': 0,
    }
    for k, v in extra_defines.items():
        config_params.append(f"+define+{k}={v}")

    return config_params


def get_rtl_files() -> list[str]:
    """Parse rvp_core.f file list, return RTL source paths."""
    files = []
    with open(FILELIST, 'r') as f:
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if not line or line.startswith('//') or line.startswith('#'):
                continue
            # Resolve relative to project root
            fpath = (PROJECT_ROOT / line).resolve()
            if fpath.exists():
                files.append(str(fpath))
            else:
                print(f"WARNING: File not found: {fpath}")
    return files


def run_vlib():
    """Create ModelSim working library."""
    import shutil
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    # Delete old libs if they exist
    for d in [SIM_LIB_DIR, PROJECT_ROOT / SIM_LIB_NAME]:
        if d.exists():
            shutil.rmtree(d)
    # Create library in project root with logical name "work"
    # (vlib creates directory and registers mapping)
    subprocess.run([str(VLIB), SIM_LIB_NAME], check=False, cwd=str(PROJECT_ROOT))
    print(f"[OK] ModelSim library '{SIM_LIB_NAME}' created")


def run_vlog(config_params: list[str]):
    """Compile all RTL files with vlog."""
    rtl_files = get_rtl_files()
    tb_file = str((TB_DIR / f"{TB_MODULE}.sv").resolve())

    cmd = [
        str(VLOG),
        "-sv",                          # SystemVerilog
        "-work", SIM_LIB_NAME,
        "+define+RVP_CONFIG_SVH=1",
        f"+incdir+{CONFIG_DIR}",
    ] + config_params + rtl_files + [tb_file]

    print(f"[vlog] Compiling {len(rtl_files)} RTL files + testbench...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print("[vlog] COMPILATION FAILED:")
        # Print errors
        for line in result.stdout.split('\n') + result.stderr.split('\n'):
            if 'Error' in line or 'error' in line or '**' in line:
                print(f"  {line}")
        print(result.stdout[-3000:] if len(result.stdout) > 3000 else result.stdout)
        sys.exit(1)
    else:
        # Print summary only
        for line in result.stdout.split('\n'):
            if 'Errors:' in line or 'Warnings:' in line:
                print(f"  {line}")
        print("[OK] Compilation successful")


def run_vsim(firmware: str | None = None):
    """Run simulation in batch mode."""
    cmd = [
        str(VSIM),
        "-c",                           # Batch mode (no GUI)
        "-do", "onbreak {resume}; run -all; quit",
        f"work.{SIM_TOP}"
    ]

    if firmware:
        # Firmware path — passed as plusarg to simulation
        # Use absolute path, escaped for Windows (spaces)
        fw_path = str(Path(firmware).resolve())
        # Use +firmware=<path> format (matching $value$plusargs("firmware=%s", ...))
        cmd.append(f"+firmware={fw_path}")

    print(f"[vsim] Running simulation (top={SIM_TOP})...")
    result = subprocess.run(cmd, capture_output=False)


def cmd_configs():
    """List all available configurations."""
    print("=" * 60)
    print(" Available RVP Configurations")
    print("=" * 60)
    try:
        import yaml
        with open(CONFIGS_YAML, 'r') as f:
            configs = yaml.safe_load(f)
        for i, (name, cfg) in enumerate(configs.items(), 1):
            icache = "I$" if cfg.get('ICacheEnable') else "  "
            dcache = "D$" if cfg.get('DCacheEnable') else "  "
            fwd = "FWD" if cfg.get('Forwarding') else "   "
            print(f"  {name:<28} #{i}  {icache} {dcache} {fwd}")
    except ImportError:
        print("  ERROR: PyYAML not installed")
    print("=" * 60)
    print("Usage: py rvp_build.py sim -c <config_name>")


def cmd_sim(config: str, firmware: str | None = None):
    """Run full simulation flow."""
    print("=" * 60)
    print(" RVP Simulation")
    print("=" * 60)
    print(f" Config:     {config}")
    print(f" Top module: {SIM_TOP}")
    if firmware:
        print(f" Firmware:   {firmware}")

    config_params = parse_config_yaml(config)
    print(f" Defines:    {len(config_params)} parameters")
    print("=" * 60)

    run_vlib()
    run_vlog(config_params)
    print("=" * 60)
    run_vsim(firmware)
    print("=" * 60)
    print(" Simulation complete")
    print("=" * 60)


def cmd_wave(config: str):
    """Compile and open ModelSim GUI."""
    config_params = parse_config_yaml(config)

    run_vlib()
    run_vlog(config_params)

    # Launch GUI
    cmd = [
        str(VSIM),
        "-do", "add wave -r /*; run -all",
        f"work.{SIM_TOP}"
    ]
    print("[vsim] Launching ModelSim GUI...")
    subprocess.run(cmd)


def cmd_clean():
    """Remove build artifacts."""
    import shutil
    if BUILD_DIR.exists():
        shutil.rmtree(BUILD_DIR)
        print(f"[OK] Removed: {BUILD_DIR}")
    else:
        print("[OK] Build directory already clean")


def cmd_files():
    """List RTL source files."""
    files = get_rtl_files()
    print(f"RTL source files (from {FILELIST}):")
    print("-" * 60)
    for f in files:
        rel = Path(f).relative_to(PROJECT_ROOT)
        print(f"  {rel}")
    print("-" * 60)
    print(f"Total: {len(files)} files")


def cmd_show_config(config: str):
    """Show parsed config parameters."""
    print(f"Configuration: {config}")
    params = parse_config_yaml(config)
    for p in params:
        print(f"  {p}")


def main():
    parser = argparse.ArgumentParser(description="RVP Build System (Python)")
    sub = parser.add_subparsers(dest="command", help="Command")

    p_sim = sub.add_parser("sim", help="Run simulation")
    p_sim.add_argument("-c", "--config", default=DEFAULT_CONFIG, help=f"Config name (default: {DEFAULT_CONFIG})")
    p_sim.add_argument("-f", "--firmware", default=None, help="Firmware hex file path")

    p_wave = sub.add_parser("wave", help="Open ModelSim GUI with waveforms")
    p_wave.add_argument("-c", "--config", default=DEFAULT_CONFIG, help=f"Config name (default: {DEFAULT_CONFIG})")

    sub.add_parser("configs", help="List available configs")
    sub.add_parser("clean", help="Remove build artifacts")
    sub.add_parser("files", help="List RTL source files")

    p_show = sub.add_parser("show-config", help="Show parsed config parameters")
    p_show.add_argument("-c", "--config", default=DEFAULT_CONFIG, help=f"Config name (default: {DEFAULT_CONFIG})")

    args = parser.parse_args()

    if args.command == "sim":
        cmd_sim(args.config, args.firmware)
    elif args.command == "wave":
        cmd_wave(args.config)
    elif args.command == "configs":
        cmd_configs()
    elif args.command == "clean":
        cmd_clean()
    elif args.command == "files":
        cmd_files()
    elif args.command == "show-config":
        cmd_show_config(args.config)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
