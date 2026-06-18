#!/system/bin/sh
# =============================================================================
# inject_cert_android.sh
# Script a ejecutar DENTRO del AVD como root via "adb shell su -c"
# Inyecta el certificado CA como System Authority en Android (sin Frida)
# Compatible: Android 10-13 (API 29-33) — sin APEX conscrypt/cacerts
#
# Uso (desde el host):
#   adb shell "su -c 'sh /storage/self/primary/inject_cert_android.sh <CERT_HASH>.0'"
# =============================================================================

CERT_FILENAME="$1"

if [ -z "$CERT_FILENAME" ]; then
    echo "[!] Error: debes pasar el nombre del certificado como argumento."
    echo "    Ejemplo: sh inject_cert_android.sh 9a5ba575.0"
    exit 1
fi

CERT_PATH="/storage/self/primary/$CERT_FILENAME"
CACERTS_DIR="/system/etc/security/cacerts"
TMP_COPY="/data/local/tmp/tmp-ca-copy"

if [ ! -f "$CERT_PATH" ]; then
    echo "[!] Error: no se encuentra el certificado en $CERT_PATH"
    echo "    Asegurate de haberlo subido con: adb push $CERT_FILENAME /storage/self/primary/"
    exit 1
fi

echo "[*] Iniciando inyeccion del certificado: $CERT_FILENAME"
echo "[*] Android API: $(getprop ro.build.version.sdk)"

# --------------------------------------------------------------------------- #
# 1. Detectar donde viven los CAs del sistema en ESTE dispositivo
# --------------------------------------------------------------------------- #
# En Android 10-13: /system/etc/security/cacerts (puede estar ya en tmpfs)
# En Android 14+:   /apex/com.android.conscrypt/cacerts  (no es nuestro caso)

