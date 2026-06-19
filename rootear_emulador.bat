@echo off
:: Cambia al directorio 'rootAVD' relativo a la ubicación de este script
cd /d "%~dp0rootAVD"

echo [*] Iniciando rootAVD para Android 13 (API 33) con FAKEBOOTIMG...
call rootAVD.bat system-images\android-33\google_apis_playstore\x86_64\ramdisk.img FAKEBOOTIMG

pause
