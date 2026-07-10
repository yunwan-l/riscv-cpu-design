@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo   RVP CPU Auto-Increment Counter - One-Click Build
echo   Board: NEXYS4 DDR
echo ============================================================
echo.

rem ============================================================
rem Find Vivado installation
rem ============================================================
set "VIVADO="

if exist "C:\Xilinx\Vivado\2018.3\bin\vivado.bat" (
    set "VIVADO=C:\Xilinx\Vivado\2018.3\bin\vivado.bat"
) else if exist "C:\Xilinx\Vivado\2019.1\bin\vivado.bat" (
    set "VIVADO=C:\Xilinx\Vivado\2019.1\bin\vivado.bat"
) else if exist "C:\Xilinx\Vivado\2020.1\bin\vivado.bat" (
    set "VIVADO=C:\Xilinx\Vivado\2020.1\bin\vivado.bat"
) else (
    rem Try to find Vivado in PATH
    where vivado >nul 2>&1
    if not errorlevel 1 (
        set "VIVADO=vivado"
    )
)

if "!VIVADO!"=="" (
    echo ERROR: Cannot find Vivado.
    echo Please set VIVADO variable to your Vivado installation.
    echo   Example: set VIVADO=C:\Xilinx\Vivado\2018.3\bin\vivado.bat
    echo.
    echo Alternatively, open Vivado GUI and run in Tcl Console:
    echo   source C:/rvp_proj/synth/vivado/build_counter.tcl
    pause
    exit /b 1
)

echo Vivado: !VIVADO!
echo.

rem ============================================================
rem Clean up stale synthesis state (fixes "synthesis already running")
rem ============================================================
echo Cleaning up stale synthesis state...
if exist "C:\rvp_proj\build\vivado\rvp_nexys4.runs\synth_1\__synthesis_is_running__" (
    del /q "C:\rvp_proj\build\vivado\rvp_nexys4.runs\synth_1\__synthesis_is_running__"
    echo [OK] Removed stale __synthesis_is_running__ marker
)
if exist "C:\rvp_proj\build\vivado\rvp_nexys4.runs\impl_1\__implementation_is_running__" (
    del /q "C:\rvp_proj\build\vivado\rvp_nexys4.runs\impl_1\__implementation_is_running__"
    echo [OK] Removed stale __implementation_is_running__ marker
)
echo.

rem ============================================================
rem Run the build script in Vivado batch mode
rem ============================================================
echo ============================================================
echo   Starting Vivado batch build...
echo   This will take 5-15 minutes. Please wait.
echo ============================================================
echo.

"!VIVADO!" -mode batch -source "C:\rvp_proj\synth\vivado\build_counter.tcl" -log "C:\rvp_proj\build\vivado\build_counter.log" -journal "C:\rvp_proj\build\vivado\build_counter.jou"

echo.
echo ============================================================
if not errorlevel 1 (
    echo   BUILD COMPLETE!
    echo   Bitstream: C:\rvp_proj\build\vivado\rvp_nexys4.bit
    echo.
    echo   Now program the FPGA:
    echo   1. Open Vivado Hardware Manager
    echo   2. Open Target -^> Auto Connect
    echo   3. Program Device with rvp_nexys4.bit
    echo.
    echo   Expected: LEDs show incrementing counter (0,1,2,3,...)
) else (
    echo   BUILD FAILED! Check the log:
    echo   C:\rvp_proj\build\vivado\build_counter.log
)
echo ============================================================
pause
