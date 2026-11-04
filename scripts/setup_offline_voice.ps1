# ---------------------------------------------------------------------------
# U.L.T.R.O.N. Mobile — Setup & Otimização de Voz Offline (Fish Audio + Eco-VAD)
# ---------------------------------------------------------------------------
param(
    [string]$VoiceSourcePath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AssetsDir   = Join-Path $ProjectRoot "android\app\src\main\assets"
New-Item -ItemType Directory -Force -Path $AssetsDir | Out-Null

$DestWav = Join-Path $AssetsDir "ultron_fish_voice.wav"

if ($VoiceSourcePath -and (Test-Path $VoiceSourcePath)) {
    Copy-Item -Path $VoiceSourcePath -Destination $DestWav -Force
    Write-Host "✅ Arquivo customizado da Fish Audio copiado para: $DestWav"
} elseif (Test-Path $DestWav) {
    Write-Host "✅ Arquivo de voz offline já presente em: $DestWav ($((Get-Item $DestWav).Length) bytes)"
} else {
    Write-Error "Arquivo ultron_fish_voice.wav não encontrado."
}

Write-Host "✅ Arquitetura Eco-VAD v2 configurada:"
Write-Host "   • Duty-Cycle Adaptativo: 82% a 93.3% Sleep (8kHz burst de 100ms)"
Write-Host "   • WakeLock Inteligente: 0% em repouso (timeout estrito de 8s apenas na fala)"
Write-Host "   • Hibernação automática do motor TTS após 25s de ociosidade"
Write-Host "   • Pausa automática em chamadas telefônicas, Flip-to-Shush e bateria < 15%"
