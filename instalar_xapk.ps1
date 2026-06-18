# =============================================================================
# instalar_xapk.ps1
# Script para automatizar la instalación de Split APKs / XAPKs engañando al gestor
# de paquetes de Android para saltarse las restricciones de Play Integrity (error "Get this app from Play").
# =============================================================================

# Colores y logging
function Log-Info ($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Log-Ok ($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Log-Warn ($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Log-Error ($msg) { Write-Host "[-] $msg" -ForegroundColor Red }

Write-Host "=== Instalador Automatizado de XAPK / Split APKs (Bypass Play Integrity) ===" -ForegroundColor Blue

# 1. Verificar adb
if (-not (Get-Command "adb" -ErrorAction SilentlyContinue)) {
    Log-Error "Error: 'adb' no está instalado o no se encuentra en el PATH."
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
    Log-Error "Error: No hay ningún dispositivo o emulador Android conectado a ADB."
    Log-Warn "Asegúrate de iniciar tu emulador antes de ejecutar este script."
    exit 1
}

# 3. Obtener ruta del archivo XAPK / APKS / ZIP
$inputFile = $args[0]
if (-not $inputFile) {
    Log-Warn "Uso: .\instalar_xapk.ps1 <ruta_al_archivo.xapk | ruta_al_archivo.apks | ruta_al_archivo.zip>"
    $inputFile = Read-Host "Introduce la ruta del archivo a instalar"
}

if (-not (Test-Path $inputFile -PathType Leaf)) {
    Log-Error "Error: El archivo '$inputFile' no existe."
    exit 1
}

# 4. Crear directorio temporal dentro del espacio de trabajo
$tmpDirName = "tmp_xapk_extracted_" + (New-Guid).Guid.Substring(0,8)
$tmpDir = Join-Path (Get-Location) $tmpDirName
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    # Descomprimir XAPK/ZIP
    Log-Info "Descomprimiendo '$inputFile'..."
    
    # Expand-Archive nativo de PowerShell requiere que el archivo termine en .zip para ser reconocido a veces.
    # Copiamos a un temporal con extension .zip para garantizar la compatibilidad.
    $tempZip = Join-Path $env:TEMP ("temp_extract_" + (New-Guid).Guid.Substring(0,8) + ".zip")
    Copy-Item -Path $inputFile -Destination $tempZip -Force
    Expand-Archive -Path $tempZip -DestinationPath $tmpDir -Force
    Remove-Item -Path $tempZip -Force

    # 5. Obtener ABI del dispositivo Android
    Log-Info "Detectando arquitectura del emulador/dispositivo..."
    $deviceAbis = (adb shell getprop ro.product.cpu.abilist).Trim() -replace ',', ' ' -replace '-', '_'
    if (-not $deviceAbis) {
        $deviceAbis = (adb shell getprop ro.product.cpu.abi).Trim() -replace '-', '_'
    }
    Log-Ok "ABIs soportadas por el dispositivo: $deviceAbis"

    # Filtrar APKs compatibles
    $apksToInstall = @()
    $baseApkFound = $false
    $archKeywords = @("arm64", "armeabi", "x86", "x86_64", "mips")

    $apks = Get-ChildItem -Path $tmpDir -Filter "*.apk"
    if ($apks.Count -eq 0 -and -not $apks) {
        Log-Error "Error: No se encontraron archivos APK en el paquete."
        exit 1
    }

    # Si Get-ChildItem devuelve un solo objeto, forzamos comportamiento de array
    $apkList = @()
    if ($apks -is [array]) {
        $apkList = $apks
    } elseif ($apks) {
        $apkList = @($apks)
    }

    foreach ($apk in $apkList) {
        $filename = $apk.Name
        $isAbiSplit = $false
        $matchesDevice = $false

        foreach ($kw in $archKeywords) {
            if ($filename -like "*$kw*") {
                $isAbiSplit = $true
                $normalizedFilename = $filename -replace '-', '_'
                foreach ($abi in ($deviceAbis -split '\s+')) {
                    if ($kw -eq "x86_64" -and $normalizedFilename -like "*x86_64*") {
                        if ($deviceAbis -like "*x86_64*") { $matchesDevice = $true }
                    }
                    elseif ($kw -eq "arm64" -and $normalizedFilename -like "*arm64*") {
                        if ($deviceAbis -like "*arm64*") { $matchesDevice = $true }
                    }
                    elseif ($kw -eq "x86" -and $normalizedFilename -like "*x86*" -and $normalizedFilename -notlike "*x86_64*") {
                        if ($deviceAbis -like "*x86*") { $matchesDevice = $true }
                    }
                    elseif ($kw -eq "armeabi" -and $normalizedFilename -like "*armeabi*") {
                        if ($deviceAbis -like "*armeabi*") { $matchesDevice = $true }
                    }
                }
                break
            }
        }

        # Decidir si conservar el APK
        if ($isAbiSplit) {
            if ($matchesDevice) {
                Log-Ok "Conservando split de arquitectura compatible: $filename"
                $apksToInstall += $apk.FullName
            } else {
                Log-Warn "Omitiendo split de arquitectura no compatible: $filename"
            }
        } else {
            # Si no es un split de arquitectura, es la base o config de idioma/densidad. Las incluimos.
            if ($filename -notlike "*config*" -and $filename -notlike "*split*") {
                $baseApkFound = $true
                Log-Ok "Base APK detectada: $filename"
            } else {
                Log-Ok "Conservando split de configuracion (idioma/densidad): $filename"
            }
            $apksToInstall += $apk.FullName
        }
    }

    if ($apksToInstall.Count -eq 0) {
        Log-Error "Error: No se seleccionaron APKs compatibles para instalar."
        exit 1
    }

    if (-not $baseApkFound) {
        Log-Warn "Advertencia: No se ha identificado con seguridad un base APK principal."
        Log-Warn "Se intentará instalar todos los APKs seleccionados de todas formas."
    }

    # Intentar extraer el nombre del paquete para desinstalar versiones previas si es necesario (usando aapt)
    $packageName = ""
    if (Get-Command "aapt" -ErrorAction SilentlyContinue) {
        foreach ($apkPath in $apksToInstall) {
            $filename = Split-Path $apkPath -Leaf
            if ($filename -notlike "*config*" -and $filename -notlike "*split*") {
                $badging = & aapt dump badging $apkPath 2>$null
                $packageLine = $badging | Select-String -Pattern "^package:"
                if ($packageLine -match "name='([^']+)'") {
                    $packageName = $Matches[1]
                    break
                }
            }
        }
    }

    if ($packageName) {
        Log-Info "Desinstalando versión previa del paquete '$packageName' (si existe)..."
        adb uninstall "$packageName" *>$null
    }

    # Proceder con la instalación forzando com.android.vending
    Log-Info "Ejecutando instalación forzando el origen oficial de Google Play (com.android.vending)..."
    $adbArgs = @("install-multiple", "-r", "-i", "com.android.vending") + $apksToInstall
    
    & adb $adbArgs

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Log-Ok "¡Instalación completada con éxito!"
        Log-Info "La aplicación se ha registrado con el origen oficial de Play Store para evitar bloqueos de integridad."
    } else {
        Write-Host ""
        Log-Error "Error al realizar adb install-multiple."
        exit 1
    }

} finally {
    # Asegurar limpieza al salir
    if (Test-Path $tmpDir) {
        Log-Info "Limpiando archivos temporales..."
        Remove-Item -Path $tmpDir -Recurse -Force | Out-Null
    }
}
