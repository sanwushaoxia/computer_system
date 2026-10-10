$ErrorActionPreference = 'Stop'

$Script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$Script:ImageDir = Join-Path $Script:ProjectRoot 'image'
$Script:RepoRoot = Split-Path -Parent $Script:ProjectRoot
$Script:RufusDir = if (Test-Path -LiteralPath (Join-Path $Script:RepoRoot 'rufus')) {
    Join-Path $Script:RepoRoot 'rufus'
}
else {
    Join-Path $Script:ProjectRoot 'tools\Rufus'
}
$Script:IsoName = 'win7_install_usb.iso'
$Script:IsoLabel = 'GRMCPRXFRER'
$Script:UsbLabel = 'WIN7USB'
$Script:LogFile = $null

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    if (-not (Test-IsAdmin)) {
        throw '请以管理员身份运行。双击「启动Win7备份恢复.bat」。'
    }
}

function Get-IsoPath { Join-Path $Script:ImageDir $Script:IsoName }
function Get-BakPath { Join-Path $Script:ImageDir ($Script:IsoName + '.bak') }
function Get-WorkDir { Join-Path $Script:ImageDir 'work' }
function Get-RufusExe { Join-Path $Script:RufusDir 'rufus-4.15p.exe' }

function Format-Gb($Bytes) {
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

function Read-Token([string]$Prompt, [string]$Token) {
    Write-Host $Prompt -ForegroundColor Yellow
    $answer = Read-Host "输入 $Token 继续，直接回车取消"
    return ($answer -eq $Token)
}

function Get-IsoRecord {
    $path = Join-Path $Script:ImageDir 'SHA256.txt'
    $rec = [pscustomobject]@{
        Path    = $path
        Hash    = ''
        Size    = [int64]0
        Cleaned = ''
        Note    = ''
        Exists  = (Test-Path -LiteralPath $path)
    }
    if (-not $rec.Exists) { return $rec }
    foreach ($line in [System.IO.File]::ReadAllLines($path)) {
        if ($line.StartsWith('SHA256=')) { $rec.Hash = $line.Substring(7).Trim() }
        elseif ($line.StartsWith('SIZE=')) {
            $raw = $line.Substring(5).Trim()
            if ($raw -match '^\d+$') { $rec.Size = [int64]$raw }
        }
        elseif ($line.StartsWith('CLEANED=')) { $rec.Cleaned = $line.Substring(8).Trim() }
        elseif ($line.StartsWith('NOTE=')) { $rec.Note = $line.Substring(5).Trim() }
    }
    return $rec
}

function Write-HashRecord([string]$Hash, [int64]$Size, [string]$Note) {
    $path = Join-Path $Script:ImageDir 'SHA256.txt'
    $text = @(
        $Script:IsoName
        "SHA256=$Hash"
        "SIZE=$Size"
        ("CLEANED={0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        "NOTE=$Note"
    ) -join [Environment]::NewLine
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $text + [Environment]::NewLine, $utf8)
}

function Get-IsoQuickStatus {
    $iso = Get-IsoPath
    if (-not (Test-Path -LiteralPath $iso)) { return '还没有 win7_install_usb.iso' }
    $len = (Get-Item -LiteralPath $iso).Length
    $rec = Get-IsoRecord
    $sizeText = Format-Gb $len
    if ($rec.Size -gt 0 -and $rec.Size -eq $len) { return "$sizeText，大小与记录一致" }
    if ($rec.Size -gt 0) { return "$sizeText，大小与记录不一致" }
    return $sizeText
}

function Get-OscdimgPath {
    if ($Script:OscdimgCache) { return $Script:OscdimgCache }
    $known = @(
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe',
        'C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe'
    )
    foreach ($path in $known) {
        if (Test-Path -LiteralPath $path) {
            $Script:OscdimgCache = $path
            return $path
        }
    }
    foreach ($root in @('C:\Program Files (x86)\Windows Kits', 'C:\Program Files\Windows Kits')) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $hit = Get-ChildItem -Path $root -Recurse -Filter oscdimg.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($hit) {
            $Script:OscdimgCache = $hit.FullName
            return $Script:OscdimgCache
        }
    }
    return $null
}

