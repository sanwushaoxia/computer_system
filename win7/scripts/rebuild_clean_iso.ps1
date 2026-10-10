#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Rebuild-CleanIso.ps1')
