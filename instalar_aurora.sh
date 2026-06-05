#!/usr/bin/env bash
# =============================================================================
# instalar_aurora.sh
# Descarga e instala Aurora Store en el emulador Android conectado.
# Aurora Store permite descargar apps directamente desde Google Play Store
# sin requerir los servicios de Google ni tener que rootear con Magisk.
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

# 1. Verificar adb
if ! command -v adb &>/dev/null; then
    log_error "No se encontro 'adb' en el sistema."
    log_warn "Por favor, añade Android Platform-Tools a tu PATH."
    exit 1
fi

# 2. Verificar AVD conectado
devices=$(adb devices | grep -v "List of devices" | grep "device$" | wc -l)
if [ "$devices" -eq 0 ]; then
    log_error "No se detecto ningun emulador/dispositivo conectado via adb."
    log_warn "Enciende tu AVD primero e intenta de nuevo."
    exit 1
fi

device_id=$(adb devices | grep -v "List of devices" | grep "device$" | awk '{print $1}' | head -1)
log_ok "Dispositivo conectado detectado: $device_id"

# 3. Descargar APK
APK_URL="https://auroraoss.com/downloads/AuroraStore/Release/AuroraStore-4.6.1.apk"
TMP_APK="/tmp/AuroraStore-4.6.1.apk"

log_info "Descargando Aurora Store desde el servidor oficial..."
log_info "URL: $APK_URL"

if command -v wget &>/dev/null; then
    wget -q --show-progress -O "$TMP_APK" "$APK_URL"
elif command -v curl &>/dev/null; then
    curl -L -o "$TMP_APK" "$APK_URL"
else
    log_error "No se encontro 'wget' ni 'curl' para descargar el archivo."
    exit 1
fi

log_ok "Descarga completada correctamente: $TMP_APK"

# 4. Instalar APK
log_info "Instalando Aurora Store en el emulador ($device_id)..."
if adb install -r "$TMP_APK"; then
    log_ok "¡Aurora Store se ha instalado correctamente!"
    echo -e ""
    echo -e "${GREEN}${BOLD}======================================================================${NC}"
    echo -e "  ✅ INSTALACION COMPLETADA"
    echo -e "  Ahora puedes abrir la app 'Aurora Store' en tu emulador:"
    echo -e "    1. Inicia sesion usando el modo ${BOLD}'Anonimo'${NC} (no requiere tu cuenta)"
    echo -e "    2. Busca y descarga cualquier aplicacion de la Google Play Store"
    echo -e "    3. ¡Listo! Puedes interceptar su trafico HTTPS sin problemas"
    echo -e "${GREEN}${BOLD}======================================================================${NC}"
else
    log_error "Fallo al instalar la aplicacion via adb."
fi

# Limpieza
rm -f "$TMP_APK"
