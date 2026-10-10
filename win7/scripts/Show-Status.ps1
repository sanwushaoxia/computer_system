$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin

Write-Host ''
Write-Host '镜像' -ForegroundColor Cyan
$iso = Get-IsoPath
if (Test-Path -LiteralPath $iso) {
    $item = Get-Item -LiteralPath $iso
    Write-Host ("  文件    {0}" -f $item.FullName)
    Write-Host ("  大小    {0}  ({1} 字节)" -f (Format-Gb $item.Length), $item.Length)
    Write-Host ("  修改    {0}" -f $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
}
else {
    Write-Host '  还没有 win7_install_usb.iso。可用菜单第 2 项从 U 盘备份。'
}
$rec = Get-IsoRecord
if ($rec.Exists) {
    Write-Host ("  SHA256  {0}" -f $(if ($rec.Hash) { $rec.Hash } else { '（空）' }))
    if ($rec.Size -gt 0) { Write-Host ("  记录大小  {0} 字节" -f $rec.Size) }
    if ($rec.Cleaned) { Write-Host ("  记录时间  {0}" -f $rec.Cleaned) }
    if ($rec.Note) { Write-Host ("  说明    {0}" -f $rec.Note) }
    if ((Test-Path -LiteralPath $iso) -and $rec.Size -gt 0) {
        $same = ((Get-Item -LiteralPath $iso).Length -eq $rec.Size)
        Write-Host ("  大小核对  {0}" -f $(if ($same) { '一致' } else { '不一致，建议做一次完整校验' }))
    }
}
else {
    Write-Host '  还没有 SHA256.txt。备份或重建成功后会自动写上。'
}
$bak = Get-BakPath
if (Test-Path -LiteralPath $bak) {
    $bakItem = Get-Item -LiteralPath $bak
    Write-Host ("  上一份  {0}  {1}" -f $bakItem.Name, (Format-Gb $bakItem.Length))
}

Write-Host ''
Write-Host '工具' -ForegroundColor Cyan
$oscdimg = Get-OscdimgPath
Write-Host ("  oscdimg   {0}" -f $(if ($oscdimg) { $oscdimg } else { '未找到。备份和重建需要 Windows ADK 部署工具。' }))
$bootsect = Get-BootsectPath
Write-Host ("  bootsect  {0}" -f $(if ($bootsect) { $bootsect } else { '未找到。写入 U 盘需要它。' }))
$rufus = Get-RufusExe
Write-Host ("  Rufus     {0}" -f $(if (Test-Path -LiteralPath $rufus) { $rufus } else { '未找到 rufus-4.15p.exe' }))

Write-Host ''
Write-Host 'U 盘' -ForegroundColor Cyan
$usbs = Get-OnlineUsbDisks
if ($usbs.Count -eq 0) {
    Write-Host '  当前没有插入 U 盘。'
}
else {
    foreach ($d in $usbs) {
        $name = if ($d.FriendlyName) { [string]$d.FriendlyName } else { 'USB' }
        $boot = ''
        foreach ($part in @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)) {
            if ($part.DriveLetter -and (Test-Path -LiteralPath "$($part.DriveLetter):\bootmgr")) {
                $boot = '  含 bootmgr'
            }
        }
        Write-Host ("  磁盘 {0}  {1}  {2}  {3}  {4}{5}" -f $d.Number, $name, (Format-Gb $d.Size), $d.PartitionStyle, (Get-DiskLetterText $d.Number), $boot)
    }
}
Write-Host ''
Write-Host ("日志目录  {0}" -f (Join-Path $Script:ProjectRoot 'logs'))
