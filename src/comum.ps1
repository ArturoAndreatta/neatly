# Funcoes compartilhadas pelo organizador e pelo painel.

$script:PastaApp = Join-Path $env:LOCALAPPDATA 'OrganizadorDownloads'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:NomeTarefa = 'Organizar Downloads'
$script:NomeTarefaPainel = 'Organizar Downloads - Painel'

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
