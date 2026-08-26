@echo off
setlocal
cd /d "%~dp0"
title Diagnostico y soporte del equipo

if not exist "%~dp0Auditar-Trafico.ps1" (
    echo ERROR: No se encontro Auditar-Trafico.ps1 en esta carpeta.
    echo.
    pause
    exit /b 1
)

fltmc >nul 2>&1
if errorlevel 1 (
    echo Solicitando permisos de administrador...
    set "SUPPORT_LAUNCHER=%~f0"
    powershell.exe -NoLogo -NoProfile -Command "Start-Process -FilePath $env:SUPPORT_LAUNCHER -Verb RunAs"
    exit /b
)

echo.
echo ==========================================
echo       DIAGNOSTICO Y SOPORTE DEL EQUIPO
echo ==========================================
echo.
echo 1. Diagnostico rapido
echo 2. Diagnostico completo
echo 3. Auditoria de red
echo 4. Limpieza de temporales
echo.
choice /c 1234 /n /m "Seleccione una opcion [1-4]: "

if errorlevel 4 (
    set "PARAMETROS=-Modo Limpieza"
) else if errorlevel 3 (
    set "PARAMETROS=-Modo Red"
) else if errorlevel 2 (
    set "PARAMETROS=-Modo Completo -IncluirVerificacionSistema"
) else (
    set "PARAMETROS=-Modo Rapido"
)

echo.
echo Ejecutando. No cierre esta ventana...
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { & '%~dp0Auditar-Trafico.ps1' %PARAMETROS% } catch { Write-Host ''; Write-Host 'ERROR DETALLADO:' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red; Write-Host $_.InvocationInfo.PositionMessage; Write-Host $_.ScriptStackTrace; exit 1 }"
set "CODIGO=%ERRORLEVEL%"

echo.
if "%CODIGO%"=="0" (
    echo Proceso finalizado correctamente.
) else (
    echo El proceso termino con el codigo de error %CODIGO%.
    echo Revise el mensaje mostrado arriba.
)
echo.
pause
exit /b %CODIGO%
