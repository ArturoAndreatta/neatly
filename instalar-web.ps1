# Instalacao em uma linha:
#   irm https://raw.githubusercontent.com/ArturoAndreatta/organizador-downloads/main/instalar-web.ps1 | iex
$ErrorActionPreference = 'Stop'
$zip = Join-Path $env:TEMP 'organizador-downloads.zip'
$pasta = Join-Path $env:TEMP 'organizador-downloads'
Write-Host 'Baixando o Organizador de Downloads...' -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$commit = (Invoke-RestMethod 'https://api.github.com/repos/ArturoAndreatta/organizador-downloads/commits/main' -Headers @{ 'User-Agent' = 'organizador-downloads' } -UseBasicParsing).sha
Invoke-WebRequest "https://codeload.github.com/ArturoAndreatta/organizador-downloads/zip/$commit" -OutFile $zip -UseBasicParsing
if (Test-Path $pasta) { Remove-Item $pasta -Recurse -Force }
Expand-Archive -LiteralPath $zip -DestinationPath $pasta -Force
$src = Get-ChildItem -LiteralPath $pasta -Directory | Select-Object -First 1
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $src.FullName 'src\instalar.ps1') -Commit $commit
