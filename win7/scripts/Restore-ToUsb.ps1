$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
Start-Log 'restore.log'
$sw = [Diagnostics.Stopwatch]::StartNew()

$iso = Get-IsoPath
if (-not (Test-Path -LiteralPath $iso)) { throw "找不到 $iso" }
$bootsect = Get-BootsectPath
if (-not $bootsect) { throw '找不到 bootsect.exe，无法写入启动扇区。' }

$disk = Read-UsbDisk '选择要写入的 U 盘。这一步会清空该盘上的全部数据。'
if (-not $disk) { Write-Host '已取消。'; return }
if ([double]$disk.Size -lt 7GB) { throw 'U 盘容量不足。请使用 8GB 到 32GB 的 U 盘。' }
if ([double]$disk.Size -gt 34GB) {
    throw '目标盘大于 32GB。Windows 自带工具通常无法把它格式化成 FAT32。请换一块 8GB 到 32GB 的 U 盘。'
}
$name = if ($disk.FriendlyName) { [string]$disk.FriendlyName } else { 'USB' }
Write-Host ''
Write-Host ("将清空并格式化  磁盘 {0}  {1}  {2}" -f $disk.Number, $name, (Format-Gb $disk.Size)) -ForegroundColor Yellow
Write-Host '盘上的文件会全部消失。' -ForegroundColor Yellow
if (-not (Read-Yes)) { Write-Host '已取消。'; return }

Write-Log '正在计算 SHA256，大约需要一分钟...'
$hash = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
$rec = Get-IsoRecord
Write-Log ("SHA256=" + $hash)
if ($rec.Hash -and ($rec.Hash.ToUpperInvariant() -ne $hash.ToUpperInvariant())) {
    Write-Host ("记录  " + $rec.Hash) -ForegroundColor Yellow
    Write-Host ("实际  " + $hash) -ForegroundColor Yellow
    if (-not (Read-Token '镜像哈希与 SHA256.txt 不一致。' 'CONTINUE')) {
        Write-Host '已取消。'
        return
    }
}
elseif (-not $rec.Hash) {
    if (-not (Read-Token '没有 SHA256.txt，无法核对镜像。' 'CONTINUE')) {
        Write-Host '已取消。'
        return
    }
}
else {
    Write-Log '哈希与记录一致'
}

$mounted = $false
$wiped = $false
try {
    Write-Log '正在挂载 ISO...'
    $isoLetter = Mount-IsoLetter $iso
    $mounted = $true
    $source = "${isoLetter}:\"
    Assert-InstallTree $source
    if (Test-Path -LiteralPath (Join-Path $source 'System Volume Information')) {
        Write-Log '源 ISO 含有 System Volume Information，复制时会跳过。建议之后用菜单第 5 项重建。'
    }
    $big = @(Get-OversizeFiles $source)
    if ($big.Count -gt 0) {
        foreach ($file in $big) { Write-Log $file.FullName }
        throw '镜像里有大于等于 4GB 的文件，FAT32 无法保存。'
    }

    Assert-SameUsb $disk
    $letter = Get-FreeDriveLetter
    Write-Log ("目标盘 磁盘 {0} {1}，将使用盘符 {2}:" -f $disk.Number, $name, $letter)
    Write-Log 'diskpart: clean + FAT32 + active'
    Invoke-Diskpart (@(
        "select disk $($disk.Number)"
        'clean'
        'create partition primary'
        'active'
        "format fs=fat32 quick label=$($Script:UsbLabel)"
        "assign letter=$letter"
        'exit'
    ) -join "`r`n")
    $wiped = $true
    Start-Sleep -Seconds 2
    $dest = "${letter}:\"
    if (-not (Test-Path -LiteralPath $dest)) { throw "格式化后没有出现 ${letter}:" }
    $fs = (Get-Volume -DriveLetter $letter).FileSystem
    Write-Log ("卷 {0}: 文件系统={1}" -f $letter, $fs)
    if ($fs -ne 'FAT32') { throw "期望 FAT32，实际为 $fs" }

    Write-Log '正在复制安装文件...'
    $items = @(Get-ChildItem -LiteralPath $source -Force | Where-Object {
        $_.Name -notin @('System Volume Information', '$RECYCLE.BIN', 'RECYCLER')
    })
    foreach ($item in $items) {
        Write-Log ("复制 " + $item.Name)
        $target = Join-Path $dest $item.Name
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            & robocopy.exe $item.FullName $target /E /XJ /XD 'System Volume Information' /R:2 /W:1 /NFL /NDL /NJH /NJS | Out-Null
            $code = $LASTEXITCODE
            if ($code -ge 8) { throw "复制 $($item.Name) 失败，robocopy 退出码 $code。" }
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
    Assert-InstallTree $dest
    Write-Log '正在写入启动扇区...'
    & $bootsect /nt60 "${letter}:" /mbr /force
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "bootsect 失败，退出码 $code。请关掉正在打开该 U 盘的窗口后重试。" }
    Write-Log ("完成，用时 {0:n0} 秒" -f $sw.Elapsed.TotalSeconds)
    Write-Host ''
    Write-Host ("完成：{0}: 已是 FAT32 / MBR 安装盘。" -f $letter) -ForegroundColor Green
    Write-Host '请用 USB 2.0 接口启动，并在 BIOS 中启用 Legacy/CSM。' -ForegroundColor Green
}
catch {
    $msg = $_.Exception.Message
    if ($wiped) { $msg += ' U 盘已经被清空，请排除问题后重新执行菜单第 4 项。' }
    throw $msg
}
finally {
    if ($mounted) { Dismount-IsoFile $iso }
}
