#!/usr/bin/env bash
# =============================================================================
# asistente_bypass_ssl.sh — Wizard interactivo para bypass de SSL Pinning en AVDs
# Basado en: https://www.mfumis.com/posts/bypassing-ssl-pinning-on-play-store-avds-without-frida/
# Uso: chmod +x asistente_bypass_ssl.sh && ./asistente_bypass_ssl.sh
# =============================================================================

set -euo pipefail

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ── Estado global ─────────────────────────────────────────────────────────────
CERT_FILE=""; CERT_TYPE=""; CERT_HASH=""; CERT_ANDROID_NAME=""
PROXY_IP=""; PROXY_PORT="8080"
AVD_API="33"; AVD_ARCH="x86_64"
ROOTAVD_DIR=""; ANDROID_SDK=""

# ── Helpers ───────────────────────────────────────────────────────────────────
clear_screen() { clear; }

banner() {
    clear_screen
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════════════════════════════╗"
    echo "  ║     📲 SSL Pinning Bypass Wizard — Play Store AVDs           ║"
    echo "  ║        Sin Frida | Magisk | Burp Suite / Caido               ║"
    echo "  ╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

step_header() {
    local num="$1" title="$2"
    echo -e "\n${BOLD}${MAGENTA}┌─────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${MAGENTA}│  PASO $num: $title${NC}"
    echo -e "${BOLD}${MAGENTA}└─────────────────────────────────────────────────┘${NC}\n"
}

info()    { echo -e "  ${BLUE}[*]${NC} $*"; }
ok()      { echo -e "  ${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $*"; }
error()   { echo -e "  ${RED}[✘]${NC} $*"; }
cmd_hint(){ echo -e "  ${DIM}$ $*${NC}"; }
tip()     { echo -e "  ${CYAN}[→]${NC} $*"; }

separator() { echo -e "\n  ${DIM}─────────────────────────────────────────────────${NC}\n"; }

press_enter() {
    echo ""
    echo -e "  ${BOLD}${GREEN}Pulsa [ENTER] para continuar...${NC}"
    read -r
}

confirm() {
    local prompt="$1"
    local response
    echo -e "\n  ${BOLD}${YELLOW}$prompt [s/N]:${NC} \c"
    read -r response
    [[ "$response" =~ ^[sS]$ ]]
}

ask() {
    local prompt="$1" var_name="$2" default="${3:-}"
    if [ -n "$default" ]; then
        echo -e "\n  ${BOLD}$prompt${NC} ${DIM}[por defecto: $default]${NC}: \c"
    else
        echo -e "\n  ${BOLD}$prompt${NC}: \c"
    fi
    read -r "$var_name"
    if [ -z "${!var_name}" ] && [ -n "$default" ]; then
        eval "$var_name=\"$default\""
    fi
}

wait_for_step() {
    local msg="${1:-¿Completaste este paso?}"
    echo ""
    while ! confirm "$msg"; do
        warn "Completa el paso antes de continuar."
    done
}

check_cmd() {
    if command -v "$1" &>/dev/null; then
        ok "$1 encontrado: $(command -v "$1")"
        return 0
    else
        error "$1 NO encontrado."
        return 1
    fi
}

run_cmd() {
    info "Ejecutando: $*"
    echo ""
    if "$@"; then
        ok "Comando completado."
    else
        error "El comando falló (código: $?)."
        warn "Revisa el error antes de continuar."
    fi
}

# =============================================================================
# PASO 0 — Bienvenida y resumen
# =============================================================================
step_0_welcome() {
    banner
    echo -e "  ${BOLD}Bienvenido al wizard interactivo para bypassear SSL Pinning${NC}"
    echo -e "  en emuladores Android con Google Play Store — sin Frida.\n"
    echo -e "  ${BOLD}Este wizard te guiará por estos pasos:${NC}\n"
    echo -e "    ${CYAN}1.${NC} Verificar dependencias (Android Studio, SDK Tools, Git)"
    echo -e "    ${CYAN}2.${NC} Clonar rootAVD"
    echo -e "    ${CYAN}3.${NC} Crear AVD con Play Store"
    echo -e "    ${CYAN}4.${NC} Rootear el AVD con Magisk"
    echo -e "    ${CYAN}5.${NC} Instalar certificado CA como System Authority"
    echo -e "    ${CYAN}6.${NC} Configurar proxy (Burp / Caido)"
    separator
    warn "Este script es para fines de pentesting legítimo y educativo."
    warn "Úsalo solo con permisos explícitos del propietario de la app."
    separator
    press_enter
}

# =============================================================================
# PASO 1 — Verificar / instalar dependencias
# =============================================================================
step_1_dependencies() {
    banner
    step_header "1" "Verificar Dependencias"

    info "Comprobando herramientas necesarias...\n"

    local all_ok=true

    # adb
    if ! check_cmd "adb"; then
        all_ok=false
        tip "Instala el SDK Platform-Tools desde Android Studio:"
        tip "  Settings → Languages & Frameworks → Android SDK → SDK Tools"
        tip "  Luego añade al PATH en ~/.bashrc o ~/.zshrc:"
        cmd_hint 'export ANDROID_HOME="$HOME/Android/Sdk"'
        cmd_hint 'export PATH="$PATH:$ANDROID_HOME/platform-tools"'
    fi

    # openssl
    if ! check_cmd "openssl"; then
        all_ok=false
        tip "Instala openssl:"
        cmd_hint "sudo apt install -y openssl"
    fi

    # git
    if ! check_cmd "git"; then
        all_ok=false
        tip "Instala git:"
        cmd_hint "sudo apt install -y git"
    fi

    separator

    if $all_ok; then
        ok "Todas las dependencias están disponibles."
    else
        warn "Faltan algunas dependencias. Instálalas y vuelve a ejecutar el wizard."
        if confirm "¿Quieres intentar instalar git y openssl ahora (apt)?"; then
            sudo apt install -y git openssl
        fi
    fi

    # Detectar ANDROID_HOME
    if [ -n "${ANDROID_HOME:-}" ]; then
        ok "ANDROID_HOME detectado: $ANDROID_HOME"
        ANDROID_SDK="$ANDROID_HOME"
    elif [ -d "$HOME/Android/Sdk" ]; then
        ANDROID_SDK="$HOME/Android/Sdk"
        ok "SDK detectado en: $ANDROID_SDK"
    else
        warn "No se detectó ANDROID_HOME automáticamente."
        ask "Ruta de tu Android SDK" ANDROID_SDK "$HOME/Android/Sdk"
    fi

    press_enter
}

# =============================================================================
# PASO 2 — Clonar rootAVD
# =============================================================================
step_2_rootavd() {
    banner
    step_header "2" "Descargar rootAVD"

    info "rootAVD es el script que rootea tu AVD e instala Magisk."
    tip  "Repositorio: https://gitlab.com/newbit/rootAVD\n"

    ask "¿Dónde quieres clonar rootAVD?" ROOTAVD_DIR "$HOME/rootAVD"

    if [ -d "$ROOTAVD_DIR/.git" ]; then
        ok "rootAVD ya existe en $ROOTAVD_DIR"
        if confirm "¿Actualizar el repositorio (git pull)?"; then
            git -C "$ROOTAVD_DIR" pull
        fi
    else
        info "Clonando rootAVD en $ROOTAVD_DIR ..."
        run_cmd git clone https://gitlab.com/newbit/rootAVD.git "$ROOTAVD_DIR"
    fi

    ok "rootAVD disponible en: $ROOTAVD_DIR"
    press_enter
}

# =============================================================================
# PASO 3 — Crear AVD con Play Store
# =============================================================================
step_3_create_avd() {
    banner
    step_header "3" "Crear AVD con Play Store"

    info "Necesitas crear un AVD con Google Play Store desde Android Studio.\n"
    echo -e "  ${BOLD}Instrucciones:${NC}\n"
    echo -e "  ${CYAN}1.${NC} Abre ${BOLD}Android Studio${NC}"
    echo -e "  ${CYAN}2.${NC} Ve a ${BOLD}Virtual Device Manager${NC} (icono de teléfono en la barra lateral)"
    echo -e "  ${CYAN}3.${NC} Haz clic en ${BOLD}\"Create Device\"${NC}"
    echo -e "  ${CYAN}4.${NC} Selecciona ${BOLD}\"Medium Phone\"${NC} (o cualquier modelo)"
    echo -e "  ${CYAN}5.${NC} En la pantalla de imagen del sistema, elige una imagen que tenga"
    echo -e "       el icono ${BOLD}▶ Play Store${NC} (ej: API 33 - Google Play - x86_64)"
    echo -e "  ${CYAN}6.${NC} Completa la creación y ${BOLD}enciende el AVD${NC}"
    separator

    ask "API level del AVD que creaste" AVD_API "33"
    ask "Arquitectura del AVD (x86_64 / arm64-v8a)" AVD_ARCH "x86_64"

    separator
    info "Listando AVDs disponibles en rootAVD para verificar..."

    local ramdisk_path="system-images/android-${AVD_API}/google_apis_playstore/${AVD_ARCH}/ramdisk.img"

    if [ -f "${ANDROID_SDK}/${ramdisk_path}" ]; then
        ok "Ramdisk encontrado: ${ramdisk_path}"
    else
        warn "No se encontró el ramdisk en: ${ANDROID_SDK}/${ramdisk_path}"
        warn "Asegúrate de haber instalado la imagen del sistema en Android Studio."
        tip "Settings → Android SDK → SDK Platforms → descarga la API $AVD_API con Play Store"
    fi

    separator
    info "Comandos de rootAVD para listar AVDs:"
    cmd_hint "cd $ROOTAVD_DIR"
    cmd_hint "./rootAVD.sh ListAllAVDs"

    if confirm "¿Quieres ejecutar 'ListAllAVDs' ahora para verificar?"; then
        if [ -f "$ROOTAVD_DIR/rootAVD.sh" ]; then
            cd "$ROOTAVD_DIR"
            bash rootAVD.sh ListAllAVDs || true
            cd - > /dev/null
        else
            error "No se encontró rootAVD.sh en $ROOTAVD_DIR"
        fi
    fi

    wait_for_step "¿El AVD con Play Store está creado y encendido?"
    press_enter
}

# =============================================================================
# PASO 4 — Rootear el AVD con rootAVD + Magisk
# =============================================================================
step_4_root_avd() {
    banner
    step_header "4" "Rootear el AVD con rootAVD + Magisk"

    local ramdisk_rel="system-images/android-${AVD_API}/google_apis_playstore/${AVD_ARCH}/ramdisk.img"
    local ramdisk_full="${ANDROID_SDK}/${ramdisk_rel}"

    info "Ruta del ramdisk que se usará:"
    echo -e "\n  ${BOLD}$ramdisk_full${NC}\n"

    if [ ! -f "$ramdisk_full" ]; then
        warn "El ramdisk no existe en esa ruta."
        ask "Introduce la ruta completa al ramdisk.img de tu AVD" ramdisk_full ""
    fi

    separator
    echo -e "  ${BOLD}Instrucciones para rootear:${NC}\n"
    echo -e "  ${CYAN}1.${NC} El AVD debe estar ${BOLD}encendido${NC} en este momento."
    echo -e "  ${CYAN}2.${NC} Ejecutaremos rootAVD con tu ramdisk."
    echo -e "  ${CYAN}3.${NC} El AVD se ${BOLD}apagará automáticamente${NC} al finalizar."
    echo -e "  ${CYAN}4.${NC} Tras apagarse, haz un ${BOLD}Cold Boot${NC} en Android Studio:"
    echo -e "       Click derecho en el AVD → ${BOLD}Cold Boot Now${NC}"
    echo -e "  ${CYAN}5.${NC} Abre la app ${BOLD}Magisk${NC} en el AVD y acepta el reboot."
    separator

    wait_for_step "¿El AVD está encendido y listo?"

    info "Ejecutando rootAVD..."
    cmd_hint "cd $ROOTAVD_DIR && bash rootAVD.sh \"$ramdisk_full\""
    echo ""

    if confirm "¿Ejecutar rootAVD ahora?"; then
        cd "$ROOTAVD_DIR"
        bash rootAVD.sh "$ramdisk_full" || warn "rootAVD terminó con errores. Revisa la salida."
        cd - > /dev/null
    else
        warn "Ejecútalo manualmente:"
        cmd_hint "cd $ROOTAVD_DIR"
        cmd_hint "bash rootAVD.sh \"$ramdisk_full\""
    fi

    separator
    echo -e "  ${BOLD}Ahora debes:${NC}\n"
    echo -e "  ${CYAN}1.${NC} Hacer ${BOLD}Cold Boot${NC} del AVD en Android Studio"
    echo -e "  ${CYAN}2.${NC} Abrir la app ${BOLD}Magisk${NC} y completar el setup (reboot)"
    echo -e "  ${CYAN}3.${NC} Verificar root con:"
    cmd_hint "adb shell"
    cmd_hint "su"
    cmd_hint "whoami   # debe mostrar: root"

    separator
    if confirm "¿Quieres verificar el acceso root ahora?"; then
        info "Intentando verificar root en el AVD..."
        echo ""
        local result
        result=$(adb shell su -c whoami 2>/dev/null || echo "error")
        if [ "$result" = "root" ]; then
            ok "¡Root verificado! El AVD está correctamente rooteado."
        else
            warn "No se pudo verificar root automáticamente."
            warn "Asegúrate de aceptar el prompt de Magisk en el AVD."
            tip "Resultado obtenido: $result"
        fi
    fi

    wait_for_step "¿El AVD tiene root y Magisk configurado?"
    press_enter
}

# =============================================================================
# PASO 5 — Preparar e instalar el certificado CA
# =============================================================================
step_5_install_cert() {
    banner
    step_header "5" "Instalar Certificado CA como System Authority"

    # 5a — Elegir tipo de proxy
    echo -e "  ${BOLD}¿Qué proxy interceptor usas?${NC}\n"
    echo -e "  ${CYAN}1)${NC} Burp Suite  ${DIM}(exporta .der)${NC}"
    echo -e "  ${CYAN}2)${NC} Caido       ${DIM}(exporta .crt PEM)${NC}"
    echo ""

    local choice
    while true; do
        echo -e "  Elige [1/2]: \c"
        read -r choice
        case "$choice" in
            1) CERT_TYPE="burp";  break ;;
            2) CERT_TYPE="caido"; break ;;
            *) warn "Elige 1 o 2." ;;
        esac
    done

    separator

    # 5b — Instrucciones para exportar el cert
    if [ "$CERT_TYPE" = "burp" ]; then
        echo -e "  ${BOLD}Exportar certificado desde Burp Suite:${NC}\n"
        echo -e "  ${CYAN}1.${NC} Abre Burp Suite"
        echo -e "  ${CYAN}2.${NC} Ve a ${BOLD}Proxy → Options → CA Certificate${NC}"
        echo -e "  ${CYAN}3.${NC} Exporta como ${BOLD}\"Certificate in DER format\"${NC}"
        echo -e "  ${CYAN}4.${NC} Guárdalo como ${BOLD}cacert.der${NC}"
    else
        echo -e "  ${BOLD}Exportar certificado desde Caido:${NC}\n"
        echo -e "  ${CYAN}1.${NC} Abre Caido en el navegador"
        echo -e "  ${CYAN}2.${NC} Ve a ${BOLD}Settings → Proxy → Export CA Certificate${NC}"
        echo -e "  ${CYAN}3.${NC} Descarga el ${BOLD}.crt${NC} (formato PEM)"
    fi

    separator
    wait_for_step "¿Ya exportaste el certificado?"

    # 5c — Ruta al cert
    local default_cert
    if [ "$CERT_TYPE" = "burp" ]; then
        default_cert="$HOME/cacert.der"
    else
        default_cert="$HOME/ca.crt"
    fi

    while true; do
        ask "Ruta completa al archivo del certificado" CERT_FILE "$default_cert"
        if [ -f "$CERT_FILE" ]; then
            ok "Certificado encontrado: $CERT_FILE"
            break
        else
            error "Archivo no encontrado: $CERT_FILE"
        fi
    done

    separator
    info "Procesando certificado..."

    # 5d — Convertir si es necesario y obtener hash
    local der_file
    if [ "$CERT_TYPE" = "caido" ]; then
        der_file="${CERT_FILE%.crt}.der"
        info "Convirtiendo PEM → DER..."
        run_cmd openssl x509 -in "$CERT_FILE" -outform DER -out "$der_file"
    else
        der_file="$CERT_FILE"
    fi

    info "Generando Android subject hash..."
    CERT_HASH=$(openssl x509 -inform DER -subject_hash_old -in "$der_file" | head -1)
    CERT_ANDROID_NAME="${CERT_HASH}.0"

    local cert_final="/tmp/${CERT_ANDROID_NAME}"
    cp "$der_file" "$cert_final"

    ok "Hash del certificado: ${BOLD}$CERT_HASH${NC}"
    ok "Nombre para Android:  ${BOLD}$CERT_ANDROID_NAME${NC}"

    separator
    info "Subiendo certificado al AVD..."
    run_cmd adb push "$cert_final" /storage/self/primary/

    separator
    info "Subiendo script de inyección al AVD..."
    local inject_script
    inject_script="$(dirname "$(realpath "$0")")/scripts/inyectar_certificado.sh"

    if [ ! -f "$inject_script" ]; then
        warn "No se encontró inyectar_certificado.sh en la carpeta scripts/."
        warn "Generando el script de inyección en /tmp/inyectar_certificado.sh..."
        _write_inject_script "/tmp/inyectar_certificado.sh"
        inject_script="/tmp/inyectar_certificado.sh"
    fi

    run_cmd adb push "$inject_script" /storage/self/primary/inyectar_certificado.sh

    separator
    info "Ejecutando inyección del certificado como root en el AVD..."
    warn "Si aparece un popup de Magisk en el AVD, acepta el acceso root."
    echo ""
    press_enter

    run_cmd adb shell su -c "sh /storage/self/primary/inyectar_certificado.sh $CERT_ANDROID_NAME"

    separator
    ok "¡Certificado instalado como System Authority!"
    warn "Recuerda: debes repetir la inyección cada vez que reinicies el AVD."

    press_enter
}

