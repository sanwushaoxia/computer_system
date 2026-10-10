param(
    [int]$DiskNumber = -1,
    [string]$Confirm = '',
    [ValidateSet('Install', 'CopyOnly')]
    [string]$Mode = 'Install',
    [ValidatePattern('^[A-Za-z]$')]
    [string]$SourceDriveLetter = 'D',
    [ValidateSet('Auto', 'UEFI', 'BIOS')]
    [string]$BootMode = 'Auto',
    [ValidatePattern('^$|^[0-9.]+$')]
    [string]$VentoyVersion = '',
    [ValidateSet('exFAT', 'NTFS')]
    [string]$PartitionFs = 'exFAT'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-Admin
Start-Log 'make.log'
$sw = [Diagnostics.Stopwatch]::StartNew()

if ($Mode -eq 'Install') { Select-VentoyVersion $VentoyVersion }

$iso = Get-IsoPath
if (-not (Test-Path -LiteralPath $iso)) { throw "找不到 $iso" }
$isoItem = Get-Item -LiteralPath $iso
$isoLen = [int64]$isoItem.Length
if ($isoLen -lt 1GB) { throw "ISO 太小（$isoLen 字节），不像是完整的 Win10 安装镜像。" }

$heading = '选择要写入的 U 盘。'
if ($Mode -eq 'Install') {
    $heading = '选择要做成安装盘的 U 盘。'
}
else {
    $heading = '选择已经装有 Ventoy 的 U 盘。这一步只复制 ISO，不格式化。'
}
$disk = Resolve-UsbDisk -DiskNumber $DiskNumber -Heading $heading
if (-not $disk) { Write-Host '已取消。'; return }

$reserve = 128MB
if ($Mode -eq 'Install' -and [int64]$disk.Size -lt ($isoLen + $reserve)) {
    throw ("U 盘容量不足。ISO 为 {0}，请使用大于 {1} 的 U 盘。" -f (Format-Gb $isoLen), (Format-Gb ($isoLen + $reserve)))
}

$name = if ($disk.FriendlyName) { [string]$disk.FriendlyName } else { 'USB' }
$useGpt = if ($BootMode -eq 'UEFI') { $true }
elseif ($BootMode -eq 'BIOS') { $false }
else { [int64]$disk.Size -gt 2TB }
$styleText = if ($useGpt) { 'GPT' } else { 'MBR' }

function Get-PartVolume($Part) {
    try { return Get-Volume -Partition $Part -ErrorAction SilentlyContinue }
    catch { return $null }
}

function Get-VentoyDataPartition([int]$Number) {
    $found = $null
    $efi = $false
    foreach ($part in @(Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue)) {
        $vol = Get-PartVolume $part
        $label = Get-VolumeLabelText $vol
        if ($label -eq 'VTOYEFI') { $efi = $true }
        if ($label -eq 'Ventoy') { $found = $part }
    }
    if ($found) { return $found }
    if (-not $efi) { throw '这块 U 盘上看不到 Ventoy 分区。请先用菜单第 2 项制作。' }
    $parts = @(Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue | Sort-Object Size -Descending)
    if ($parts.Count -eq 0) { throw '这块 U 盘上没有分区。' }
    return $parts[0]
}

function Wait-VentoyDataPartition([int]$Number) {
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        try { Update-HostStorageCache | Out-Null } catch {}
        try {
            $now = Get-Disk -Number $Number
            if ($now.IsOffline) { Set-Disk -Number $Number -IsOffline $false }
            if ($now.IsReadOnly) { Set-Disk -Number $Number -IsReadOnly $false }
        }
        catch {}
        foreach ($part in @(Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue)) {
            $vol = Get-PartVolume $part
            $label = Get-VolumeLabelText $vol
            if ($label -eq 'Ventoy' -and $vol.FileSystem -in @('NTFS', 'exFAT')) {
                return $part
            }
        }
        Start-Sleep -Seconds 2
    }
    throw 'Ventoy 安装后 90 秒内没有出现名为 Ventoy 的分区。请重新插拔 U 盘，再用菜单第 3 项只复制 ISO。'
}

