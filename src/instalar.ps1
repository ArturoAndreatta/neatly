# Instala (ou atualiza) o Neatly para o usuario atual.
# Nao precisa de administrador. Pode rodar de novo para atualizar: mantem config, historico e token.
# -Atualizacao: chamado pelo botao Atualizar do painel (sem perguntas e sem abrir o navegador).
param([switch]$Atualizacao, [string]$Commit)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comum.ps1')

function Titulo($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t) { Write-Host "  [ok] $t" -ForegroundColor Green }
function Info($t) { Write-Host "       $t" -ForegroundColor DarkGray }
function Pergunta($t, $padraoSim = $true) {
  $sufixo = if ($padraoSim) { '[S/n]' } else { '[s/N]' }
  $r = Read-Host "  $t $sufixo"
  if (-not $r) { return $padraoSim }
  return ($r.Trim().ToLower() -in 's', 'sim', 'y', 'yes')
}

Write-Host ''
Write-Host '  ============================================' -ForegroundColor DarkCyan
Write-Host '              Neatly - Instalador' -ForegroundColor White
Write-Host '  ============================================' -ForegroundColor DarkCyan

$dir = $script:PastaApp
$atualizando = Test-Path -LiteralPath (Join-Path $dir 'config.json')

# 1. Limpa instalacoes antigas (versao antes do repositorio)
Titulo 'Preparando'
foreach ($antiga in $script:TarefasAntigas) {
  if (Get-ScheduledTask -TaskName $antiga -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $antiga -Confirm:$false
    Info "removida tarefa antiga: $antiga"
  }
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { ($_.CommandLine -like '*\Neatly\painel.ps1*' -or $_.CommandLine -like '*OrganizadorDownloads*painel.ps1*') } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
$desktop = [Environment]::GetFolderPath('Desktop')
foreach ($a in $script:AtalhosAntigos) {
  foreach ($p in (Join-Path $desktop $a), (Join-Path ([Environment]::GetFolderPath('Programs')) $a)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
  }
}
# Instalacao antiga (OrganizadorDownloads): traz historico, configuracao e token para a pasta nova
if ((Test-Path -LiteralPath $script:PastaAppAntiga) -and -not (Test-Path -LiteralPath $dir)) {
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  foreach ($f in 'historico.jsonl', 'config.json', 'token.dat', 'versao.json', 'claude-path.txt') {
    $p = Join-Path $script:PastaAppAntiga $f
    if (Test-Path -LiteralPath $p) { Copy-Item -LiteralPath $p -Destination (Join-Path $dir $f) -Force }
  }
  $atualizando = Test-Path -LiteralPath (Join-Path $dir 'config.json')
  Remove-Item -LiteralPath $script:PastaAppAntiga -Recurse -Force -ErrorAction SilentlyContinue
  Info 'historico e configuracao da versao antiga trazidos'
}
Ok 'pronto para instalar'

# 2. Copia os arquivos
Titulo 'Copiando arquivos'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
Get-ChildItem -LiteralPath $PSScriptRoot -File | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $dir $_.Name) -Force
}
Get-ChildItem -LiteralPath $dir -File | Unblock-File -ErrorAction SilentlyContinue
foreach ($velho in 'organizar-downloads-claude.ps1', 'organizar-downloads.ps1', 'organizador-claude.log') {
  $p = Join-Path $dir $velho
  if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
}
Ok "arquivos em $dir"

# 3. Modo de funcionamento
Titulo 'Modo de funcionamento'
$exe = Get-ClaudeExe
if ($atualizando) {
  $cfg = Get-Config
  Info "mantendo sua configuracao atual (modo: $($cfg.modo))"
} else {
  $cfg = Get-Config
  if ($exe) {
    Info "Claude Code encontrado: $exe"
    Info 'Modo Claude: o Claude Haiku 5.5 organiza, usando sua assinatura do Claude.'
    Info 'Modo script: regras fixas por extensao, sem IA e sem gastar limite.'
    if ($Atualizacao) { $cfg.modo = 'claude' }
    elseif (Pergunta 'Usar o Claude?') { $cfg.modo = 'claude' } else { $cfg.modo = 'script' }
  } else {
    Info 'Claude Code nao encontrado: usando o modo script (regras fixas, sem IA).'
    Info 'Se instalar o Claude Code depois, da para trocar no painel.'
    $cfg.modo = 'script'
  }
  Save-Config $cfg
}
if ($exe) { Set-Content -LiteralPath (Join-Path $dir 'claude-path.txt') -Value $exe }
Ok "modo: $($cfg.modo)"

