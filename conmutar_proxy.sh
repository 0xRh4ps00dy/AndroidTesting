#!/usr/bin/env bash
# =============================================================================
# toggle_proxy.sh
# Commuta (activa/desactiva) el proxy configurado en el emulador Android.
# Uso:
#   ./toggle_proxy.sh [IP:PUERTO]
#   Ejemplo: ./toggle_proxy.sh 192.168.1.137:8080
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

# IP y puerto por defecto si no se especifica
DEFAULT_PROXY="192.168.1.137:8080"
TARGET_PROXY="${1:-$DEFAULT_PROXY}"

# 1. Verificar adb
if ! command -v adb &>/dev/null; then
    log_error "No se encontro 'adb' en el sistema."
    exit 1
fi

# 2. Verificar dispositivo conectado
devices=$(adb devices | grep -v "List of devices" | grep "device$" | wc -l)
if [ "$devices" -eq 0 ]; then
    log_error "No hay ningun emulador/dispositivo conectado via adb."
    exit 1
fi

# 3. Obtener estado actual del proxy
current_proxy=$(adb shell settings get global http_proxy | tr -d '\r\n')

if [ "$current_proxy" = "null" ] || [ "$current_proxy" = ":0" ] || [ -z "$current_proxy" ]; then
    # El proxy esta desactivado, lo activamos
    log_info "El proxy actual esta DESACTIVADO (valor: $current_proxy)."
    log_info "Activando proxy en el emulador -> $TARGET_PROXY"
    adb shell settings put global http_proxy "$TARGET_PROXY"
    
    # Confirmacion
    updated_proxy=$(adb shell settings get global http_proxy | tr -d '\r\n')
    log_ok "Proxy ACTIVADO correctamente: $updated_proxy"
else
    # El proxy esta activado, lo desactivamos
    log_info "El proxy actual esta ACTIVADO (valor: $current_proxy)."
    log_info "Desactivando proxy..."
    adb shell settings put global http_proxy :0
    
    # Confirmacion
    updated_proxy=$(adb shell settings get global http_proxy | tr -d '\r\n')
    log_ok "Proxy DESACTIVADO correctamente (valor: $updated_proxy)"
fi
