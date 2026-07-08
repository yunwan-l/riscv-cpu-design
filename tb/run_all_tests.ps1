# =============================================================================
# run_all_tests.ps1 — RVP 一键回归测试脚本
# =============================================================================
# 用法：在项目根目录下执行 .\tb\run_all_tests.ps1
# 功能：编译所有 RTL，运行所有测试，汇总 PASS/FAIL
# =============================================================================

param(
    [string]$ModelSim = "C:\modeltech64_10.7\win64"
)

$ms = $ModelSim
$vlog = "$ms\vlog.exe"
$vsim = "$ms\vsim.exe"
# 使用 junction link 避免中文路径问题（C:\rvp_proj → d:\大学资料\北邮\课程\阶段式程序设计2）
$projRoot = "C:\rvp_proj"
$tbDir = "$projRoot\tb"
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
$rtlPipe = @(
    "$projRoot\rtl\core\rvp_pipeline_regs.sv",
    "$projRoot\rtl\core\rvp_forward_unit.sv",
    "$projRoot\rtl\core\rvp_hazard_unit.sv",
    "$projRoot\rtl\core\rvp_core_pipeline.sv"
)
$rtlPeriph = @(
    "$projRoot\rtl\periph\rvp_uart.sv",
    "$projRoot\rtl\periph\rvp_gpio.sv",
    "$projRoot\rtl\periph\rvp_timer.sv"
)
$rtlSocTop = "$projRoot\rtl\rvp_soc.sv"

# 测试定义：名称 → (源文件, 需要的RTL, 预期输出模式)
$tests = @(
    @{ Name="ALU";              Src="tb_alu.sv";            Rtl=@($rtlPkg)+@($rtlCore[0]);                                      Pattern="PASSED|FAILED" },
    @{ Name="Register File";    Src="tb_register_file.sv";  Rtl=@($rtlPkg)+@($rtlCore[1]);                                      Pattern="PASSED|FAILED" },
    @{ Name="Imm Generator";    Src="tb_imm_generator.sv";  Rtl=@($rtlPkg)+@($rtlCore[2]);                                      Pattern="PASSED|FAILED" },
    @{ Name="Decoder";          Src="tb_decoder.sv";        Rtl=@($rtlPkg)+@($rtlCore[3]);                                      Pattern="PASSED|FAILED" },
    @{ Name="Branch Unit";      Src="tb_branch_unit.sv";    Rtl=@($rtlCore[4]);                                                 Pattern="PASSED|FAILED" },
    @{ Name="MultDiv (M-ext)";  Src="tb_multdiv.sv";        Rtl=@($rtlPkg)+@($rtlCore[7]);                                      Pattern="PASSED|FAILED" },
    @{ Name="Single-Cycle CPU"; Src="tb_core_single.sv";    Rtl=@($rtlPkg)+$rtlCore+@("$projRoot\rtl\core\rvp_core_single.sv"); Pattern="PASSED|FAILED" },
    @{ Name="Pipeline CPU";     Src="tb_core_pipeline.sv";  Rtl=@($rtlPkg)+$rtlCore+$rtlPipe;                                   Pattern="PASSED|FAILED" },
    @{ Name="RV32I Self-Check"; Src="tb_rv32ui_p_all.sv";   Rtl=@($rtlPkg)+$rtlCore+$rtlPipe;                                   Pattern="RESULT.*PASSED|RESULT.*FAILED" },
    @{ Name="SoC Integration";  Src="tb_soc.sv";            Rtl=@($rtlPkg)+$rtlCore+$rtlPipe+$rtlPeriph+@($rtlSocTop);          Pattern="PASSED|FAILED" }
)

$totalPass = 0
$totalFail = 0

Write-Output ""
Write-Output "============================================================"
Write-Output " RVP Regression Test Suite"
Write-Output " $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "============================================================"
Write-Output ""

Set-Location $tbDir

foreach ($t in $tests) {
    # 重建 work 库
    if (Test-Path work) { Remove-Item -Recurse -Force work }
    & "$ms\vlib.exe" work 2>&1 | Out-Null

    # 编译
    $compileArgs = @("-sv", "-work", "work") + $t.Rtl + $t.Src
    $compileOut = & $vlog @compileArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Output "  [COMPILE FAIL] $($t.Name)"
        $totalFail++
        continue
    }

    # 运行
    $tbModule = $t.Src -replace '\.sv$',''
    $simOut = (& $vsim -c -do "run -all; quit -f" -lib work $tbModule 2>&1) | Out-String
    $result = ""
    if ($simOut -match "ALL PASSED") {
        $result = "PASSED"
    } elseif ($simOut -match "FAILED: \d+ / \d+ tests") {
        $result = "FAILED"
    } elseif ($simOut -match "RESULT: ALL PASSED") {
        $result = "PASSED"
    } elseif ($simOut -match "RESULT: FAILED") {
        $result = "FAILED"
    }

    if ($result -eq "PASSED") {
        Write-Output "  [ PASS ] $($t.Name)"
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
Write-Output " Summary: $totalPass passed, $totalFail failed, $($tests.Count) total"
Write-Output "============================================================"
Write-Output ""

# =============================================================================
# 性能测试（使用 run_perf.do，需要预先生成 hex 文件）
# =============================================================================
$hexDir = "$projRoot\sw\tests"
if (Test-Path "$hexDir\perf_matmul.hex") {
    Write-Output "============================================================"
    Write-Output " Performance Benchmark (tb_perf.sv)"
    Write-Output "============================================================"
    # 切回项目根目录运行 do 脚本
    Set-Location $projRoot
    $env:HEX_DIR = $hexDir
    $perfOut = (& $vsim -c -do "do tb/run_perf.do" 2>&1) | Out-String
    if ($perfOut -match "PASS.*所有") {
        Write-Output "  [ PASS ] Performance Benchmark (3/3 data verified)"
        $totalPass++
    } elseif ($perfOut -match "FAIL") {
        Write-Output "  [ FAIL ] Performance Benchmark"
        $totalFail++
    } else {
        Write-Output "  [ ??  ] Performance Benchmark (check output)"
    }
    Write-Output ""
    Write-Output "============================================================"
    Write-Output " Final: $totalPass passed, $totalFail failed, $($tests.Count + 1) total"
    Write-Output "============================================================"
} else {
    Write-Output "[SKIP] Performance test: hex files not found in $hexDir"
    Write-Output "       Run 'python sw\tests\rv_assembler.py' to generate hex files first."
}
