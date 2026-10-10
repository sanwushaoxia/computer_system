param(
    [string]$Source = '',
    [switch]$KeepSource
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

$items = @(
    'win10\image\Windows_10.iso',
    'win10\image\Win10_22H2_English_x64v1.iso',
    'win7\image\win7_install_usb.iso',
    'win7\image\win7_install_usb.iso.bak',
    'win7\image\iso_clean',
    'ventoy',
    'rufus'
)

function Resolve-Source([string]$Requested) {
    if ($Requested) {
        $path = Join-Path $RepoRoot $Requested
        if (-not (Test-Path -LiteralPath $path)) { $path = $Requested }
        if (-not (Test-Path -LiteralPath $path)) { throw "找不到 $Requested" }
        return (Get-Item -LiteralPath $path).FullName
    }
    $candidates = @(
        (Join-Path $RepoRoot 'pack'),
        (Join-Path $RepoRoot 'pack\computer-system-largefiles.zip')
    )
    $zip = Get-ChildItem -LiteralPath $RepoRoot -Filter 'computer-system-largefiles-*.zip' -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($zip) { $candidates += $zip.FullName }
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'pack')) {
        $inner = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'pack') -Filter 'computer-system-largefiles-*.zip' -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($inner) { $candidates += $inner.FullName }
    }
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return (Get-Item -LiteralPath $path).FullName }
    }
    throw '未找到 pack 目录或 computer-system-largefiles-*.zip。请用 -Source 指定。'
}

$src = Resolve-Source $Source
$staging = $null
if ((Get-Item -LiteralPath $src).PSIsContainer) {
    Write-Host ("导入来源（目录）：{0}" -f $src) -ForegroundColor Cyan
}
else {
    Write-Host ("导入来源（zip）：{0}" -f $src) -ForegroundColor Cyan
    Write-Host '正在解压到临时目录...'
    $staging = Join-Path (Split-Path -Parent $src) ('_unzip_' + $stamp)
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    & tar.exe -xf $src -C $staging
    if ($LASTEXITCODE -ne 0) { throw "zip 解压失败，tar 退出码 $LASTEXITCODE。" }
    $src = $staging
}

$mode = if ($KeepSource) { '复制（保留 pack 源）' } else { '移动（导入后删除 pack 源）' }
Write-Host ("导入方式：{0}" -f $mode) -ForegroundColor Yellow
$found = 0
foreach ($item in $items) {
    if (Test-Path -LiteralPath (Join-Path $src $item)) { $found++ }
}
if ($found -eq 0) { throw '来源里没有可导入的内容。确认这是 Pack-LargeFiles.ps1 生成的包。' }
if (-not $KeepSource) {
    $answer = Read-Host ("将移动导入 {0} 项并删除 pack 源，输入 YES 继续（或回车改用复制）" -f $found)
    if ($answer -ne 'YES') { $KeepSource = $true; Write-Host '已改为复制模式，pack 源保留。' }
}

$restored = @()
foreach ($item in $items) {
    $from = Join-Path $src $item
    if (-not (Test-Path -LiteralPath $from)) {
        Write-Host ("跳过（包内没有）  {0}" -f $item) -ForegroundColor DarkGray
        continue
    }
    $to = Join-Path $RepoRoot $item
    New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
    if ((Get-Item -LiteralPath $from).PSIsContainer) {
        $argList = @($from, $to, '/E', '/IS', '/MT:8', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NP')
        if (-not $KeepSource) { $argList += '/MOVE' }
        & robocopy.exe @argList
        if ($LASTEXITCODE -ge 8) { throw "导入失败：$item，robocopy 退出码 $LASTEXITCODE。" }
    }
    else {
        if ($KeepSource) {
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
        else {
            Move-Item -LiteralPath $from -Destination $to -Force
        }
    }
    $restored += $item
    Write-Host ("完成  {0}" -f $item) -ForegroundColor Green
}

if (-not $KeepSource -and (Test-Path -LiteralPath (Join-Path $src 'README-restore.txt'))) {
    Remove-Item -LiteralPath (Join-Path $src 'README-restore.txt') -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '==== 导入结果 ====' -ForegroundColor Cyan
foreach ($item in $restored) {
    $to = Join-Path $RepoRoot $item
    if (Test-Path -LiteralPath $to -PathType Leaf) {
        Write-Host ("  OK  {0}  ({1:N0} 字节)" -f $item, (Get-Item -LiteralPath $to).Length)
    }
    else {
        $count = @(Get-ChildItem -LiteralPath $to -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host ("  OK  {0}  ({1} 个文件)" -f $item, $count)
    }
}
if ($staging -and (Test-Path -LiteralPath $staging)) {
    $left = @(Get-ChildItem -LiteralPath $staging -Recurse -File -ErrorAction SilentlyContinue).Count
    if ($left -eq 0) {
        Remove-Item -LiteralPath $staging -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host '临时解压目录已清理。'
    }
    else {
        Write-Host ("临时解压目录还剩 {0} 个未导入文件：{1}" -f $left, $staging) -ForegroundColor Yellow
    }
}
Write-Host '导入完成。运行各项目菜单（如 win10\启动Win10安装盘.bat 选 1）确认状态。' -ForegroundColor Green