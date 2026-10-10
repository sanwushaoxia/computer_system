param(
    [int]$DiskNumber = -1,
    [string]$Confirm = '',
    [ValidateSet('Auto', 'UEFI', 'BIOS')]
    [string]$BootMode = 'Auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
Start-Log 'make-rufus.log'

$iso = Get-IsoPath
if (-not (Test-Path -LiteralPath $iso)) { throw "找不到 $iso" }

$rufus = Get-RufusExe
if (-not $rufus) { throw '在根目录 rufus 文件夹找不到 rufus-4.15p.exe。请把 Rufus 放进 computer_system\rufus。' }
Write-Log ("Rufus 路径 " + $rufus)

$disk = Resolve-UsbDisk -DiskNumber $DiskNumber -Heading '选择要做成安装盘的 U 盘（Rufus 会清空它）。'
if (-not $disk) { Write-Host '已取消。'; return }

$name = if ($disk.FriendlyName) { [string]$disk.FriendlyName } else { 'USB' }
$style = if ($BootMode -eq 'BIOS') { 'MBR' } else { 'GPT' }
Write-Host ''
Write-Host ("将在 Rufus 中制作：磁盘 {0}  {1}  {2}" -f $disk.Number, $name, (Format-Gb $disk.Size)) -ForegroundColor Yellow
Write-Host ("建议选择：分区结构 {0}；目标系统 {1}；文件系统 NTFS（默认）。" -f $style, $(if ($style -eq 'GPT') { 'UEFI(非 CSM)' } else { 'BIOS(或 UEFI-CSM)' }))
Write-Host 'Rufus 不经过 Ventoy，没有虚拟光驱和过滤驱动，正好验证并绕开 PE 读 U 盘损坏的问题。' -ForegroundColor Green
if ($Confirm -ne 'YES') {
    Write-Host '确认后 Rufus 会打开，点「开始」才会写入。'
    if (-not (Read-Yes)) { Write-Host '已取消。'; return }
}

Write-Log ("启动 Rufus，参数 -i " + $iso)
Start-Process -FilePath $rufus -ArgumentList ('-i "' + $iso + '"') -WorkingDirectory (Split-Path -Parent $rufus) | Out-Null
Write-Host ''
Write-Host 'Rufus 已打开并载入 ISO。请在 Rufus 界面里：' -ForegroundColor Green
Write-Host ("  1. 设备：选磁盘 {0}（{1}）" -f $disk.Number, $name)
Write-Host ("  2. 分区结构：{0}；目标系统：{1}" -f $style, $(if ($style -eq 'GPT') { 'UEFI(非 CSM)' } else { 'BIOS(或 UEFI-CSM)' }))
Write-Host '  3. 其他保持默认，点「开始」，弹出选项选「以 ISO 镜像模式写入(推荐)」'
Write-Host '  4. 等待完成（绿色进度条走完、状态栏变「准备就绪」）'
Write-Host ''
Write-Host '写完后直接用这块 U 盘启动安装，不再有 Ventoy 启动菜单。' -ForegroundColor Green