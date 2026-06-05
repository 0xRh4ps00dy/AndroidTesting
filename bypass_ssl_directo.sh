#!/usr/bin/env bash
# =============================================================================
# bypass_ssl_directo.sh
# Script principal (ejecutar en el HOST Linux)
# Automatiza el bypass de SSL Pinning en AVDs de Play Store sin Frida
# Basado en: https://www.mfumis.com/posts/bypassing-ssl-pinning-on-play-store-avds-without-frida/
#
# PRE-REQUISITOS (manuales antes de ejecutar este script):
#   1. Android Studio instalado con SDK Platform-Tools
#   2. AVD con Google Play Store creado y ENCENDIDO
#   3. AVD rooteado con rootAVD (https://gitlab.com/newbit/rootAVD)
#   4. Magisk configurado correctamente (Cold Boot + reboot)
#   5. adb disponible en PATH
#   6. openssl disponible en PATH
#
# USO:
#   chmod +x bypass_ssl_directo.sh
#   ./bypass_ssl_directo.sh --cert <ruta_al_cert> --type <burp|caido> [--proxy-ip <ip>] [--proxy-port <puerto>]
#
# EJEMPLOS:
#   ./bypass_ssl_directo.sh --cert ~/burp_cacert.der --type burp
#   ./bypass_ssl_directo.sh --cert ~/caido_ca.crt --type caido --proxy-ip 192.168.1.14 --proxy-port 8082
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# Colores
# --------------------------------------------------------------------------- #
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --------------------------------------------------------------------------- #
# Variables por defecto
# --------------------------------------------------------------------------- #
CERT_FILE=""
CERT_TYPE=""          # burp | caido
PROXY_IP=""
PROXY_PORT=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INJECT_SCRIPT="$SCRIPT_DIR/scripts/inyectar_certificado.sh"

# --------------------------------------------------------------------------- #
# Funciones de utilidad
# --------------------------------------------------------------------------- #
log_info()    { echo -e "${BLUE}[*]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[-]${NC} $*"; }
log_section() { echo -e "\n${BOLD}${CYAN}==============================${NC}"; echo -e "${BOLD}${CYAN}  $*${NC}"; echo -e "${BOLD}${CYAN}==============================${NC}"; }

pause_for_user() {
    local msg="${1:-Pulsa ENTER para continuar...}"
    echo -e ""
    echo -e "${YELLOW}${BOLD}  ┌─────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}${BOLD}  │  ⏸  ACCION MANUAL REQUERIDA                 │${NC}"
    echo -e "${YELLOW}${BOLD}  └─────────────────────────────────────────────┘${NC}"
    echo -e "${YELLOW}$msg${NC}"
    echo ""
    read -r -p "  >>> Pulsa ENTER cuando hayas terminado: "
    echo ""
}

usage() {
    echo -e "${BOLD}Uso:${NC}"
    echo "  $0 --cert <ruta_al_cert> --type <burp|caido> [--proxy-ip <ip>] [--proxy-port <puerto>]"
    echo ""
    echo -e "${BOLD}Opciones:${NC}"
    echo "  --cert        Ruta al archivo de certificado CA"
    echo "                  Burp:  archivo .der  (exportado desde Burp > Proxy > Options > CA Certificate)"
    echo "                  Caido: archivo .crt  (exportado desde Caido)"
    echo "  --type        Tipo de proxy: 'burp' o 'caido'"
    echo "  --proxy-ip    IP del proxy para configurar en el AVD (opcional)"
    echo "  --proxy-port  Puerto del proxy (opcional, por defecto 8080)"
    echo ""
    echo -e "${BOLD}Ejemplos:${NC}"
    echo "  $0 --cert ~/burp_cacert.der --type burp"
    echo "  $0 --cert ~/caido_ca.crt --type caido --proxy-ip 192.168.1.14 --proxy-port 8082"
    exit 1
}

check_dependency() {
    if ! command -v "$1" &>/dev/null; then
        log_error "No se encontro '$1'. Por favor, instalalo primero."
        exit 1
    fi
}

check_avd_connected() {
    local devices
    devices=$(adb devices | grep -v "List of devices" | grep "device$" | wc -l)
    if [ "$devices" -eq 0 ]; then
        log_error "No se detecto ningun AVD conectado via adb."
        log_warn "Asegurate de que el AVD esta encendido y ejecuta: adb devices"
        exit 1
    fi
    local device_id
    device_id=$(adb devices | grep -v "List of devices" | grep "device$" | awk '{print $1}' | head -1)
    log_ok "AVD detectado: $device_id"
}

