#!/usr/bin/env bash

# Script para automatizar la instalación de Split APKs / XAPKs engañando al gestor de paquetes de Android
# para saltarse las restricciones de Play Integrity (error "Get this app from Play").

# Colores para la consola
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

echo -e "${BLUE}=== Instalador Automatizado de XAPK / Split APKs (Bypass Play Integrity) ===${NC}"

# Verificar dependencias
if ! command -v adb &> /dev/null; then
    echo -e "${RED}Error: 'adb' no está instalado o no se encuentra en el PATH.${NC}"
    exit 1
fi

if ! command -v unzip &> /dev/null; then
    echo -e "${RED}Error: 'unzip' no está instalado. Instálalo con: sudo apt install unzip${NC}"
    exit 1
fi

# Verificar dispositivo conectado
device_count=$(adb devices | grep -v "List of devices" | grep -v "^$" | wc -l)
if [ "$device_count" -eq 0 ]; then
    echo -e "${RED}Error: No hay ningún dispositivo o emulador Android conectado a ADB.${NC}"
    echo -e "Asegúrate de iniciar tu emulador antes de ejecutar este script."
    exit 1
elif [ "$device_count" -gt 1 ]; then
    echo -e "${YELLOW}Advertencia: Hay múltiples dispositivos conectados.${NC}"
    # Si hay múltiples dispositivos, adb usará el predeterminado o fallará. Podemos dejar que el usuario use adb normalmente.
fi

# Obtener ruta del archivo XAPK / APKS / ZIP
INPUT_FILE="$1"
if [ -z "$INPUT_FILE" ]; then
    echo -e "${YELLOW}Uso: $0 <ruta_al_archivo.xapk | ruta_al_archivo.apks | ruta_al_archivo.zip>${NC}"
    read -p "Introduce la ruta del archivo a instalar: " INPUT_FILE
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: El archivo '$INPUT_FILE' no existe.${NC}"
    exit 1
fi

# Crear directorio temporal dentro del espacio de trabajo
TMP_DIR=$(mktemp -d -p "$(pwd)" tmp_xapk_extracted_XXXXXX)

