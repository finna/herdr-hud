param([string]$Dotnet = 'dotnet', [string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    & $Dotnet restore Windows/HerdrHUD.Windows.csproj -r $Runtime --locked-mode
    if ($LASTEXITCODE -ne 0) { throw 'Dependency restore failed.' }
    & $Dotnet run --project Windows.Tests/HerdrHUD.Tests.csproj -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Transport tests failed.' }
    & $Dotnet publish Windows/HerdrHUD.Windows.csproj -c Release -r $Runtime --self-contained true --no-restore -o "dist/$Runtime"
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }
    Copy-Item LICENSE "dist/$Runtime/LICENSE.txt" -Force
    Copy-Item README.md "dist/$Runtime/README.md" -Force
    Write-Host "Built dist/$Runtime/HerdrHUD.exe. Keep the whole directory together."
} finally { Pop-Location }
