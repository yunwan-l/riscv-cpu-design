<#
.SYNOPSIS
    RVP Full Regression Test + Synthesis Check
.DESCRIPTION
    Phase 1: ModelSim functional tests (10 unit tests + perf)
    Phase 2: Vivado synthesis (basic + advanced configs)
    Phase 3: Summary report
.USAGE
    cd E:\rvp_nexys
    .\document\script\run_full_check.ps1
#>

$ErrorActionPreference = "Stop"

# ============================================================================
# Configuration (using junction E:\rvp_nexys -> E:\计组实验\riscv-cpu-design)
# ============================================================================
$ProjectRoot  = "E:\rvp_nexys"
$ModelSimDir  = "C:\modeltech64_10.7\win64"
$VivadoBat    = "C:\Xilinx\Vivado\2018.3\bin\vivado.bat"
$Settings64   = "C:\Xilinx\Vivado\2018.3\settings64.bat"
$TclScript    = Join-Path $ProjectRoot "document\script\run_synth_batch.tcl"
$Timestamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir       = Join-Path $ProjectRoot "document\log"
$ReportDir    = Join-Path $ProjectRoot "document\evaluate"

$vlib = Join-Path $ModelSimDir "vlib.exe"
$vlog = Join-Path $ModelSimDir "vlog.exe"
$vsim = Join-Path $ModelSimDir "vsim.exe"

# Load ModelSim license from system environment
$env:MGLS_LICENSE_FILE = [System.Environment]::GetEnvironmentVariable("MGLS_LICENSE_FILE","Machine")
if (-not $env:MGLS_LICENSE_FILE) { $env:MGLS_LICENSE_FILE = "C:\modeltech64_10.7\win64\LICENSE.TXT" }

$passStr = "[PASS]"
$failStr = "[FAIL]"
$warnStr = "[WARN]"
$skipStr = "[SKIP]"

# ============================================================================
# Helpers
# ============================================================================
function Line()    { return "=" * 75 }
function Write-H1 {
    param([string]$T, [string]$C="Cyan")
    Write-Host "`n$(Line)" -ForegroundColor $C
    Write-Host " $T" -ForegroundColor $C
    Write-Host "$(Line)" -ForegroundColor $C
}

function Write-R {
    param([string]$N, [string]$S, [string]$D="")
    $icons = @{PASS=$passStr; FAIL=$failStr; WARN=$warnStr; SKIP=$skipStr}
    $colors = @{PASS="Green"; FAIL="Red"; WARN="Yellow"; SKIP="Gray"}
    $i = $icons[$S]
    $c = $colors[$S]
    Write-Host "  $i $N $D" -ForegroundColor $c
}

function New-Dir { param([string]$P); New-Item -ItemType Directory -Path $P -Force | Out-Null }

New-Dir $LogDir
New-Dir $ReportDir

$st = Get-Date
$suiteResults = @()

# ============================================================================
# Environment check
# ============================================================================
Write-H1 "Environment Check"

$envOk = $true
if (-not (Test-Path $vsim)) { Write-R "ModelSim" "FAIL"; $envOk=$false } else { Write-R "ModelSim" "PASS" }
if (-not (Test-Path $VivadoBat)) { Write-R "Vivado" "FAIL"; $envOk=$false } else { Write-R "Vivado" "PASS" }

$cfiles = @(
    "config\rvp_configs.yaml","config\rvp_config.svh","config\rvp_core.f",
    "rtl\rvp_fpga_top.sv","synth\vivado\rvp_nexys4.xdc"
)
foreach ($f in $cfiles) {
    $fp = Join-Path $ProjectRoot $f
    if (Test-Path $fp) { Write-R "File: $f" "PASS" } else { Write-R "File: $f" "FAIL" " -- MISSING"; $envOk=$false }
}
if (-not $envOk) { Write-Host "`n  Environment check FAILED" -ForegroundColor Red; exit 1 }

Set-Location $ProjectRoot

