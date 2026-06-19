# Inyección de Certificado CA (HTTP Toolkit) en Android 13+

Este documento explica paso a paso cómo inyectar el certificado CA de **HTTP Toolkit** (o cualquier otro proxy de interceptación como Burp Suite o Caido) en un emulador de Android con API 33 (Android 13) o superior de manera persistente y mediante línea de comandos.

---

## Prerrequisitos

1. **Emulador Rooteado**: El emulador debe haber sido rooteado previamente. Puedes usar el script del repositorio:
   ```bash
   rootear_emulador.bat
   ```
2. **OpenSSL**: Necesario para obtener el hash del certificado. En Windows, puedes utilizar el OpenSSL integrado con Git en la ruta por defecto:
   `C:\Program Files\Git\usr\bin\openssl.exe`
3. **Dispositivo conectado**: Asegúrate de que el emulador esté visible ejecutando:
   ```bash
   adb devices
   ```

---

## Guía Paso a Paso

### 1. Obtener el certificado de HTTP Toolkit
Cuando HTTP Toolkit intenta interceptar el emulador, suele colocar su certificado en la carpeta de descargas del dispositivo. Puedes extraerlo a tu máquina usando:
```cmd
adb pull "/sdcard/Download/HTTP Toolkit Certificate.crt" ./http_toolkit.crt
```

### 2. Calcular el Hash del Certificado
Android requiere que los certificados de sistema estén nombrados según el hash de su sujeto con la extensión `.0`. Para calcularlo y prepararlo:

```cmd
# 1. Calcular el hash del sujeto (usualmente da algo como 0db75fbd)
"C:\Program Files\Git\usr\bin\openssl.exe" x509 -inform DER -subject_hash_old -in http_toolkit.crt

# 2. Convertir el certificado DER a formato PEM con el nombre correcto (<HASH>.0)
"C:\Program Files\Git\usr\bin\openssl.exe" x509 -inform DER -in http_toolkit.crt -out 0db75fbd.0
```

*Nota: Reemplaza `0db75fbd` por el hash obtenido en el comando anterior si este fuera diferente.*

### 3. Subir el Certificado y el Script al Emulador
Envía el certificado renombrado y el script de inyección al almacenamiento del dispositivo:

```cmd
adb push 0db75fbd.0 /sdcard/
adb push inyectar_certificado.sh /sdcard/
```

### 4. Ejecutar la Inyección
Ejecuta el script con privilegios de root (`su`):

```cmd
adb shell "su -c 'sh /sdcard/inyectar_certificado.sh 0db75fbd.0'"
```

---

## ¿Qué hace el script `inyectar_certificado.sh`?

1. **Crea un sistema de archivos en memoria (tmpfs)** sobre el directorio de certificados del sistema (`/system/etc/security/cacerts`). Esto evita tener que remontar la partición `/system` como escritura (lo cual está bloqueado en Android moderno).
2. **Copia los certificados legítimos de Android** al nuevo `tmpfs` para mantener la estabilidad del sistema.
3. **Copia el certificado de HTTP Toolkit** en el mismo directorio con el nombre correcto del hash.
4. **Ajusta permisos, propietarios y contextos de SELinux** (`chmod 644`, `chcon`).
5. **Propaga el montaje a los namespaces de Zygote** y de las aplicaciones que ya están en ejecución para que confíen de inmediato en el nuevo certificado sin necesidad de reiniciar el emulador.
