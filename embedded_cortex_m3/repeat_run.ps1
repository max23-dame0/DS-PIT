param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Defs = "",
    [int]$N = 3,
    [int]$WaitSec = 30
)
$ErrorActionPreference = "Continue"
if ($Defs -eq "NONE") { $Defs = "" }   # 哨兵：空字符串在嵌套调用中会被丢弃，用 NONE 表示默认配置
$env:Path = "C:\Program Files (x86)\Arm GNU Toolchain arm-none-eabi\14.2 rel1\bin;" + $env:Path
$ocd = "C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Packages\xpack-dev-tools.openocd-xpack_Microsoft.Winget.Source_8wekyb3d8bbwe\xpack-openocd-0.12.0-7\bin\openocd.exe"
$root = "d:\小论文\manuscript_JBHI_IEEEtran\revision\audit\embedded_mcu_20260921"
$fw = Join-Path $root "fw"
$mat = Join-Path $root "results\matrix"
if (-not (Test-Path $mat)) { New-Item -ItemType Directory -Path $mat | Out-Null }

Push-Location $fw
Remove-Item *.o, fw.elf, fw.bin, fw.map -ErrorAction SilentlyContinue
if ($Defs -ne "") { make EXTRA_DEFS="$Defs" 2>&1 | Out-Null } else { make 2>&1 | Out-Null }
if (-not (Test-Path "fw.bin")) { throw "build failed" }
Pop-Location

& $ocd -f interface/stlink.cfg -f target/stm32f1x.cfg -c "adapter speed 1000" `
    -c "init" -c "reset halt" -c "program $($fw -replace '\\','/')/fw.elf verify" -c "reset run" -c "shutdown" 2>&1 |
    Select-String -Pattern 'Verified OK|Error|Failed' | ForEach-Object { $_.Line }

for ($i = 1; $i -le $N; $i++) {
    & $ocd -f interface/stlink.cfg -f target/stm32f1x.cfg -c "adapter speed 480" `
        -c "init" -c "reset run" -c "shutdown" 2>&1 | Out-Null
    Start-Sleep -Seconds $WaitSec
    $dump = "$($mat -replace '\\','/')/$($Tag)_r$i.bin"
    & $ocd -f interface/stlink.cfg -f target/stm32f1x.cfg -c "adapter speed 480" `
        -c "init" -c "halt" -c "mdw 0x20000c94 1" `
        -c "dump_image $dump 0x20000c94 0x1014" -c "shutdown" 2>&1 |
        Select-String -Pattern '0x20000c94' | ForEach-Object { $_.Line }
    "[$Tag] rep $i of $N -> $dump"
}