# --------------------------------------------------------------------------- #
# Parsear argumentos
# --------------------------------------------------------------------------- #
parse_args() {
    if [ $# -eq 0 ]; then
        usage
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cert)        CERT_FILE="$2";  shift 2 ;;
            --type)        CERT_TYPE="$2";  shift 2 ;;
            --proxy-ip)    PROXY_IP="$2";   shift 2 ;;
            --proxy-port)  PROXY_PORT="$2"; shift 2 ;;
            -h|--help)     usage ;;
            *)
                log_error "Argumento desconocido: $1"
                usage
                ;;
        esac
    done

    if [ -z "$CERT_FILE" ] || [ -z "$CERT_TYPE" ]; then
        log_error "Faltan argumentos obligatorios: --cert y --type"
        usage
    fi

    if [ ! -f "$CERT_FILE" ]; then
        log_error "El archivo de certificado no existe: $CERT_FILE"
        exit 1
    fi

    if [[ "$CERT_TYPE" != "burp" && "$CERT_TYPE" != "caido" ]]; then
        log_error "El tipo debe ser 'burp' o 'caido', recibido: $CERT_TYPE"
        usage
    fi

    # Puerto por defecto
    if [ -n "$PROXY_IP" ] && [ -z "$PROXY_PORT" ]; then
        PROXY_PORT="8080"
        log_warn "No se especifico puerto de proxy, usando por defecto: $PROXY_PORT"
    fi
}

# --------------------------------------------------------------------------- #
# PASO 5a: Preparar el certificado (generar hash + renombrar)
# --------------------------------------------------------------------------- #
prepare_certificate() {
    log_section "PASO 5a: Preparando el certificado CA"

    local der_file=""

    if [[ "$CERT_TYPE" == "burp" ]]; then
        # Burp exporta directamente en DER
        der_file="$CERT_FILE"
        log_info "Tipo Burp Suite: usando el .der directamente."
    else
        # Caido exporta en PEM (.crt), hay que convertir a DER
        log_info "Tipo Caido: convirtiendo PEM (.crt) a DER (.der)..."
        der_file="${CERT_FILE%.crt}.der"
        openssl x509 -in "$CERT_FILE" -outform DER -out "$der_file"
        log_ok "Certificado convertido a DER: $der_file"
    fi

    # Generar el Android subject hash (formato antiguo)
    log_info "Generando Android subject hash..."
    CERT_HASH=$(openssl x509 -inform DER -subject_hash_old -in "$der_file" | head -1)
    CERT_ANDROID_NAME="${CERT_HASH}.0"

    log_ok "Hash del certificado: $CERT_HASH"
    log_ok "Nombre para Android: $CERT_ANDROID_NAME"

    # Copiar/renombrar el archivo con el nombre correcto
    CERT_PREPARED="/tmp/${CERT_ANDROID_NAME}"
    cp "$der_file" "$CERT_PREPARED"
    log_ok "Certificado preparado en: $CERT_PREPARED"
}

# --------------------------------------------------------------------------- #
# PASO 5b: Subir el certificado y el inject script al AVD
# --------------------------------------------------------------------------- #
push_files_to_avd() {
    log_section "PASO 5b: Subiendo archivos al AVD"

    log_info "Subiendo certificado: $CERT_ANDROID_NAME ..."
    adb push "$CERT_PREPARED" /storage/self/primary/
    log_ok "Certificado subido correctamente."

    log_info "Subiendo script de inyeccion..."
    adb push "$INJECT_SCRIPT" /storage/self/primary/inyectar_certificado.sh
    log_ok "Script de inyeccion subido."
}

# --------------------------------------------------------------------------- #
# PASO 5c: Ejecutar el script de inyeccion como root en el AVD
# --------------------------------------------------------------------------- #
check_magisk_su() {
    # Devuelve 0 si su esta disponible via Magisk, 1 si no
    adb shell "su -c 'id'" 2>&1 | grep -q "uid=0" && return 0 || return 1
}

check_native_root() {
    # Devuelve 0 si el shell de adb ya corre como root (AVD Google APIs)
    adb shell "id" 2>&1 | grep -q "uid=0" && return 0 || return 1
}

