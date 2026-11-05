param(
    [string]$Apk = "build\app\outputs\flutter-apk\app-debug.apk"
)
$ErrorActionPreference = "Stop"

if (-not (adb devices | Select-String "device$")) {
    Write-Host "ERRO: Nenhum dispositivo adb conectado."
    exit 1
}
if (-not (Test-Path $Apk)) {
    Write-Host "ERRO: APK nao encontrado: $Apk (gere com flutter build apk --debug)."
    exit 1
}

Write-Host "Instalando APK: $Apk"
adb install -r $Apk | Out-Null

Write-Host "Limpando logcat e tag UltronWake..."
adb logcat -c | Out-Null

Write-Host "Acompanhando tag UltronWake:V (Ctrl+C encerra a coleta)."
adb logcat -s UltronWake:V