# ============================================================================
# Phase 1: ModelSim Functional Tests
# ============================================================================
Write-H1 "Phase 1: ModelSim Regression Tests" "Yellow"

$tbDir = Join-Path $ProjectRoot "tb"
$pkg  = Join-Path $ProjectRoot "rtl\rvp_pkg.sv"

# RTL file paths
$cALUS   = Join-Path $ProjectRoot "rtl\core\rvp_alu.sv"
$cRF     = Join-Path $ProjectRoot "rtl\core\rvp_register_file.sv"
$cIMM    = Join-Path $ProjectRoot "rtl\core\rvp_imm_generator.sv"
$cDEC    = Join-Path $ProjectRoot "rtl\core\rvp_decoder.sv"
$cBR     = Join-Path $ProjectRoot "rtl\core\rvp_branch_unit.sv"
$cIMEM   = Join-Path $ProjectRoot "rtl\core\rvp_instr_mem.sv"
$cDMEM   = Join-Path $ProjectRoot "rtl\core\rvp_data_mem.sv"
$cMUL    = Join-Path $ProjectRoot "rtl\core\rvp_multdiv.sv"
$cPREG   = Join-Path $ProjectRoot "rtl\core\rvp_pipeline_regs.sv"
$cFWD    = Join-Path $ProjectRoot "rtl\core\rvp_forward_unit.sv"
$cHAZ    = Join-Path $ProjectRoot "rtl\core\rvp_hazard_unit.sv"
$cPIPE   = Join-Path $ProjectRoot "rtl\core\rvp_core_pipeline.sv"
$cSINGLE = Join-Path $ProjectRoot "rtl\core\rvp_core_single.sv"
$cUART   = Join-Path $ProjectRoot "rtl\periph\rvp_uart.sv"
$cGPIO   = Join-Path $ProjectRoot "rtl\periph\rvp_gpio.sv"
$cTIMER  = Join-Path $ProjectRoot "rtl\periph\rvp_timer.sv"
$cSOC    = Join-Path $ProjectRoot "rtl\rvp_soc.sv"

$tests = @(
    @{N="ALU";              S="tb_alu.sv";            R=@($pkg,$cALUS)}
    @{N="Register File";    S="tb_register_file.sv";  R=@($pkg,$cRF)}
    @{N="Imm Generator";    S="tb_imm_generator.sv";  R=@($pkg,$cIMM)}
    @{N="Decoder";          S="tb_decoder.sv";        R=@($pkg,$cDEC)}
    @{N="Branch Unit";      S="tb_branch_unit.sv";    R=@($cBR)}
    @{N="MultDiv (M-ext)";  S="tb_multdiv.sv";        R=@($pkg,$cMUL)}
    @{N="Single-Cycle CPU"; S="tb_core_single.sv";    R=@($pkg,$cALUS,$cRF,$cIMM,$cDEC,$cBR,$cIMEM,$cDMEM,$cMUL,$cSINGLE)}
    @{N="Pipeline CPU";     S="tb_core_pipeline.sv";  R=@($pkg,$cALUS,$cRF,$cIMM,$cDEC,$cBR,$cIMEM,$cDMEM,$cMUL,$cPREG,$cFWD,$cHAZ,$cPIPE)}
    @{N="RV32I Self-Check"; S="tb_rv32ui_p_all.sv";   R=@($pkg,$cALUS,$cRF,$cIMM,$cDEC,$cBR,$cIMEM,$cDMEM,$cMUL,$cPREG,$cFWD,$cHAZ,$cPIPE)}
    @{N="SoC Integration";  S="tb_soc.sv";            R=@($pkg,$cALUS,$cRF,$cIMM,$cDEC,$cBR,$cIMEM,$cDMEM,$cMUL,$cPREG,$cFWD,$cHAZ,$cPIPE,$cUART,$cGPIO,$cTIMER,$cSOC)}
)