run_rootavd_if_needed() {
    local rootavd_dir="$SCRIPT_DIR/rootAVD"

    log_section "PASO previo: Verificando root"

    # Intentar habilitar adb root por si es una imagen Google APIs (no Play Store)
    log_info "Intentando habilitar root nativo (adb root)..."
    adb root >/dev/null 2>&1 || true
    sleep 1

    if check_native_root; then
        log_ok "Root nativo (adb root) activo. Continuando sin necesidad de Magisk/rootAVD."
        return 0
    fi

    if check_magisk_su; then
        log_ok "Magisk su disponible. Continuando..."
        return 0
    fi

    log_warn "Root nativo ni Magisk/su detectados en el AVD."

    # Detectar API y arquitectura para sugerir la ruta del ramdisk.img
    local sdk_ver
    local cpu_abi
    local build_flavor
    sdk_ver=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
    cpu_abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
    build_flavor=$(adb shell getprop ro.build.flavor | tr -d '\r')

    local image_type="google_apis_playstore"
    if [[ "$build_flavor" == *"apis"* && "$build_flavor" != *"playstore"* ]]; then
        image_type="google_apis"
    fi

    # Si es arquitectura de 16KB (Android 15+ AVDs de 16k)
    local page_size
    page_size=$(adb shell getprop ro.boot.hardware.cpu.pagesize | tr -d '\r')
    if [ "$page_size" = "16384" ]; then
        log_warn "¡ATENCION! El AVD detectado utiliza paginas de 16 KB (Android 15/16/17+ 16k)."
        log_warn "Los binarios de rootAVD/Busybox por defecto pueden no funcionar si no estan alineados a 16 KB."
        log_warn "Se recomienda usar una imagen 'Google APIs' en lugar de 'Google Play' para usar root nativo sin Magisk."
    fi

    # Buscar el ramdisk.img de forma dinamica usando comodines (soporta android-37.0 y google_apis_playstore_ps16k)
    local sdk_base="${ANDROID_HOME:-$HOME/Android/Sdk}/system-images"
    local ramdisk_path=""
    # Buscar patrones como: system-images/android-37.0/google_apis_playstore_ps16k/x86_64/ramdisk.img
    # Desactivamos failglob temporalmente si estuviera activo y usamos globbing
    local found_file=""
    for file in "$sdk_base"/android-${sdk_ver}*/${image_type}*/${cpu_abi}/ramdisk.img; do
        if [ -f "$file" ]; then
            found_file="$file"
            break
        fi
    done

    if [ -n "$found_file" ]; then
        # Extraer la ruta relativa desde system-images/ en adelante para pasarsela a rootAVD
        ramdisk_path="system-images/${found_file#$sdk_base/}"
    else
        # Fallback si no se encuentra
        ramdisk_path="system-images/android-${sdk_ver}/${image_type}/${cpu_abi}/ramdisk.img"
    fi

    log_info "Ruta de ramdisk autodetectada para rootAVD: $ramdisk_path"

    if [ ! -f "$rootavd_dir/rootAVD.sh" ]; then
        log_error "No se encontro rootAVD en $rootavd_dir"
        log_error "Clonalo con: git clone https://gitlab.com/newbit/rootAVD.git $rootavd_dir"
        exit 1
    fi

    log_info "Ejecutando rootAVD para parchear el ramdisk con Magisk..."
    log_warn "rootAVD te pedira elegir la version de Magisk. Selecciona [1] (local stable) o la que prefieras."
    echo ""

    ( cd "$rootavd_dir" && bash rootAVD.sh "$ramdisk_path" )

    echo ""
    log_ok "rootAVD completado. El AVD se ha apagado automaticamente."

    pause_for_user "$(cat <<'EOF'
  Ahora debes hacer el COLD BOOT del emulador:

    1. Abre Android Studio → Device Manager
    2. Haz clic en la flecha ▼ junto a tu AVD
    3. Selecciona  "Cold Boot Now"
    4. Espera a que el AVD arranque completamente (puede tardar 1-2 min)
    5. Abre la app  Magisk  en el emulador
    6. Si Magisk pide completar la instalacion → acepta y espera el reboot automatico
    7. Vuelve a esperar que el AVD arranque del todo
EOF
    )"

    log_info "Verificando que root esta disponible ahora..."
    adb wait-for-device
    adb root >/dev/null 2>&1 || true
    sleep 3

    if ! check_native_root && ! check_magisk_su; then
        log_error "Ni root nativo ni Magisk su responden."
        log_warn "Asegurate de haber:"
        echo "    - Hecho Cold Boot (no Reboot normal)"
        echo "    - Abierto Magisk y completado la instalacion adicional si te lo pidio"
        echo "    - Esperado que el AVD arranque completamente"
        echo ""
        pause_for_user "Cuando el dispositivo este listo y rooteado, pulsa ENTER para reintentar."

        if ! check_native_root && ! check_magisk_su; then
            log_error "No se puede continuar sin root. Revisa la instalacion manualmente."
            exit 1
        fi
    fi

    log_ok "Root verificado correctamente."
}