# Asegurar limpieza al salir
cleanup() {
    if [ -d "$TMP_DIR" ]; then
        echo -e "${BLUE}Limpiando archivos temporales...${NC}"
        rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

# Descomprimir XAPK/ZIP
echo -e "${BLUE}Descomprimiendo '$INPUT_FILE'...${NC}"
if ! unzip -q "$INPUT_FILE" -d "$TMP_DIR"; then
    echo -e "${RED}Error al descomprimir el archivo. ¿Es un XAPK/ZIP válido?${NC}"
    exit 1
fi

# Obtener ABI del dispositivo Android
echo -e "${BLUE}Detectando arquitectura del emulador/dispositivo...${NC}"
device_abis=$(adb shell getprop ro.product.cpu.abilist | tr ',' ' ' | tr '-' '_')
if [ -z "$device_abis" ]; then
    device_abis=$(adb shell getprop ro.product.cpu.abi | tr '-' '_')
fi
echo -e "ABIs soportadas por el dispositivo: ${GREEN}$device_abis${NC}"

# Filtrar APKs compatibles
APKS_TO_INSTALL=()
BASE_APK_FOUND=false

# Palabras clave de arquitectura para filtrar
ARCH_KEYWORDS=("arm64" "armeabi" "x86" "x86_64" "mips")

for apk_path in "$TMP_DIR"/*.apk; do
    [ -e "$apk_path" ] || continue
    filename=$(basename "$apk_path")
    
    # Comprobar si es un APK de arquitectura (ABI split)
    is_abi_split=false
    matches_device=false
    
    for kw in "${ARCH_KEYWORDS[@]}"; do
        if [[ "$filename" == *"$kw"* ]]; then
            is_abi_split=true
            # Comprobar si el dispositivo soporta esta arquitectura
            # Nota: para evitar falsos positivos como que "x86" coincida con "x86_64",
            # hacemos una comprobación más limpia.
            # Normalizar nombres para la búsqueda:
            normalized_filename=$(echo "$filename" | tr '-' '_')
            for abi in $device_abis; do
                # Si el archivo tiene x86_64, el dispositivo debe tener x86_64
                if [[ "$kw" == "x86_64" && "$normalized_filename" == *"x86_64"* ]]; then
                    if [[ "$device_abis" == *"x86_64"* ]]; then
                        matches_device=true
                    fi
                # Si el archivo tiene arm64 o v8a, el dispositivo debe soportar arm64
                elif [[ "$kw" == "arm64" && "$normalized_filename" == *"arm64"* ]]; then
                    if [[ "$device_abis" == *"arm64"* ]]; then
                        matches_device=true
                    fi
                # Para x86 de 32-bit (evitar conflicto con x86_64)
                elif [[ "$kw" == "x86" && "$normalized_filename" == *"x86"* && "$normalized_filename" != *"x86_64"* ]]; then
                    if [[ "$device_abis" == *"x86"* ]]; then
                        matches_device=true
                    fi
                # Para armeabi
                elif [[ "$kw" == "armeabi" && "$normalized_filename" == *"armeabi"* ]]; then
                    if [[ "$device_abis" == *"armeabi"* ]]; then
                        matches_device=true
                    fi
                fi
            done
            break
        fi
    done
    
    # Decidir si conservar el APK
    if [ "$is_abi_split" = true ]; then
        if [ "$matches_device" = true ]; then
            echo -e "Conservando split de arquitectura compatible: ${GREEN}$filename${NC}"
            APKS_TO_INSTALL+=("$apk_path")
        else
            echo -e "Omitiendo split de arquitectura no compatible: ${YELLOW}$filename${NC}"
        fi
    else
        # Si no es un split de arquitectura, es la base o una config de idioma/densidad. Las incluimos todas.
        if [[ "$filename" != *config* && "$filename" != *split* ]]; then
            BASE_APK_FOUND=true
            echo -e "Base APK detectada: ${GREEN}$filename${NC}"
        else
            echo -e "Conservando split de configuración (idioma/densidad): ${GREEN}$filename${NC}"
        fi
        APKS_TO_INSTALL+=("$apk_path")
    fi
done

if [ ${#APKS_TO_INSTALL[@]} -eq 0 ]; then
    echo -e "${RED}Error: No se encontraron archivos APK en el paquete.${NC}"
    exit 1
fi

if [ "$BASE_APK_FOUND" = false ]; then
    echo -e "${YELLOW}Advertencia: No se ha identificado con seguridad un base APK principal.${NC}"
    echo -e "Se intentará instalar todos los APKs seleccionados de todas formas."
fi

# Intentar extraer el nombre del paquete para desinstalar versiones previas si es necesario
# Intentamos usar aapt si existe, si no, simplemente mostramos advertencia y dejamos que adb haga la sobreescritura o falle
PACKAGE_NAME=""
if command -v aapt &> /dev/null; then
    # Buscar el apk base en la lista
    for apk in "${APKS_TO_INSTALL[@]}"; do
        filename=$(basename "$apk")
        if [[ "$filename" != *config* && "$filename" != *split* ]]; then
            PACKAGE_NAME=$(aapt dump badging "$apk" 2>/dev/null | grep package | awk -F"'" '{print $2}')
            break
        fi
    done
fi

if [ -n "$PACKAGE_NAME" ]; then
    echo -e "${BLUE}Desinstalando versión previa del paquete '${PACKAGE_NAME}' (si existe)...${NC}"
    adb uninstall "$PACKAGE_NAME" &> /dev/null || true
fi

# Proceder con la instalación forzando com.android.vending
echo -e "${BLUE}Ejecutando instalación forzando el origen oficial de Google Play (com.android.vending)...${NC}"
if adb install-multiple -r -i com.android.vending "${APKS_TO_INSTALL[@]}"; then
    echo -e "\n${GREEN}✔ ¡Instalación completada con éxito!${NC}"
    echo -e "La aplicación se ha registrado con el origen oficial de Play Store para evitar bloqueos de integridad."
else
    echo -e "\n${RED}✘ Error al realizar adb install-multiple.${NC}"
    exit 1
fi
