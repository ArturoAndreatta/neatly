# Instalacao em uma linha:
#   irm https://raw.githubusercontent.com/ArturoAndreatta/organizador-downloads/main/instalar-web.ps1 | iex
$ErrorActionPreference = 'Stop'
$zip = Join-Path $env:TEMP 'organizador-downloads.zip'
$pasta = Join-Path $env:TEMP 'organizador-downloads'
Write-Host 'Baixando o Organizador de Downloads...' -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest 'https://github.com/ArturoAndreatta/organizador-downloads/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
if (Test-Path $pasta) { Remove-Item $pasta -Recurse -Force }
Expand-Archive -LiteralPath $zip -DestinationPath $pasta -Force
$src = Get-ChildItem -LiteralPath $pasta -Directory | Select-Object -First 1
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $src.FullName 'src\instalar.ps1')
