@echo off
if "%~1"=="" (
    echo [!] Por favor, especifica el script de PowerShell a ejecutar.
    echo Ejemplo: ejecutar_script.bat conmutar_proxy.ps1
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~1"