# =============================================================================
# PASO 6 — Configurar proxy en el AVD
# =============================================================================
step_6_proxy() {
    banner
    step_header "6" "Configurar Proxy en el AVD"

    echo -e "  ${BOLD}Obtén la IP de tu máquina host:${NC}\n"
    cmd_hint "ip addr show | grep 'inet ' | grep -v 127.0.0.1"
    echo ""

    local detected_ip
    detected_ip=$(ip addr show 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d/ -f1 | head -1 || echo "")

    if [ -n "$detected_ip" ]; then
        info "IP detectada automáticamente: ${BOLD}$detected_ip${NC}"
    fi

    ask "IP de tu máquina (donde corre Burp/Caido)" PROXY_IP "${detected_ip:-192.168.1.x}"
    ask "Puerto del proxy" PROXY_PORT "8080"

    separator
    echo -e "  ${BOLD}Asegúrate de que Burp/Caido está configurado para:${NC}\n"
    echo -e "  ${CYAN}→${NC} Escuchar en ${BOLD}All Interfaces${NC} (0.0.0.0) o en tu IP local"
    echo -e "  ${CYAN}→${NC} Puerto: ${BOLD}$PROXY_PORT${NC}"
    separator

    if confirm "¿Configurar el proxy en el AVD ahora?"; then
        run_cmd adb shell settings put global http_proxy "${PROXY_IP}:${PROXY_PORT}"

        local current
        current=$(adb shell settings get global http_proxy 2>/dev/null || echo "?")
        ok "Proxy activo en el AVD: ${BOLD}$current${NC}"
    fi

    separator
    echo -e "  ${DIM}Para desconectar el proxy cuando termines:${NC}"
    cmd_hint "adb shell settings put global http_proxy :0"

    press_enter
}