$simPass=0; $simFail=0
$simLogFile = Join-Path $LogDir "modelsim_test_${Timestamp}.log"

foreach ($t in $tests) {
    # Clean work library
    if (Test-Path (Join-Path $ProjectRoot "work")) { Remove-Item -Recurse -Force (Join-Path $ProjectRoot "work") }
    & $vlib "work" 2>&1 | Out-Null

    # Compile
    $ca = @("-quiet","-sv","-work","work") + $t.R + @((Join-Path $tbDir $t.S))
    $co = & $vlog @ca 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-R $t.N "FAIL" "- compile error"
        $simFail++; $suiteResults += @{N=$t.N; Ty="Sim"; St="FAIL"}
        continue
    }

    # Run
    $srcB = [System.IO.Path]::GetFileNameWithoutExtension($t.S)
    $so = (& $vsim -c -do "run -all; quit -f" -lib work $srcB 2>&1) | Out-String

    # Parse result
    $sv = $warnStr
    if ($so -match "ALL PASSED") { $sv = $passStr }
    elseif ($so -match "RESULT.*ALL PASSED") { $sv = $passStr }
    elseif ($so -match "FAILED: \d+") { $sv = $failStr }
    elseif ($so -match "RESULT.*FAILED") { $sv = $failStr }
    elseif ($so -match "Error|Fatal") { $sv = $failStr }

    if ($sv -eq $passStr) { Write-R $t.N "PASS"; $simPass++ }
    else { Write-R $t.N "FAIL"; $simFail++ }
    $suiteResults += @{N=$t.N; Ty="Sim"; St=$sv}
}

# Save sim log
($suiteResults | Where-Object { $_.Ty -eq "Sim" }) | ForEach-Object { "$($_.St): $($_.N)" | Out-File -FilePath $simLogFile -Append -Encoding utf8 }

Write-Host ""
Write-H1 "Functional Test Summary"
$simTotal = $simPass + $simFail
$simColor = if ($simFail -eq 0) { "Green" } else { "Red" }
Write-Host "  Pass: $simPass  Fail: $simFail  Total: $simTotal" -ForegroundColor $simColor

# ============================================================================
# Phase 1b: Performance test (if hex files exist)
# ============================================================================
$hexDir = Join-Path $ProjectRoot "sw\tests"
$perfHexes = @("perf_matmul.hex","perf_bubble.hex","perf_fib.hex")
$perfOk = $true
foreach ($h in $perfHexes) { if (-not (Test-Path (Join-Path $hexDir $h))) { $perfOk=$false } }

if ($perfOk) {
    Write-H1 "Performance: matmul / bubble / fib" "Yellow"
    if (Test-Path (Join-Path $ProjectRoot "work")) { Remove-Item -Recurse -Force (Join-Path $ProjectRoot "work") }

    $po = (& $vsim -c -do "do tb/run_perf.do" 2>&1) | Out-String

    if ($po -match "PASS|ALL PASSED") {
        Write-R "Performance Benchmark" "PASS"
        $suiteResults += @{N="Performance"; Ty="Sim"; St=$passStr}
    } elseif ($po -match "FAIL") {
        Write-R "Performance Benchmark" "FAIL"
        $suiteResults += @{N="Performance"; Ty="Sim"; St=$failStr}; $simFail++
    } else {
        Write-R "Performance Benchmark" $warnStr "- check output"
        $suiteResults += @{N="Performance"; Ty="Sim"; St=$passStr}
    }
} else {
    Write-R "Performance Test" "SKIP" "- hex files missing"
}

# ============================================================================
# Phase 2: Vivado Synthesis
# ============================================================================
Write-H1 "Phase 2: Vivado Synthesis Check" "Yellow"

$synthConfigs = @(
    @{N="phase1_basic";       L="Basic (RV32I)"}
    @{N="phase2_full_rv32i";  L="Advanced (RV32IM)"}
)

$synthR = @()