inject_certificate() {
    log_section "PASO 5c: Inyectando certificado como System Authority"

    log_info "Ejecutando inyectar_certificado.sh como root..."
    # Ejecuta usando su si esta disponible; de lo contrario, ejecuta directamente (asumiendo adb root)
    if check_magisk_su; then
        adb shell "su -c 'sh /storage/self/primary/inyectar_certificado.sh $CERT_ANDROID_NAME'"
    else
        adb shell "sh /storage/self/primary/inyectar_certificado.sh $CERT_ANDROID_NAME"
    fi
    log_ok "Certificado instalado como System Authority correctamente."
}

# --------------------------------------------------------------------------- #
# PASO 6: Configurar el proxy en el AVD (opcional)
# --------------------------------------------------------------------------- #
configure_proxy() {
    if [ -z "$PROXY_IP" ]; then
        log_warn "No se especifico proxy (--proxy-ip). Saltando configuracion de proxy."
        log_warn "Para configurarlo manualmente despues, usa:"
        echo "    adb shell settings put global http_proxy <IP>:<PUERTO>"
        echo "    adb shell settings put global http_proxy :0   # para desconectar"
        return
    fi

    log_section "PASO 6: Configurando proxy en el AVD"
    log_info "Configurando proxy: ${PROXY_IP}:${PROXY_PORT}"

    adb shell settings put global http_proxy "${PROXY_IP}:${PROXY_PORT}"
    log_ok "Proxy configurado: ${PROXY_IP}:${PROXY_PORT}"

    local current_proxy
    current_proxy=$(adb shell settings get global http_proxy)
    log_info "Proxy activo en el AVD: $current_proxy"
}

# --------------------------------------------------------------------------- #
# Funcion para desconectar el proxy (modo standalone)
# --------------------------------------------------------------------------- #
disconnect_proxy() {
    log_section "Desconectando proxy del AVD"
    adb shell settings put global http_proxy :0
    log_ok "Proxy desconectado del AVD."
}

# --------------------------------------------------------------------------- #
# MAIN
# --------------------------------------------------------------------------- #
main() {
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║      SSL Pinning Bypass - AVD Play Store Setup       ║"
    echo "  ║   Sin Frida | Basado en mfumis.com/posts/...         ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    parse_args "$@"

    log_section "Verificando dependencias"
    check_dependency "adb"
    check_dependency "openssl"
    log_ok "Todas las dependencias encontradas."

    log_section "Verificando AVD conectado"
    check_avd_connected

    run_rootavd_if_needed
    prepare_certificate
    push_files_to_avd
    inject_certificate
    configure_proxy

    log_section "COMPLETADO"
    echo -e "${GREEN}${BOLD}"
    echo "  ✅ El certificado CA esta instalado como System Authority."
    if [ -n "$PROXY_IP" ]; then
        echo "  ✅ Proxy configurado: ${PROXY_IP}:${PROXY_PORT}"
    fi
    echo ""
    echo "  ⚠️  NOTA: Cada vez que reinicies el AVD, debes volver a"
    echo "     ejecutar la inyeccion del certificado:"
    echo ""
     echo "     adb root && adb shell sh /storage/self/primary/inyectar_certificado.sh ${CERT_ANDROID_NAME}"
    echo -e "${NC}"
}

# --------------------------------------------------------------------------- #
# Modo desconectar proxy (si se pasa 'disconnect' como primer argumento)
# --------------------------------------------------------------------------- #
if [[ "${1:-}" == "disconnect" ]]; then
    check_dependency "adb"
    disconnect_proxy
    exit 0
fi

main "$@"

