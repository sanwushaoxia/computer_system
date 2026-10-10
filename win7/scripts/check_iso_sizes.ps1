$iso = 'C:\Backup\Win7_InstallUSB\image\win7_install_usb.iso'
Mount-DiskImage -ImagePath $iso | Out-Null
$L = (Get-DiskImage -ImagePath $iso | Get-Volume).DriveLetter
Get-ChildItem "${L}:\" -Recurse -File -Force -ErrorAction SilentlyContinue |
  Sort-Object Length -Descending |
  Select-Object -First 15 Length, FullName |
  Format-Table -AutoSize
$over = Get-ChildItem "${L}:\" -Recurse -File -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.Length -ge 4GB }
Write-Host ("Files >= 4GB: " + @($over).Count)
Dismount-DiskImage -ImagePath $iso | Out-Null
