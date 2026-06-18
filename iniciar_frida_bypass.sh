#!/usr/bin/env bash
# =============================================================================
# iniciar_frida_bypass.sh
# Automatiza el arranque de frida-server en el emulador y ejecuta el bypass.
# Descarga automaticamente la version correcta de frida-server si no existe.
#
# Uso:
#   ./iniciar_frida_bypass.sh [nombre_del_paquete_app]
#   Ejemplo: ./iniciar_frida_bypass.sh com.google.android.youtube
# =============================================================================

set -euo pipefail

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[*]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[-]${NC} $*"; }

# 1. Comprobar dependencias en el Host
if ! command -v frida &>/dev/null; then
    log_error "No se encontro 'frida' en tu sistema host."
    log_warn "Instalalo ejecutando: pip install frida-tools"
    exit 1
fi

if ! command -v adb &>/dev/null; then
    log_error "No se encontro 'adb' en el sistema."
    exit 1
fi

# 2. Comprobar AVD conectado
devices=$(adb devices | grep -v "List of devices" | grep "device$" | wc -l)
if [ "$devices" -eq 0 ]; then
    log_error "No se detecto ningun AVD conectado."
    exit 1
fi

device_id=$(adb devices | grep -v "List of devices" | grep "device$" | awk '{print $1}' | head -1)
log_ok "Dispositivo conectado detectado: $device_id"

# 3. Detectar version local de Frida y arquitectura del emulador
FRIDA_VERSION=$(frida --version | tr -d '\r\n')
log_info "Version local de Frida en el Host: $FRIDA_VERSION"

RAW_ABI=$(adb shell getprop ro.product.cpu.abi | tr -d '\r\n')
log_info "Arquitectura del emulador detectada: $RAW_ABI"

# Mapear arquitectura para el release de Frida
ABI=""
case "$RAW_ABI" in
    x86_64) ABI="x86_64" ;;
    x86) ABI="x86" ;;
    arm64-v8a|arm64) ABI="arm64" ;;
    armeabi-v7a|armeabi|arm) ABI="arm" ;;
    *)
        log_error "Arquitectura no soportada: $RAW_ABI"
        exit 1
        ;;
esac

# 4. Comprobar si frida-server ya esta en el emulador y corriendo
log_info "Comprobando si frida-server ya esta ejecutandose en el dispositivo..."
if adb shell "ps -A" 2>/dev/null | grep -q "frida-server"; then
    log_ok "frida-server ya esta corriendo en el emulador."
else
    # Comprobar si el archivo ya esta en /data/local/tmp/
    server_exists=$(adb shell "ls /data/local/tmp/frida-server" 2>/dev/null | tr -d '\r\n' || echo "")
    
    if [ "$server_exists" != "/data/local/tmp/frida-server" ]; then
        log_warn "frida-server no encontrado en /data/local/tmp/."
        
        # Descarga y preparacion de frida-server
        SERVER_TAR_NAME="frida-server-${FRIDA_VERSION}-android-${ABI}.xz"
        DOWNLOAD_URL="https://github.com/frida/frida/releases/download/${FRIDA_VERSION}/${SERVER_TAR_NAME}"
        
        log_info "Descargando frida-server oficial..."
        log_info "URL: $DOWNLOAD_URL"
        
        # Crear directorio de scripts temporales si no existe
        mkdir -p ./scripts
        TMP_DOWNLOAD="./scripts/${SERVER_TAR_NAME}"
        
        if command -v wget &>/dev/null; then
            wget -q --show-progress -O "$TMP_DOWNLOAD" "$DOWNLOAD_URL"
        elif command -v curl &>/dev/null; then
            curl -L -o "$TMP_DOWNLOAD" "$DOWNLOAD_URL"
        else
            log_error "No se encontro 'wget' ni 'curl' para descargar."
            exit 1
        fi
        
        log_info "Descomprimiendo frida-server..."
        if command -v xz &>/dev/null; then
            xz -d -f "$TMP_DOWNLOAD"
        else
            log_error "No se encontro 'xz' para descomprimir. Instala 'xz-utils'."
            exit 1
        fi
        
        DECOMPRESSED_FILE="./scripts/frida-server-${FRIDA_VERSION}-android-${ABI}"
        
        log_info "Subiendo frida-server al emulador..."
        adb push "$DECOMPRESSED_FILE" /data/local/tmp/frida-server
        
        # Limpieza local
        rm -f "$DECOMPRESSED_FILE"
    else
        log_ok "El ejecutable frida-server ya existia en el dispositivo."
    fi

    # Iniciar frida-server como root
    log_info "Iniciando frida-server como root en segundo plano..."
    # Se le dan permisos y se arranca en background
    adb shell "su -c 'chmod +x /data/local/tmp/frida-server'"
    adb shell "su -c '/data/local/tmp/frida-server >/dev/null 2>&1 &'"
    sleep 2
    
    if adb shell "ps -A" 2>/dev/null | grep -q "frida-server"; then
        log_ok "frida-server iniciado con exito."
    else
        log_error "No se pudo iniciar frida-server. Asegurate de otorgar permisos de root (su) en el emulador."
        exit 1
    fi
fi

# 5. Lanzar el bypass con Frida
APP_TARGET="${1:-com.google.android.youtube}"
log_info "Iniciando bypass de SSL Pinning en la aplicacion: $APP_TARGET"

# Asegurar que bypass-ssl.js existe
if [ ! -f "./bypass-ssl.js" ]; then
    log_error "No se encontro el archivo 'bypass-ssl.js' en la raiz del directorio."
    exit 1
fi

log_ok "Ejecutando Frida..."
frida -U -f "$APP_TARGET" -l ./bypass-ssl.js
