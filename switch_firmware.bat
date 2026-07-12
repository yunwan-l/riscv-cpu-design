@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo   RVP Processor - Test Firmware Switcher
echo   Project: rvp_nexys4 (基础实验)
echo   Board:  NEXYS4 DDR
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
echo   --- Integrated Test (SW selectable) ---
echo   [0] all          - All 8 tests, SW[3:0] selects (DEFAULT)
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

set /p choice="Select firmware (0-9): "

if "%choice%"=="0" (
    set "src=firmware_all.hex"
    set "name=All Tests (SW selectable)"
) else if "%choice%"=="1" (
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
rem Copy firmware.hex to rvp_nexys4 project locations ONLY
rem NEVER touch build/vivado_piano/ (Pianooo's project)
rem ============================================================
set "COPIED=0"

rem Location 1: synth/vivado/firmware.hex (xpr references this)
copy /y "%FWDIR%%src%" "%FWDIR%firmware.hex" >nul 2>&1
if not errorlevel 1 (
    echo [OK] %FWDIR%firmware.hex
    set "COPIED=1"
)

rem Location 2: build/vivado/rvp_nexys4.srcs/sources_1/imports/firmware.hex
set "PROJFW=%BATDIR%build\vivado\rvp_nexys4.srcs\sources_1\imports\firmware.hex"
if not exist "%PROJFW%" set "PROJFW=C:\rvp_proj\build\vivado\rvp_nexys4.srcs\sources_1\imports\firmware.hex"
if exist "%PROJFW%" (
    copy /y "%FWDIR%%src%" "%PROJFW%" >nul 2>&1
    if not errorlevel 1 (
        echo [OK] %PROJFW%
        set "COPIED=1"
    )
)

rem Location 3: root firmware.hex
set "ROOTFW=%BATDIR%firmware.hex"
if not exist "%ROOTFW%" set "ROOTFW=C:\rvp_proj\firmware.hex"
if exist "%ROOTFW%" (
    copy /y "%FWDIR%%src%" "%ROOTFW%" >nul 2>&1
    if not errorlevel 1 (
        echo [OK] %ROOTFW%
        set "COPIED=1"
    )
)

rem ============================================================
rem Clean up orphaned build/vivado/firmware.hex
rem This file is NOT in the xpr source list but Vivado's $readmemh
rem may find it and use the wrong firmware!
rem ============================================================
if exist "%BATDIR%build\vivado\firmware.hex" (
    del /q "%BATDIR%build\vivado\firmware.hex" >nul 2>&1
    echo [CLEANED] Deleted orphaned build\vivado\firmware.hex
)
if exist "C:\rvp_proj\build\vivado\firmware.hex" (
    del /q "C:\rvp_proj\build\vivado\firmware.hex" >nul 2>&1
    echo [CLEANED] Deleted orphaned C:\rvp_proj\build\vivado\firmware.hex
)

if "%COPIED%"=="0" (
    echo ERROR: All copy attempts failed!
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   Firmware switched: %name%
echo   Project: rvp_nexys4 ONLY (Piano project untouched)
echo ============================================================
echo.
echo Next steps in Vivado (rvp_nexys4.xpr):
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
echo For integrated test [0]:
echo   - SW[3:0] selects test 0-8
echo   - SW=0000: LED blink, SW=0001: PC seq, ... SW=1000: Muldiv UART
echo.
pause
