@echo off
:: abre una consola de PowerShell con la política de ejecución omitida para esta sesión
powershell -NoProfile -ExecutionPolicy Bypass -NoExit -Command "Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; Write-Host '==================================================' -ForegroundColor Yellow; Write-Host ' Consola de PowerShell con ExecutionPolicy Bypass' -ForegroundColor Green; Write-Host '==================================================' -ForegroundColor Yellow; Write-Host 'Ahora puedes ejecutar tus scripts .ps1 sin restricciones.' -ForegroundColor Cyan; Write-Host ''"
