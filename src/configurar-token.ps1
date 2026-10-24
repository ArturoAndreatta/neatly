# Gera e guarda o token de 1 ano que a tarefa usa para falar com o Claude.
. (Join-Path $PSScriptRoot 'comum.ps1')
New-Item -ItemType Directory -Force -Path $script:PastaApp | Out-Null

$exe = Get-ClaudeExe
if (-not $exe) {
  Write-Host 'Claude Code nao encontrado. Instale em https://claude.com/claude-code e tente de novo.' -ForegroundColor Red
  exit 1
}

Write-Host ''
Write-Host '1) Vai abrir o navegador para voce autorizar. Depois o token aparece aqui no terminal.' -ForegroundColor Cyan
Write-Host ''
& $exe setup-token
Write-Host ''
Write-Host '2) Copie o token que apareceu acima (comeca com sk-ant-oat) e cole abaixo.' -ForegroundColor Cyan
Write-Host '   Nada aparece enquanto voce cola, e normal.' -ForegroundColor DarkGray
$sec = Read-Host 'Token' -AsSecureString
if ($sec.Length -lt 20) { Write-Host 'Token vazio ou curto demais. Nada salvo.' -ForegroundColor Red; exit 1 }
$sec | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $script:PastaApp 'token.dat')
Write-Host ''
Write-Host 'Pronto. Token salvo criptografado: so o seu usuario do Windows consegue ler.' -ForegroundColor Green
exit 0
