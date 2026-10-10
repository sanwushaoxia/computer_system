$root = 'E:\'
Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
Write-Host '--- match ---'
Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'usb3|xhci|USB3|XHCI' } |
  Select-Object -First 25 -ExpandProperty FullName