APEX_CACERTS="/apex/com.android.conscrypt/cacerts"
USE_APEX=0
if [ -d "$APEX_CACERTS" ] && ls "$APEX_CACERTS"/*.0 >/dev/null 2>&1; then
    USE_APEX=1
    SRC_CACERTS="$APEX_CACERTS"
    echo "[*] Modo APEX: usando $APEX_CACERTS"
else
    SRC_CACERTS="$CACERTS_DIR"
    echo "[*] Modo clasico: usando $CACERTS_DIR"
fi

# --------------------------------------------------------------------------- #
# 2. Crear directorio temporal y copiar CAs existentes
# --------------------------------------------------------------------------- #
mkdir -p "$TMP_COPY"

# Comprobar si ya hay un tmpfs montado en cacerts (re-ejecucion)
if mount | grep -q "tmpfs on $CACERTS_DIR"; then
    echo "[*] tmpfs ya montado en $CACERTS_DIR, recogiendo certs actuales desde ahi..."
    # Si ya habia un mount anterior correcto (con certs del sistema), copiar desde ahi
    CERT_COUNT=$(ls "$CACERTS_DIR" 2>/dev/null | wc -l)
    echo "[-] Certs en cacerts ahora: $CERT_COUNT"
    if [ "$CERT_COUNT" -le 2 ]; then
        # Solo esta nuestro cert (mount anterior roto) — recuperar del APEX/sistema original
        echo "[!] Mount anterior incompleto. Recuperando CAs del sistema desde el APEX versioned..."
        # Intentar recuperar desde el APEX versionado que no esta sobreescrito
        APEX_VERSIONED=$(find /apex -maxdepth 1 -name "com.android.conscrypt@*" -type d | head -1)
        if [ -n "$APEX_VERSIONED" ] && [ -d "$APEX_VERSIONED/cacerts" ]; then
            cp "$APEX_VERSIONED/cacerts"/* "$TMP_COPY/" 2>/dev/null && \
                echo "[+] CAs recuperados desde $APEX_VERSIONED/cacerts" || \
                echo "[!] No se pudo recuperar desde APEX versionado"
        fi
        # Fallback: usar los del sistema (aunque esten en tmpfs roto)
        if [ "$(ls $TMP_COPY 2>/dev/null | wc -l)" -eq 0 ]; then
            echo "[!] Fallback: desmontando tmpfs y copiando desde el sistema real..."
            # Umount temporal para acceder a los originales
            umount "$CACERTS_DIR" 2>/dev/null || true
            cp "$CACERTS_DIR"/* "$TMP_COPY/" 2>/dev/null || true
        fi
    else
        cp "$CACERTS_DIR"/* "$TMP_COPY/" 2>/dev/null || true
        umount "$CACERTS_DIR" 2>/dev/null || true
    fi
else
    # Primera ejecucion — copiar CAs originales del sistema
    if [ "$USE_APEX" -eq 1 ]; then
        cp "$APEX_CACERTS"/* "$TMP_COPY/" || { echo "[!] No se pudo copiar desde APEX"; exit 1; }
    else
        cp "$CACERTS_DIR"/* "$TMP_COPY/" || { echo "[!] No se pudo copiar desde $CACERTS_DIR"; exit 1; }
    fi
    echo "[+] $(ls $TMP_COPY | wc -l) CAs del sistema copiadas al directorio temporal."
fi

# --------------------------------------------------------------------------- #
# 3. Montar tmpfs sobre el directorio de cacerts del sistema
# --------------------------------------------------------------------------- #
if ! mount | grep -q "tmpfs on $CACERTS_DIR"; then
    mount -t tmpfs tmpfs "$CACERTS_DIR" || { echo "[!] No se pudo montar tmpfs en $CACERTS_DIR"; exit 1; }
    echo "[+] tmpfs montado sobre $CACERTS_DIR"
fi

# --------------------------------------------------------------------------- #
# 4. Restaurar CAs originales + añadir nuestro certificado
# --------------------------------------------------------------------------- #
cp "$TMP_COPY"/* "$CACERTS_DIR/" 2>/dev/null || true
cp "$CERT_PATH" "$CACERTS_DIR/$CERT_FILENAME"

# --------------------------------------------------------------------------- #
# 5. Permisos y contexto SELinux correctos
# --------------------------------------------------------------------------- #
chown root:root "$CACERTS_DIR"/*
chmod 644 "$CACERTS_DIR"/*
chcon u:object_r:system_file:s0 "$CACERTS_DIR"/* 2>/dev/null || true

TOTAL=$(ls "$CACERTS_DIR" | wc -l)
echo "[+] $TOTAL certs en $CACERTS_DIR (sistema + el nuestro)."
echo "[*] Permisos actualizados correctamente."

# --------------------------------------------------------------------------- #
# 6. Propagar el mount a los namespaces de Zygote (apps en ejecucion)
#    Solo necesario si los CAs del sistema estan en APEX (Android 14+)
#    En Android 13, el tmpfs sobre /system/etc/security/cacerts is suficiente
#    para apps nuevas; para apps ya en ejecucion usamos nsenter igualmente.
# --------------------------------------------------------------------------- #
MOUNT_SRC="$CACERTS_DIR"
MOUNT_DST="$CACERTS_DIR"

if [ "$USE_APEX" -eq 1 ]; then
    MOUNT_DST="$APEX_CACERTS"
fi

ZYGOTE_PID=$(pidof zygote 2>/dev/null || true)
ZYGOTE64_PID=$(pidof zygote64 2>/dev/null || true)

for Z_PID in $ZYGOTE_PID $ZYGOTE64_PID; do
    if [ -n "$Z_PID" ] && [ -d "/proc/$Z_PID/ns" ]; then
        nsenter --mount="/proc/$Z_PID/ns/mnt" -- \
            /bin/mount --bind "$MOUNT_SRC" "$MOUNT_DST" 2>/dev/null && \
            echo "[*] Cert propagado al namespace de Zygote PID=$Z_PID" || \
            echo "[!] No se pudo propagar a Zygote PID=$Z_PID (puede ser normal en Android 13)"
    fi
done

# Propagar a apps ya en ejecucion
if [ -n "$ZYGOTE_PID" ] || [ -n "$ZYGOTE64_PID" ]; then
    APP_PIDS=$(
        for zpid in $ZYGOTE_PID $ZYGOTE64_PID; do
            ps -o PID -P "$zpid" 2>/dev/null | grep -v PID || true
        done
    )
    for PID in $APP_PIDS; do
        [ -d "/proc/$PID/ns" ] || continue
        nsenter --mount="/proc/$PID/ns/mnt" -- \
            /bin/mount --bind "$MOUNT_SRC" "$MOUNT_DST" 2>/dev/null &
    done
    wait
fi

# --------------------------------------------------------------------------- #
# 7. Limpiar directorio temporal
# --------------------------------------------------------------------------- #
rm -rf "$TMP_COPY"

echo ""
echo "[+] Certificado de sistema inyectado correctamente."
echo "[+] CAs del sistema preservados: OK"
echo "[+] Ya puedes interceptar trafico HTTPS con Burp Suite o Caido."
echo ""
echo "[i] NOTA: Las apps ya abiertas pueden necesitar ser reiniciadas para"
#    que confien en el nuevo certificado.
