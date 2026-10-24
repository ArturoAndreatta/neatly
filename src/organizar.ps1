# Organiza os arquivos soltos na raiz da pasta Downloads em subpastas por tipo.
# Modo "script": regras fixas, sem IA. Modo "claude": chama o Claude Code.
# Cada execucao vira uma linha em historico.jsonl, lida pelo painel.
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'comum.ps1')

$cfg = Get-Config
$mapa = Get-Categorias $cfg
$downloads = Get-PastaDownloads
$hist = Join-Path $script:PastaApp 'historico.jsonl'
$flag = Join-Path $script:PastaApp 'manual.flag'

$origem = 'agendada'
if (Test-Path -LiteralPath $flag) { $origem = 'manual'; Remove-Item -LiteralPath $flag -Force }

$inicio = Get-Date
$movidos = New-Object System.Collections.ArrayList
$codigo = 0
$resumo = ''
$res = $null
$limites = $null
$modo = "$($cfg.modo)"

if ($modo -eq 'claude') {
  $exe = Get-ClaudeExe
  if (-not $exe) {
    $codigo = 2
    $resumo = 'Claude Code nao encontrado. Instale o Claude Code ou troque para o modo "Só script" no painel.'
  } else {
    # Token de longa duracao (claude setup-token), criptografado para este usuario do Windows
    $tokFile = Join-Path $script:PastaApp 'token.dat'
    if (Test-Path -LiteralPath $tokFile) {
      try {
        $sec = Get-Content -LiteralPath $tokFile -Raw | ConvertTo-SecureString
        $env:CLAUDE_CODE_OAUTH_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
      } catch {}
    }

    $regras = ($mapa.Keys | ForEach-Object { "- ${_}: $($mapa[$_] -join ' ')" }) -join "`n"
    $prompt = @"
Organize a raiz desta pasta (Downloads). Mova apenas ARQUIVOS soltos na raiz para as subpastas conforme a extensao, criando a subpasta se nao existir:
$regras
Regras: nunca mexa em subpastas nem no conteudo delas; nunca apague nada; ignore arquivos cujo nome bata com estes padroes: $(@($cfg.ignorar) -join ', '); ignore arquivos modificados nos ultimos $($cfg.minutosRecentes) minutos; extensao fora da lista fica onde esta. Se ja existir arquivo com o mesmo nome no destino, use "nome (1).ext", "(2)" etc., nunca sobrescreva. Se a raiz ja estiver organizada, termine sem fazer nada. No final responda numa linha quantos arquivos foram movidos por pasta.
"@

    $antes = @(Get-ChildItem -LiteralPath $downloads -File -Force | Select-Object Name, Length)
    Set-Location -LiteralPath $downloads
    [Console]::OutputEncoding = [Text.Encoding]::UTF8
    # stream-json: alem do resultado, traz os eventos rate_limit_event com o uso das janelas de 5h e semanal
    $saida = & $exe -p $prompt --model "$($cfg.modelo)" --permission-mode acceptEdits --permission-prompts none --max-turns 40 --no-session-persistence --output-format stream-json --verbose 2>&1
    $codigo = $LASTEXITCODE

    $eventosLimite = New-Object System.Collections.ArrayList
    foreach ($linha in $saida) {
      if (-not ($linha -is [string]) -or -not $linha.TrimStart().StartsWith('{')) { continue }
      try { $obj = $linha | ConvertFrom-Json } catch { continue }
      if ($obj.type -eq 'result') { $res = $obj }
      elseif ($obj.type -eq 'rate_limit_event') { [void]$eventosLimite.Add($obj.rate_limit_info) }
    }
    $limites = Get-ConsumoLimites $eventosLimite
    if ($res -and $res.result) { $resumo = "$($res.result)" } else { $resumo = (($saida | Where-Object { $_ -is [string] -and -not $_.TrimStart().StartsWith('{') } | Out-String).Trim()) }
    if (-not $resumo) { $resumo = (($saida | Out-String).Trim()) }
    if ($codigo -eq 0 -and $res -and $res.is_error) { $codigo = 1 }

    # Descobre para onde cada arquivo que sumiu da raiz foi parar
    $depois = @(Get-ChildItem -LiteralPath $downloads -File -Force | ForEach-Object Name)
    $usados = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($a in $antes) {
      if ($depois -contains $a.Name) { continue }
      $base = [IO.Path]::GetFileNameWithoutExtension($a.Name)
      $ext = [IO.Path]::GetExtension($a.Name)
      $padrao = '^' + [regex]::Escape($base) + '( \(\d+\))?' + [regex]::Escape($ext) + '$'
      $destino = $null
      foreach ($c in $mapa.Keys) {
        $p = Join-Path $downloads $c
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $cand = Get-ChildItem -LiteralPath $p -File -Force |
          Where-Object { $_.Name -match $padrao -and $_.Length -eq $a.Length -and -not $usados.Contains($_.FullName) } |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($cand) { [void]$usados.Add($cand.FullName); $destino = "$c\$($cand.Name)"; break }
      }
      $pasta = '?'
      if ($destino) { $pasta = $destino.Split('\')[0] }
      [void]$movidos.Add([ordered]@{ nome = $a.Name; pasta = $pasta; destino = $destino; tamanho = $a.Length })
    }
  }
} else {
  $modo = 'script'
  $limite = (Get-Date).AddMinutes(-[double]$cfg.minutosRecentes)
  $falhas = 0
  foreach ($f in @(Get-ChildItem -LiteralPath $downloads -File -Force)) {
    if (Test-Ignorado $cfg $f.Name) { continue }
    if ($f.LastWriteTime -gt $limite) { continue }
    $c = Get-CategoriaDoArquivo $mapa $f.Name
    if (-not $c) { continue }
    $pastaDestino = Join-Path $downloads $c
    try {
      New-Item -ItemType Directory -Force -Path $pastaDestino | Out-Null
      $alvo = Get-DestinoLivre $pastaDestino $f.Name
      Move-Item -LiteralPath $f.FullName -Destination $alvo -ErrorAction Stop
      [void]$movidos.Add([ordered]@{ nome = $f.Name; pasta = $c; destino = "$c\$([IO.Path]::GetFileName($alvo))"; tamanho = $f.Length })
    } catch { $falhas++ }
  }
  $grupos = $movidos | Group-Object { $_.pasta } | ForEach-Object { "$($_.Name): $($_.Count)" }
  if ($movidos.Count) { $resumo = 'Movidos: ' + ($grupos -join ', ') } else { $resumo = 'Nada para mover.' }
  if ($falhas) { $resumo += " | $falhas arquivo(s) em uso ou sem permissao ficaram na raiz."; $codigo = 1 }
}

$fim = Get-Date
if ($resumo.Length -gt 2000) { $resumo = $resumo.Substring(0, 2000) }
$status = 'ok'
if ($codigo -ne 0) { $status = 'erro' }

$entrada = [ordered]@{
  id = $inicio.ToString('yyyyMMddHHmmss')
  inicio = $inicio.ToString('o')
  fim = $fim.ToString('o')
  duracaoSeg = [math]::Round(($fim - $inicio).TotalSeconds, 1)
  origem = $origem
  modo = $modo
  status = $status
  codigoSaida = $codigo
  resumo = $resumo
  turnos = $(if ($res) { $res.num_turns } else { $null })
  custoUsd = $(if ($res) { $res.total_cost_usd } else { $null })
  limites = $limites
  movidos = $movidos
  desfeito = $false
}
$json = ConvertTo-Json -InputObject $entrada -Depth 5 -Compress
[IO.File]::AppendAllText($hist, $json + [Environment]::NewLine, $script:Utf8)
exit $codigo