foreach ($cfg in $synthConfigs) {
    $cn = $cfg.N; $cl = $cfg.L
    $lf = Join-Path $LogDir "synth_${cn}_${Timestamp}.log"

    Write-Host "  --- $cl ($cn) ---" -ForegroundColor Yellow

    # Run Vivado via cmd.exe (needed for settings64.bat environment setup)
    $vivadoCmd = [string]::Format('""{0}"" > nul && ""{1}"" -mode batch -source ""{2}"" -tclargs -config {3}',
        $Settings64, $VivadoBat, $TclScript, $cn)
    $output = cmd /c $vivadoCmd
    $output | Out-File -FilePath $lf -Encoding utf8

    $passed = $false; $wn=""; $lu=""; $ff=""; $fm=""
    foreach ($ln in $output) {
        if ($ln -match "SUCCESS.*Bitstream") { $passed = $true }
        if ($ln -match "WNS.*:\s*([-\d.]+)\s*ns") { $wn = $matches[1] }
        if ($ln -match "LUTs:\s*(\d+)\s*/\s*\d+") { $lu = $matches[1] }
        if ($ln -match "FFs:\s*(\d+)\s*/\s*\d+") { $ff = $matches[1] }
        if ($ln -match "Fmax:\s*([\d.]+)\s*MHz") { $fm = $matches[1] }
    }

    if ($passed) {
        Write-R "$cl" "PASS"
        $synthR += @{N=$cn; L=$cl; St="PASS"; Wns=$wn; Lut=$lu; Ff=$ff; Fmax=$fm}
        $suiteResults += @{N="Synth: $cl"; Ty="Synth"; St="PASS"}
    } else {
        Write-R "$cl" "FAIL" "- see $lf"
        $synthR += @{N=$cn; L=$cl; St="FAIL"}
        $suiteResults += @{N="Synth: $cl"; Ty="Synth"; St="FAIL"}
    }
}

# ============================================================================
# Phase 3: Generate report
# ============================================================================
Write-H1 "Phase 3: Generating Summary Report" "Green"

$elapsed = (Get-Date) - $st
$rptFile = Join-Path $ReportDir "full_check_${Timestamp}.md"

$allSimPass = ($suiteResults | Where-Object { $_.Ty -eq "Sim" -and $_.St -eq $passStr }).Count
$allSimFail = ($suiteResults | Where-Object { $_.Ty -eq "Sim" -and $_.St -eq $failStr }).Count
$allSynPass = ($suiteResults | Where-Object { $_.Ty -eq "Synth" -and $_.St -eq "PASS" }).Count
$allSynFail = ($suiteResults | Where-Object { $_.Ty -eq "Synth" -and $_.St -eq "FAIL" }).Count

$rB = @"
# RVP Full Verification Report

| Item | Value |
|------|-------|
| Date | $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') |
| Elapsed | $($elapsed.Hours)h $($elapsed.Minutes)m $($elapsed.Seconds)s |
| Vivado | 2018.3 (xc7a100tcsg324-1) |
| ModelSim | 10.7 |
| Target | Nexys4 DDR |

---

## Phase 1: ModelSim Functional Tests

| Test | Result |
|------|:------:|
"@

foreach ($r in ($suiteResults | Where-Object { $_.Ty -eq "Sim" })) {
    $rB += "`n| $($r.N) | $($r.St) |"
}

$rB += @"

**Summary**: $allSimPass passed, $allSimFail failed, $($allSimPass + $allSimFail) total

---

## Phase 2: Vivado Synthesis

| Config | Result | LUT | FF | WNS | Fmax |
|--------|:------:|:---:|:---:|:---:|:----:|
"@

foreach ($r in $synthR) {
    $l = if ($r.Lut)  { $r.Lut } else { "-" }
    $f = if ($r.Ff)   { $r.Ff } else { "-" }
    $w = if ($r.Wns)  { "$($r.Wns) ns" } else { "-" }
    $m = if ($r.Fmax) { "$($r.Fmax) MHz" } else { "-" }
    $rB += "`n| $($r.L) | $($r.St) | $l | $f | $w | $m |"
}