function Get-BootsectPath {
    $path = Join-Path $env:SystemRoot 'System32\bootsect.exe'
    if (Test-Path -LiteralPath $path) { return $path }
    return $null
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
    if ($disk.IsBoot -or $disk.IsSystem) { throw "磁盘 $number 是系统盘或启动盘，已拒绝。" }
    $systemDisk = (Get-Partition -DriveLetter C -ErrorAction SilentlyContinue).DiskNumber
    if ($number -eq $systemDisk) { throw '不能选择系统所在的磁盘。' }
    if ([double]$disk.Size -gt 128GB) {
        Write-Host '这块盘大于 128GB，请确认选对了。' -ForegroundColor Yellow
    }
    return $disk
}

function Assert-SameUsb($Disk) {
    $now = Get-Disk -Number $Disk.Number -ErrorAction SilentlyContinue
    if (-not $now -or $now.BusType -ne 'USB' -or $now.OperationalStatus -ne 'Online') {
        throw "磁盘 $($Disk.Number) 已经不在了，或已不是 USB 盘。已中止。"
    }
    if ($now.IsBoot -or $now.IsSystem) { throw "磁盘 $($Disk.Number) 是系统盘或启动盘。已中止。" }
    if ($now.Size -ne $Disk.Size -or $now.FriendlyName -ne $Disk.FriendlyName) {
        throw "磁盘 $($Disk.Number) 的信息发生了变化。请重新选择。"
    }
    $systemDisk = (Get-Partition -DriveLetter C -ErrorAction SilentlyContinue).DiskNumber
    if ($now.Number -eq $systemDisk) { throw '不能操作系统所在的磁盘。' }
}

function Get-FreeDriveLetter {
    $used = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name })
    foreach ($n in ([int][char]'D')..([int][char]'Z')) {
        $letter = [string][char]$n
        if ($used -notcontains $letter) { return $letter }
    }
    throw '没有可用的盘符。'
}

