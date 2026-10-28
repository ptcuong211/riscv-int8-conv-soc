@echo off
setlocal enabledelayedexpansion

echo ==================================================================
echo    RISC-V INT8 Accelerator - Regression Verification Runner (BAT)
echo ==================================================================

set VIVADO_BIN=D:\vivado\2025.1\Vivado\bin
set SCRIPT_DIR=%~dp0
set WORKSPACE_ROOT=%SCRIPT_DIR%..

echo [INFO] Kiem tra duong dan Vivado tai: %VIVADO_BIN%
if not exist "%VIVADO_BIN%\xvlog.bat" (
    echo [ERROR] Khong tim thay Vivado binaries tai %VIVADO_BIN%!
    pause
    exit /b 1
)

:: Anh xa thu muc sang o dia ao V: de tranh loi ky tu unicode trong xsim
echo [INFO] Anh xa thu muc sang o dia ao V:...
subst V: "%WORKSPACE_ROOT%" >nul 2>&1

cd /d V:\build
if not exist V:\build (
    mkdir V:\build
)

echo.
echo ==================================================================
echo [1/4] Dang chay tb_int8_multiplier...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\tb\tb_int8_multiplier.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_int8_multiplier -s tb_int8_multiplier_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_int8_multiplier_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [2/4] Dang chay tb_mac_int8...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\tb\tb_mac_int8.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_mac_int8 -s tb_mac_int8_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_mac_int8_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [3/4] Dang chay tb_dot9_int8...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\tb\tb_dot9_int8.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_dot9_int8 -s tb_dot9_int8_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_dot9_int8_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [4/5] Dang chay tb_conv_window_reader...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\rtl\ram_sync_read.sv" "..\rtl\conv_window_reader.sv" "..\tb\tb_conv_window_reader.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_conv_window_reader -s tb_conv_window_reader_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_conv_window_reader_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [5/5] Dang chay tb_conv2d_raster_scanner...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\rtl\ram_sync_read.sv" "..\rtl\conv_window_reader.sv" "..\rtl\conv2d_raster_scanner.sv" "..\tb\tb_conv2d_raster_scanner.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_conv2d_raster_scanner -s tb_conv2d_raster_scanner_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_conv2d_raster_scanner_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo    KET QUA: TAT CA TESTBENCH GIAI DOAN 1, 2, 3 & 4 DEU DAT PASS 100%%!
echo ==================================================================
echo File waveform VCD duoc tao tai:
echo   - V:\build\int8_multiplier_waveform.vcd
echo   - V:\build\mac_int8_waveform.vcd
echo   - V:\build\dot9_int8_waveform.vcd
echo   - V:\build\conv_window_reader_waveform.vcd
echo   - V:\build\conv2d_raster_scanner_waveform.vcd
goto end

:error
echo.
echo [ERROR] Qua trinh bien dich hoac mo phong bi loi!
exit /b 1

:end
endlocal
