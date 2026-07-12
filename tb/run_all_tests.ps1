# =============================================================================
# run_all_tests.ps1 - RVP Regression Test Suite
# =============================================================================
# Usage:  .\tb\run_all_tests.ps1
# Steps:  1. Generate hex files (via Python assembler)
#         2. Compile RTL + run functional tests (10 modules)
#         3. Run performance benchmark (6 benchmarks, CPI measurement)
# =============================================================================

param(
    [string]$ModelSim = "C:\modeltech64_10.7\win64"
)

$ms = $ModelSim
$vlog = "$ms\vlog.exe"
$vsim = "$ms\vsim.exe"

# Use junction link to avoid non-ASCII path issues
$projRoot = "C:\rvp_proj"
$tbDir = "$projRoot\tb"
$hexDir = "$projRoot\sw\tests"

$rtlPkg = "$projRoot\rtl\rvp_pkg.sv"
$rtlCore = @(
    "$projRoot\rtl\core\rvp_alu.sv",
    "$projRoot\rtl\core\rvp_register_file.sv",
    "$projRoot\rtl\core\rvp_imm_generator.sv",
    "$projRoot\rtl\core\rvp_decoder.sv",
    "$projRoot\rtl\core\rvp_branch_unit.sv",
    "$projRoot\rtl\core\rvp_instr_mem.sv",
    "$projRoot\rtl\core\rvp_data_mem.sv",
    "$projRoot\rtl\core\rvp_multdiv.sv"
)
$rtlCache = @(
    "$projRoot\rtl\cache\rvp_icache_pmru8.sv"
)
$rtlPipe = @(
    "$projRoot\rtl\core\rvp_pipeline_regs.sv",
    "$projRoot\rtl\core\rvp_forward_unit.sv",
    "$projRoot\rtl\core\rvp_hazard_unit.sv",
    "$projRoot\rtl\core\rvp_core_pipeline.sv"
)
$rtlPeriph = @(
    "$projRoot\rtl\periph\rvp_uart.sv",
    "$projRoot\rtl\periph\rvp_gpio.sv",
    "$projRoot\rtl\periph\rvp_timer.sv",
    "$projRoot\rtl\periph\rvp_piano.sv"
)
$rtlSocTop = "$projRoot\rtl\rvp_soc.sv"

# Common RTL sets
$rtlPipelineAll = @($rtlPkg) + $rtlCore + $rtlCache + $rtlPipe
$rtlSocAll = $rtlPipelineAll + $rtlPeriph + @($rtlSocTop)

# Test definitions
$tests = @(
    @{ Name="ALU";              Src="tb_alu.sv";            Rtl=@($rtlPkg)+@($rtlCore[0]) },
    @{ Name="Register File";    Src="tb_register_file.sv";  Rtl=@($rtlPkg)+@($rtlCore[1]) },
    @{ Name="Imm Generator";    Src="tb_imm_generator.sv";  Rtl=@($rtlPkg)+@($rtlCore[2]) },
    @{ Name="Decoder";          Src="tb_decoder.sv";        Rtl=@($rtlPkg)+@($rtlCore[3]) },
    @{ Name="Branch Unit";      Src="tb_branch_unit.sv";    Rtl=@($rtlCore[4]) },
    @{ Name="MultDiv (M-ext)";  Src="tb_multdiv.sv";        Rtl=@($rtlPkg)+@($rtlCore[7]) },
    @{ Name="Single-Cycle CPU"; Src="tb_core_single.sv";    Rtl=@($rtlPkg)+$rtlCore+@("$projRoot\rtl\core\rvp_core_single.sv") },
    @{ Name="Pipeline CPU";     Src="tb_core_pipeline.sv";  Rtl=$rtlPipelineAll },
    @{ Name="RV32I Self-Check"; Src="tb_rv32ui_p_all.sv";   Rtl=$rtlPipelineAll },
    @{ Name="SoC Integration";  Src="tb_soc.sv";            Rtl=$rtlSocAll }
)

$totalPass = 0
$totalFail = 0

Write-Output ""
Write-Output "============================================================"
Write-Output " RVP Regression Test Suite"
Write-Output " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "============================================================"
Write-Output ""

# =============================================================================
# Step 1: Generate hex files for performance benchmarks
# =============================================================================
Write-Output "============================================================"
Write-Output " Step 1: Generate hex files (Python assembler)"
Write-Output "============================================================"
$assemblerScript = "$projRoot\sw\tests\rv_assembler.py"
if (Test-Path $assemblerScript) {
    & python $assemblerScript
    if ($LASTEXITCODE -eq 0) {
        Write-Output "  [OK] Hex files generated successfully"
    } else {
        Write-Output "  [WARN] Assembler returned error code $LASTEXITCODE"
    }
} else {
    Write-Output "  [SKIP] Assembler not found: $assemblerScript"
}

# Verify hex files exist
$hexFiles = @(
    "perf_matmul.hex", "perf_matmul_opt.hex",
    "perf_bubble.hex", "perf_bubble_opt.hex",
    "perf_fib.hex", "perf_fib_opt.hex"
)
$hexMissing = $false
foreach ($f in $hexFiles) {
    if (!(Test-Path "$hexDir\$f")) {
        Write-Output "  [MISSING] $f"
        $hexMissing = $true
    }
}
if (!$hexMissing) {
    Write-Output "  [OK] All 6 hex files present"
}
Write-Output ""

