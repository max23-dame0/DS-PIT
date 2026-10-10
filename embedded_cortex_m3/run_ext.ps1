param(
    [Parameter(Mandatory = $true)][string]$Tag,      # e.g. s2 / ws1
    [Parameter(Mandatory = $true)][string]$SrcBin,   # e.g. results/mcu_logL_s2.bin
    [int]$N = 256,
    [int]$K = 161,
    [int]$WaitSec = 32
)
$ErrorActionPreference = "Continue"
$env:Path = "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\14.2 rel1\bin;" + $env:Path
$ocd = "C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\bin\openocd.exe"
$root = "d:\小论文\manuscript_JBHI_IEEEtran\revision\audit\embedded_mcu_20260921"
$fw = Join-Path $root "fw"
$mat = Join-Path $root "results\matrix"

Push-Location $root
py -3 build_data.py $SrcBin 0 $N $K (Join-Path $fw "win_data.bin")
Pop-Location

Push-Location $fw
Remove-Item *.o, fw.elf, fw.bin, fw.map -ErrorAction SilentlyContinue
make 2>&1 | Out-Null
if (-not (Test-Path "fw.bin")) { throw "build failed" }
Pop-Location

& $ocd -f interface/stlink.cfg -f target/stm32f1x.cfg -c "adapter speed 1000" `
    -c "init" -c "reset halt" -c "program $($fw -replace '\\','/')/fw.elf verify" -c "reset run" -c "shutdown" 2>&1 |
    Select-String -Pattern 'Verified OK|Failed|Error' | ForEach-Object { $_.Line }

Start-Sleep -Seconds $WaitSec

$dump = "$($mat -replace '\\','/')/$Tag.bin"
& $ocd -f interface/stlink.cfg -f target/stm32f1x.cfg -c "adapter speed 480" `
    -c "init" -c "halt" -c "mdw 0x20000c94 1" `
    -c "dump_image $dump 0x20000c94 0x1014" -c "shutdown" 2>&1 |
    Select-String -Pattern '0x20000c94|dumped' | ForEach-Object { $_.Line }
"[$Tag] dump -> $dump"
