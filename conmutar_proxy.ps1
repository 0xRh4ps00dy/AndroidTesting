# =============================================================================
# conmutar_proxy.ps1
# Conmuta (activa/desactiva) el proxy configurado en el emulador Android.
# Uso:
#   .\conmutar_proxy.ps1 [IP:PUERTO]
#   Ejemplo: .\conmutar_proxy.ps1 192.168.1.137:8080
# =============================================================================

# Colores y logging
function Log-Info ($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Log-Ok ($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Log-Warn ($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Log-Error ($msg) { Write-Host "[-] $msg" -ForegroundColor Red }

# IP y puerto por defecto si no se especifica
$DEFAULT_PROXY = "192.168.1.137:8080"
$TARGET_PROXY = $args[0]
if (-not $TARGET_PROXY) {
    $TARGET_PROXY = $DEFAULT_PROXY
}

# 1. Verificar adb
if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
    Log-Error "No se encontro 'adb' en el sistema. Por favor, añade Android Platform-Tools a tu PATH."
    exit 1
}

# 2. Verificar dispositivo conectado
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
    exit 1
}

# 3. Obtener estado actual del proxy
$currentProxy = (adb shell settings get global http_proxy).Trim()

if ($currentProxy -eq "null" -or $currentProxy -eq ":0" -or -not $currentProxy) {
    # El proxy esta desactivado, lo activamos
    Log-Info "El proxy actual esta DESACTIVADO (valor: $currentProxy)."
    Log-Info "Activando proxy en el emulador -> $TARGET_PROXY"
    adb shell settings put global http_proxy "$TARGET_PROXY"
    
    # Confirmacion
    $updatedProxy = (adb shell settings get global http_proxy).Trim()
    Log-Ok "Proxy ACTIVADO correctamente: $updatedProxy"
} else {
    # El proxy esta activado, lo desactivamos
    Log-Info "El proxy actual esta ACTIVADO (valor: $currentProxy)."
    Log-Info "Desactivando proxy..."
    adb shell settings put global http_proxy :0
    
    # Confirmacion
    $updatedProxy = (adb shell settings get global http_proxy).Trim()
    Log-Ok "Proxy DESACTIVADO correctamente (valor: $updatedProxy)"
}
