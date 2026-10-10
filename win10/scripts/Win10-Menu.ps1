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

try { $Host.UI.RawUI.WindowTitle = 'Win10 Ventoy 安装盘' } catch {}

function Show-Status {
    Write-Host ''
    Write-Host '镜像' -ForegroundColor Cyan
    $iso = Get-IsoPath
    if (Test-Path -LiteralPath $iso) {
        $item = Get-Item -LiteralPath $iso
        Write-Host ("  文件  {0}" -f $item.FullName)
        Write-Host ("  大小  {0}  ({1} 字节)" -f (Format-Gb $item.Length), $item.Length)
    }
    else {
        Write-Host ("  找不到 {0}" -f $iso)
    }

    Write-Host ''
    Write-Host 'Ventoy' -ForegroundColor Cyan
    $versions = Get-VentoyVersions
    if ($versions.Count -eq 0) {
        Write-Host ("  在 {0} 找不到 ventoy-*-windows.zip" -f $Script:VentoyDir)
    }
    foreach ($v in $versions) {
        $zipPath = @($Script:VentoyDir, $Script:VentoyDirLocal) |
            ForEach-Object { Join-Path $_ ('ventoy-' + $v + '-windows.zip') } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        $root = Join-Path $Script:VentoyDir ('ventoy-' + $v)
        $versionFile = Join-Path $root 'ventoy\version'
        $state = if ($zipPath) { '压缩包  ' + $zipPath } else { '压缩包不在 ventoy 文件夹' }
        if (Test-Path -LiteralPath $versionFile) {
            $state += ("，已解压（版本 {0}）" -f (([System.IO.File]::ReadAllText($versionFile)).Trim()))
        }
        Write-Host ("  {0}  {1}" -f $v, $state)
    }

    Write-Host ''
    Write-Host 'U 盘' -ForegroundColor Cyan
    $usbs = Get-OnlineUsbDisks
    if ($usbs.Count -eq 0) {
        Write-Host '  当前没有插入 U 盘。'
    }
    else {
        $isoName = $Script:IsoFileName
        foreach ($d in $usbs) {
            $diskName = if ($d.FriendlyName) { [string]$d.FriendlyName } else { 'USB' }
            $ventoy = ''
            $hasIso = ''
            foreach ($part in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)) {
                $vol = $null
                try { $vol = Get-Volume -Partition $part -ErrorAction SilentlyContinue } catch {}
                $label = Get-VolumeLabelText $vol
                if ($label -eq 'Ventoy') { $ventoy = '  Ventoy' }
                if ($part.DriveLetter -and (Test-Path -LiteralPath ('{0}:\{1}' -f $part.DriveLetter, $isoName))) {
                    $hasIso = '  已有 ISO'
                }
            }
            Write-Host ("  磁盘 {0}  {1}  {2}  {3}  {4}{5}{6}" -f $d.Number, $diskName, (Format-Gb $d.Size), $d.PartitionStyle, (Get-DiskLetterText $d.Number), $ventoy, $hasIso)
        }
    }
    Write-Host ''
    Write-Host ("日志  {0}" -f (Join-Path $Script:ProjectRoot 'logs\make.log'))
}

while ($true) {
    Clear-Host
    Write-Host '============================================'
    Write-Host '  Win10 安装盘（Ventoy）'
    Write-Host '============================================'
    Write-Host ("  目录  {0}" -f $Script:ProjectRoot)
    $iso = Get-IsoPath
    if (Test-Path -LiteralPath $iso) {
        Write-Host ("  镜像  {0}  {1}" -f $Script:IsoFileName, (Format-Gb (Get-Item -LiteralPath $iso).Length))
    }
    else {
        Write-Host ("  镜像  找不到 {0}" -f $Script:IsoFileName)
    }
    Write-Host ''
    Write-Host '  1  查看状态（镜像、Ventoy、已插入的 U 盘）'
    Write-Host '  2  制作安装盘（默认 UEFI/GPT；Ventoy 未装完整或分区表不符时清空重装，ISO 已拷完则跳过）'
    Write-Host '  3  只复制 ISO（U 盘已经是 Ventoy 时）'
    Write-Host '  4  用 Rufus 制作安装盘（清空 U 盘，不经过 Ventoy）'
    Write-Host '  0  退出'
    Write-Host ''
    $choice = Read-Host '请选择'
    try {
        switch ($choice) {
            '1' { Show-Status }
            '2' {
                $bm = Read-Host '启动模式：1=UEFI(GPT)  2=BIOS(MBR)，回车默认 UEFI'
                $mode = if ($bm -eq '2') { 'BIOS' } else { 'UEFI' }
                $fsRaw = Read-Host '分区格式：1=exFAT（Linux 文档做法，默认）  2=NTFS'
                $fs = if ($fsRaw -eq '2') { 'NTFS' } else { 'exFAT' }
                & (Join-Path $PSScriptRoot 'Make-Win10Usb.ps1') -Mode Install -BootMode $mode -PartitionFs $fs
            }
            '3' { & (Join-Path $PSScriptRoot 'Make-Win10Usb.ps1') -Mode CopyOnly }
            '4' { & (Join-Path $PSScriptRoot 'Make-Win10UsbRufus.ps1') }
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
