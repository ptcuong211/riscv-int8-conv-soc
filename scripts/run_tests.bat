@echo off
setlocal enabledelayedexpansion

echo ==================================================================
echo    RISC-V INT8 Accelerator - Regression Verification Runner (Stage 6)
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
echo [1/9] Dang chay tb_int8_multiplier...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\tb\tb_int8_multiplier.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_int8_multiplier -s tb_int8_multiplier_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_int8_multiplier_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [2/9] Dang chay tb_mac_int8...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\tb\tb_mac_int8.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_mac_int8 -s tb_mac_int8_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_mac_int8_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [3/9] Dang chay tb_dot9_int8...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\tb\tb_dot9_int8.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_dot9_int8 -s tb_dot9_int8_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_dot9_int8_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [4/9] Dang chay tb_conv_window_reader...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\rtl\ram_sync_read.sv" "..\rtl\conv_window_reader.sv" "..\tb\tb_conv_window_reader.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_conv_window_reader -s tb_conv_window_reader_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_conv_window_reader_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [5/9] Dang chay tb_conv2d_raster_scanner...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\rtl\ram_sync_read.sv" "..\rtl\conv_window_reader.sv" "..\rtl\conv2d_raster_scanner.sv" "..\tb\tb_conv2d_raster_scanner.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_conv2d_raster_scanner -s tb_conv2d_raster_scanner_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_conv2d_raster_scanner_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [6/9] Dang chay tb_output_buffer...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\output_buffer.sv" "..\tb\tb_output_buffer.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_output_buffer -s tb_output_buffer_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_output_buffer_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [7/9] Dang chay tb_conv_accelerator_top...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\rtl\ram_sync_read.sv" "..\rtl\conv_window_reader.sv" "..\rtl\conv2d_raster_scanner.sv" "..\rtl\output_buffer.sv" "..\rtl\conv_accelerator_top.sv" "..\tb\tb_conv_accelerator_top.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_conv_accelerator_top -s tb_conv_accelerator_top_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_conv_accelerator_top_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [8/9] Dang chay tb_accelerator_mmio...
echo ==================================================================
call "%VIVADO_BIN%\xvlog.bat" -sv "..\rtl\accelerator_mmio.sv" "..\tb\tb_accelerator_mmio.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_accelerator_mmio -s tb_accelerator_mmio_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_accelerator_mmio_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo [9/9] Dang chay tb_soc_top (PicoRV32 End-to-End)...
echo ==================================================================
if not exist V:\build\firmware mkdir V:\build\firmware
copy /y "..\firmware\firmware.hex" "firmware.hex" >nul
copy /y "..\firmware\firmware.hex" "firmware\firmware.hex" >nul

call "%VIVADO_BIN%\xvlog.bat" -v "..\rtl\picorv32.v" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\rtl\ram_sync_read.sv" "..\rtl\conv_window_reader.sv" "..\rtl\conv2d_raster_scanner.sv" "..\rtl\output_buffer.sv" "..\rtl\conv_accelerator_top.sv" "..\rtl\soc_ram.sv" "..\rtl\accelerator_mmio.sv" "..\rtl\soc_top.sv" "..\tb\tb_soc_top.sv"
if errorlevel 1 goto error
call "%VIVADO_BIN%\xelab.bat" -debug typical tb_soc_top -s tb_soc_top_sim
if errorlevel 1 goto error
call "%VIVADO_BIN%\xsim.bat" tb_soc_top_sim -R
if errorlevel 1 goto error

echo.
echo ==================================================================
echo    KET QUA: TAT CA 9/9 TESTBENCH GIAI DOAN 1 -> 6 DEU DAT PASS 100%%!
echo ==================================================================
goto end

:error
echo.
echo [ERROR] Qua trinh bien dich hoac mo phong bi loi!
exit /b 1

:end
