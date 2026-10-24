# Instalacao em uma linha:
#   irm https://raw.githubusercontent.com/ArturoAndreatta/neatly/main/instalar-web.ps1 | iex
$ErrorActionPreference = 'Stop'
$zip = Join-Path $env:TEMP 'neatly.zip'
$pasta = Join-Path $env:TEMP 'neatly'
Write-Host 'Baixando o Neatly...' -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$commit = (Invoke-RestMethod 'https://api.github.com/repos/ArturoAndreatta/neatly/commits/main' -Headers @{ 'User-Agent' = 'neatly' } -UseBasicParsing).sha
Invoke-WebRequest "https://codeload.github.com/ArturoAndreatta/neatly/zip/$commit" -OutFile $zip -UseBasicParsing
if (Test-Path $pasta) { Remove-Item $pasta -Recurse -Force }
Expand-Archive -LiteralPath $zip -DestinationPath $pasta -Force
$src = Get-ChildItem -LiteralPath $pasta -Directory | Select-Object -First 1
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $src.FullName 'src\instalar.ps1') -Commit $commit
