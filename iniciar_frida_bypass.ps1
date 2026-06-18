# =============================================================================
# iniciar_frida_bypass.ps1
# Automatiza el arranque de frida-server en el emulador y ejecuta el bypass.
# Descarga automaticamente la version correcta de frida-server si no existe.
#
# Uso:
#   .\iniciar_frida_bypass.ps1 [nombre_del_paquete_app]
#   Ejemplo: .\iniciar_frida_bypass.ps1 com.google.android.youtube
# =============================================================================

# Colores y logging
function Log-Info ($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Log-Ok ($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Log-Warn ($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Log-Error ($msg) { Write-Host "[-] $msg" -ForegroundColor Red }

# 1. Comprobar dependencias en el Host
if (-not (Get-Command "frida" -ErrorAction SilentlyContinue)) {
    Log-Error "No se encontro 'frida' en tu sistema host."
    Log-Warn "Instalalo ejecutando: pip install frida-tools"
    exit 1
}

if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
    Log-Error "No se encontro 'adb' en el sistema."
    exit 1
}

# 2. Comprobar AVD conectado
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
    Log-Error "No se detecto ningun AVD conectado."
    exit 1
}

$deviceId = (adb devices | Where-Object { $_ -match 'device$' } | Select-Object -First 1).Split("`t")[0].Trim()
Log-Ok "Dispositivo conectado detectado: $deviceId"

# 3. Detectar version local de Frida y arquitectura del emulador
$fridaVersion = (frida --version).Trim()
Log-Info "Version local de Frida en el Host: $fridaVersion"

$rawAbi = (adb shell getprop ro.product.cpu.abi).Trim()
Log-Info "Arquitectura del emulador detectada: $rawAbi"

# Mapear arquitectura para el release de Frida
$abi = ""
switch ($rawAbi) {
    "x86_64" { $abi = "x86_64" }
    "x86" { $abi = "x86" }
    "arm64-v8a" { $abi = "arm64" }
    "arm64" { $abi = "arm64" }
    "armeabi-v7a" { $abi = "arm" }
    "armeabi" { $abi = "arm" }
    "arm" { $abi = "arm" }
    Default {
        Log-Error "Arquitectura no soportada: $rawAbi"
        exit 1
    }
}

# 4. Comprobar si frida-server ya esta en el emulador y corriendo
Log-Info "Comprobando si frida-server ya esta ejecutandose en el dispositivo..."
$running = adb shell "ps -A" 2>$null | Select-String "frida-server"

if ($running) {
    Log-Ok "frida-server ya esta corriendo en el emulador."
} else {
    # Comprobar si el archivo ya esta en /data/local/tmp/
    $serverExists = (adb shell "ls /data/local/tmp/frida-server" 2>$null).Trim()
    
    if ($serverExists -ne "/data/local/tmp/frida-server") {
        Log-Warn "frida-server no encontrado en /data/local/tmp/."
        
        # Descarga y preparacion de frida-server
        $serverTarName = "frida-server-$fridaVersion-android-$abi.xz"
        $downloadUrl = "https://github.com/frida/frida/releases/download/$fridaVersion/$serverTarName"
        
        Log-Info "Descargando frida-server oficial..."
        Log-Info "URL: $downloadUrl"
        
        # Crear directorio de scripts temporales si no existe
        if (-not (Test-Path ".\scripts")) {
            New-Item -ItemType Directory -Path ".\scripts" | Out-Null
        }
        
        $tmpDownload = Join-Path ".\scripts" $serverTarName
        $decompressedFile = Join-Path ".\scripts" ("frida-server-$fridaVersion-android-$abi")
        
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpDownload -UseBasicParsing
            Log-Ok "Descarga completada."
        } catch {
            Log-Error "Fallo al descargar frida-server: $_"
            exit 1
        }
        
        Log-Info "Descomprimiendo frida-server..."
        $decompressSuccess = $false
        
        # Intentar con Python (módulo lzma) ya que al tener Frida instalado Python debe estar disponible
        if (Get-Command "python" -ErrorAction SilentlyContinue) {
            Log-Info "Usando Python (modulo lzma) para descomprimir..."
            try {
                $pythonCmd = "import lzma; open(r'$decompressedFile', 'wb').write(lzma.open(r'$tmpDownload').read())"
                python -c $pythonCmd
                if (Test-Path $decompressedFile) {
                    $decompressSuccess = $true
                }
            } catch {
                Log-Warn "Fallo al descomprimir con Python: $_"
            }
        }
        
        # Fallback a 7-Zip si está disponible
        if (-not $decompressSuccess -and (Get-Command "7z" -ErrorAction SilentlyContinue)) {
            Log-Info "Usando 7-Zip para descomprimir..."
            try {
                & 7z x "$tmpDownload" -o"scripts" -y | Out-Null
                if (Test-Path $decompressedFile) {
                    $decompressSuccess = $true
                }
            } catch {
                Log-Warn "Fallo al descomprimir con 7-Zip: $_"
            }
        }
        
        if (-not $decompressSuccess) {
            Log-Error "No se encontro un metodo de descompresion compatible para archivos .xz (se requiere Python o 7-Zip)."
            exit 1
        }
        
        Log-Info "Subiendo frida-server al emulador..."
        adb push "$decompressedFile" /data/local/tmp/frida-server
        
        # Limpieza local
        Remove-Item -Path $decompressedFile -Force
        Remove-Item -Path $tmpDownload -Force
    } else {
        Log-Ok "El ejecutable frida-server ya existia en el dispositivo."
    }

    # Iniciar frida-server como root
    Log-Info "Iniciando frida-server como root en segundo plano..."
    adb shell "su -c 'chmod +x /data/local/tmp/frida-server'"
    adb shell "su -c 'nohup /data/local/tmp/frida-server >/dev/null 2>&1 &'"
    Start-Sleep -Seconds 2
    
    $runningNow = adb shell "ps -A" 2>$null | Select-String "frida-server"
    if ($runningNow) {
        Log-Ok "frida-server iniciado con exito."
    } else {
        Log-Error "No se pudo iniciar frida-server. Asegurate de otorgar permisos de root (su) en el emulador."
        exit 1
    }
}

# 5. Lanzar el bypass con Frida
$appTarget = $args[0]
if (-not $appTarget) {
    $appTarget = "com.google.android.youtube"
}

Log-Info "Iniciando bypass de SSL Pinning en la aplicacion: $appTarget"

# Asegurar que bypass-ssl.js existe
if (-not (Test-Path ".\bypass-ssl.js")) {
    Log-Error "No se encontro el archivo 'bypass-ssl.js' en la raiz del directorio."
    exit 1
}

Log-Ok "Ejecutando Frida..."
frida -U -f "$appTarget" -l .\bypass-ssl.js
