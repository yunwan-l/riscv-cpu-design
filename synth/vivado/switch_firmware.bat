@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo   RVP Processor - Test Firmware Switcher
echo   Board: NEXYS4 DDR
echo ============================================================
echo.

set "BATDIR=%~dp0"

rem ============================================================
rem Auto-detect firmware source directory
rem ============================================================
set "FWDIR="

if exist "%BATDIR%firmware_blink.hex" (
    set "FWDIR=%BATDIR%"
    goto :found
)
if exist "%BATDIR%synth\vivado\firmware_blink.hex" (
    set "FWDIR=%BATDIR%synth\vivado\"
    goto :found
)
if exist "C:\rvp_proj\synth\vivado\firmware_blink.hex" (
    set "FWDIR=C:\rvp_proj\synth\vivado\"
    goto :found
)

echo ERROR: Cannot find firmware files!
echo Searched:
echo   %BATDIR%
echo   %BATDIR%synth\vivado\
echo   C:\rvp_proj\synth\vivado\
echo.
pause
exit /b 1

:found
echo Firmware source dir: %FWDIR%
echo.
echo Available test firmware:
echo.
echo   [1] led_blink    - LED all blink (original, verified)
echo   [2] pc_seq       - PC sequential increment (LED counter)
echo   [3] forward      - Pipeline forwarding (LED 0x0800 blink)
echo   [4] loaduse      - Load-Use hazard (LED 0x00AA blink)
echo   [5] branch       - Branch jump (LED 0x000F/0x00F0 alt)
echo   [6] alu          - ALU all operations (8 ops display)
echo   [7] mem          - Memory R/W (byte/half/word sign-ext)
echo   [8] muldiv       - MUL/DIV/REM (M-extension)
echo   [9] pipeline     - Pipeline demo (4-stage cycle)
echo.

set /p choice="Select firmware (1-9): "

if "%choice%"=="1" (
    set "src=firmware_blink.hex"
    set "name=LED Blink"
) else if "%choice%"=="2" (
    set "src=firmware_pc_seq.hex"
    set "name=PC Sequential"
) else if "%choice%"=="3" (
    set "src=firmware_forward.hex"
    set "name=Forwarding"
) else if "%choice%"=="4" (
    set "src=firmware_loaduse.hex"
    set "name=Load-Use"
) else if "%choice%"=="5" (
    set "src=firmware_branch.hex"
    set "name=Branch"
) else if "%choice%"=="6" (
    set "src=firmware_alu.hex"
    set "name=ALU"
) else if "%choice%"=="7" (
    set "src=firmware_mem.hex"
    set "name=Memory"
) else if "%choice%"=="8" (
    set "src=firmware_muldiv.hex"
    set "name=MUL/DIV"
) else if "%choice%"=="9" (
    set "src=firmware_pipeline.hex"
    set "name=Pipeline Demo"
) else (
    echo ERROR: Invalid choice
    pause
    exit /b 1
)

echo.
echo Selected: %name%
echo Source: %src%
echo.

if not exist "%FWDIR%%src%" (
    echo ERROR: File %src% not found in %FWDIR%
    pause
    exit /b 1
)

rem ============================================================
rem Copy firmware.hex to ALL known locations
rem ============================================================
set "COPIED=0"

rem 1. Source directory
copy /y "%FWDIR%%src%" "%FWDIR%firmware.hex" >nul 2>&1
if not errorlevel 1 (
    echo [OK] %FWDIR%firmware.hex
    set "COPIED=1"
)

rem 2. Vivado project internal copy
set "PROJFW=%BATDIR%build\vivado\rvp_nexys4.srcs\sources_1\imports\firmware.hex"
if not exist "%PROJFW%" set "PROJFW=C:\rvp_proj\build\vivado\rvp_nexys4.srcs\sources_1\imports\firmware.hex"
if exist "%PROJFW%" (
    copy /y "%FWDIR%%src%" "%PROJFW%" >nul 2>&1
    if not errorlevel 1 (
        echo [OK] %PROJFW%
        set "COPIED=1"
    )
)

rem 3. rvp_build directory
if exist "C:\Users\13691\AppData\Roaming\Xilinx\Vivado\rvp_build\firmware.hex" (
    copy /y "%FWDIR%%src%" "C:\Users\13691\AppData\Roaming\Xilinx\Vivado\rvp_build\firmware.hex" >nul 2>&1
    if not errorlevel 1 echo [OK] rvp_build\firmware.hex
)

if "%COPIED%"=="0" (
    echo ERROR: All copy attempts failed!
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   Firmware switched: %name%
echo ============================================================
echo.
echo IMPORTANT: In Vivado, you MUST do this before re-synthesis:
echo   Option A: Right-click synth_1 -^> Reset Run
echo   Option B: Tcl Console: reset_run synth_1
echo.
echo Then:
echo   1. Run Synthesis
echo   2. Run Implementation
echo   3. Generate Bitstream
echo   4. Open Hardware Manager -^> Program Device
echo.
pause