function Set-PartitionLetter($Part) {
    $current = Get-Partition -DiskNumber $Part.DiskNumber -PartitionNumber $Part.PartitionNumber
    if ($current.DriveLetter -and ([int][char]$current.DriveLetter) -ne 0) {
        return [string]$current.DriveLetter
    }
    $letter = Get-FreeDriveLetter
    Set-Partition -DiskNumber $current.DiskNumber -PartitionNumber $current.PartitionNumber -NewDriveLetter $letter
    Start-Sleep -Seconds 2
    $again = Get-Partition -DiskNumber $current.DiskNumber -PartitionNumber $current.PartitionNumber
    if (-not $again.DriveLetter) { throw "无法为 Ventoy 分区分配盘符 $letter" }
    return [string]$again.DriveLetter
}

function Invoke-VentoyInstall([string]$Root, [string]$Exe, [int]$Number, [bool]$Gpt, [string]$Fs) {
    foreach ($logName in @('cli_done.txt', 'cli_log.txt', 'cli_percent.txt')) {
        $path = Join-Path $Root $logName
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    $argList = @('VTOYCLI', '/I', ('/PhyDrive:' + $Number), ('/FS:' + $Fs))
    if ($Gpt) { $argList += '/GPT' }
    Write-Log ("运行 " + $Exe + ' ' + ($argList -join ' '))
    Write-Host '如果 Windows 弹出「需要格式化磁盘」，直接关掉，不要格式化。' -ForegroundColor Yellow
    $proc = Start-Process -FilePath $Exe -ArgumentList $argList -WorkingDirectory $Root -PassThru -WindowStyle Hidden
    $deadline = (Get-Date).AddMinutes(10)
    $lastPercent = ''
    while (-not $proc.HasExited) {
        if ((Get-Date) -gt $deadline) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            throw 'Ventoy 安装超过 10 分钟，已中止。U 盘可能已被清空，请重新制作。'
        }
        $percentFile = Join-Path $Root 'cli_percent.txt'
        if (Test-Path -LiteralPath $percentFile) {
            $text = ''
            try { $text = ([System.IO.File]::ReadAllText($percentFile)).Trim() } catch {}
            if ($text -and $text -ne $lastPercent) {
                $lastPercent = $text
                Write-Log ("Ventoy 进度 " + $text)
            }
        }
        Start-Sleep -Seconds 1
    }
    try { $proc.Refresh() } catch {}
    Write-Log ("Ventoy 进程退出码 " + $proc.ExitCode)
    $logPath = Join-Path $Root 'cli_log.txt'
    $log = ''
    if (Test-Path -LiteralPath $logPath) {
        $log = [System.IO.File]::ReadAllText($logPath)
        $tail = @($log -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 20)
        foreach ($line in $tail) { Write-Log $line }
    }
    $okAt = $log.LastIndexOf('Ventoy CLI SUCCESS')
    $badAt = $log.LastIndexOf('Ventoy CLI FAILED')
    if ($okAt -lt 0 -or $badAt -gt $okAt) {
        throw ("Ventoy 安装失败。详情见 logs\make.log 和 tools\ventoy-{0}\cli_log.txt。" -f $Script:VentoyVersion)
    }
}

