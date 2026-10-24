# Testes (Pester 5). Rodar: Invoke-Pester ./tests
BeforeAll {
  $script:src = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
  $script:shell = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'powershell.exe' } else { 'pwsh' }

  function Novo-Ambiente {
    $raiz = Join-Path ([IO.Path]::GetTempPath()) ('org-teste-' + [guid]::NewGuid().ToString('N'))
    $dl = Join-Path $raiz 'Downloads'
    $app = Join-Path $raiz 'Local'
    New-Item -ItemType Directory -Force -Path $dl, (Join-Path $app 'OrganizadorDownloads') | Out-Null
    $env:ORGANIZADOR_DOWNLOADS = $dl
    $env:LOCALAPPDATA = $app
    return [pscustomobject]@{ Raiz = $raiz; Downloads = $dl; App = (Join-Path $app 'OrganizadorDownloads') }
  }

  function Novo-Arquivo($pasta, $nome, [int]$minutosAtras = 60) {
    $p = Join-Path $pasta $nome
    New-Item -ItemType Directory -Force -Path (Split-Path $p -Parent) | Out-Null
    Set-Content -LiteralPath $p -Value $nome
    (Get-Item -LiteralPath $p -Force).LastWriteTime = (Get-Date).AddMinutes(-$minutosAtras)
    return $p
  }

  function Rodar-Organizador {
    & $script:shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:src 'organizar.ps1') | Out-Null
    return $LASTEXITCODE
  }

  function Ler-Historico($amb) {
    @(Get-Content -LiteralPath (Join-Path $amb.App 'historico.jsonl') -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
  }
}

Describe 'Modo script' {
  BeforeEach { $script:amb = Novo-Ambiente }
  AfterEach { Remove-Item -LiteralPath $script:amb.Raiz -Recurse -Force -ErrorAction SilentlyContinue }

  It 'move cada arquivo para a pasta do seu tipo' {
    Novo-Arquivo $amb.Downloads 'foto.png' | Out-Null
    Novo-Arquivo $amb.Downloads 'contrato.pdf' | Out-Null
    Novo-Arquivo $amb.Downloads 'setup.exe' | Out-Null
    Rodar-Organizador | Should -Be 0
    Join-Path $amb.Downloads 'Imagens\foto.png' | Should -Exist
    Join-Path $amb.Downloads 'Documentos\contrato.pdf' | Should -Exist
    Join-Path $amb.Downloads 'Instaladores\setup.exe' | Should -Exist
  }

  It 'nunca mexe em arquivos com cara de segredo' {
    foreach ($n in '.env', 'chave.pem', 'servidor.key', 'meu-firebase-adminsdk-x.json', 'credentials.json') { Novo-Arquivo $amb.Downloads $n | Out-Null }
    Rodar-Organizador | Should -Be 0
    foreach ($n in '.env', 'chave.pem', 'servidor.key', 'meu-firebase-adminsdk-x.json', 'credentials.json') {
      Join-Path $amb.Downloads $n | Should -Exist
    }
  }

  It 'nao sobrescreve: arquivo com o mesmo nome ganha (1)' {
    Novo-Arquivo (Join-Path $amb.Downloads 'Imagens') 'foto.png' | Out-Null
    Novo-Arquivo $amb.Downloads 'foto.png' | Out-Null
    Rodar-Organizador | Should -Be 0
    Join-Path $amb.Downloads 'Imagens\foto.png' | Should -Exist
    Join-Path $amb.Downloads 'Imagens\foto (1).png' | Should -Exist
  }

  It 'espera a proxima rodada para arquivo mexido agora' {
    Novo-Arquivo $amb.Downloads 'baixando.zip' 1 | Out-Null
    Rodar-Organizador | Should -Be 0
    Join-Path $amb.Downloads 'baixando.zip' | Should -Exist
  }

  It 'deixa no lugar extensao fora da lista e subpastas' {
    Novo-Arquivo $amb.Downloads 'sem-extensao' | Out-Null
    Novo-Arquivo $amb.Downloads 'arquivo.xyz' | Out-Null
    Novo-Arquivo (Join-Path $amb.Downloads 'Projeto') 'dentro.pdf' | Out-Null
    Rodar-Organizador | Should -Be 0
    Join-Path $amb.Downloads 'sem-extensao' | Should -Exist
    Join-Path $amb.Downloads 'arquivo.xyz' | Should -Exist
    Join-Path $amb.Downloads 'Projeto\dentro.pdf' | Should -Exist
  }

  It 'grava a rodada no historico com o destino de cada arquivo' {
    Novo-Arquivo $amb.Downloads 'musica.mp3' | Out-Null
    Rodar-Organizador | Should -Be 0
    $h = @(Ler-Historico $amb)
    $h.Count | Should -Be 1
    $h[0].modo | Should -Be 'script'
    $h[0].status | Should -Be 'ok'
    $h[0].movidos[0].nome | Should -Be 'musica.mp3'
    $h[0].movidos[0].destino | Should -Be "$('Áudio')\musica.mp3"
  }
}

Describe 'Consumo do limite do Claude' {
  BeforeAll {
    $script:amb2 = Novo-Ambiente
    . (Join-Path $script:src 'comum.ps1')
    function Ev($u5, $r5, $u7, $r7) {
      [pscustomobject]@{ unifiedWindows = [pscustomobject]@{
        five_hour = [pscustomobject]@{ utilization = $u5; resetsAt = $r5 }
        seven_day = [pscustomobject]@{ utilization = $u7; resetsAt = $r7 } } }
    }
  }
  AfterAll { Remove-Item -LiteralPath $script:amb2.Raiz -Recurse -Force -ErrorAction SilentlyContinue }

  It 'soma o que subiu na janela de 5h e na semanal' {
    $r = Get-ConsumoLimites @((Ev 0.45 100 0.62 900), (Ev 0.46 100 0.621 900), (Ev 0.48 100 0.623 900))
    $r.cincoHoras.antes | Should -Be 45
    $r.cincoHoras.depois | Should -Be 48
    $r.cincoHoras.consumo | Should -Be 3
    $r.cincoHoras.reiniciou | Should -BeFalse
    $r.semanal.consumo | Should -Be 0.3
  }

  It 'conta certo quando a janela de 5h reinicia no meio da rodada' {
    $r = Get-ConsumoLimites @((Ev 0.97 100 0.7 900), (Ev 0.99 100 0.71 900), (Ev 0.01 200 0.711 900), (Ev 0.02 200 0.712 900))
    $r.cincoHoras.consumo | Should -Be 4
    $r.cincoHoras.reiniciou | Should -BeTrue
  }

  It 'aceita o formato antigo do evento' {
    $r = Get-ConsumoLimites @([pscustomobject]@{ rateLimitType = 'five_hour'; utilization = 0.3; resetsAt = 100 })
    $r.cincoHoras.antes | Should -Be 30
  }

  It 'devolve nada sem eventos' {
    Get-ConsumoLimites @() | Should -BeNullOrEmpty
  }
}