# =============================================================================
# Script de inyección inline (por si no existe el archivo separado)
# =============================================================================
_write_inject_script() {
    local path="$1"
    cat > "$path" << 'INJECT_EOF'
#!/system/bin/sh
CERT_FILENAME="$1"
if [ -z "$CERT_FILENAME" ]; then echo "[!] Uso: inyectar_certificado.sh <hash>.0"; exit 1; fi
CERT_PATH="/storage/self/primary/$CERT_FILENAME"
if [ ! -f "$CERT_PATH" ]; then echo "[!] Cert no encontrado: $CERT_PATH"; exit 1; fi
echo "[*] Inyectando certificado: $CERT_FILENAME"
mkdir -p -m 700 /data/local/tmp/tmp-ca-copy
cp /apex/com.android.conscrypt/cacerts/* /data/local/tmp/tmp-ca-copy/
mount -t tmpfs tmpfs /system/etc/security/cacerts
mv /data/local/tmp/tmp-ca-copy/* /system/etc/security/cacerts/
cp "$CERT_PATH" /system/etc/security/cacerts/
chown root:root /system/etc/security/cacerts/*
chmod 644 /system/etc/security/cacerts/*
chcon u:object_r:system_file:s0 /system/etc/security/cacerts/*
ZYGOTE_PID=$(pidof zygote || true)
ZYGOTE64_PID=$(pidof zygote64 || true)
for Z_PID in "$ZYGOTE_PID" "$ZYGOTE64_PID"; do
    if [ -n "$Z_PID" ]; then
        nsenter --mount=/proc/$Z_PID/ns/mnt -- /bin/mount --bind /system/etc/security/cacerts /apex/com.android.conscrypt/cacerts
    fi
done
APP_PIDS=$(echo "$ZYGOTE_PID $ZYGOTE64_PID" | xargs -n1 ps -o 'PID' -P | grep -v PID)
for PID in $APP_PIDS; do
    nsenter --mount=/proc/$PID/ns/mnt -- /bin/mount --bind /system/etc/security/cacerts /apex/com.android.conscrypt/cacerts &
done
wait
echo "[+] Certificado de sistema inyectado correctamente."
INJECT_EOF
    chmod +x "$path"
}

# =============================================================================
# RESUMEN FINAL
# =============================================================================
step_final_summary() {
    banner
    step_header "✔" "¡Setup completado!"

    echo -e "  ${BOLD}${GREEN}Resumen de lo configurado:${NC}\n"
    echo -e "  ${CYAN}•${NC} Proxy interceptor: ${BOLD}$(echo "$CERT_TYPE" | tr '[:lower:]' '[:upper:]')${NC}"
    echo -e "  ${CYAN}•${NC} Certificado CA:    ${BOLD}$CERT_ANDROID_NAME${NC}"
    if [ -n "$PROXY_IP" ]; then
        echo -e "  ${CYAN}•${NC} Proxy en AVD:      ${BOLD}${PROXY_IP}:${PROXY_PORT}${NC}"
    fi
    separator
    echo -e "  ${BOLD}Flujo en cada sesión de pentest:${NC}\n"
    echo -e "  ${CYAN}1.${NC} Enciende el AVD"
    echo -e "  ${CYAN}2.${NC} Inyecta el certificado:"
    cmd_hint "adb shell su -c \"sh /storage/self/primary/inyectar_certificado.sh $CERT_ANDROID_NAME\""
    echo -e "  ${CYAN}3.${NC} Configura el proxy (si no persiste):"
    cmd_hint "adb shell settings put global http_proxy ${PROXY_IP:-<IP>}:${PROXY_PORT}"
    echo -e "  ${CYAN}4.${NC} ¡Intercepta tráfico con Burp/Caido!"
    echo -e "  ${CYAN}5.${NC} Al terminar, desconecta el proxy:"
    cmd_hint "adb shell settings put global http_proxy :0"
    separator
    echo -e "  ${DIM}Puedes volver a ejecutar este wizard cuando necesites:${NC}"
    cmd_hint "./asistente_bypass_ssl.sh"
    echo ""
    echo -e "  ${BOLD}${GREEN}Happy Hacking! 🔓${NC}\n"
}

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================
main_menu() {
    banner
    echo -e "  ${BOLD}¿Qué quieres hacer?${NC}\n"
    echo -e "  ${CYAN}1)${NC} Ejecutar wizard completo (todos los pasos)"
    echo -e "  ${CYAN}2)${NC} Solo inyectar certificado  ${DIM}(AVD ya rooteado)${NC}"
    echo -e "  ${CYAN}3)${NC} Solo configurar proxy"
    echo -e "  ${CYAN}4)${NC} Desconectar proxy del AVD"
    echo -e "  ${CYAN}5)${NC} Salir"
    echo ""

    local choice
    while true; do
        echo -e "  Elige [1-5]: \c"
        read -r choice
        case "$choice" in
            1) break ;;
            2)
                step_1_dependencies
                step_5_install_cert
                step_final_summary
                exit 0
                ;;
            3)
                step_1_dependencies
                step_6_proxy
                exit 0
                ;;
            4)
                info "Desconectando proxy..."
                adb shell settings put global http_proxy :0 && ok "Proxy desconectado."
                exit 0
                ;;
            5) echo ""; exit 0 ;;
            *) warn "Elige entre 1 y 5." ;;
        esac
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================
main() {
    main_menu

    step_0_welcome
    step_1_dependencies
    step_2_rootavd
    step_3_create_avd
    step_4_root_avd
    step_5_install_cert
    step_6_proxy
    step_final_summary
}

main
