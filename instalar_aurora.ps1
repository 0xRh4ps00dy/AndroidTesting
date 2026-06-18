# =============================================================================
# instalar_aurora.ps1
# Descarga e instala Aurora Store en el emulador Android conectado.
# Aurora Store permite descargar apps directamente desde Google Play Store
# sin requerir los servicios de Google ni tener que rootear con Magisk.
# =============================================================================

# Colores y logging
function Log-Info ($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Log-Ok ($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Log-Warn ($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Log-Error ($msg) { Write-Host "[-] $msg" -ForegroundColor Red }

# 1. Verificar adb
if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
    Log-Error "No se encontro 'adb' en el sistema. Por favor, añade Android Platform-Tools a tu PATH."
    exit 1
}

# 2. Verificar AVD conectado
$devices = adb devices | Where-Object { $_ -match 'device$' }
$deviceCount = 0
if ($devices) {
    if ($devices -is [array]) {
        $deviceCount = $devices.Count
    } else {
        $deviceCount = 1
    }
}

if ($deviceCount -eq 0) {
    Log-Error "No se detecto ningun emulador/dispositivo conectado via adb."
    Log-Warn "Enciende tu AVD primero e intenta de nuevo."
    exit 1
}

$deviceId = (adb devices | Where-Object { $_ -match 'device$' } | Select-Object -First 1).Split("`t")[0].Trim()
Log-Ok "Dispositivo conectado detectado: $deviceId"

# 3. Descargar APK
$APK_URL = "https://auroraoss.com/downloads/AuroraStore/Release/AuroraStore-4.6.1.apk"
$TMP_APK = Join-Path $env:TEMP "AuroraStore-4.6.1.apk"

Log-Info "Descargando Aurora Store desde el servidor oficial..."
Log-Info "URL: $APK_URL"

try {
    # Usamos WebClient o Invoke-WebRequest. Para mayor robustez y barra de progreso:
    Invoke-WebRequest -Uri $APK_URL -OutFile $TMP_APK -UseBasicParsing
    Log-Ok "Descarga completada correctamente: $TMP_APK"
} catch {
    Log-Error "Fallo al descargar la aplicacion: $_"
    exit 1
}

# 4. Instalar APK
Log-Info "Instalando Aurora Store en el emulador ($deviceId)..."
$installResult = adb install -r "$TMP_APK"

if ($LASTEXITCODE -eq 0) {
    Log-Ok "¡Aurora Store se ha instalado correctamente!"
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host "  ✅ INSTALACION COMPLETADA" -ForegroundColor Green
    Write-Host "  Ahora puedes abrir la app 'Aurora Store' en tu emulador:" -ForegroundColor Green
    Write-Host "    1. Inicia sesion usando el modo 'Anonimo' (no requiere tu cuenta)" -ForegroundColor Green
    Write-Host "    2. Busca y descarga cualquier aplicacion de la Google Play Store" -ForegroundColor Green
    Write-Host "    3. ¡Listo! Puedes interceptar su trafico HTTPS sin problemas" -ForegroundColor Green
    Write-Host "======================================================================" -ForegroundColor Green
} else {
    Log-Error "Fallo al instalar la aplicacion via adb."
}

# Limpieza
if (Test-Path $TMP_APK) {
    Remove-Item -Path $TMP_APK -Force
}
