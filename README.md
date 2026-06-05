# Android SSL Pinning Bypass (No-Frida)

Este proyecto proporciona un conjunto de herramientas y scripts automatizados en Bash para realizar el bypass de SSL Pinning en Emuladores de Android (AVDs) que tienen instalada la tienda **Google Play Store**, todo esto **sin necesidad de utilizar Frida**.

El método se basa en inyectar el certificado CA de tu herramienta de interceptación (como Burp Suite o Caido) dentro del almacén de credenciales del sistema (`System Authority`) y configurar el enrutamiento del proxy.

## 📋 Requisitos Previos

Antes de ejecutar los scripts, asegúrate de cumplir con los siguientes requisitos en tu máquina Linux (Host):

1. **Android Studio** instalado junto con el SDK y las herramientas de plataforma (`platform-tools` que incluye `adb` en el PATH).
2. Un emulador Android (AVD) con **Google Play Store** creado y encendido.
3. El AVD debe estar rooteado utilizando [rootAVD](https://gitlab.com/newbit/rootAVD).
4. La aplicación **Magisk** debe estar configurada correctamente en el emulador (realizando un Cold Boot y completando su instalación).
5. Las dependencias `adb` y `openssl` instaladas en tu sistema host.

---

## 🚀 Uso Rápido

Para hacer funcionar el proyecto y configurar el bypass de SSL Pinning utilizando **Burp Suite** con la configuración solicitada, ejecuta el siguiente comando:

```bash
bash setup_ssl_bypass.sh --cert ~/Documents/burpsuite.der --type burp --proxy-ip 192.168.1.137 --proxy-port 8080
```

---

## 🛠️ Herramientas Incluidas

### 1. Script Principal: `setup_ssl_bypass.sh`
Automatiza todo el proceso a través de argumentos en la línea de comandos.

**Sintaxis:**
```bash
bash setup_ssl_bypass.sh --cert <ruta_al_certificado> --type <burp|caido> [--proxy-ip <ip_host>] [--proxy-port <puerto>]
```

* **Ejemplo para Burp Suite:**
  ```bash
  bash setup_ssl_bypass.sh --cert ~/Documents/burpsuite.der --type burp --proxy-ip 192.168.1.137 --proxy-port 8080
  ```
* **Ejemplo para Caido:**
  ```bash
  bash setup_ssl_bypass.sh --cert ~/ca.crt --type caido --proxy-ip 192.168.1.137 --proxy-port 8080
  ```

---

### 2. Wizard Interactivo: `ssl_bypass_wizard.sh`
Un asistente guiado paso a paso en la terminal que te ayuda a:
* Verificar que tienes todas las dependencias instaladas.
* Descargar y configurar `rootAVD`.
* Guiarte en la configuración de Magisk.
* Importar e inyectar el certificado.
* Configurar o desconectar el proxy del AVD de manera interactiva.

**Ejecución:**
```bash
chmod +x ssl_bypass_wizard.sh
./ssl_bypass_wizard.sh
```

---

### 3. Script de Inyección Interno: `inject_cert_android.sh`
Este script es subido automáticamente al dispositivo por los scripts anteriores. Realiza la magia a nivel de sistema de archivos en Android para montar temporalmente el almacén de certificados del sistema (`/apex/com.android.conscrypt/cacerts` y `/system/etc/security/cacerts`) y forzar la persistencia del certificado inyectado durante la sesión actual del emulador.

---

## ⚠️ Nota Importante sobre el Reinicio del AVD

Debido a la forma en que funciona la seguridad y los puntos de montaje en versiones modernas de Android:
* Cada vez que reinicies por completo el AVD, deberás volver a ejecutar el script de inyección de certificados en el dispositivo.
* Puedes hacerlo ejecutando nuevamente el comando principal o bien usando:
  ```bash
  adb root && adb shell sh /storage/self/primary/inject_cert_android.sh <HASH_DEL_CERTIFICADO>.0
  ```

---

## 🛑 Desactivar el Proxy en el AVD

Cuando termines tus pruebas y desees retirar la configuración de proxy del emulador para que vuelva a navegar con normalidad por internet, ejecuta:

```bash
bash setup_ssl_bypass.sh disconnect
```
o mediante comandos adb directos:
```bash
adb shell settings put global http_proxy :0
```
