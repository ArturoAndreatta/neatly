# Funcoes compartilhadas pelo organizador e pelo painel.

$script:PastaApp = Join-Path $env:LOCALAPPDATA 'OrganizadorDownloads'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:NomeTarefa = 'Organizar Downloads'
$script:NomeTarefaPainel = 'Organizar Downloads - Painel'
$script:Repo = 'ArturoAndreatta/organizador-downloads'

function Get-PastaDownloads {
  # Pasta Downloads real do usuario (funciona mesmo se ela foi movida, ex: OneDrive)
  try {
    $p = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  } catch {}
  return (Join-Path $env:USERPROFILE 'Downloads')
}

function Get-Config {
  $arq = Join-Path $script:PastaApp 'config.json'
  if (-not (Test-Path -LiteralPath $arq)) { $arq = Join-Path $PSScriptRoot 'config.padrao.json' }
  return ([IO.File]::ReadAllText($arq, $script:Utf8).TrimStart([char]0xFEFF) | ConvertFrom-Json)
}

function Save-Config($cfg) {
  $json = ConvertTo-Json -InputObject $cfg -Depth 6
  [IO.File]::WriteAllText((Join-Path $script:PastaApp 'config.json'), $json, $script:Utf8)
}

function Get-Categorias($cfg) {
  $mapa = [ordered]@{}
  foreach ($p in $cfg.categorias.PSObject.Properties) { $mapa[$p.Name] = @($p.Value | ForEach-Object { "$_".ToLower().TrimStart('.') }) }
  return $mapa
}

function Get-CategoriaDoArquivo($mapa, $nome) {
  $ext = [IO.Path]::GetExtension($nome).TrimStart('.').ToLower()
  if (-not $ext) { return $null }
  foreach ($k in $mapa.Keys) { if ($mapa[$k] -contains $ext) { return $k } }
  return $null
}

function Test-Ignorado($cfg, $nome) {
  foreach ($padrao in @($cfg.ignorar)) { if ($nome -like $padrao) { return $true } }
  return $false
}

function Get-Pendentes($cfg) {
  # Arquivos soltos na raiz que a proxima rodada vai mover
  $downloads = Get-PastaDownloads
  $mapa = Get-Categorias $cfg
  $limite = (Get-Date).AddMinutes(-[double]$cfg.minutosRecentes)
  $lista = New-Object System.Collections.ArrayList
  Get-ChildItem -LiteralPath $downloads -File -Force | ForEach-Object {
    if (Test-Ignorado $cfg $_.Name) { return }
    $c = Get-CategoriaDoArquivo $mapa $_.Name
    if (-not $c) { return }
    [void]$lista.Add([ordered]@{ nome = $_.Name; pasta = $c; tamanho = $_.Length; recente = ($_.LastWriteTime -gt $limite) })
  }
  return ,$lista
}

function Get-DestinoLivre($pasta, $nome) {
  # Nunca sobrescreve: nome (1).ext, nome (2).ext...
  $alvo = Join-Path $pasta $nome
  $n = 1
  while (Test-Path -LiteralPath $alvo) {
    $alvo = Join-Path $pasta ('{0} ({1}){2}' -f [IO.Path]::GetFileNameWithoutExtension($nome), $n, [IO.Path]::GetExtension($nome))
    $n++
  }
  return $alvo
}

function Get-ClaudeExe {
  $arq = Join-Path $script:PastaApp 'claude-path.txt'
  if (Test-Path -LiteralPath $arq) {
    $p = (Get-Content -LiteralPath $arq -Raw).Trim()
    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
  }
  $cmd = Get-Command claude -ErrorAction SilentlyContinue
  if (-not $cmd) { return $null }
  $exe = $cmd.Source
  $shim = [IO.Path]::ChangeExtension($exe, '.cmd')
  if ($exe -like '*.ps1' -and (Test-Path -LiteralPath $shim)) { $exe = $shim }
  return $exe
}

function Get-ConsumoLimites($eventos) {
  # Recebe os rate_limit_event do Claude Code (em ordem) e calcula, para as janelas de 5h e semanal,
  # o uso no primeiro e no ultimo evento e quanto a rodada consumiu.
  # utilization vem de 0 a 1; aqui tudo vira porcentagem (0 a 100).
  # Se a janela reiniciar no meio (resetsAt muda), o consumo da janela nova conta a partir do zero.
  if (-not $eventos -or $eventos.Count -eq 0) { return $null }
  $saida = [ordered]@{}
  foreach ($nome in 'five_hour', 'seven_day') {
    $serie = New-Object System.Collections.ArrayList
    foreach ($ev in $eventos) {
      $u = $null; $r = $null
      if ($ev.unifiedWindows -and $ev.unifiedWindows.$nome) {
        $u = $ev.unifiedWindows.$nome.utilization; $r = $ev.unifiedWindows.$nome.resetsAt
      } elseif ($ev.rateLimitType -eq $nome -and $ev.utilization -ne $null) {
        $u = $ev.utilization; $r = $ev.resetsAt
      }
      if ($u -ne $null) { [void]$serie.Add([pscustomobject]@{ u = [double]$u * 100; r = [long]$r }) }
    }
    if ($serie.Count -eq 0) { continue }
    $consumo = 0.0; $reinicios = 0
    for ($i = 1; $i -lt $serie.Count; $i++) {
      $a = $serie[$i - 1]; $b = $serie[$i]
      if ($b.r -ne $a.r -or $b.u -lt $a.u) { $consumo += $b.u; $reinicios++ }
      else { $consumo += ($b.u - $a.u) }
    }
    $ult = $serie[$serie.Count - 1]
    $saida[$(if ($nome -eq 'five_hour') { 'cincoHoras' } else { 'semanal' })] = [ordered]@{
      antes = [math]::Round($serie[0].u, 2)
      depois = [math]::Round($ult.u, 2)
      consumo = [math]::Round($consumo, 2)
      reiniciou = ($reinicios -gt 0)
      leituras = $serie.Count
      reseta = $(if ($ult.r) { [DateTimeOffset]::FromUnixTimeSeconds($ult.r).ToLocalTime().ToString('o') } else { $null })
    }
  }
  if ($saida.Count -eq 0) { return $null }
  return $saida
}

function Invoke-GitHub($caminho) {
  # API publica do GitHub (sem login: funciona com o repositorio publico, ate 60 consultas por hora)
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  return Invoke-RestMethod "https://api.github.com/repos/$($script:Repo)/$caminho" -TimeoutSec 15 -UseBasicParsing `
    -Headers @{ 'User-Agent' = 'organizador-downloads'; 'Accept' = 'application/vnd.github+json' }
}

function Get-VersaoLocal {
  $arq = Join-Path $script:PastaApp 'versao.json'
  if (-not (Test-Path -LiteralPath $arq)) { return $null }
  try { return ([IO.File]::ReadAllText($arq, $script:Utf8) | ConvertFrom-Json) } catch { return $null }
}

function Set-VersaoLocal($commit) {
  $json = ConvertTo-Json -InputObject ([ordered]@{ commit = $commit; instaladoEm = (Get-Date).ToString('o') }) -Compress
  [IO.File]::WriteAllText((Join-Path $script:PastaApp 'versao.json'), $json, $script:Utf8)
}
