# Ponte do Neatly 1 para o Neatly 2.
# O botao Atualizar do painel antigo baixa o repositorio e roda este arquivo.
# Ele baixa o instalador novo (NeatlySetup.exe) do ultimo release e instala em
# silencio; o Neatly 2 traz modo e horario e remove o que era do Neatly 1.
param([switch]$Atualizacao, [string]$Commit)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$setup = Join-Path $env:TEMP 'NeatlySetup.exe'
Invoke-WebRequest 'https://github.com/ArturoAndreatta/neatly/releases/latest/download/NeatlySetup.exe' -OutFile $setup -UseBasicParsing -TimeoutSec 120
Unblock-File -LiteralPath $setup -ErrorAction SilentlyContinue
if ($Atualizacao) {
  Start-Process -FilePath $setup -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
} else {
  Start-Process -FilePath $setup
}
