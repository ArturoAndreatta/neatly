# Painel local do Organizador de Downloads em http://localhost:8765
# Inicia escondido no logon (-SemAbrir) e fica sempre no ar. O atalho so abre o navegador.
param([switch]$SemAbrir)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'comum.ps1')

$dir = $script:PastaApp
$hist = Join-Path $dir 'historico.jsonl'
$porta = 8765
$url = "http://localhost:$porta/"

# Se ja estiver rodando, so abre o navegador
try { Invoke-WebRequest "${url}api/ping" -UseBasicParsing -TimeoutSec 2 | Out-Null; if (-not $SemAbrir) { Start-Process $url }; exit } catch {}

$token = [guid]::NewGuid().ToString('N')
$utf8 = $script:Utf8

function Json($o) { ConvertTo-Json -InputObject $o -Depth 6 -Compress }
function FmtData($d) { if ($d -and $d.Year -gt 2000) { $d.ToString('o') } else { $null } }

function Responder($ctx, $codigo, $corpo, $tipo = 'application/json; charset=utf-8') {
  $bytes = $utf8.GetBytes($corpo)
  $ctx.Response.StatusCode = $codigo
  $ctx.Response.ContentType = $tipo
  $ctx.Response.Headers['Cache-Control'] = 'no-store'
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
  $ctx.Response.OutputStream.Close()
}

function Status {
  $cfg = Get-Config
  $base = [ordered]@{
    instalada = $false
    modo = "$($cfg.modo)"
    modelo = "$($cfg.modelo)"
    categorias = @((Get-Categorias $cfg).Keys)
    claudeDisponivel = [bool](Get-ClaudeExe)
    tokenSalvo = (Test-Path -LiteralPath (Join-Path $dir 'token.dat'))
    downloads = Get-PastaDownloads
    pendentes = Get-Pendentes $cfg
  }
  $t = Get-ScheduledTask -TaskName $script:NomeTarefa -ErrorAction SilentlyContinue
  if (-not $t) { return $base }
  $i = Get-ScheduledTaskInfo -TaskName $script:NomeTarefa
  $hora = ''
  try { $hora = ([datetime]$t.Triggers[0].StartBoundary).ToString('HH:mm') } catch {}
  $base.instalada = $true
  $base.habilitada = ("$($t.State)" -ne 'Disabled')
  $base.estado = "$($t.State)"
  $base.horario = $hora
  $base.proxima = FmtData $i.NextRunTime
  $base.ultima = FmtData $i.LastRunTime
  $base.ultimoResultado = $i.LastTaskResult
  return $base
}

function LerHistorico {
  if (-not (Test-Path -LiteralPath $hist)) { return '[]' }
  $linhas = @([IO.File]::ReadAllLines($hist, $utf8) | ForEach-Object { $_.TrimStart([char]0xFEFF).Trim() } | Where-Object { $_ })
  [array]::Reverse($linhas)
  return '[' + ($linhas -join ',') + ']'
}

