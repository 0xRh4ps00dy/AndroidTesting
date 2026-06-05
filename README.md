# Android SSL Pinning Bypass (No-Frida)

Este proyecto proporciona un conjunto de herramientas y scripts automatizados en Bash para realizar el bypass de SSL Pinning en Emuladores de Android (AVDs) que tienen instalada la tienda **Google Play Store** o de desarrollo (**Google APIs**), todo esto **sin necesidad de utilizar Frida**.

El método se basa en inyectar el certificado CA de tu herramienta de interceptación (como Burp Suite o Caido) dentro del almacén de credenciales del sistema (`System Authority`) y configurar el enrutamiento del proxy.

## 📋 Requisitos Previos

Antes de ejecutar los scripts, asegúrate de cumplir con los siguientes requisitos en tu máquina Linux (Host):

1. **Android Studio** instalado junto con el SDK y las herramientas de plataforma (`platform-tools` que incluye `adb` en el PATH).
2. Un emulador Android (AVD) encendido.
3. El AVD debe tener privilegios de root (vía `adb root` nativo en imágenes "Google APIs", o rooteado con Magisk/rootAVD en imágenes de "Google Play").
4. Las dependencias `adb` y `openssl` instaladas en tu sistema host.

---

## 🚀 Uso Rápido (Bypass Directo)

Para configurar el bypass de SSL Pinning de manera directa sin preguntas, ejecuta el siguiente comando:

```bash
bash bypass_ssl_directo.sh --cert ~/Documents/burpsuite.der --type burp --proxy-ip 192.168.1.137 --proxy-port 8080
```

---

## 🛠️ Herramientas Incluidas en la Raíz

El repositorio contiene cuatro herramientas esenciales renombradas para mayor facilidad:

### 1. Asistente Interactivo: `asistente_bypass_ssl.sh`
Un menú interactivo que te guía de manera guiada a verificar dependencias, rootear con Magisk, inyectar el certificado y activar/desactivar el proxy de forma cómoda.

**Ejecución:**
```bash
chmod +x asistente_bypass_ssl.sh
./asistente_bypass_ssl.sh
```

### 2. Bypass Directo: `bypass_ssl_directo.sh`
El script principal por línea de comandos automatizado sin menús visuales.

**Sintaxis:**
```bash
bash bypass_ssl_directo.sh --cert <ruta_al_certificado> --type <burp|caido> [--proxy-ip <ip_host>] [--proxy-port <puerto>]
```

### 3. Conmutador Rápido de Proxy: `conmutar_proxy.sh`
Un script para activar y desactivar con un solo comando la redirección de tráfico al proxy interceptor, ideal para cuando se necesita descargar apps de tiendas que no permiten proxies.

**Ejecución (activa/desactiva alternando):**
```bash
./conmutar_proxy.sh [IP:PUERTO]
# Ejemplo: ./conmutar_proxy.sh
```

### 4. Instalador de Tienda Aurora: `instalar_aurora.sh`
Un script de descarga e instalación rápida para **Aurora Store** en el emulador, útil en imágenes "Google APIs" donde no hay Play Store oficial preinstalada.

---

## 📂 Archivos Secundarios

### `scripts/inyectar_certificado.sh`
Este script secundario se localiza dentro de la carpeta `scripts/` y realiza las modificaciones de namespaces y sistemas de archivos temporales (`tmpfs`) dentro del sistema de archivos interno de Android. Se encarga de sobreescribir de forma transitoria el almacén inmuntable de APEX Conscrypt en Android 10-17.

**Ejecución manual si reinicias el dispositivo:**
```bash
adb root && adb shell sh /storage/self/primary/inyectar_certificado.sh <HASH_DEL_CERTIFICADO>.0
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
