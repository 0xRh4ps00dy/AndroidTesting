# =============================================================================
# bypass_ssl_directo.ps1
# Script principal (ejecutar en el HOST Windows)
# Automatiza el bypass de SSL Pinning en AVDs de Play Store sin Frida
# Basado en: https://www.mfumis.com/posts/bypassing-ssl-pinning-on-play-store-avds-without-frida/
# =============================================================================

param (
    [string]$Cert,
    [string]$Type,
    [string]$ProxyIp,
    [string]$ProxyPort = "8080",
    [switch]$Disconnect
)

# Colores y logging
function Log-Info ($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Log-Ok ($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Log-Warn ($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Log-Error ($msg) { Write-Host "[-] $msg" -ForegroundColor Red }
function Log-Section ($msg) {
    Write-Host "`n==============================" -ForegroundColor Blue
    Write-Host "  $msg" -ForegroundColor Blue
    Write-Host "==============================" -ForegroundColor Blue
}

# ClÃ¡usula para manejar "disconnect" como primer parÃ¡metro posicional
if ($args[0] -eq "disconnect") {
    $Disconnect = $true
}

$INJECT_SCRIPT = Join-Path $PSScriptRoot "scripts\inyectar_certificado.sh"

# --------------------------------------------------------------------------- #
# Funciones auxiliares
# --------------------------------------------------------------------------- #
function Show-Usage {
    Write-Host "Uso:" -ForegroundColor White
    Write-Host "  .\bypass_ssl_directo.ps1 -Cert <ruta_al_cert> -Type <burp|caido> [-ProxyIp <ip>] [-ProxyPort <puerto>]"
    Write-Host "  .\bypass_ssl_directo.ps1 disconnect"
    Write-Host ""
    Write-Host "Opciones:" -ForegroundColor White
    Write-Host "  -Cert        Ruta al archivo de certificado CA"
    Write-Host "                  Burp:  archivo .der (exportado desde Burp)"
    Write-Host "                  Caido: archivo .crt (exportado desde Caido)"
    Write-Host "  -Type        Tipo de proxy: 'burp' o 'caido'"
    Write-Host "  -ProxyIp     IP del proxy para configurar en el AVD (opcional)"
    Write-Host "  -ProxyPort   Puerto del proxy (opcional, por defecto 8080)"
    Write-Host "  -Disconnect  Desconecta el proxy del AVD"
    exit 1
}

# Limpiar Git usr/bin de PATH para evitar conflictos con herramientas del sistema (como find.exe/FIND.exe)
$paths = $env:Path -split ';' | Where-Object { $_ -and $_ -notlike "*\Git\usr\bin*" }
$env:Path = $paths -join ';'

$global:OpenSslCmd = "openssl"

function Check-Dependency ($cmd) {
    if ($cmd -eq "openssl") {
        if (Get-Command "openssl" -ErrorAction SilentlyContinue) {
            $global:OpenSslCmd = "openssl"
            return
        }
        $commonPaths = @(
            "C:\Program Files\Git\usr\bin\openssl.exe",
            "C:\Program Files (x86)\Git\usr\bin\openssl.exe",
            "C:\Git\usr\bin\openssl.exe"
        )
        foreach ($p in $commonPaths) {
            if (Test-Path $p) {
                $global:OpenSslCmd = $p
                Log-Info "OpenSSL autodetectado en: $p"
                return
            }
        }
        Log-Error "No se encontro 'openssl'. Por favor, instalalo primero y agregalo al PATH."
        exit 1
    }
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Log-Error "No se encontro '$cmd'. Por favor, instalalo primero y agregalo al PATH."
        exit 1
    }
}

function Check-AvdConnected {
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
        Log-Error "No se detecto ningun AVD conectado via adb."
        Log-Warn "Asegurate de que el AVD esta encendido y ejecuta: adb devices"
        exit 1
    }
    $deviceId = (adb devices | Where-Object { $_ -match 'device$' } | Select-Object -First 1).Split("`t")[0].Trim()
    Log-Ok "AVD detectado: $deviceId"
}

function Check-MagiskSu {
    $res = adb shell "su -c 'id'" 2>&1
    if ($res -match "uid=0") { return $true } else { return $false }
}

function Check-NativeRoot {
    $res = adb shell "id" 2>&1
    if ($res -match "uid=0") { return $true } else { return $false }
}

function Pause-ForUser ($msg) {
    Write-Host ""
    Write-Host "  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”" -ForegroundColor Yellow
    Write-Host "  â”‚  â¸  ACCION MANUAL REQUERIDA                 â”‚" -ForegroundColor Yellow
    Write-Host "  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜" -ForegroundColor Yellow
    Write-Host "  $msg" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  >>> Pulsa ENTER cuando hayas terminado"
    Write-Host ""
}

# --------------------------------------------------------------------------- #
# DesconexiÃ³n de Proxy
# --------------------------------------------------------------------------- #
if ($Disconnect) {
    Check-Dependency "adb"
    Log-Section "Desconectando proxy del AVD"
    adb shell settings put global http_proxy :0
    Log-Ok "Proxy desconectado del AVD."
    exit 0
}

# --------------------------------------------------------------------------- #
# Validaciones iniciales
# --------------------------------------------------------------------------- #
if (-not $Cert -or -not $Type) {
    Log-Error "Faltan argumentos obligatorios: -Cert y -Type"
    Show-Usage
}

if (-not (Test-Path $Cert -PathType Leaf)) {
    Log-Error "El archivo de certificado no existe: $Cert"
    exit 1
}

if ($Type -ne "burp" -and $Type -ne "caido") {
    Log-Error "El tipo debe ser 'burp' o 'caido', recibido: $Type"
    Show-Usage
}

# --------------------------------------------------------------------------- #
# PASO previo: Verificando y obteniendo root en el AVD
# --------------------------------------------------------------------------- #
function Run-RootAvdIfNeeded {
    Log-Section "PASO previo: Verificando root"

    Log-Info "Intentando habilitar root nativo (adb root)..."
    $null = adb root
    Start-Sleep -Seconds 1

    if (Check-NativeRoot) {
        Log-Ok "Root nativo (adb root) activo. Continuando sin necesidad de Magisk/rootAVD."
        return
    }

    if (Check-MagiskSu) {
        Log-Ok "Magisk su disponible. Continuando..."
        return
    }

    Log-Warn "Root nativo ni Magisk/su detectados en el AVD."

    # Detectar API y arquitectura para sugerir ramdisk.img
    $sdkVer = (adb shell getprop ro.build.version.sdk).Trim()
    $cpuAbi = (adb shell getprop ro.product.cpu.abi).Trim()
    $buildFlavor = (adb shell getprop ro.build.flavor).Trim()

    $imageType = "google_apis_playstore"
    if ($buildFlavor -like "*apis*" -and $buildFlavor -notlike "*playstore*") {
        $imageType = "google_apis"
    }

    # Si es arquitectura de 16KB (Android 15+)
    $pageSize = (adb shell getprop ro.boot.hardware.cpu.pagesize).Trim()
    if ($pageSize -eq "16384") {
        Log-Warn "Â¡ATENCION! El AVD detectado utiliza paginas de 16 KB (Android 15/16/17+ 16k)."
        Log-Warn "Los binarios de rootAVD/Busybox por defecto pueden no funcionar si no estan alineados a 16 KB."
        Log-Warn "Se recomienda usar una imagen 'Google APIs' en lugar de 'Google Play' para usar root nativo sin Magisk."
    }

    # Buscar el ramdisk.img de forma dinÃ¡mica
    $androidHome = $env:ANDROID_HOME
    if (-not $androidHome) {
        $androidHome = Join-Path $env:LOCALAPPDATA "Android\Sdk"
    }
    if (-not (Test-Path $androidHome)) {
        $androidHome = Join-Path $env:USERPROFILE "AppData\Local\Android\Sdk"
    }

    $sdkBase = Join-Path $androidHome "system-images"
    if (-not (Test-Path $sdkBase)) {
        Log-Error "No se encontro la ruta de system-images en el SDK: $sdkBase"
        Log-Warn "Define la variable de entorno ANDROID_HOME apuntando a tu Android SDK."
        exit 1
    }

    Log-Info "Buscando ramdisk.img compatible en $sdkBase ..."
    $foundFile = Get-ChildItem -Path $sdkBase -Filter "ramdisk.img" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*android-$sdkVer*" -and $_.FullName -like "*$imageType*" -and $_.FullName -like "*$cpuAbi*" } |
        Select-Object -First 1

    if (-not $foundFile) {
        Log-Error "No se pudo encontrar un ramdisk.img adecuado en las system-images del SDK."
        exit 1
    }

    # Ruta relativa a ANDROID_HOME (con barras invertidas corregidas)
    $ramdiskPath = $foundFile.FullName.Substring($androidHome.Length).TrimStart('\/')
    Log-Info "Ruta de ramdisk autodetectada para rootAVD: $ramdiskPath"

    $rootavdDir = Join-Path $PSScriptRoot "rootAVD"
    if (-not (Test-Path (Join-Path $rootavdDir "rootAVD.bat"))) {
        Log-Error "No se encontro rootAVD en $rootavdDir"
        Log-Error "Clonalo con: git clone https://gitlab.com/newbit/rootAVD.git $rootavdDir"
        exit 1
    }

    Log-Info "Ejecutando rootAVD para parchear el ramdisk con Magisk..."
    Log-Warn "rootAVD te pedira elegir la version de Magisk. Selecciona [1] (local stable) o la que prefieras."
    Write-Host ""

    # Ejecutar rootAVD.bat directamente en la misma ventana de la consola sin redirecciones
    Log-Info "Ejecutando rootAVD directamente en esta ventana..."
    Push-Location $rootavdDir
    try {
        $env:TMP_RAMDISK_PATH = $ramdiskPath
        & cmd.exe /c "rootAVD.bat %TMP_RAMDISK_PATH%"
    } finally {
        $env:TMP_RAMDISK_PATH = $null
        Pop-Location
    }

    Write-Host ""
    Log-Ok "rootAVD completado. El AVD se ha apagado automaticamente."

    Pause-ForUser "Ahora debes hacer el COLD BOOT del emulador:

    1. Abre Android Studio -> Device Manager
    2. Haz clic en la flecha [v] junto a tu AVD
    3. Selecciona  'Cold Boot Now'
    4. Espera a que el AVD arranque completamente (puede tardar 1-2 min)
    5. Abre la app  Magisk  en el emulador
    6. Si Magisk pide completar la instalacion -> acepta y espera el reboot automatico
    7. Vuelve a esperar que el AVD arranque del todo"

    Log-Info "Verificando que root esta disponible ahora..."
    adb wait-for-device
    $null = adb root
    Start-Sleep -Seconds 3

    if (-not (Check-NativeRoot) -and -not (Check-MagiskSu)) {
        Log-Error "Ni root nativo ni Magisk su responden."
        Log-Warn "Asegurate de haber hecho Cold Boot y completado la instalacion de Magisk."
        Pause-ForUser "Cuando el dispositivo este listo y rooteado, pulsa ENTER para reintentar."
        
        if (-not (Check-NativeRoot) -and -not (Check-MagiskSu)) {
            Log-Error "No se puede continuar sin root. Revisa la instalacion manualmente."
            exit 1
        }
    }

    Log-Ok "Root verificado correctamente."
}

# --------------------------------------------------------------------------- #
# PASO 5a: Preparar el certificado (generar hash + renombrar)
# --------------------------------------------------------------------------- #
$certAndroidName = ""
$certPrepared = ""

function Prepare-Certificate {
    Log-Section "PASO 5a: Preparando el certificado CA"

    $derFile = ""
    if ($Type -eq "burp") {
        $derFile = $Cert
        Log-Info "Tipo Burp Suite: usando el .der directamente."
    } else {
        # Caido: convertir PEM (.crt) a DER
        Log-Info "Tipo Caido: convirtiendo PEM (.crt) a DER (.der)..."
        $derFile = $Cert -replace '\.crt$', '.der'
        & $global:OpenSslCmd x509 -in $Cert -outform DER -out $derFile
        Log-Ok "Certificado convertido a DER: $derFile"
    }

    # Generar el Android subject hash
    Log-Info "Generando Android subject hash..."
    $certHash = (& $global:OpenSslCmd x509 -inform DER -subject_hash_old -in $derFile | Select-Object -First 1).Trim()
    $script:certAndroidName = "$certHash.0"

    Log-Ok "Hash del certificado: $certHash"
    Log-Ok "Nombre para Android: $script:certAndroidName"

    # Copiar/renombrar en la carpeta temporal de Windows
    $script:certPrepared = Join-Path $env:TEMP $script:certAndroidName
    Copy-Item -Path $derFile -Destination $script:certPrepared -Force
    Log-Ok "Certificado preparado en: $script:certPrepared"
}

# --------------------------------------------------------------------------- #
# PASO 5b: Subir el certificado y el inject script al AVD
# --------------------------------------------------------------------------- #
function Push-FilesToAvd {
    Log-Section "PASO 5b: Subiendo archivos al AVD"

    Log-Info "Subiendo certificado: $certAndroidName ..."
    adb push "$certPrepared" /storage/self/primary/
    Log-Ok "Certificado subido correctamente."

    Log-Info "Subiendo script de inyeccion..."
    adb push "$INJECT_SCRIPT" /storage/self/primary/inyectar_certificado.sh
    Log-Ok "Script de inyeccion subido."
}

# --------------------------------------------------------------------------- #
# PASO 5c: Ejecutar el script de inyeccion como root en el AVD
# --------------------------------------------------------------------------- #
function Inject-Certificate {
    Log-Section "PASO 5c: Inyectando certificado como System Authority"

    Log-Info "Ejecutando inyectar_certificado.sh como root..."
    if (Check-MagiskSu) {
        adb shell "su -c 'sh /storage/self/primary/inyectar_certificado.sh $certAndroidName'"
    } else {
        adb shell "sh /storage/self/primary/inyectar_certificado.sh $certAndroidName"
    }
    Log-Ok "Certificado instalado como System Authority correctamente."
}

# --------------------------------------------------------------------------- #
# PASO 6: Configurar el proxy en el AVD
# --------------------------------------------------------------------------- #
function Configure-Proxy {
    if (-not $ProxyIp) {
        Log-Warn "No se especifico proxy (-ProxyIp). Saltando configuracion de proxy."
        Log-Warn "Para configurarlo manualmente despues, usa:"
        Write-Host "    adb shell settings put global http_proxy <IP>:<PUERTO>"
        Write-Host "    adb shell settings put global http_proxy :0 # para desconectar"
        return
    }

    Log-Section "PASO 6: Configurando proxy en el AVD"
    Log-Info "Configurando proxy: ${ProxyIp}:${ProxyPort}"

    adb shell settings put global http_proxy "${ProxyIp}:${ProxyPort}"
    Log-Ok "Proxy configurado: ${ProxyIp}:${ProxyPort}"

    $currentProxy = (adb shell settings get global http_proxy).Trim()
    Log-Info "Proxy activo en el AVD: $currentProxy"
}

# --------------------------------------------------------------------------- #
# MAIN
# --------------------------------------------------------------------------- #
function Main {
    Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |      SSL Pinning Bypass - AVD Play Store Setup       |" -ForegroundColor Cyan
    Write-Host "  |   Sin Frida | Basado en mfumis.com/posts/...         |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    Log-Section "Verificando dependencias"
    Check-Dependency "adb"
    Check-Dependency "openssl"
    Log-Ok "Todas las dependencias encontradas."

    Log-Section "Verificando AVD conectado"
    Check-AvdConnected

    Run-RootAvdIfNeeded
    Prepare-Certificate
    Push-FilesToAvd
    Inject-Certificate
    Configure-Proxy

    Log-Section "COMPLETADO"
    Write-Host "  [OK] El certificado CA esta instalado como System Authority." -ForegroundColor Green
    if ($ProxyIp) {
        Write-Host "  [OK] Proxy configurado: ${ProxyIp}:${ProxyPort}" -ForegroundColor Green
    }
    Write-Host ""
    Log-Warn "NOTA: Cada vez que reinicies el AVD, debes volver a"
    Log-Warn "ejecutar la inyeccion del certificado:"
    Write-Host ""
    Write-Host "     adb root && adb shell sh /storage/self/primary/inyectar_certificado.sh $certAndroidName" -ForegroundColor Yellow
    Write-Host ""

    # Limpieza local
    if (Test-Path $certPrepared) {
        Remove-Item -Path $certPrepared -Force
    }
}

Main
