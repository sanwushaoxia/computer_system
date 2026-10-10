$inner = Join-Path $PSScriptRoot 'Rebuild-CleanIso.ps1'
$argLine = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $inner
$proc = Start-Process -FilePath powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $argLine
Write-Host ("ExitCode=" + $proc.ExitCode)
$log = Join-Path (Split-Path -Parent $PSScriptRoot) 'logs\rebuild.log'
Get-Content -LiteralPath $log -Encoding UTF8 -ErrorAction SilentlyContinue
exit $proc.ExitCode