function Copy-FileWithProgress([string]$Source, [string]$Dest, [string]$Title) {
    $total = [int64](Get-Item -LiteralPath $Source).Length
    Write-Log ("{0}：{1}（{2}）。每 5 秒报一次进度。" -f $Title, $Dest, (Format-Gb $total))
    $buffer = New-Object byte[] 1MB
    $inFile = $null
    $outFile = $null
    try {
        $inFile = [System.IO.File]::Open($Source, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $outFile = [System.IO.File]::Open($Dest, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $copiedBytes = [int64]0
        $lastLog = [datetime]::MinValue
        while (($read = $inFile.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $outFile.Write($buffer, 0, $read)
            $copiedBytes += $read
            $now = Get-Date
            if (($now - $lastLog).TotalSeconds -ge 5) {
                $pct = [int](($copiedBytes * 100) / $total)
                Write-Log ("已复制 {0} / {1}（{2}%）" -f (Format-Gb $copiedBytes), (Format-Gb $total), $pct)
                $lastLog = $now
            }
        }
        $outFile.Flush()
    }
    finally {
        if ($outFile) { $outFile.Dispose() }
        if ($inFile) { $inFile.Dispose() }
    }
    $copied = [int64](Get-Item -LiteralPath $Dest).Length
    if ($copied -ne $total) { throw "复制不完整。源 $total 字节，目标 $copied 字节。" }
}

function Get-SetupImageName([string]$IsoLetter) {
    foreach ($name in @('install.wim', 'install.esd')) {
        $path = '{0}:\sources\{1}' -f $IsoLetter, $name
        if (Test-Path -LiteralPath $path) { return $name }
    }
    return $null
}

function Get-MountedIsoLetter {
    $img = Mount-DiskImage -ImagePath $iso -PassThru
    try {
        for ($i = 0; $i -lt 20; $i++) {
            $vol = Get-DiskImage -ImagePath $iso | Get-Volume -ErrorAction SilentlyContinue
            if ($vol -and $vol.DriveLetter) { return [string]$vol.DriveLetter }
            Start-Sleep -Milliseconds 500
        }
    }
    catch {
        Dismount-DiskImage -ImagePath $iso | Out-Null
        throw
    }
    Dismount-DiskImage -ImagePath $iso | Out-Null
    throw '挂载 ISO 后没有盘符。'
}

function Test-SetupSourceReady([string]$UsbLetter) {
    $isoLetter = Get-MountedIsoLetter
    try {
        $name = Get-SetupImageName $isoLetter
        if (-not $name) { return $false }
        $src = '{0}:\sources\{1}' -f $isoLetter, $name
        $dst = '{0}:\sources\{1}' -f $UsbLetter, $name
        $boot = '{0}:\bootmgr' -f $UsbLetter
        if (-not (Test-Path -LiteralPath $dst)) { return $false }
        if (-not (Test-Path -LiteralPath $boot)) { return $false }
        return ([int64](Get-Item -LiteralPath $dst).Length -eq [int64](Get-Item -LiteralPath $src).Length)
    }
    finally {
        try { Dismount-DiskImage -ImagePath $iso | Out-Null } catch {}
    }
}

function Expand-SetupSource([string]$UsbLetter) {
    Write-Log '正在挂载 ISO，准备解出安装程序要读的系统镜像。'
    $isoLetter = Get-MountedIsoLetter
    try {
        $name = Get-SetupImageName $isoLetter
        if (-not $name) { throw 'ISO 里没有 sources\install.wim 或 install.esd。' }
        $src = '{0}:\sources\{1}' -f $isoLetter, $name
        $dstDir = '{0}:\sources' -f $UsbLetter
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
        $dst = Join-Path $dstDir $name
        $srcLen = [int64](Get-Item -LiteralPath $src).Length
        $existing = [int64]0
        if (Test-Path -LiteralPath $dst) { $existing = [int64](Get-Item -LiteralPath $dst).Length }
        if ($existing -eq $srcLen) {
            Write-Log ("{0} 已在 U 盘上，大小一致，跳过解出。" -f $name)
        }
        else {
            $vol = Get-Volume -DriveLetter $UsbLetter
            if (([int64]$vol.SizeRemaining + $existing) -lt $srcLen) {
                throw ("剩余空间不足，无法解出 {0}。" -f $name)
            }
            Copy-FileWithProgress $src $dst ("正在解出 " + $name)
        }
        Write-Log '正在复制 ISO 中的其余安装文件...'
        & robocopy.exe ('{0}:\' -f $isoLetter) ('{0}:\' -f $UsbLetter) /E /R:1 /W:1 /XF $name bootmgr bootmgr.efi bootx64.efi cdboot.efi cdboot_noprompt.efi memtest.efi autorun.inf /XD 'System Volume Information' '$RECYCLE.BIN' boot efi support /NFL /NDL /NJH
        if ($LASTEXITCODE -ge 8) { throw "复制安装文件失败，robocopy 退出码 $LASTEXITCODE。" }
        Write-Log ("安装源已放在 {0}:\sources\{1}" -f $UsbLetter, $name)
    }
    finally {
        try { Dismount-DiskImage -ImagePath $iso | Out-Null } catch {}
    }
}

function Copy-InstallIso([string]$Letter) {
    $destDir = '{0}:\' -f $Letter
    $dest = Join-Path $destDir $Script:IsoFileName
    $vol = Get-Volume -DriveLetter $Letter
    if (-not $vol) { throw "找不到盘符 ${Letter}:" }
    if ($vol.FileSystem -eq 'FAT32' -and $isoLen -ge 4GB) {
        throw '目标卷是 FAT32，放不下这个 ISO。请用菜单第 2 项重新制作。'
    }
    $existing = [int64]0
    if (Test-Path -LiteralPath $dest) {
        $existing = [int64](Get-Item -LiteralPath $dest).Length
        if ($existing -eq $isoLen) {
            Write-Log 'U 盘上的 ISO 大小与源文件一致，跳过复制。'
            return $dest
        }
        Write-Log 'U 盘上的 ISO 大小不一致，将重新复制。'
    }
    $free = [int64]$vol.SizeRemaining
    if (($free + $existing) -lt $isoLen) {
        throw ("剩余空间不足。需要 {0}，约剩余 {1}。" -f (Format-Gb $isoLen), (Format-Gb $free))
    }
    Copy-FileWithProgress $iso $dest '正在复制 ISO'
    Write-Log 'ISO 大小核对一致。'
    return $dest
}

function Test-VentoyMbr([int]$Number) {
    try {
        $stream = [System.IO.File]::Open('\\.\PHYSICALDRIVE' + $Number, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $buffer = New-Object byte[] 512
            [void]$stream.Read($buffer, 0, 512)
        }
        finally { $stream.Dispose() }
        $text = [System.Text.Encoding]::ASCII.GetString($buffer)
        if ($text -match 'NTLDR') {
            Write-Log 'MBR 已是 NT60 直接启动引导，不再是 Ventoy。'
            return $false
        }
        return $true
    }
    catch {
        return $true
    }
}

function Test-VentoyInstallComplete([int]$Number) {
    $style = ''
    try { $style = (Get-Disk -Number $Number -ErrorAction Stop).PartitionStyle } catch {}
    $shown = if ($style) { $style } else { '未知' }
    if ($BootMode -eq 'UEFI' -and $style -ne 'GPT') {
        Write-Log ("分区表为 {0}，UEFI 制作要求 GPT，需要重装 Ventoy。" -f $shown)
        return $false
    }
    if ($BootMode -eq 'BIOS' -and $style -ne 'MBR') {
        Write-Log ("分区表为 {0}，BIOS 制作要求 MBR，需要重装 Ventoy。" -f $shown)
        return $false
    }
    if (-not (Test-VentoyMbr $Number)) { return $false }
    $dataPart = $null
    $efiPart = $null
    foreach ($part in @(Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue)) {
        $vol = Get-PartVolume $part
        $label = Get-VolumeLabelText $vol
        if ($label -eq 'Ventoy') { $dataPart = $part }
        elseif ($label -eq 'VTOYEFI') { $efiPart = $part }
    }
    if (-not $dataPart) {
        Write-Log '没有名为 Ventoy 的分区，需要安装。'
        return $false
    }
    if (-not $efiPart) {
        Write-Log '没有 VTOYEFI 分区，Ventoy 未安装完整。'
        return $false
    }
    $dataVol = Get-PartVolume $dataPart
    $dataFs = ''
    if ($dataVol -and $dataVol.FileSystem) { $dataFs = [string]$dataVol.FileSystem }
    if ($dataFs -notin @('NTFS', 'exFAT')) {
        $shown = if ($dataFs) { $dataFs } else { '未知' }
        Write-Log ("Ventoy 分区文件系统为 {0}。FAT32 放不下超过 4GB 的 ISO，请用菜单第 2 项重装。" -f $shown)
        return $false
    }
    if ($Mode -eq 'Install' -and $dataFs -ne $PartitionFs) {
        Write-Log ("数据分区文件系统为 {0}，与选择的 {1} 不一致，需要重装 Ventoy。" -f $dataFs, $PartitionFs)
        return $false
    }
    $efiVol = Get-PartVolume $efiPart
    $efiFs = ''
    if ($efiVol -and $efiVol.FileSystem) { $efiFs = [string]$efiVol.FileSystem }
    if ($efiFs -notin @('FAT', 'FAT32')) {
        $shown = if ($efiFs) { $efiFs } else { '未知' }
        Write-Log ("VTOYEFI 文件系统为 {0}，未安装完整。" -f $shown)
        return $false
    }
    $letter = $null
    try { $letter = Set-PartitionLetter $efiPart }
    catch {
        Write-Log ("无法读取 VTOYEFI：{0}" -f $_.Exception.Message)
        return $false
    }
    $root = '{0}:\' -f $letter
    $need = @(
        @{ Rel = 'EFI\BOOT\BOOTX64.EFI'; Min = 512KB },
        @{ Rel = 'grub\grub.cfg'; Min = 1KB },
        @{ Rel = 'ventoy\ventoy.cpio'; Min = 10KB },
        @{ Rel = 'ventoy\ventoy_x64.efi'; Min = 32KB }
    )
    foreach ($item in $need) {
        $path = Join-Path $root $item.Rel
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Log ("缺少 {0}，Ventoy 未安装完整。" -f $path)
            return $false
        }
        $len = [int64](Get-Item -LiteralPath $path).Length
        if ($len -lt [int64]$item.Min) {
            Write-Log ("{0} 只有 {1} 字节，Ventoy 未安装完整。" -f $path, $len)
            return $false
        }
    }
    if ($Mode -eq 'Install' -and $Script:VentoyVersion) {
        $grubCfg = Join-Path $root 'grub\grub.cfg'
        $onDisk = ''
        if (Test-Path -LiteralPath $grubCfg) {
            $text = [System.IO.File]::ReadAllText($grubCfg)
            $m = [regex]::Match($text, 'set\s+VENTOY_VERSION="([^"]+)"')
            if ($m.Success) { $onDisk = $m.Groups[1].Value }
        }
        if ($onDisk -ne $Script:VentoyVersion) {
            $shown = if ($onDisk) { $onDisk } else { '未知' }
            Write-Log ("盘上 Ventoy 版本为 {0}，与选择的 {1} 不一致，需要重装。" -f $shown, $Script:VentoyVersion)
            return $false
        }
        Write-Log ("盘上 Ventoy 版本 {0}，与选择一致。" -f $onDisk)
    }
    Write-Log ("Ventoy 已安装完整，VTOYEFI 盘符 {0}: 。" -f $letter)
    return $true
}

function Find-CompletedIsoPath([int]$Number) {
    $ventoyPart = $null
    foreach ($part in @(Get-Partition -DiskNumber $Number -ErrorAction SilentlyContinue)) {
        $vol = Get-PartVolume $part
        if ((Get-VolumeLabelText $vol) -eq 'Ventoy') { $ventoyPart = $part }
    }
    if (-not $ventoyPart) { return $null }
    $letter = Set-PartitionLetter $ventoyPart
    $path = '{0}:\{1}' -f $letter, $Script:IsoFileName
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    if ([int64](Get-Item -LiteralPath $path).Length -ne $isoLen) { return $null }
    return $path
}

function Write-PeDiagnostic([string]$UsbLetter) {
    $ascii = New-Object System.Text.ASCIIEncoding
    $text = @'
@echo off
echo ============================================
echo  WinPE install-source diagnostic v3
echo ============================================
echo.
echo -- Raw diskpart volume list --
echo list volume | diskpart
echo.
echo -- Identify each drive by root contents --
echo (Autounattend.xml and the ISO file exist ONLY on the Ventoy partition;
echo  the virtual CD-ROM only has sources\install.wim)
echo.
for %%d in (D E F G H I J) do (
    if exist %%d:\sources\install.wim echo   %%d: HAS sources\install.wim
    if exist %%d:\Autounattend.xml echo   %%d: HAS Autounattend.xml  =^> Ventoy partition
    if exist %%d:\*.iso echo   %%d: HAS an ISO file       =^> Ventoy partition
)
echo.
echo -- Read this table as follows --
echo If the drive named in the Setup error has "HAS Autounattend.xml",
echo Setup read the real Ventoy partition.
echo If it does NOT, the virtual CD-ROM stole that drive letter and Setup
echo was reading the ISO image through the broken virtual CD drive.
echo.
echo Press any key to close...
pause >nul
'@
    $path = '{0}:\check-source.bat' -f $UsbLetter
    $utf8 = New-Object System.Text.ASCIIEncoding
    [System.IO.File]::WriteAllText($path, ($text -replace "`n", "`r`n"), $utf8)
    Write-Log ("诊断脚本已放在 {0}" -f $path)
    $launcher = @'
@echo off
echo Looking for install source and launching setup...
echo.
for %%d in (F E G H I J D) do (
    if exist %%d:\sources\setup.exe (
        if exist %%d:\sources\install.wim (
            echo Found source: %%d:\sources
            echo Starting Windows Setup from %%d: ...
            echo.
            %%d:\sources\setup.exe
            goto :eof
        )
    )
)
echo No drive with sources setup.exe and install.wim was found.
echo Run check-source.bat to see what volumes exist.
pause
'@
    $path2 = '{0}:\start-setup.bat' -f $UsbLetter
    [System.IO.File]::WriteAllText($path2, ($launcher -replace "`n", "`r`n"), $ascii)
    Write-Log ("手动启动脚本已放在 {0}" -f $path2)
    Write-AutoUnattend $UsbLetter
}

function Write-AutoUnattend([string]$UsbLetter) {
    $wimPath = '{0}:\sources\install.wim' -f $SourceDriveLetter
    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <Path>$wimPath</Path>
          </InstallFrom>
        </OSImage>
      </ImageInstall>
    </component>
  </settings>
</unattend>
"@
    $path = '{0}:\Autounattend.xml' -f $UsbLetter
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($path, ($xml -replace "`n", "`r`n"), $utf8)
    Write-Log ("Autounattend.xml 已放在 {0}，安装源指向 {1}（不依赖盘符）" -f $path, $wimPath)
}

$ventoyComplete = Test-VentoyInstallComplete $disk.Number
$done = $null
if ($ventoyComplete) { $done = Find-CompletedIsoPath $disk.Number }
if ($ventoyComplete -and $done) {
    $readyLetter = $done.Substring(0, 1)
    if (Test-SetupSourceReady $readyLetter) {
        Write-Log ("Ventoy、ISO 和 sources\install.wim 都已就绪，跳过。{0}" -f $done)
        Write-PeDiagnostic $readyLetter
        Write-Host ''
        Write-Host 'Ventoy、ISO 和 sources\install.wim 都已在 U 盘上。' -ForegroundColor Green
        Write-Host '启动时选中 ISO 后直接回车。安装程序读的是 U 盘上的 sources\install.wim，不是 ISO 文件。'
        Write-Host ("Autounattend.xml 已就位，Setup 会自动从 {0}:\sources\install.wim 读取系统镜像，不再报缺少驱动。" -f $SourceDriveLetter) -ForegroundColor Green
        if ($useGpt) { Write-Host '本盘为 UEFI(GPT)，开机请在启动菜单里选择带 UEFI 字样的 U 盘启动项。' -ForegroundColor Green }
        Write-Host $done
        return
    }
    Write-Host ''
    Write-Host 'ISO 文件已经在 U 盘上。WIM 启动后安装程序不会打开 ISO，所以会报缺少驱动。' -ForegroundColor Yellow
    Write-Host ("将把 sources\install.wim 解到磁盘 {0}  {1}，不清空现有文件。" -f $disk.Number, $name) -ForegroundColor Yellow
    if ($Confirm -ne 'YES') {
        if (-not (Read-Yes)) { Write-Host '已取消。'; return }
    }
    try {
        Expand-SetupSource $readyLetter
    }
    catch {
        throw $_.Exception.Message
    }
    Write-Host ''
    Write-Host ("完成：{0}:\sources\install.wim 已放好。" -f $readyLetter) -ForegroundColor Green
    Write-PeDiagnostic $readyLetter
    Write-Host '那个窗口不是要你选硬件驱动。选中 ISO 后直接回车启动，Setup 会自动读取 Autounattend.xml，无需命令行。' -ForegroundColor Green
    return
}
if ((-not $ventoyComplete) -and $Mode -eq 'CopyOnly') {
    throw 'Ventoy 未安装完整。请用菜单第 2 项重装后再复制 ISO。'
}

Write-Host ''
if (-not $ventoyComplete) {
    Write-Host ("Ventoy 未安装完整。将清空磁盘 {0}  {1}  {2}，安装 Ventoy {3}（{4} / {5}），再复制 ISO。" -f $disk.Number, $name, (Format-Gb $disk.Size), $Script:VentoyVersion, $styleText, $PartitionFs) -ForegroundColor Yellow
    Write-Host '盘上的文件会全部消失。' -ForegroundColor Yellow
}
else {
    Write-Host ("Ventoy 已安装完整，不重装。将把 ISO 复制到磁盘 {0}  {1}  {2}。" -f $disk.Number, $name, (Format-Gb $disk.Size)) -ForegroundColor Yellow
}
if ($Confirm -ne 'YES') {
    if (-not (Read-Yes)) { Write-Host '已取消。'; return }
}

$wiped = $false
try {
    Assert-SameUsb $disk
    $part = $null
    if ($Mode -eq 'Install' -and -not $ventoyComplete) {
        $ventoyRoot = Ensure-VentoyExtracted
        $exe = Get-VentoyExe $ventoyRoot
        Assert-SameUsb $disk
        Write-Log ("目标盘 磁盘 {0} {1} {2}，分区 {3}" -f $disk.Number, $name, (Format-Gb $disk.Size), $styleText)
        $wiped = $true
        Invoke-VentoyInstall -Root $ventoyRoot -Exe $exe -Number $disk.Number -Gpt $useGpt -Fs $PartitionFs
        $part = Wait-VentoyDataPartition $disk.Number
    }
    else {
        $part = Get-VentoyDataPartition $disk.Number
    }
    $letter = Set-PartitionLetter $part
    Write-Log ("Ventoy 分区盘符 {0}:" -f $letter)
    $dest = Copy-InstallIso $letter
    Expand-SetupSource $letter
    Write-PeDiagnostic $letter
    Write-Log ("完成，用时 {0:n0} 秒" -f $sw.Elapsed.TotalSeconds)
    Write-Host ''
    Write-Host ("完成：{0}: 已放入 {1}" -f $letter, $Script:IsoFileName) -ForegroundColor Green
    Write-Host ("从这块 U 盘启动。选中 ISO 后直接回车。系统镜像在 {0}:\sources\install.wim。" -f $letter) -ForegroundColor Green
    Write-Host ("Autounattend.xml 已就位，Setup 会自动从 {0}:\sources\install.wim 读取系统镜像，不再报缺少驱动。" -f $SourceDriveLetter) -ForegroundColor Green
    Write-Host '若固件开启了安全启动，第一次会要求登记 Ventoy 密钥，按屏幕提示操作。' -ForegroundColor Green
    if ($useGpt) { Write-Host '本盘为 UEFI(GPT)，开机请在启动菜单里选择带 UEFI 字样的 U 盘启动项。' -ForegroundColor Green }
    Write-Host $dest
}
catch {
    $msg = $_.Exception.Message
    if ($wiped) {
        $msg += ' U 盘可能已被清空。排除问题后重新执行菜单第 2 项；若 Ventoy 已装好，可用第 3 项只复制 ISO。'
    }
    throw $msg
}