function Invoke-Diskpart([string]$Body) {
    $file = Join-Path $env:TEMP ('win7usb_{0}.txt' -f [guid]::NewGuid().ToString('N'))
    $ascii = New-Object System.Text.ASCIIEncoding
    [System.IO.File]::WriteAllText($file, $Body, $ascii)
    try {
        $proc = Start-Process -FilePath diskpart.exe -ArgumentList "/s `"$file`"" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) { throw "diskpart 失败，退出码 $($proc.ExitCode)。" }
    }
    finally {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-SourceLetter([int]$DiskNumber) {
    $parts = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue)
    foreach ($part in $parts) {
        if ($part.DriveLetter -and (Test-Path -LiteralPath "$($part.DriveLetter):\bootmgr")) {
            return [string]$part.DriveLetter
        }
    }
    $main = $parts | Sort-Object Size -Descending | Select-Object -First 1
    if (-not $main) { throw 'U 盘上没有分区。' }
    $letter = [string]$main.DriveLetter
    if (-not $letter) {
        $letter = Get-FreeDriveLetter
        Invoke-Diskpart (@(
            "select disk $DiskNumber"
            "select partition $($main.PartitionNumber)"
            "assign letter=$letter"
            'exit'
        ) -join "`r`n")
        Start-Sleep -Seconds 2
    }
    if (-not (Test-Path -LiteralPath "${letter}:\bootmgr")) {
        throw "在 ${letter}: 找不到 bootmgr。请确认插入的是 Win7 安装 U 盘。"
    }
    return $letter
}

function Assert-InstallTree([string]$Root) {
    $root = $Root
    if (-not $root.EndsWith('\')) { $root += '\' }
    foreach ($rel in @('bootmgr', 'boot\etfsboot.com', 'efi\microsoft\boot\efisys.bin')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $rel))) {
            throw "缺少 $rel，这不像一份完整的 Win7 安装盘。"
        }
    }
    $hasImage = (Test-Path -LiteralPath (Join-Path $root 'sources\install.wim')) -or
        (Test-Path -LiteralPath (Join-Path $root 'sources\install.esd'))
    if (-not $hasImage) { throw '缺少 sources\install.wim（或 install.esd）。' }
}

function Get-OversizeFiles([string]$Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -ge 4GB })
}

function Remove-Tree([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $full = [System.IO.Path]::GetFullPath($Path)
    $work = [System.IO.Path]::GetFullPath((Get-WorkDir))
    $prefix = $work.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw '拒绝删除工作目录以外的路径。'
    }
    $svi = Join-Path $full 'System Volume Information'
    if (Test-Path -LiteralPath $svi) {
        & takeown.exe /F $svi /R /D Y | Out-Null
        & icacls.exe $svi /grant Administrators:F /T /C | Out-Null
        & cmd.exe /c "rd /s /q `"$svi`""
    }
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $full) {
        & cmd.exe /c "rd /s /q `"$full`""
    }
    if (Test-Path -LiteralPath $full) { throw "无法删除 $full" }
}

function Copy-InstallTree([string]$Source, [string]$Destination) {
    Remove-Tree $Destination
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $items = @(Get-ChildItem -LiteralPath $Source -Force | Where-Object {
        $_.Name -notin @('System Volume Information', '$RECYCLE.BIN', 'RECYCLER')
    })
    if ($items.Count -eq 0) { throw '源目录是空的。' }
    foreach ($item in $items) {
        Write-Log ("复制 " + $item.Name)
        $dest = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            & robocopy.exe $item.FullName $dest /E /XJ /XD 'System Volume Information' /R:2 /W:1 /NFL /NDL /NJH /NJS | Out-Null
            $code = $LASTEXITCODE
            if ($code -ge 8) { throw "复制 $($item.Name) 失败，robocopy 退出码 $code。" }
        }
        else {
            Copy-Item -LiteralPath $item.FullName -Destination $dest -Force
        }
    }
}

function Dismount-IsoFile([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return }
    $image = Get-DiskImage -ImagePath $Path -ErrorAction SilentlyContinue
    if ($image -and $image.Attached) {
        Dismount-DiskImage -ImagePath $Path | Out-Null
        Start-Sleep -Seconds 1
    }
}

function Mount-IsoLetter([string]$Path) {
    Dismount-IsoFile $Path
    Mount-DiskImage -ImagePath $Path | Out-Null
    for ($i = 0; $i -lt 20; $i++) {
        $vol = Get-DiskImage -ImagePath $Path | Get-Volume
        if ($vol.DriveLetter) { return [string]$vol.DriveLetter }
        Start-Sleep -Milliseconds 500
    }
    throw 'ISO 挂载后没有出现盘符。'
}

function Assert-FreeSpace {
    $qual = (Split-Path -Qualifier $Script:ProjectRoot)
    if ($qual[-1] -ne '\') { $qual += '\' }
    $bak = Get-BakPath
    $drive = [System.IO.DriveInfo]::new($qual)
    if ((Test-Path -LiteralPath $bak) -and $drive.AvailableFreeSpace -lt 12GB) {
        Write-Log '空间偏紧，先删除上一份 .bak'
        Remove-Item -LiteralPath $bak -Force
        $drive = [System.IO.DriveInfo]::new($qual)
    }
    if ($drive.AvailableFreeSpace -lt 8GB) {
        throw ('磁盘剩余空间不足。需要约 8 GB，当前 {0}。' -f (Format-Gb $drive.AvailableFreeSpace))
    }
}

function Publish-CleanIso([string]$SourceRoot, [string]$Note) {
    Assert-InstallTree $SourceRoot
    $oscdimg = Get-OscdimgPath
    if (-not $oscdimg) {
        throw '找不到 oscdimg.exe。请安装 Windows ADK 的「部署工具」(Deployment Tools)。'
    }
    Assert-FreeSpace
    $moved = $false
    $stage = $null
    $newIso = $null
    try {
        $work = Get-WorkDir
        $stage = Join-Path $work 'stage'
        $newIso = Join-Path $work 'new.iso'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        if (Test-Path -LiteralPath $newIso) { Remove-Item -LiteralPath $newIso -Force }
        Write-Log '正在复制文件（已排除 System Volume Information）...'
        Copy-InstallTree -Source $SourceRoot -Destination $stage
        Assert-InstallTree $stage
        if (Test-Path -LiteralPath (Join-Path $stage 'System Volume Information')) {
            throw '临时目录里仍有 System Volume Information。'
        }
        Write-Log '正在制作 ISO...'
        $bootdata = '2#p0,e,bboot\etfsboot.com#pEF,e,befi\microsoft\boot\efisys.bin'
        $proc = Start-Process -FilePath $oscdimg -WorkingDirectory $stage -Wait -PassThru -NoNewWindow -ArgumentList @(
            '-m', '-o', '-u2', '-udfver102',
            "-bootdata:$bootdata",
            "-l$($Script:IsoLabel)",
            $stage,
            $newIso
        )
        if ($proc.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $newIso)) {
            throw "oscdimg 失败，退出码 $($proc.ExitCode)。"
        }
        if ((Get-Item -LiteralPath $newIso).Length -lt 100MB) {
            throw '生成的 ISO 过小，已保留原来的镜像。'
        }
        Write-Log '正在检查新 ISO...'
        $letter = Mount-IsoLetter $newIso
        try {
            $mountedRoot = "${letter}:\"
            if (Test-Path -LiteralPath (Join-Path $mountedRoot 'System Volume Information')) {
                throw '新 ISO 里仍有 System Volume Information。'
            }
            Assert-InstallTree $mountedRoot
        }
        finally {
            Dismount-IsoFile $newIso
        }
        Write-Log '正在计算 SHA256...'
        $hash = (Get-FileHash -LiteralPath $newIso -Algorithm SHA256).Hash
        $size = (Get-Item -LiteralPath $newIso).Length
        $final = Get-IsoPath
        $bak = Get-BakPath
        Dismount-IsoFile $final
        Write-Log '正在替换原来的 ISO...'
        if (Test-Path -LiteralPath $final) {
            if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force }
            $renamed = $false
            for ($try = 1; $try -le 5; $try++) {
                try {
                    Rename-Item -LiteralPath $final -NewName (Split-Path -Leaf $bak) -ErrorAction Stop
                    $renamed = $true
                    break
                }
                catch {
                    if ($try -eq 5) { throw }
                    Start-Sleep -Seconds 1
                }
            }
            if (-not $renamed) { throw '无法改名原来的 ISO。原来的镜像仍在。' }
        }
        try {
            $movedFile = $false
            for ($try = 1; $try -le 5; $try++) {
                try {
                    Move-Item -LiteralPath $newIso -Destination $final -ErrorAction Stop
                    $movedFile = $true
                    break
                }
                catch {
                    if ($try -eq 5) { throw }
                    Start-Sleep -Seconds 1
                }
            }
            if (-not $movedFile) { throw '无法放入新的 ISO。' }
        }
        catch {
            if ((-not (Test-Path -LiteralPath $final)) -and (Test-Path -LiteralPath $bak)) {
                Rename-Item -LiteralPath $bak -NewName (Split-Path -Leaf $final)
            }
            throw
        }
        Write-HashRecord -Hash $hash -Size $size -Note $Note
        $moved = $true
        Write-Log ("SHA256=" + $hash)
        Write-Log ("SIZE=" + $size)
        return $hash
    }
    finally {
        try { if ($newIso) { Dismount-IsoFile $newIso } } catch { Write-Log $_.Exception.Message }
        try {
            if (-not $moved -and $newIso -and (Test-Path -LiteralPath $newIso)) {
                Remove-Item -LiteralPath $newIso -Force
            }
        }
        catch { Write-Log $_.Exception.Message }
        try {
            if ($stage -and (Test-Path -LiteralPath $stage)) {
                Write-Log '正在清理临时文件...'
                Remove-Tree $stage
            }
        }
        catch { Write-Log $_.Exception.Message }
    }
}