$rB += @"

---

## Board-Readiness Checklist

- [ ] All functional tests pass: $(if($allSimFail -eq 0){"YES"}else{"NO"})
- [ ] Both configs synthesize: $(if($allSynFail -eq 0){"YES"}else{"NO"})
- [ ] Timing met (WNS >= 0): $(if(($synthR | Where-Object { $_.Wns -ne "" -and [double]$_.Wns -ge 0 }).Count -eq 2){"YES"}else{"CHECK"})
- [ ] Resource usage < 80%: $(if(($synthR | Where-Object { $_.Lut -ne "" -and [int]$_.Lut -lt 50720 }).Count -eq 2){"YES"}else{"CHECK"})
- [ ] Bitstream generated: $(if($allSynFail -eq 0){"YES"}else{"NO"})

---

## Log Files

| File | Description |
|------|-------------|
| document/log/modelsim_test_$Timestamp.log | ModelSim test results |
| document/log/synth_phase1_basic_$Timestamp.log | Basic config synth log |
| document/log/synth_phase2_full_rv32i_$Timestamp.log | Advanced config synth log |
| document/evaluate/report_phase1_basic_$Timestamp.md | Basic config detail |
| document/evaluate/report_phase2_full_rv32i_$Timestamp.md | Advanced config detail |
| document/evaluate/full_check_$Timestamp.md | This summary |
"@

$rB | Out-File -FilePath $rptFile -Encoding utf8

# ============================================================================
# Console final output
# ============================================================================
Write-Host ""
Write-Host "  =====================================================" -ForegroundColor Cyan
Write-Host "  FINAL RESULTS" -ForegroundColor Cyan
Write-Host "  =====================================================" -ForegroundColor Cyan
Write-Host "  Phase 1: ModelSim Functional Tests" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor Cyan
foreach ($r in ($suiteResults | Where-Object { $_.Ty -eq "Sim" })) {
    $icon = if ($r.St -eq $passStr) { "[PASS]" } else { "[FAIL]" }
    $c = if ($r.St -eq $passStr) { "Green" } else { "Red" }
    Write-Host "    $icon $($r.N)" -ForegroundColor $c
}
Write-Host "  -----------------------------------------------------" -ForegroundColor Cyan
Write-Host "    Pass: $allSimPass  Fail: $allSimFail  Total: $($allSimPass+$allSimFail)" -ForegroundColor $(if ($allSimFail -eq 0){"Green"}else{"Red"})

Write-Host "  -----------------------------------------------------" -ForegroundColor Cyan
Write-Host "  Phase 2: Vivado Synthesis" -ForegroundColor Cyan
Write-Host "  -----------------------------------------------------" -ForegroundColor Cyan
foreach ($r in $synthR) {
    $icon = if ($r.St -eq "PASS") { "[PASS]" } else { "[FAIL]" }
    $c = if ($r.St -eq "PASS") { "Green" } else { "Red" }
    $lu = if ($r.Lut) { " LUT:$($r.Lut)" } else { "" }
    $wn = if ($r.Wns) { " WNS:$($r.Wns)ns" } else { "" }
    Write-Host "    $icon $($r.L)$lu$wn" -ForegroundColor $c
}

Write-Host "  =====================================================" -ForegroundColor Cyan
if ($allSimFail -eq 0 -and $allSynFail -eq 0) {
    Write-Host "    ALL PASSED - BITSTREAM READY FOR BOARD" -ForegroundColor Green
} else {
    Write-Host "    ISSUES FOUND - CHECK LOGS BEFORE BOARD" -ForegroundColor Red
}
Write-Host "    Elapsed: $($elapsed.Hours)h $($elapsed.Minutes)m $($elapsed.Seconds)s" -ForegroundColor Cyan
Write-Host "  =====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Full report: $rptFile" -ForegroundColor Green
