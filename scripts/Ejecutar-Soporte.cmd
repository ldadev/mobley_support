@echo off
setlocal
cd /d "%~dp0"
title Diagnostico y Soporte PC

if not exist "%~dp0Auditar-Trafico.ps1" (
    echo.
    echo  [x] ERROR CRITICO: No se encontro Auditar-Trafico.ps1
    echo.
    pause
    exit /b 1
)

fltmc >nul 2>&1
if errorlevel 1 (
    echo [i] Solicitando elevacion de privilegios de Administrador...
    set "SUPPORT_LAUNCHER=%~f0"
    powershell.exe -NoLogo -NoProfile -Command "Start-Process -FilePath $env:SUPPORT_LAUNCHER -Verb RunAs"
    exit /b
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Menu-Soporte.ps1"