# 4. Tarefas agendadas
Titulo 'Agendando'
$oculto = Join-Path $dir 'oculto.vbs'
$config = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -MultipleInstances IgnoreNew
$acao = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$oculto`" `"$(Join-Path $dir 'organizar.ps1')`""
$existente = Get-ScheduledTask -TaskName $script:NomeTarefa -ErrorAction SilentlyContinue
if ($existente) {
  Set-ScheduledTask -TaskName $script:NomeTarefa -Action $acao -Settings $config | Out-Null
  Ok 'tarefa diaria atualizada (horario e estado mantidos)'
} else {
  Register-ScheduledTask -TaskName $script:NomeTarefa -Action $acao -Trigger (New-ScheduledTaskTrigger -Daily -At '20:00') -Settings $config -Description 'Organiza a pasta Downloads por tipo de arquivo' | Out-Null
  Ok 'tarefa diaria criada: todo dia 20:00 (muda no painel). PC desligado nessa hora? Roda quando ligar.'
}
$acaoPainel = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "`"$oculto`" `"$(Join-Path $dir 'painel.ps1')`" -SemAbrir"
$gatilhoPainel = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$configPainel = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $script:NomeTarefaPainel -Action $acaoPainel -Trigger $gatilhoPainel -Settings $configPainel -Description 'Mantem o painel do Neatly no ar (http://localhost:8765)' -Force | Out-Null
Ok 'painel inicia sozinho quando voce entra no Windows'

# 5. Atalhos
Titulo 'Atalhos'
$ws = New-Object -ComObject WScript.Shell
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Neatly.lnk'
foreach ($destino in (Join-Path $desktop 'Neatly.lnk'), $menu) {
  $lnk = $ws.CreateShortcut($destino)
  $lnk.TargetPath = 'wscript.exe'
  $lnk.Arguments = "`"$(Join-Path $dir 'abrir-painel.vbs')`""
  $lnk.IconLocation = "$(Join-Path $dir 'neatly.ico'),0"
  $lnk.Description = 'Painel do Neatly'
  $lnk.Save()
}
Ok 'area de trabalho e menu Iniciar: "Neatly"'

# 6. Token do Claude
if (-not $Atualizacao -and $cfg.modo -eq 'claude' -and -not (Test-Path -LiteralPath (Join-Path $dir 'token.dat'))) {
  Titulo 'Login do Claude'
  Info 'Para rodar sozinho todo dia, o Claude precisa de um token de 1 ano (oficial, gerado pelo Claude Code).'
  if (Pergunta 'Configurar agora?') {
    & (Join-Path $dir 'configurar-token.ps1')
  } else {
    Info 'Depois: painel > Dados > configurar-token.cmd'
  }
}

# 7. Versao instalada (o botao Atualizar do painel compara com o GitHub)
if (-not $Commit) { try { $Commit = (Invoke-GitHub 'commits/main').sha } catch {} }
if ($Commit) { Set-VersaoLocal $Commit; Ok "versao $($Commit.Substring(0, 7))" }

# 8. Abre o painel
Start-ScheduledTask -TaskName $script:NomeTarefaPainel
if ($Atualizacao) { exit 0 }
Start-Sleep -Seconds 3
Start-Process 'http://localhost:8765/'

Write-Host ''
Write-Host '  Tudo pronto! O painel abriu no navegador.' -ForegroundColor Green
Write-Host '  Para remover: desinstalar.cmd' -ForegroundColor DarkGray
Write-Host ''
