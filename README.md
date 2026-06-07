# Android SSL Pinning Bypass (No-Frida & Frida Option)

Este proyecto proporciona un conjunto de herramientas y scripts automatizados en Bash para realizar el bypass de SSL Pinning en Emuladores de Android (AVDs) que tienen instalada la tienda **Google Play Store** o de desarrollo (**Google APIs**).

Ofrece dos métodos de funcionamiento:
1. **Método Sin Frida (Defectuoso en Apps Grandes):** Inyección del certificado a nivel de sistema (`System Authority`). Excelente para la mayoría de las apps (ej: Marca).
2. **Método Con Frida (Recomendado para Apps Complejas):** Modificación en tiempo de ejecución de las llamadas SSL. Indispensable para apps con SSL Pinning estricto *hardcoded* (ej: YouTube, Facebook).

## 📋 Requisitos Previos

Antes de ejecutar los scripts, asegúrate de cumplir con los siguientes requisitos en tu máquina Linux (Host):

1. **Android Studio** instalado junto con el SDK y las herramientas de plataforma (`platform-tools` que incluye `adb` en el PATH).
2. Un emulador Android (AVD) encendido.
3. El AVD debe tener privilegios de root (vía `adb root` nativo en imágenes "Google APIs", o rooteado con Magisk/rootAVD en imágenes de "Google Play").
4. Las dependencias `adb`, `openssl` y `xz-utils` instaladas en tu sistema host.
5. Para el método con Frida: tener instalado `frida-tools` (`pip install frida-tools`).

---

## 🚀 Método 1: Bypass Sin Frida (Certificado del Sistema)

Para configurar el bypass de SSL Pinning tradicional e inyectar el certificado CA en el almacén de credenciales del emulador, ejecuta:

```bash
bash bypass_ssl_directo.sh --cert ~/Documents/burpsuite.der --type burp --proxy-ip 192.168.1.137 --proxy-port 8080
```

---

## 🚀 Método 2: Bypass Con Frida (Para YouTube, Facebook, etc.)

Para saltar las comprobaciones de SSL Pinning avanzadas en memoria ejecutando automáticamente `frida-server` en el emulador y lanzando el script interceptor:

```bash
./iniciar_frida_bypass.sh [nombre_del_paquete_app]
# Ejemplo para YouTube:
./iniciar_frida_bypass.sh com.google.android.youtube
```

*Este script detectará la arquitectura del dispositivo, descargará automáticamente la versión de `frida-server` coincidente con tu host, la subirá, la iniciará como root en background y ejecutará el hooking.*

---

## 🛠️ Herramientas Incluidas en la Raíz

El repositorio contiene las siguientes herramientas:

* **`asistente_bypass_ssl.sh`:** Asistente interactivo guiado por menús en la terminal.
* **`bypass_ssl_directo.sh`:** Script principal por argumentos en línea de comandos.
* **`conmutar_proxy.sh`:** Activa y desactiva con un solo comando la redirección de tráfico al proxy interceptor.
* **`instalar_aurora.sh`:** Instala de forma rápida **Aurora Store** (tienda alternativa para descargar apps de Google Play).
* **`instalar_xapk.sh`:** Automatiza la descompresión e instalación de paquetes múltiples (`.xapk`, `.apks`, `.zip`) forzando la procedencia desde Google Play (`com.android.vending`) y filtrando los splits de arquitectura de CPU no compatibles con el emulador.
* **`iniciar_frida_bypass.sh`:** Automatiza el arranque de Frida y la inyección en caliente de `bypass-ssl.js`.
* **`bypass-ssl.js`:** Script JavaScript universal de hooking para Frida (intercepta OkHttp3, WebView, TrustManager, etc.).

---

## 📂 Archivos Secundarios

### `scripts/inyectar_certificado.sh`
Este script secundario se localiza dentro de la carpeta `scripts/` y realiza las modificaciones de namespaces y sistemas de archivos temporales (`tmpfs`) dentro del sistema de archivos interno de Android. Se encarga de sobreescribir de forma transitoria el almacén inmuntable de APEX Conscrypt en Android 10-17.

**Ejecución manual si reinicias el dispositivo:**

* Si usas una imagen **Google APIs** (con root nativo):
  ```bash
  adb root && adb shell sh /storage/self/primary/inyectar_certificado.sh <HASH_DEL_CERTIFICADO>.0
  ```
* Si usas una imagen **Google Play Store** (rooteada con Magisk):
  ```bash
  adb shell "su -c 'sh /storage/self/primary/inyectar_certificado.sh <HASH_DEL_CERTIFICADO>.0'"
  ```

---

## 🛑 Desactivar el Proxy en el AVD

Cuando termines tus pruebas y desees retirar la configuración de proxy del emulador para navegar con normalidad por internet:

```bash
bash bypass_ssl_directo.sh disconnect
```
O bien:
```bash
./conmutar_proxy.sh
```
También con comandos adb directos:
```bash
adb shell settings put global http_proxy :0
```
