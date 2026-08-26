@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title Diagnostico y Soporte de Equipos PC

if not exist "%~dp0Auditar-Trafico.ps1" (
    color 0C
    echo.
    echo  [!] ERROR CRITICO: No se encontro Auditar-Trafico.ps1
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

:MENU
cls
color 0F
echo.
echo  ====================================================================
echo                 SISTEMA DE DIAGNOSTICO Y SOPORTE PC
echo  ====================================================================
echo.
echo   [1] Diagnostico Rapido      (5 min - Estado general, red basica y hardware)
echo   [2] Diagnostico Completo    (Extenso - SMART, parches, DISM/SFC, eventos)
echo   [3] Auditoria de Red        (30 min - Muestreo de conexiones y trafico)
echo   [4] Limpieza de Temporales  (Libera espacio en discos de cache antiguos)
echo   [Q] Salir del Menu
echo.
echo  --------------------------------------------------------------------
echo   (*) Al finalizar, el reporte HTML se abrira automaticamente en el
echo       navegador y los archivos temporales creados en C:\AuditoriaRed
echo       o %%TEMP%% se eliminaran al presionar una tecla para salir.
echo  ====================================================================
echo.

set "OPCION="
set /p "OPCION= Seleccione una opcion [1, 2, 3, 4 o Q]: "

if /i "%OPCION%"=="Q" (
    echo.
    echo Saliendo...
    timeout /t 1 >nul
    exit /b 0
)

if "%OPCION%"=="1" (
    set "PARAMETROS=-Modo Rapido -AutoEliminarAlCerrar"
) else if "%OPCION%"=="2" (
    set "PARAMETROS=-Modo Completo -IncluirVerificacionSistema -AutoEliminarAlCerrar"
) else if "%OPCION%"=="3" (
    set "PARAMETROS=-Modo Red -AutoEliminarAlCerrar"
) else if "%OPCION%"=="4" (
    set "PARAMETROS=-Modo Limpieza -AutoEliminarAlCerrar"
) else (
    echo.
    echo  [!] Opcion no valida. Intente de nuevo.
    timeout /t 2 >nul
    goto MENU
)

echo.
echo ====================================================================
echo  Iniciando proceso. Durante el muestreo puede presionar 'Q' para parar.
echo ====================================================================
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { & '%~dp0Auditar-Trafico.ps1' %PARAMETROS% } catch { Write-Host ''; Write-Host 'ERROR DETALLADO:' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red; Write-Host $_.InvocationInfo.PositionMessage; Write-Host $_.ScriptStackTrace; exit 1 }"
set "CODIGO=%ERRORLEVEL%"

echo.
if "%CODIGO%"=="0" (
    echo [OK] Proceso completado exitosamente.
) else (
    color 0C
    echo [!] El proceso termino with codigo de error %CODIGO%.
    pause
)

goto MENU