# =============================================================================
# Step 2: Functional regression tests (10 modules)
# =============================================================================
Write-Output "============================================================"
Write-Output " Step 2: Functional Regression Tests"
Write-Output "============================================================"
Write-Output ""

Set-Location $tbDir

foreach ($t in $tests) {
    # Recreate work library
    if (Test-Path work) { Remove-Item -Recurse -Force work }
    & "$ms\vlib.exe" work 2>&1 | Out-Null

    # Compile
    $compileArgs = @("-sv", "-work", "work") + $t.Rtl + $t.Src
    $compileOut = & $vlog @compileArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output "  [COMPILE FAIL] $($t.Name)"
        $totalFail++
        continue
    }

    # Run simulation
    $tbModule = $t.Src -replace '\.sv$',''
    $simOut = (& $vsim -c -do "run -all; quit -f" -lib work $tbModule 2>&1) | Out-String
    $result = ""

    # Check for load/design errors first
    if ($simOut -match "Error loading design") {
        $result = "FAILED"
    } elseif ($simOut -match "ALL PASSED") {
        $result = "PASSED"
    } elseif ($simOut -match "FAILED: \d+ / \d+ tests") {
        $result = "FAILED"
    } elseif ($simOut -match "RESULT: ALL PASSED") {
        $result = "PASSED"
    } elseif ($simOut -match "RESULT: FAILED") {
        $result = "FAILED"
    }

    # Extract test count if available
    $testCount = ""
    if ($simOut -match "ALL PASSED\s+\((\d+)\s*tests?\)") {
        $testCount = " ($($Matches[1]) tests)"
    } elseif ($simOut -match "RESULT: ALL PASSED\s+\(gp\s*=\s*(\d+)\)") {
        $testCount = " (gp=$($Matches[1]))"
    }

    if ($result -eq "PASSED") {
        Write-Output "  [ PASS ] $($t.Name)$testCount"
        $totalPass++
    } elseif ($result -eq "FAILED") {
        Write-Output "  [ FAIL ] $($t.Name)"
        $totalFail++
    } else {
        Write-Output "  [ ??  ] $($t.Name)  (no result)"
        $totalFail++
    }
}

Write-Output ""
Write-Output "============================================================"
Write-Output " Functional Summary: $totalPass passed, $totalFail failed, $($tests.Count) total"
Write-Output "============================================================"
Write-Output ""

# =============================================================================
# Step 3: Performance benchmark (tb_perf.sv, 6 benchmarks)
# =============================================================================
if (!$hexMissing) {
    Write-Output "============================================================"
    Write-Output " Step 3: Performance Benchmark (tb_perf.sv)"
    Write-Output "============================================================"

    # Switch to project root to run do script
    Set-Location $projRoot
    $env:HEX_DIR = $hexDir

    # Run and capture output
    $perfOut = (& $vsim -c -do "do tb/run_perf.do" 2>&1) | Out-String

    # Print the full benchmark output (lines with numeric data)
    $perfLines = $perfOut -split "`n"
    foreach ($line in $perfLines) {
        $trimmed = $line.Trim()
        # Show lines with benchmark data
        if ($trimmed -match "Benchmark:|Total Cycles|Instructions|Load-Use|Branch Flush|Branch/Jump|CPI|Stall Rate|Flush Rate|Branch Rate|PASS|FAIL|Halt Cycle|Data verification|Summary|MIPS|formula|HEX dir|Clock|Halt detect|Optimized|passed" -or
            $trimmed -match "^#?\s*(Benchmark:|Total Cycles|Instructions|Load-Use|Branch Flush|Branch/Jump|CPI|Stall Rate|Flush Rate|Branch Rate|PASS|FAIL|Halt Cycle|Data verification|Summary|MIPS|formula|HEX dir|Clock|Halt detect|Optimized|passed)") {
            # Strip leading "# " from ModelSim output
            $clean = $trimmed -replace "^#\s*", ""
            if ($clean.Length -gt 0) {
                Write-Output "  $clean"
            }
        }
    }

    Write-Output ""

    # Determine pass/fail
    $perfResult = ""
    $passCount = ""
    if ($perfOut -match "(\d+)/6 PASS") {
        $passCount = " ($($Matches[1])/6 verified)"
    }
    if ($perfOut -match "PASS:") {
        $perfResult = "PASS"
        $totalPass++
    } elseif ($perfOut -match "FAIL") {
        $perfResult = "FAIL"
        $totalFail++
    } else {
        $perfResult = "??"
        $totalFail++
    }

    Write-Output "  [ $perfResult ] Performance Benchmark$passCount"
    Write-Output ""
    Write-Output "============================================================"
    Write-Output " Final: $totalPass passed, $totalFail failed, $($tests.Count + 1) total"
    Write-Output "============================================================"
} else {
    Write-Output "[SKIP] Performance test: hex files missing."
    Write-Output "       Run: python sw\tests\rv_assembler.py"
}
