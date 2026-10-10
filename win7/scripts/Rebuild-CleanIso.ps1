$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
Start-Log 'rebuild.log'
$sw = [Diagnostics.Stopwatch]::StartNew()

$iso = Get-IsoPath
if (-not (Test-Path -LiteralPath $iso)) { throw "找不到 $iso" }
Write-Host ''
Write-Host '将重新制作干净 ISO，并替换 win7_install_usb.iso。' -ForegroundColor Yellow
Write-Host '会去掉 System Volume Information。原来的文件改名为 .bak。' -ForegroundColor Yellow
if (-not (Read-Yes)) { Write-Host '已取消。'; return }

Write-Log '正在挂载当前 ISO...'
$letter = Mount-IsoLetter $iso
try {
    $hash = Publish-CleanIso -SourceRoot "${letter}:\" -Note 'Rebuilt with oscdimg; System Volume Information removed'
}
finally {
    Dismount-IsoFile $iso
}
Write-Log ("完成，用时 {0:n0} 秒" -f $sw.Elapsed.TotalSeconds)
Write-Host ''
Write-Host "SHA256  $hash" -ForegroundColor Green
Write-Host '重建完成。' -ForegroundColor Green
