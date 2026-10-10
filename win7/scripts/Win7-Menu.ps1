$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

if (-not (Test-IsAdmin)) {
    try {
        $argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $PSCommandPath
        Start-Process -FilePath powershell.exe -Verb RunAs -WorkingDirectory $PSScriptRoot -ArgumentList $argLine | Out-Null
    }
    catch {
        Write-Host '没有获得管理员权限，已退出。'
        Read-Host '按回车关闭'
    }
    return
}

try { $Host.UI.RawUI.WindowTitle = 'Win7 安装盘镜像备份与恢复' } catch {}

function Open-Rufus {
    $exe = Get-RufusExe
    if (-not (Test-Path -LiteralPath $exe)) { throw '找不到 rufus-4.15p.exe' }
    Start-Process -FilePath $exe -WorkingDirectory $Script:RufusDir | Out-Null
    Write-Host '已打开 Rufus。'
    Write-Host '备份：选中 U 盘后，点「选择」旁边的保存图标，类型选 ISO。'
    Write-Host '恢复：引导类型选镜像文件，点「选择」打开 image\win7_install_usb.iso，分区类型选 MBR。'
    Write-Host '要做成 FAT32 安装盘，请用菜单第 4 项。'
}

while ($true) {
    Clear-Host
    Write-Host '============================================'
    Write-Host '  Win7 安装盘镜像  备份与恢复'
    Write-Host '============================================'
    Write-Host ("  目录  {0}" -f $Script:ProjectRoot)
    Write-Host ("  镜像  {0}" -f (Get-IsoQuickStatus))
    $rec = Get-IsoRecord
    if ($rec.Hash) { Write-Host ("  记录  {0}" -f $rec.Hash) }
    else { Write-Host '  记录  还没有 SHA256.txt' }
    Write-Host ''
    Write-Host '  1  查看状态（镜像、工具、已插入的 U 盘）'
    Write-Host '  2  从 U 盘备份成干净 ISO'
    Write-Host '  3  校验当前 ISO'
    Write-Host '  4  把 ISO 写入 U 盘（FAT32，会清空该盘）'
    Write-Host '  5  从现有 ISO 重建干净 ISO'
    Write-Host '  6  打开 Rufus'
    Write-Host '  0  退出'
    Write-Host ''
    $choice = Read-Host '请选择'
    try {
        switch ($choice) {
            '1' { & (Join-Path $PSScriptRoot 'Show-Status.ps1') }
            '2' { & (Join-Path $PSScriptRoot 'Backup-FromUsb.ps1') }
            '3' { & (Join-Path $PSScriptRoot 'Verify-Iso.ps1') }
            '4' { & (Join-Path $PSScriptRoot 'Restore-ToUsb.ps1') }
            '5' { & (Join-Path $PSScriptRoot 'Rebuild-CleanIso.ps1') }
            '6' { Open-Rufus }
            '0' { return }
            default { Write-Host '没有这个选项。' }
        }
    }
    catch {
        Write-Host ''
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
    Write-Host ''
    Read-Host '按回车返回菜单'
}