function Desfazer($id) {
  $downloads = Get-PastaDownloads
  $linhas = [IO.File]::ReadAllLines($hist, $utf8)
  $idx = -1
  for ($k = 0; $k -lt $linhas.Length; $k++) { if ($linhas[$k] -like "*`"id`":`"$id`"*") { $idx = $k; break } }
  if ($idx -lt 0) { throw 'Execução não encontrada' }
  $e = $linhas[$idx].TrimStart([char]0xFEFF) | ConvertFrom-Json
  if ($e.desfeito) { throw 'Essa execução já foi desfeita' }
  $ok = 0; $falhas = New-Object System.Collections.ArrayList
  foreach ($m in @($e.movidos)) {
    if (-not $m.destino) { [void]$falhas.Add($m.nome); continue }
    $atual = Join-Path $downloads $m.destino
    if (-not (Test-Path -LiteralPath $atual)) { [void]$falhas.Add($m.nome); continue }
    Move-Item -LiteralPath $atual -Destination (Get-DestinoLivre $downloads $m.nome)
    $ok++
  }
  $linhas[$idx] = $linhas[$idx].Replace('"desfeito":false', '"desfeito":true')
  [IO.File]::WriteAllLines($hist, $linhas, $utf8)
  return [ordered]@{ restaurados = $ok; falhas = $falhas }
}

$script:cacheVersao = $null
$script:cacheVersaoEm = [datetime]::MinValue

function Versao([bool]$forcar) {
  # Compara a versao instalada com o main do GitHub. Guarda 30 min para nao gastar a cota da API.
  if (-not $forcar -and $script:cacheVersao -and ((Get-Date) - $script:cacheVersaoEm).TotalMinutes -lt 30) { return $script:cacheVersao }
  $loc = Get-VersaoLocal
  $r = [ordered]@{ local = $null; remoto = $null; novidade = $false; novidades = @(); erro = $null }
  if ($loc -and $loc.commit) { $r.local = "$($loc.commit)".Substring(0, 7) }
  try {
    $remoto = (Invoke-GitHub 'commits/main').sha
    $r.remoto = $remoto.Substring(0, 7)
    $r.sha = $remoto
    if (-not ($loc -and $loc.commit)) {
      $r.novidade = $true
    } elseif ($loc.commit -ne $remoto) {
      $r.novidade = $true
      try {
        $cmp = Invoke-GitHub "compare/$($loc.commit)...$remoto"
        $lista = @($cmp.commits | ForEach-Object { ("$($_.commit.message)" -split "`n")[0] })
        [array]::Reverse($lista)
        $r.novidades = $lista
      } catch {}
    }
  } catch {
    $r.erro = 'Não consegui consultar o GitHub (sem internet ou repositório privado).'
  }
  $script:cacheVersao = $r
  $script:cacheVersaoEm = Get-Date
  return $r
}

function Atualizar {
  $v = Versao $true
  if (-not $v.sha) { throw ($(if ($v.erro) { $v.erro } else { 'Versão do GitHub indisponível' })) }
  $temp = Join-Path $env:TEMP "organizador-downloads-$($v.remoto)"
  $zip = "$temp.zip"
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest "https://codeload.github.com/$($script:Repo)/zip/$($v.sha)" -OutFile $zip -UseBasicParsing -TimeoutSec 60
  Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
  $instalador = Get-ChildItem -LiteralPath $temp -Recurse -Filter 'instalar.ps1' | Where-Object { $_.Directory.Name -eq 'src' } | Select-Object -First 1
  if (-not $instalador) { throw 'O pacote baixado veio sem o instalador' }
  Get-ChildItem -LiteralPath $instalador.DirectoryName -File | Unblock-File -ErrorAction SilentlyContinue
  # Aviso do que mudou, mostrado uma vez quando o painel voltar
  $aviso = ConvertTo-Json -InputObject ([ordered]@{ de = $v.local; para = $v.remoto; novidades = @($v.novidades) }) -Compress
  [IO.File]::WriteAllText((Join-Path $dir 'atualizacao.json'), $aviso, $utf8)
  # O instalador fecha este painel, troca os arquivos e liga o painel de novo
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$($instalador.FullName)`" -Atualizacao -Commit $($v.sha)"
  return [ordered]@{ ok = $true; para = $v.remoto }
}

function AvisoAtualizacao {
  $arq = Join-Path $dir 'atualizacao.json'
  if (-not (Test-Path -LiteralPath $arq)) { return '{}' }
  $txt = [IO.File]::ReadAllText($arq, $utf8)
  $a = $txt | ConvertFrom-Json
  $loc = Get-VersaoLocal
  # So mostra quando a versao nova ja esta instalada
  if (-not ($loc -and "$($loc.commit)".StartsWith("$($a.para)"))) { return '{}' }
  Remove-Item -LiteralPath $arq -Force
  return $txt
}

function Rotear($ctx) {
  $req = $ctx.Request
  $caminho = $req.Url.AbsolutePath
  if ($caminho -eq '/') {
    $html = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'painel.html'), $utf8).Replace('__TOKEN__', $token)
    Responder $ctx 200 $html 'text/html; charset=utf-8'; return
  }
  if ($caminho -eq '/api/ping') { Responder $ctx 200 '{"ok":true}'; return }
  if ($req.Headers['X-Token'] -ne $token) { Responder $ctx 403 (Json @{ erro = 'Sessão expirada. Recarregue a página.' }); return }

  $corpo = $null
  if ($req.HttpMethod -eq 'POST') {
    $sr = New-Object System.IO.StreamReader($req.InputStream, $utf8)
    $txt = $sr.ReadToEnd()
    if ($txt) { $corpo = $txt | ConvertFrom-Json }
  }

  switch ($caminho) {
    '/api/status'    { Responder $ctx 200 (Json (Status)) }
    '/api/historico' { Responder $ctx 200 (LerHistorico) }
    '/api/alternar' {
      if ($corpo.habilitar) { Enable-ScheduledTask -TaskName $script:NomeTarefa | Out-Null } else { Disable-ScheduledTask -TaskName $script:NomeTarefa | Out-Null }
      Responder $ctx 200 (Json (Status))
    }
    '/api/executar' {
      New-Item -ItemType File -Force -Path (Join-Path $dir 'manual.flag') | Out-Null
      Start-ScheduledTask -TaskName $script:NomeTarefa
      Start-Sleep -Milliseconds 800
      Responder $ctx 200 (Json (Status))
    }
    '/api/horario' {
      if ("$($corpo.hora)" -notmatch '^([01]\d|2[0-3]):[0-5]\d$') { Responder $ctx 400 (Json @{ erro = 'Horário inválido' }); return }
      Set-ScheduledTask -TaskName $script:NomeTarefa -Trigger (New-ScheduledTaskTrigger -Daily -At $corpo.hora) | Out-Null
      Responder $ctx 200 (Json (Status))
    }
    '/api/modo' {
      $novo = "$($corpo.modo)"
      if ($novo -notin 'script', 'claude') { Responder $ctx 400 (Json @{ erro = 'Modo inválido' }); return }
      if ($novo -eq 'claude' -and -not (Get-ClaudeExe)) { Responder $ctx 400 (Json @{ erro = 'Claude Code não está instalado neste PC' }); return }
      $cfg = Get-Config
      $cfg.modo = $novo
      Save-Config $cfg
      Responder $ctx 200 (Json (Status))
    }
    '/api/versao'    { Responder $ctx 200 (Json (Versao ($req.QueryString['forcar'] -eq '1'))) }
    '/api/atualizar' { Responder $ctx 200 (Json (Atualizar)) }
    '/api/aviso_atualizacao' { Responder $ctx 200 (AvisoAtualizacao) }
    '/api/desfazer' { Responder $ctx 200 (Json (Desfazer "$($corpo.id)")) }
    '/api/abrir' {
      $downloads = Get-PastaDownloads
      $alvo = $downloads
      if ($corpo.alvo -eq 'dados') { $alvo = $dir }
      elseif ($corpo.alvo -and $corpo.alvo -ne 'downloads') {
        $p = [IO.Path]::GetFullPath((Join-Path $downloads "$($corpo.alvo)"))
        if ($p.StartsWith($downloads) -and (Test-Path -LiteralPath $p)) { $alvo = $p }
      }
      if (Test-Path -LiteralPath $alvo -PathType Leaf) { Start-Process explorer.exe "/select,`"$alvo`"" } else { Start-Process explorer.exe "`"$alvo`"" }
      Responder $ctx 200 '{"ok":true}'
    }
    '/api/encerrar' { Responder $ctx 200 '{"ok":true}'; $script:sair = $true }
    default { Responder $ctx 404 (Json @{ erro = 'Rota desconhecida' }) }
  }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Start()
if (-not $SemAbrir) { Start-Process $url }
$script:sair = $false

while ($listener.IsListening -and -not $script:sair) {
  $async = $listener.BeginGetContext($null, $null)
  [void]$async.AsyncWaitHandle.WaitOne()
  $ctx = $listener.EndGetContext($async)
  try { Rotear $ctx } catch { try { Responder $ctx 500 (Json @{ erro = $_.Exception.Message }) } catch {} }
}
$listener.Stop()
