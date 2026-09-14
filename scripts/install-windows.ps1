param([string]$PackagePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist/win-x64'))
$ErrorActionPreference = 'Stop'
$destination = Join-Path $env:LOCALAPPDATA 'Programs/Herdr HUD'
if (-not (Test-Path (Join-Path $PackagePath 'HerdrHUD.exe'))) { throw 'Build the Windows package first.' }
$running = Get-Process HerdrHUD -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $destination 'HerdrHUD.exe') }
if ($running) { throw 'Save your drafts and quit Herdr HUD from its tray menu before installing.' }
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item (Join-Path $PackagePath '*') $destination -Recurse -Force
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $env:APPDATA 'Microsoft/Windows/Start Menu/Programs/Herdr HUD.lnk'))
$shortcut.TargetPath = Join-Path $destination 'HerdrHUD.exe'
$shortcut.WorkingDirectory = $destination
$shortcut.Save()
Write-Host 'Installed Herdr HUD. Open it from the Start menu.'
