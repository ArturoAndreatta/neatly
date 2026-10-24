# Remove o Neatly. Os arquivos ja organizados nos Downloads ficam onde estao.
. (Join-Path $PSScriptRoot 'comum.ps1')

Write-Host ''
Write-Host '  Desinstalando o Neatly...' -ForegroundColor Cyan

foreach ($t in @($script:NomeTarefa, $script:NomeTarefaPainel) + $script:TarefasAntigas) {
  if (Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $t -Confirm:$false
    Write-Host "  [ok] tarefa removida: $t" -ForegroundColor Green
  }
}
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { ($_.CommandLine -like '*\Neatly\painel.ps1*' -or $_.CommandLine -like '*OrganizadorDownloads*painel.ps1*') } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Host '  [ok] painel desligado' -ForegroundColor Green

$desktop = [Environment]::GetFolderPath('Desktop')
foreach ($lnk in @('Neatly.lnk') + $script:AtalhosAntigos | ForEach-Object { (Join-Path $desktop $_); (Join-Path ([Environment]::GetFolderPath('Programs')) $_) }) {
  if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }
}
Write-Host '  [ok] atalhos removidos' -ForegroundColor Green

$r = Read-Host '  Apagar tambem historico, configuracao e token salvo? [s/N]'
if ($r -and $r.Trim().ToLower() -in 's', 'sim') {
  Set-Location $env:TEMP
  Remove-Item -LiteralPath $script:PastaApp -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host '  [ok] dados apagados' -ForegroundColor Green
} else {
  Write-Host "  Dados mantidos em $($script:PastaApp)" -ForegroundColor DarkGray
}
Write-Host ''
Write-Host '  Pronto. Seus arquivos nos Downloads nao foram mexidos.' -ForegroundColor Green
Write-Host ''
