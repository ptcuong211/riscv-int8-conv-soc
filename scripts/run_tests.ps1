<#
.SYNOPSIS
    Script tự động biên dịch và chạy mô phỏng Giai đoạn 1, 2 & 3 với Vivado xsim.
.DESCRIPTION
    Script này biên dịch và chạy kiểm tra hồi quy toàn diện:
      1. tb_int8_multiplier (Exhaustive 65,536 test vectors)
      2. tb_mac_int8 (Comprehensive cycle-by-cycle verification)
      3. tb_dot9_int8 (Stage 2 FSM, handshake, counters, CNN & 120 random regression tasks)
      4. tb_conv_window_reader (Stage 3 Synchronous RAM Buffers, Latency handling, Window extraction)
    Tự động xử lý đường dẫn Unicode tiếng Việt bằng ánh xạ ổ đĩa ảo tạm (subst).
#>

[CmdletBinding()]
param (
    [string]$VivadoPath = "D:\vivado\2025.1\Vivado\bin",
    [string]$DriveLetter = "V:"
)

$ErrorActionPreference = "Stop"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "   RISC-V INT8 Accelerator - Regression Verification Runner" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Kiểm tra Vivado Simulator
if (-not (Test-Path "$VivadoPath\xvlog.bat")) {
    $VivadoFromPath = Get-Command "xvlog.bat" -ErrorAction SilentlyContinue
    if ($VivadoFromPath) {
        $VivadoPath = Split-Path -Parent $VivadoFromPath.Path
    } else {
        Write-Error "Không tìm thấy Vivado binaries tại '$VivadoPath' hoặc trong PATH hệ thống!"
        exit 1
    }
}
Write-Host "[INFO] Sử dụng Vivado Simulator tại: $VivadoPath" -ForegroundColor Green

# 2. Xử lý đường dẫn Unicode nếu có
$WorkspaceRoot = (Get-Item $PSScriptRoot).Parent.FullName
$NeedSubst = $false
$ExecutionRoot = $WorkspaceRoot

if ($WorkspaceRoot -match "[^\x00-\x7F]") {
    Write-Host "[INFO] Phát hiện ký tự non-ASCII trong đường dẫn workspace: $WorkspaceRoot" -ForegroundColor Yellow
    Write-Host "[INFO] Đang ánh xạ sang ổ đĩa ảo $DriveLetter để tương thích Vivado..." -ForegroundColor Yellow
    
    # Kiểm tra xem ổ đĩa đã tồn tại chưa
    $ExistingSubst = subst
    if ($ExistingSubst -match "$DriveLetter\\:") {
        subst $DriveLetter /d | Out-Null
    }
    subst $DriveLetter "$WorkspaceRoot"
    $NeedSubst = $true
    $ExecutionRoot = "$DriveLetter\"
}

$BuildDir = Join-Path $ExecutionRoot "build"
if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
}

