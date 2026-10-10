$ErrorActionPreference = 'Stop'

$Script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$Script:ToolsDir = Join-Path $Script:ProjectRoot 'tools'
$Script:IsoFileName = 'Windows_10.iso'
$Script:VentoyDir = Join-Path (Split-Path -Parent $Script:ProjectRoot) 'ventoy'
$Script:VentoyDirLocal = Join-Path $Script:ProjectRoot 'ventoy'
$Script:VentoyVersion = ''
$Script:VentoyZipName = ''
$Script:LogFile = $null

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        throw '请以管理员身份运行。双击「启动Win10安装盘.bat」。'
    }
}

function Get-IsoPath {
    $imageDir = Join-Path $Script:ProjectRoot 'image'
    $candidates = @(
        (Join-Path $imageDir $Script:IsoFileName),
        (Join-Path $imageDir 'Win10_22H2_English_x64v1.iso'),
        (Join-Path $Script:ProjectRoot $Script:IsoFileName),
        (Join-Path $Script:ProjectRoot 'Win10_22H2_English_x64v1.iso')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $candidates[0]
}

function Format-Gb($Bytes) {
    if ($null -eq $Bytes) { return '未知' }
    '{0:N1} GB' -f ([double]$Bytes / 1GB)
}

function Write-Log([string]$Message) {
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    if ($Script:LogFile) {
        $utf8 = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::AppendAllText($Script:LogFile, $line + [Environment]::NewLine, $utf8)
    }
    Write-Host $line
}

function Start-Log([string]$Name) {
    $dir = Join-Path $Script:ProjectRoot 'logs'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $Script:LogFile = Join-Path $dir $Name
    Write-Log '==== START ===='
}

function Read-Yes {
    $answer = Read-Host '输入 YES 继续'
    return ($answer -eq 'YES')
}

function Get-VentoyVersions {
    $dirs = @($Script:VentoyDir, $Script:VentoyDirLocal, $Script:ProjectRoot, (Split-Path -Parent $Script:ProjectRoot))
    $versions = @()
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($item in @(Get-ChildItem -LiteralPath $dir -Filter 'ventoy-*-windows.zip' -File -ErrorAction SilentlyContinue)) {
            if ($item.Name -match '^ventoy-([0-9.]+)-windows\.zip$') { $versions += $Matches[1] }
        }
    }
    return @($versions | Select-Object -Unique)
}

function Set-VentoyVersion([string]$Version) {
    $Script:VentoyVersion = $Version
    $Script:VentoyZipName = 'ventoy-' + $Version + '-windows.zip'
}

function Select-VentoyVersion([string]$Requested) {
    $available = Get-VentoyVersions
    if ($available.Count -eq 0) {
        throw ("在 {0} 或 {1} 找不到 ventoy-*-windows.zip。请把 Ventoy 压缩包放进 ventoy 文件夹。" -f $Script:VentoyDir, $Script:VentoyDirLocal)
    }
    if ($Requested) {
        if ($available -notcontains $Requested) {
            throw ("没有 {0} 版的压缩包。可用版本：{1}" -f $Requested, ($available -join ', '))
        }
        Set-VentoyVersion $Requested
        return
    }
    if ($available.Count -eq 1) {
        Set-VentoyVersion $available[0]
        Write-Log ("Ventoy 版本 {0}（只有一个压缩包，自动选择）" -f $available[0])
        return
    }
    $defaultIndex = [Math]::Max(0, [Array]::IndexOf($available, '1.1.05'))
    Write-Host '发现多个 Ventoy 版本：'
    for ($i = 0; $i -lt $available.Count; $i++) {
        $tag = if ($i -eq $defaultIndex) { '（默认，老主板 PE 兼容性更好）' } else { '' }
        Write-Host ('  {0}  {1}{2}' -f ($i + 1), $available[$i], $tag)
    }
    $raw = Read-Host ('输入序号选择版本，回车默认 {0}' -f $available[$defaultIndex])
    $index = $defaultIndex
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        $raw = $raw.Trim()
        if ($raw -notmatch '^\d+$' -or [int]$raw -lt 1 -or [int]$raw -gt $available.Count) {
            throw "序号无效：$raw"
        }
        $index = [int]$raw - 1
    }
    Set-VentoyVersion $available[$index]
    Write-Log ("Ventoy 版本 {0}" -f $Script:VentoyVersion)
}

