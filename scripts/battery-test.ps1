param(
    [int]$Minutes = 60,
    [string]$Package = "com.viniciusnpaula.ultron_mobile"
)
$ErrorActionPreference = "Stop"

# Recusa rodar sem dispositivo e sem app instalado — falha honesta, nunca stack trace.
$devices = adb devices | Select-String "device$"
if (-not $devices) {
    Write-Host "ERRO: Nenhum dispositivo adb conectado. Conecte o aparelho com depuracao USB e tente novamente."
    exit 1
}
if (-not (adb shell "pm list packages $Package" | Select-String "package:$Package")) {
    Write-Host "ERRO: App nao instalado: $Package (instale o APK primeiro)."
    exit 1
}

Write-Host "Reiniciando estatisticas de bateria (batterystats --reset)..."
adb shell dumpsys batterystats --reset | Out-Null

$levelStart = (adb shell dumpsys battery | Select-String "level:").ToString().Trim()
Write-Host "Nivel inicial: $levelStart"

$start = Get-Date
Write-Host "Aguardando $Minutes minuto(s) com a tela apagada e o app em segundo plano..."
Write-Host "Durante esse tempo, deixe o aparelho parado com a sentinela ativa."
Start-Sleep -Seconds ($Minutes * 60)

$levelEnd = (adb shell dumpsys battery | Select-String "level:").ToString().Trim()
Write-Host "Nivel final: $levelEnd"

$report = Join-Path $PSScriptRoot "battery-report.txt"
adb shell dumpsys batterystats $Package > $report
adb shell dumpsys power >> $report

$duracao = (Get-Date) - $start
Write-Host "Relatorio salvo em: $report"
Write-Host ("Duracao do teste: {0:N1} minuto(s)" -f $duracao.TotalMinutes)
Write-Host "Compare $levelStart com $levelEnd para calcular %/hora e mAh."