try {
    Push-Location $BuildDir

    # =========================================================================
    # BƯỚC 1: Mô phỏng int8_multiplier (Giai đoạn 1)
    # =========================================================================
    Write-Host "`n>>> [1/4] Đang biên dịch và chạy tb_int8_multiplier..." -ForegroundColor Yellow
    & "$VivadoPath\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\tb\tb_int8_multiplier.sv"
    if ($LASTEXITCODE -ne 0) { throw "Biên dịch xvlog thất bại cho int8_multiplier!" }

    & "$VivadoPath\xelab.bat" -debug typical tb_int8_multiplier -s tb_int8_multiplier_sim
    if ($LASTEXITCODE -ne 0) { throw "Elaboration xelab thất bại cho int8_multiplier!" }

    $multiplier_out = & "$VivadoPath\xsim.bat" tb_int8_multiplier_sim -R
    $multiplier_out | ForEach-Object { Write-Host $_ }
    $multiplier_str = $multiplier_out -join "`n"
    if ($LASTEXITCODE -ne 0 -or ($multiplier_str -notmatch "MATCH GOLDEN REFERENCE")) {
        throw "Mô phỏng tb_int8_multiplier thất bại hoặc không đạt PASS!"
    }

    # =========================================================================
    # BƯỚC 2: Mô phỏng mac_int8 (Giai đoạn 1)
    # =========================================================================
    Write-Host "`n>>> [2/4] Đang biên dịch và chạy tb_mac_int8..." -ForegroundColor Yellow
    & "$VivadoPath\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\tb\tb_mac_int8.sv"
    if ($LASTEXITCODE -ne 0) { throw "Biên dịch xvlog thất bại cho mac_int8!" }

    & "$VivadoPath\xelab.bat" -debug typical tb_mac_int8 -s tb_mac_int8_sim
    if ($LASTEXITCODE -ne 0) { throw "Elaboration xelab thất bại cho mac_int8!" }

    $mac_out = & "$VivadoPath\xsim.bat" tb_mac_int8_sim -R
    $mac_out | ForEach-Object { Write-Host $_ }
    $mac_str = $mac_out -join "`n"
    if ($LASTEXITCODE -ne 0 -or ($mac_str -notmatch "COMPLETELY VERIFIED WITH ZERO ERRORS")) {
        throw "Mô phỏng tb_mac_int8 thất bại hoặc không đạt PASS!"
    }

    # =========================================================================
    # BƯỚC 3: Mô phỏng dot9_int8 (Giai đoạn 2)
    # =========================================================================
    Write-Host "`n>>> [3/4] Đang biên dịch và chạy tb_dot9_int8..." -ForegroundColor Yellow
    & "$VivadoPath\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\tb\tb_dot9_int8.sv"
    if ($LASTEXITCODE -ne 0) { throw "Biên dịch xvlog thất bại cho dot9_int8!" }

    & "$VivadoPath\xelab.bat" -debug typical tb_dot9_int8 -s tb_dot9_int8_sim
    if ($LASTEXITCODE -ne 0) { throw "Elaboration xelab thất bại cho dot9_int8!" }

    $dot9_out = & "$VivadoPath\xsim.bat" tb_dot9_int8_sim -R
    $dot9_out | ForEach-Object { Write-Host $_ }
    $dot9_str = $dot9_out -join "`n"
    if ($LASTEXITCODE -ne 0 -or ($dot9_str -notmatch "TAT CA CAC TESTBENCH GIAI DOAN 2 DA PASS")) {
        throw "Mô phỏng tb_dot9_int8 thất bại hoặc không đạt PASS!"
    }

    # =========================================================================
    # BƯỚC 4: Mô phỏng conv_window_reader (Giai đoạn 3)
    # =========================================================================
    Write-Host "`n>>> [4/4] Đang biên dịch và chạy tb_conv_window_reader..." -ForegroundColor Yellow
    & "$VivadoPath\xvlog.bat" -sv "..\rtl\int8_multiplier.sv" "..\rtl\mac_int8.sv" "..\rtl\dot9_int8.sv" "..\rtl\ram_sync_read.sv" "..\rtl\conv_window_reader.sv" "..\tb\tb_conv_window_reader.sv"
    if ($LASTEXITCODE -ne 0) { throw "Biên dịch xvlog thất bại cho conv_window_reader!" }

    & "$VivadoPath\xelab.bat" -debug typical tb_conv_window_reader -s tb_conv_window_reader_sim
    if ($LASTEXITCODE -ne 0) { throw "Elaboration xelab thất bại cho conv_window_reader!" }

    $win_out = & "$VivadoPath\xsim.bat" tb_conv_window_reader_sim -R
    $win_out | ForEach-Object { Write-Host $_ }
    $win_str = $win_out -join "`n"
    if ($LASTEXITCODE -ne 0 -or ($win_str -notmatch "TAT CA CAC TESTBENCH GIAI DOAN 3 DA PASS")) {
        throw "Mô phỏng tb_conv_window_reader thất bại hoặc không đạt PASS!"
    }

    Write-Host "`n==================================================================" -ForegroundColor Green
    Write-Host "   TẤT CẢ TESTBENCH GIAI ĐOẠN 1, 2 & 3 ĐÃ HOÀN THÀNH XUẤT SẮC (PASS 100%)!" -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host "File waveform VCD đã lưu tại:" -ForegroundColor Cyan
    Write-Host "  - $(Join-Path $BuildDir 'int8_multiplier_waveform.vcd')"
    Write-Host "  - $(Join-Path $BuildDir 'mac_int8_waveform.vcd')"
    Write-Host "  - $(Join-Path $BuildDir 'dot9_int8_waveform.vcd')"
    Write-Host "  - $(Join-Path $BuildDir 'conv_window_reader_waveform.vcd')"

} finally {
    Pop-Location
}
