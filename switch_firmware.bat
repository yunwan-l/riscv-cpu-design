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
pause
exit /b 1

:found
echo Firmware source dir: %FWDIR%
echo.
echo Available test firmware:
echo.
echo   --- Visual Tests (LED) ---
echo   [1] led_blink    - LED all blink (basic pipeline)
echo   [2] pc_seq       - PC sequential increment (LED counter)
echo   [3] forward      - Pipeline forwarding (LED 11 blink)
echo   [4] loaduse      - Load-Use hazard (LED 0xAA blink)
echo   [5] counter      - CPU auto-increment (LED binary count)
echo.
echo   --- UART Tests (serial output) ---
echo   [6] branch_uart  - Branch/Jump test (UART PASS/FAIL)
echo   [7] alu_uart     - ALU all operations (UART hex output)
echo   [8] mem_uart     - Memory R/W test (UART hex output)
echo   [9] muldiv_uart  - MUL/DIV/REM test (UART hex output)
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
    set "src=firmware_counter.hex"
    set "name=CPU Counter"
) else if "%choice%"=="6" (
    set "src=firmware_branch_uart.hex"
    set "name=Branch UART"
) else if "%choice%"=="7" (
    set "src=firmware_alu_uart.hex"
    set "name=ALU UART"
) else if "%choice%"=="8" (
    set "src=firmware_mem_uart.hex"
    set "name=Memory UART"
) else if "%choice%"=="9" (
    set "src=firmware_muldiv_uart.hex"
    set "name=MUL/DIV UART"
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

set "PROJFW=%BATDIR%build\vivado\rvp_nexys4.srcs\sources_1\imports\firmware.hex"
if not exist "%PROJFW%" set "PROJFW=C:\rvp_proj\build\vivado\rvp_nexys4.srcs\sources_1\imports\firmware.hex"

copy /y "%FWDIR%%src%" "%FWDIR%firmware.hex" >nul 2>&1
if not errorlevel 1 (
    echo [OK] %FWDIR%firmware.hex
    set "COPIED=1"
)

if exist "%PROJFW%" (
    copy /y "%FWDIR%%src%" "%PROJFW%" >nul 2>&1
    if not errorlevel 1 (
        echo [OK] %PROJFW%
        set "COPIED=1"
    )
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
echo Next steps in Vivado:
echo   1. Tcl Console: reset_run synth_1
echo   2. Run Synthesis ^> Implementation ^> Generate Bitstream
echo   3. Open Hardware Manager ^> Program Device
echo.
echo For UART tests [6-9]:
echo   - Open MobaXterm, create Serial session
echo   - Port: check Device Manager for COM number
echo   - Baud rate: 115200, 8N1
echo   - Press RESET on board after programming
echo.
pause
