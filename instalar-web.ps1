# Instalacao em uma linha:
#   irm https://raw.githubusercontent.com/ArturoAndreatta/neatly/main/instalar-web.ps1 | iex
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$setup = Join-Path $env:TEMP 'NeatlySetup.exe'
Write-Host 'Baixando o Neatly...' -ForegroundColor Cyan
Invoke-WebRequest 'https://github.com/ArturoAndreatta/neatly/releases/latest/download/NeatlySetup.exe' -OutFile $setup -UseBasicParsing
Unblock-File -LiteralPath $setup -ErrorAction SilentlyContinue
Start-Process -FilePath $setup -Wait
