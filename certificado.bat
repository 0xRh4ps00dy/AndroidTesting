@echo off
echo [*] Re-inyectando certificado CA en el AVD...
adb shell "su -c 'sh /storage/self/primary/inyectar_certificado.sh 9a5ba575.0'"

echo [*] Re-configurando proxy a 192.168.1.137:8080...
adb shell settings put global http_proxy 192.168.1.137:8080

echo [+] Listo. Abre la app en el emulador para verificar la interceptacion.
pause
