param([string]$Dotnet = 'dotnet')
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot/build-windows.ps1" -Dotnet $Dotnet
$root = Split-Path $PSScriptRoot -Parent
Copy-Item "$PSScriptRoot/install-windows.ps1" "$root/dist/win-x64/Install.ps1" -Force
'@echo off', 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"', 'pause' | Set-Content "$root/dist/win-x64/Install.cmd" -Encoding ascii
Compress-Archive -Path "$root/dist/win-x64/*" -DestinationPath "$root/dist/Herdr-HUD-Windows-x64.zip" -Force
