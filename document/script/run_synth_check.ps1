<#
.SYNOPSIS
    RVP 综合安全检查脚本
.DESCRIPTION
    自动运行基础 (phase1_basic) 和进阶 (phase2_full_rv32i) 的
    Vivado 综合 + 实现 + Bitstream 生成，保存日志和报告。
    参考: Digilent Nexys4 DDR 官方指导手册 + 项目 XDC 约束
.USAGE
    cd E:\计组实验\riscv-cpu-design
    .\document\script\run_synth_check.ps1
#>

$ErrorActionPreference = "Stop"
$ProjectRoot = "E:\计组实验\riscv-cpu-design"
$VivadoBat = "C:\Xilinx\Vivado\2018.3\bin\vivado.bat"
$Settings64 = "C:\Xilinx\Vivado\2018.3\settings64.bat"
$ScriptFile = Join-Path $ProjectRoot "document\script\run_synth_batch.tcl"
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogDir = Join-Path $ProjectRoot "document\log"
$ReportDir = Join-Path $ProjectRoot "document\evaluate"

# ============================================================================
# 打印标题
# ============================================================================
function Write-Header {
    param([string]$Title)
    $line = "=" * 75
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "$line" -ForegroundColor Cyan
}

# ============================================================================
# 运行一轮综合
# ============================================================================
function Run-Synthesis {
    param(
        [string]$ConfigName,
        [string]$Label
    )

    $logFile = Join-Path $LogDir "synth_${ConfigName}_${Timestamp}.log"
    $tempLog = Join-Path $env:TEMP "vivado_${ConfigName}.log"

    Write-Host "`n  ┌─ $Label" -ForegroundColor Yellow
    Write-Host "  ├─ Config : $ConfigName" -ForegroundColor Yellow
    Write-Host "  ├─ Log    : $logFile" -ForegroundColor Yellow
    Write-Host "  └─ Doing..." -ForegroundColor Yellow

    # 构建 Vivado 命令
    $cmd = "`"$Settings64`" && `"$VivadoBat`" -mode batch -source `"$ScriptFile`" -tclargs -config $ConfigName 2>&1"

    # 用 cmd /c 来保证 settings64.bat 的环境变量有效
    $output = cmd /c "`"$Settings64`" >nul && `"$VivadoBat`" -mode batch -source `"$ScriptFile`" -tclargs -config $ConfigName 2>&1"

    # 保存原始日志
    $output | Out-File -FilePath $logFile -Encoding utf8

    # 分析结果
    $passed = $false
    $bitstreamPath = ""
    $wnsValue = ""
    $lutUsed = ""
    $ffUsed = ""
    $fmaxValue = ""

    foreach ($line in $output) {
        if ($line -match "SUCCESS.*Bitstream generated") { $passed = $true }
        if ($line -match "Path:\s*(.+\.bit)") { $bitstreamPath = $matches[1] }
        if ($line -match "WNS.*: (.+) ns") { $wnsValue = $matches[1] }
        if ($line -match "LUTs:\s*(\d+)\s*/\s*\d+") { $lutUsed = $matches[1] }
        if ($line -match "FFs:\s*(\d+)\s*/\s*\d+") { $ffUsed = $matches[1] }
        if ($line -match "Fmax:\s*([\d.]+)\s*MHz") { $fmaxValue = $matches[1] }
    }

    if ($passed) {
        Write-Host "  ✅ $Label - PASS" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $Label - FAIL (bitstream not generated)" -ForegroundColor Red
        # 打印错误信息
        $errorLines = $output | Where-Object { $_ -match "ERROR|CRITICAL WARNING|FAIL" }
        if ($errorLines) {
            Write-Host "  Errors found:" -ForegroundColor Red
            $errorLines | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        }
    }

    return [PSCustomObject]@{
        Config         = $ConfigName
        Label          = $Label
        Passed         = $passed
        WNS            = $wnsValue
        LUT            = $lutUsed
        FF             = $ffUsed
        Fmax           = $fmaxValue
        BitstreamPath  = $bitstreamPath
        LogFile        = $logFile
    }
}

# ============================================================================
# 主流程
# ============================================================================
Clear-Host
Write-Header "RVP 综合安全检查 | 2026-07-08"
Write-Host "  Vivado: $VivadoBat" -ForegroundColor Gray
Write-Host "  项目根: $ProjectRoot" -ForegroundColor Gray
Write-Host "  脚本:   $ScriptFile" -ForegroundColor Gray
Write-Host "  日志:   $LogDir" -ForegroundColor Gray

