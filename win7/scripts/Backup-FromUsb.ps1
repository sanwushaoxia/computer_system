$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
Start-Log 'backup.log'
$sw = [Diagnostics.Stopwatch]::StartNew()

$disk = Read-UsbDisk '选择要备份的 U 盘。这一步只读取，不会格式化 U 盘。'
if (-not $disk) { Write-Host '已取消。'; return }
$name = if ($disk.FriendlyName) { [string]$disk.FriendlyName } else { 'USB' }
Write-Host ''
Write-Host ("将读取  磁盘 {0}  {1}  {2}" -f $disk.Number, $name, (Format-Gb $disk.Size)) -ForegroundColor Yellow
Write-Host ("成功后替换  {0}" -f (Get-IsoPath)) -ForegroundColor Yellow
Write-Host '原来的 ISO 会改名为 image\win7_install_usb.iso.bak' -ForegroundColor Yellow
if (-not (Read-Yes)) { Write-Host '已取消。'; return }

Assert-SameUsb $disk
$letter = Resolve-SourceLetter $disk.Number
Write-Log ("源 ${letter}:  磁盘 {0} {1}" -f $disk.Number, $name)
$hash = Publish-CleanIso -SourceRoot "${letter}:\" -Note ("Backed up from USB disk {0} {1}; System Volume Information excluded" -f $disk.Number, $name)
Write-Log ("完成，用时 {0:n0} 秒" -f $sw.Elapsed.TotalSeconds)
Write-Host ''
Write-Host "SHA256  $hash" -ForegroundColor Green
Write-Host '备份完成。上一份镜像已保存为 image\win7_install_usb.iso.bak' -ForegroundColor Green