function Get-VentoyZipPath {
    $candidates = @(
        (Join-Path $Script:VentoyDir $Script:VentoyZipName),
        (Join-Path $Script:VentoyDirLocal $Script:VentoyZipName),
        (Join-Path $Script:ProjectRoot $Script:VentoyZipName),
        (Join-Path (Split-Path -Parent $Script:ProjectRoot) $Script:VentoyZipName)
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Get-VentoyRoot {
    Join-Path $Script:VentoyDir ('ventoy-' + $Script:VentoyVersion)
}

function Get-RufusDir {
    $repoRoot = Split-Path -Parent $Script:ProjectRoot
    $candidates = @(
        (Join-Path $repoRoot 'rufus'),
        (Join-Path $Script:ProjectRoot 'tools\Rufus'),
        $repoRoot,
        $Script:ProjectRoot
    )
    foreach ($dir in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $dir 'rufus-4.15p.exe')) { return $dir }
    }
    foreach ($dir in $candidates) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $hit = Get-ChildItem -LiteralPath $dir -Filter 'rufus*.exe' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^rufus(-[0-9][^.]*)?\.exe$' } |
            Sort-Object Name -Descending |
            Select-Object -First 1
        if ($hit) { return $dir }
    }
    return $null
}

function Get-RufusExe {
    $dir = Get-RufusDir
    if (-not $dir) { return $null }
    $exe = Join-Path $dir 'rufus-4.15p.exe'
    if (Test-Path -LiteralPath $exe) { return $exe }
    $hit = Get-ChildItem -LiteralPath $dir -Filter 'rufus*.exe' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^rufus(-[0-9][^.]*)?\.exe$' } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

function Ensure-VentoyExtracted {
    $root = Get-VentoyRoot
    $versionFile = Join-Path $root 'ventoy\version'
    $imageFile = Join-Path $root 'ventoy\ventoy.disk.img.xz'
    $ready = $false
    if ((Test-Path -LiteralPath $versionFile) -and (Test-Path -LiteralPath $imageFile)) {
        $text = ([System.IO.File]::ReadAllText($versionFile)).Trim()
        if ($text -eq $Script:VentoyVersion) { $ready = $true }
    }
    if ($ready) { return $root }

    $zip = Get-VentoyZipPath
    if (-not $zip) {
        throw ("找不到 {0}。请放在 win10 目录，或放在它的上一级目录。" -f $Script:VentoyZipName)
    }
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Script:VentoyDir -Force | Out-Null
    Unblock-File -LiteralPath $zip -ErrorAction SilentlyContinue
    Write-Log ("正在解压 " + $zip)
    try {
        Expand-Archive -LiteralPath $zip -DestinationPath $Script:VentoyDir -Force
    }
    catch {
        Write-Log ("Expand-Archive 失败，改用 tar：" + $_.Exception.Message)
        & tar.exe -xf $zip -C $Script:VentoyDir
        if ($LASTEXITCODE -ne 0) { throw "解压 Ventoy 失败，tar 退出码 $LASTEXITCODE。" }
    }
    if (-not (Test-Path -LiteralPath $imageFile)) {
        throw "解压后找不到 $imageFile"
    }
    return $root
}

function Get-VentoyExe([string]$Root) {
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($arch -eq 'ARM64') {
        $exe = Join-Path $Root 'altexe\Ventoy2Disk_ARM64.exe'
    }
    elseif ($arch -eq 'ARM') {
        $exe = Join-Path $Root 'altexe\Ventoy2Disk_ARM.exe'
    }
    elseif ([Environment]::Is64BitOperatingSystem) {
        $exe = Join-Path $Root 'altexe\Ventoy2Disk_X64.exe'
    }
    else {
        $exe = Join-Path $Root 'Ventoy2Disk.exe'
    }
    if (-not (Test-Path -LiteralPath $exe)) { throw "找不到 $exe" }
    return $exe
}

function Get-DiskLetterText([int]$Number) {
    $letters = @(Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue |
        Where-Object { $_.DriveLetter } |
        ForEach-Object { '{0}:' -f $_.DriveLetter })
    if ($letters.Count -eq 0) { return '无盘符' }
    return ($letters -join ', ')
}

function Get-OnlineUsbDisks {
    @(Get-Disk | Where-Object {
        $_.BusType -eq 'USB' -and $_.Size -gt 0 -and $_.OperationalStatus -eq 'Online'
    } | Sort-Object Number)
}

function Assert-UsbTarget($Disk) {
    if ($Disk.BusType -ne 'USB') { throw "磁盘 $($Disk.Number) 不是 USB 磁盘。" }
    if ($Disk.IsBoot -or $Disk.IsSystem) { throw "磁盘 $($Disk.Number) 是系统盘或启动盘，已拒绝。" }
    $systemPart = Get-Partition -DriveLetter C -ErrorAction SilentlyContinue
    if ($systemPart -and $systemPart.DiskNumber -eq $Disk.Number) {
        throw '不能选择系统所在的磁盘。'
    }
    $paths = @($Script:ProjectRoot)
    $iso = Get-IsoPath
    if (Test-Path -LiteralPath $iso) { $paths += $iso }
    foreach ($path in $paths) {
        $full = (Resolve-Path -LiteralPath $path).Path
        $root = [System.IO.Path]::GetPathRoot($full)
        if (-not $root -or $root.Length -lt 2) { continue }
        $letter = $root.Substring(0, 1)
        if ($letter -notmatch '^[A-Za-z]$') { continue }
        $part = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue
        if ($part -and $part.DiskNumber -eq $Disk.Number) {
            throw '脚本或 ISO 位于这块磁盘上，不能对它写入。请把文件放到其他磁盘后再执行。'
        }
    }
}

function Assert-SameUsb($Disk) {
    $now = Get-Disk -Number $Disk.Number -ErrorAction SilentlyContinue
    if (-not $now -or $now.BusType -ne 'USB' -or $now.OperationalStatus -ne 'Online') {
        throw "磁盘 $($Disk.Number) 已经不在了，或已不是 USB 盘。已中止。"
    }
    Assert-UsbTarget $now
    if ($now.Size -ne $Disk.Size -or $now.FriendlyName -ne $Disk.FriendlyName) {
        throw "磁盘 $($Disk.Number) 的信息发生了变化。请重新选择。"
    }
}

function Read-UsbDisk([string]$Heading) {
    $usbs = Get-OnlineUsbDisks
    Write-Host ''
    Write-Host $Heading
    if ($usbs.Count -eq 0) { throw '没有检测到 U 盘。请插入后重试。' }
    foreach ($d in $usbs) {
        $name = if ($d.FriendlyName) { [string]$d.FriendlyName } else { 'USB' }
        if ($name.Length -gt 28) { $name = $name.Substring(0, 28) }
        Write-Host ('  磁盘 {0,-3} {1,-28} {2,10}  {3,-6}  {4}' -f $d.Number, $name, (Format-Gb $d.Size), $d.PartitionStyle, (Get-DiskLetterText $d.Number))
    }
    $raw = Read-Host '输入磁盘号，直接回车取消'
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $raw = $raw.Trim()
    if ($raw -notmatch '^\d+$') { throw '磁盘号必须是数字。' }
    $number = [int]$raw
    $disk = $usbs | Where-Object { $_.Number -eq $number } | Select-Object -First 1
    if (-not $disk) { throw "磁盘 $number 不在上面的 U 盘列表中，已拒绝。" }
    Assert-UsbTarget $disk
    if ([double]$disk.Size -gt 128GB) {
        Write-Host '这块盘大于 128GB，请确认没有选错。' -ForegroundColor Yellow
    }
    return $disk
}

function Resolve-UsbDisk([int]$DiskNumber, [string]$Heading) {
    if ($DiskNumber -ge 0) {
        $disk = Get-OnlineUsbDisks | Where-Object { $_.Number -eq $DiskNumber } | Select-Object -First 1
        if (-not $disk) { throw "磁盘 $DiskNumber 不是当前在线的 USB 磁盘。" }
        Assert-UsbTarget $disk
        return $disk
    }
    return Read-UsbDisk $Heading
}

function Get-FreeDriveLetter {
    $used = @{}
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem)) { $used[$d.Name] = $true }
    foreach ($vol in @(Get-Volume -ErrorAction SilentlyContinue)) {
        if ($vol.DriveLetter) { $used[[string]$vol.DriveLetter] = $true }
    }
    foreach ($n in ([int][char]'D')..([int][char]'Z')) {
        $letter = [string][char]$n
        if (-not $used.ContainsKey($letter)) { return $letter }
    }
    throw '没有可用的盘符。'
}

function Get-VolumeLabelText($Volume) {
    if (-not $volume -or -not $volume.FileSystemLabel) { return '' }
    return $volume.FileSystemLabel.Trim()
}