# 创建目录
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# ============================================================================
# 检查 Vivado
# ============================================================================
Write-Host "`n[检查] Vivado 2018.3..." -ForegroundColor Gray
if (-not (Test-Path $VivadoBat)) {
    Write-Host "  ❌ Vivado not found at: $VivadoBat" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $Settings64)) {
    Write-Host "  ❌ settings64.bat not found at: $Settings64" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ Vivado 就绪" -ForegroundColor Green

# ============================================================================
# 检查项目文件
# ============================================================================
Write-Host "`n[检查] 项目文件..." -ForegroundColor Gray
$checkFiles = @(
    "$ProjectRoot\config\rvp_configs.yaml",
    "$ProjectRoot\config\rvp_config.svh",
    "$ProjectRoot\config\rvp_core.f",
    "$ProjectRoot\rtl\rvp_fpga_top.sv",
    "$ProjectRoot\synth\vivado\rvp_nexys4.xdc"
)
$allOk = $true
foreach ($f in $checkFiles) {
    if (Test-Path $f) {
        Write-Host "  ✅ $f" -ForegroundColor DarkGray
    } else {
        Write-Host "  ❌ MISSING: $f" -ForegroundColor Red
        $allOk = $false
    }
}
if (-not $allOk) {
    Write-Host "  ❌ 项目文件缺失，请检查路径" -ForegroundColor Red
    exit 1
}
Write-Host "  ✅ 项目文件完整" -ForegroundColor Green

# ============================================================================
# 运行综合（基础配置）
# ============================================================================
Write-Header "第一阶段：基础配置 (phase1_basic)"
Write-Host "  RV32I 最小子集 | 无 M 扩展 | 无 Cache | 无前递 | 无分支预测" -ForegroundColor Gray
$result1 = Run-Synthesis -ConfigName "phase1_basic" -Label "基础配置"

# ============================================================================
# 运行综合（进阶配置）
# ============================================================================
Write-Header "第二阶段：进阶配置 (phase2_full_rv32i)"
Write-Host "  RV32I + M 扩展 | 无 Cache | 无前递 | 无分支预测" -ForegroundColor Gray
$result2 = Run-Synthesis -ConfigName "phase2_full_rv32i" -Label "进阶配置"

# ============================================================================
# 汇总报告
# ============================================================================
Write-Header "综合检查完成 — 结果汇总"

$summaryFile = Join-Path $ReportDir "synth_summary_${Timestamp}.md"

$summary = @"
# 综合安全检查报告

| 项目 | 值 |
|------|------|
| 日期 | $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") |
| Vivado | 2018.3 |
| 目标板 | Nexys4 DDR (xc7a100tcsg324-1) |
| 参考 | Digilent Nexys-4-DDR-Master.xdc |
| 时钟 | 100MHz 晶振 → 50MHz SoC (T 触发器二分频) |

## 两轮对比

| 指标 | 基础配置 (phase1_basic) | 进阶配置 (phase2_full_rv32i) |
|------|:---:|:---:|
| **ISA** | RV32I（无 M） | RV32I + M 扩展 |
| **Cache** | 无 | 无 |
| **前递/分支预测** | 关闭 | 关闭 |
| **结果** | $(if($result1.Passed){"✅ PASS"}else{"❌ FAIL"}) | $(if($result2.Passed){"✅ PASS"}else{"❌ FAIL"}) |
| **LUT** | $($result1.LUT) / 63400 | $($result2.LUT) / 63400 |
| **FF** | $($result1.FF) / 126800 | $($result2.FF) / 126800 |
| **WNS (Post-Impl)** | $($result1.WNS) ns | $($result2.WNS) ns |
| **Fmax 预估** | $($result1.Fmax) MHz | $($result2.Fmax) MHz |

## 日志文件

| 配置 | 日志路径 |
|------|----------|
| 基础 | $(Split-Path $result1.LogFile -Leaf) |
| 进阶 | $(Split-Path $result2.LogFile -Leaf) |

## 上板前检查清单

- [ ] 两轮综合均成功 → $(if($result1.Passed -and $result2.Passed){"✅"}else{"❌"})
- [ ] 时序收敛 (WNS ≥ 0) → $(if($result1.WNS -ge 0 -and $result2.WNS -ge 0){"✅"}else{"⚠️ 需检查"})
- [ ] 资源使用率 < 80% → $(if([int]$result1.LUT -lt 50720 -and [int]$result2.LUT -lt 50720){"✅"}else{"⚠️ 资源偏高"})
- [ ] Bitstream 成功生成 → $(if($result1.Passed -and $result2.Passed){"✅"}else{"❌"})
"@

# 写入汇总报告
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$summary | Out-File -FilePath $summaryFile -Encoding utf8

# 控制台输出
Write-Host ""
Write-Host "  ┌──────────────┬────────────┬────────────┐" -ForegroundColor Cyan
Write-Host "  │ 配置         │ 基础配置   │ 进阶配置   │" -ForegroundColor Cyan
Write-Host "  ├──────────────┼────────────┼────────────┤" -ForegroundColor Cyan
Write-Host "  │ ISA          │ RV32I      │ RV32IM     │" -ForegroundColor Cyan
Write-Host "  │ 结果         │ $(if($result1.Passed){"  ✅ PASS  "}else{"  ❌ FAIL  "}) │ $(if($result2.Passed){"  ✅ PASS  "}else{"  ❌ FAIL  "}) │" -ForegroundColor Cyan
Write-Host "  │ LUT          │ $($result1.LUT.PadLeft(8)) │ $($result2.LUT.PadLeft(8)) │" -ForegroundColor Cyan
Write-Host "  │ FF           │ $($result1.FF.PadLeft(8)) │ $($result2.FF.PadLeft(8)) │" -ForegroundColor Cyan
Write-Host "  │ WNS          │ $($result1.WNS.PadLeft(8)) │ $($result2.WNS.PadLeft(8)) │" -ForegroundColor Cyan
Write-Host "  │ Fmax         │ $($result1.Fmax.PadLeft(8)) │ $($result2.Fmax.PadLeft(8)) │" -ForegroundColor Cyan
Write-Host "  └──────────────┴────────────┴────────────┘" -ForegroundColor Cyan

Write-Host "`n  📄 日志  : document/log/" -ForegroundColor Green
Write-Host "  📊 报告  : $summaryFile" -ForegroundColor Green

# 最终结论
Write-Host "`n  ═══════════════════════════════════════════" -ForegroundColor Cyan
if ($result1.Passed -and $result2.Passed) {
    Write-Host "   ✅ 两轮综合均通过，可以上板测试" -ForegroundColor Green
    if ($result1.WNS -ge 0 -and $result2.WNS -ge 0) {
        Write-Host "   ✅ 时序收敛，上板风险较低" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ 时序未完全收敛，建议上板前检查最差路径" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ❌ 存在问题，请查看日志修复后再上板" -ForegroundColor Red
}
Write-Host "  ═══════════════════════════════════════════" -ForegroundColor Cyan
