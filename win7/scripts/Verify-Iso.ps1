$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
Start-Log 'verify.log'

$iso = Get-IsoPath
if (-not (Test-Path -LiteralPath $iso)) { throw "找不到 $iso" }
$item = Get-Item -LiteralPath $iso
$rec = Get-IsoRecord
$problems = New-Object System.Collections.Generic.List[string]

Write-Log ("文件 " + $item.FullName)
Write-Log ("大小 {0} ({1} 字节)" -f (Format-Gb $item.Length), $item.Length)
if ($rec.Size -gt 0 -and $rec.Size -ne $item.Length) {
    [void]$problems.Add("大小与记录不一致：记录 $($rec.Size) 字节")
}

Write-Log '正在计算 SHA256，大约需要一分钟...'
$hash = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
Write-Log ("SHA256=" + $hash)
if (-not $rec.Hash) {
    [void]$problems.Add('没有 SHA256 记录')
}
elseif ($rec.Hash.ToUpperInvariant() -ne $hash.ToUpperInvariant()) {
    Write-Log ("记录=" + $rec.Hash)
    [void]$problems.Add('哈希与 SHA256.txt 不一致')
}
else {
    Write-Log '哈希与记录一致'
}

$letter = Mount-IsoLetter $iso
try {
    $root = "${letter}:\"
    Write-Log ("已挂载为 ${letter}:")
    Get-ChildItem -LiteralPath $root -Force | ForEach-Object { Write-Log ("顶层 " + $_.Name) }
    if (Test-Path -LiteralPath (Join-Path $root 'System Volume Information')) {
        [void]$problems.Add('镜像里仍有 System Volume Information')
    }
    else {
        Write-Log '没有 System Volume Information'
    }
    try { Assert-InstallTree $root } catch { [void]$problems.Add($_.Exception.Message) }
    $big = @(Get-OversizeFiles $root)
    Write-Log ("大于等于 4GB 的文件：{0}" -f $big.Count)
    foreach ($file in $big) { Write-Log $file.FullName }
    if ($big.Count -gt 0) { [void]$problems.Add('含有大于等于 4GB 的文件，无法写入 FAT32') }
}
finally {
    Dismount-IsoFile $iso
}

if ($problems.Count -gt 0) {
    foreach ($problem in $problems) { Write-Log ("问题 " + $problem) }
    throw ("校验未通过：" + ($problems -join '；'))
}
Write-Log '校验通过'
Write-Host '校验通过。' -ForegroundColor Green
