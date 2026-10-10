param(
    [switch]$Zip
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$PackDir = Join-Path $RepoRoot 'pack'

$items = @(
    @{ Rel = 'win10\image\Windows_10.iso';              Kind = 'File' },
    @{ Rel = 'win10\image\Win10_22H2_English_x64v1.iso'; Kind = 'File' },
    @{ Rel = 'win7\image\win7_install_usb.iso';          Kind = 'File' },
    @{ Rel = 'win7\image\win7_install_usb.iso.bak';      Kind = 'File' },
    @{ Rel = 'win7\image\iso_clean';                     Kind = 'Dir' },
    @{ Rel = 'ventoy';                                   Kind = 'Dir' },
    @{ Rel = 'rufus';                                    Kind = 'Dir' }
)

function Format-Gb($Bytes) { '{0:N1} GB' -f ([double]$Bytes / 1GB) }

function Get-TreeSize([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return [int64](Get-Item -LiteralPath $Path).Length }
    $sum = 0
    Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { $sum += $_.Length }
    return $sum
}

Write-Host '==== 打包大文件（这些文件不进 git，需通过压缩包/网盘上传） ====' -ForegroundColor Cyan
$packItems = @()
foreach ($item in $items) {
    $src = Join-Path $RepoRoot $item.Rel
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host ("跳过（不存在）  {0}" -f $item.Rel) -ForegroundColor DarkGray
        continue
    }
    $size = Get-TreeSize $src
    Write-Host ("{0,-6} {1,10}  {2}" -f $item.Kind, (Format-Gb $size), $item.Rel)
    $packItems += $item
}
if ($packItems.Count -eq 0) { throw '没有可打包的文件。' }
$total = 0
foreach ($item in $packItems) { $total += Get-TreeSize (Join-Path $RepoRoot $item.Rel) }
Write-Host ("合计约 {0}。磁盘剩余空间请自行确认。" -f (Format-Gb $total)) -ForegroundColor Yellow

New-Item -ItemType Directory -Path $PackDir -Force | Out-Null

$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$zipPath = Join-Path $PackDir ('computer-system-largefiles-' + $stamp + '.zip')

if ($Zip) {
    Write-Host '正在用 tar.exe 生成 zip（ISO/WIM 已压缩过，不会再变小）...'
    $argList = @('-a', '-c', '-f', $zipPath)
    foreach ($item in $packItems) { $argList += $item.Rel }
    & tar.exe @argList
    if ($LASTEXITCODE -ne 0) { throw "tar 打包失败，退出码 $LASTEXITCODE。" }
    Write-Host ("已生成 {0}（{1}）" -f $zipPath, (Format-Gb (Get-Item -LiteralPath $zipPath).Length)) -ForegroundColor Green
}
else {
    Write-Host '正在复制到 pack\（同分区下 ISO 用硬链接，秒完成；目录用 robocopy）...'
    foreach ($item in $packItems) {
        $src = Join-Path $RepoRoot $item.Rel
        $dst = Join-Path $PackDir $item.Rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        if ($item.Kind -eq 'File') {
            $link = Join-Path $PackDir $item.Rel
            if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force }
            try {
                New-Item -ItemType HardLink -Path $link -Target $src | Out-Null
                Write-Host ("硬链接  {0}" -f $item.Rel) -ForegroundColor Gray
            }
            catch {
                Copy-Item -LiteralPath $src -Destination $dst -Force
                Write-Host ("复制    {0}" -f $item.Rel) -ForegroundColor Gray
            }
        }
        else {
            & robocopy.exe $src $dst /E /MT:8 /R:1 /W:1 /NFL /NDL /NJH /NP
            if ($LASTEXITCODE -ge 8) { throw "复制失败：$item.Rel，robocopy 退出码 $LASTEXITCODE。" }
            Write-Host ("复制    {0}" -f $item.Rel) -ForegroundColor Gray
        }
    }
    Write-Host ("已生成 {0}" -f $PackDir) -ForegroundColor Green
}

$manifest = @(
    'computer-system 大文件包（git 仓库之外的部分）',
    ''
    '恢复方法：把下列条目放回仓库根目录的对应位置即可。'
    ''
)
foreach ($item in $packItems) {
    $manifest += ('  {0}  ->  仓库根目录\{1}' -f $item.Rel, $item.Rel)
}
$manifest += ''
$manifest += '生成时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
if ($Zip) { $manifest += '打包方式：zip（tar.exe）' } else { $manifest += '打包方式：pack 目录（ISO 为硬链接，上传/压缩前请勿删除源文件）' }
[System.IO.File]::WriteAllLines((Join-Path $PackDir 'README-restore.txt'), $manifest, (New-Object System.Text.UTF8Encoding $true))
Write-Host '恢复说明已写入 pack\README-restore.txt' -ForegroundColor Green