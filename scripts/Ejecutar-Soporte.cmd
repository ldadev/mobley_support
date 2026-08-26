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

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "& {
    $script = Join-Path $PSScriptRoot 'Auditar-Trafico.ps1'
    if (-not (Test-Path -LiteralPath $script)) { $script = '.\Auditar-Trafico.ps1' }

    function Write-Linea([string]$c='─', [System.ConsoleColor]$col=[System.ConsoleColor]::Cyan) {
        Write-Host ($c * 68) -ForegroundColor $col
    }

    function Write-Titulo([string]$txt, [System.ConsoleColor]$col=[System.ConsoleColor]::Cyan) {
        Write-Linea -c '─' -col $col
        $pad = [Math]::Max(0, [Math]::Floor((68 - $txt.Length) / 2))
        Write-Host ((' ' * $pad) + $txt) -ForegroundColor $col
        Write-Linea -c '─' -col $col
    }

    function Write-Info([string]$txt) {
        Write-Host '  ℹ  ' -NoNewline -ForegroundColor Cyan
        Write-Host $txt -ForegroundColor White
    }

    function Write-Ok([string]$txt) {
        Write-Host '  ✔  ' -NoNewline -ForegroundColor Green
        Write-Host $txt -ForegroundColor White
    }

    function Write-Warn([string]$txt) {
        Write-Host '  ⚠  ' -NoNewline -ForegroundColor Yellow
        Write-Host $txt -ForegroundColor White
    }

    function Write-ErrorMsg([string]$txt) {
        Write-Host '  ✖  ' -NoNewline -ForegroundColor Red
        Write-Host $txt -ForegroundColor White
    }

    function Test-Pregunta([string]$txt) {
        Write-Host '  ?  ' -NoNewline -ForegroundColor Cyan
        $resp = Read-Host "$txt (s/n)"
        return ($resp.Trim().ToLower() -eq 's')
    }

    function Write-Pausar {
        Write-Host "`n  Presione Enter para continuar..." -ForegroundColor Gray
        [void][System.Console]::ReadLine()
    }

    $opciones = [ordered]@{
        '1' = @{ Icon = '⚡'; Label = 'Diagnóstico Rápido'; Desc = '(5 min - Estado general, red básica y hardware)'; Params = '-Modo Rapido -AutoEliminarAlCerrar' }
        '2' = @{ Icon = '🔍'; Label = 'Diagnóstico Completo'; Desc = '(Extenso - SMART, parches, DISM/SFC, eventos)'; Params = '-Modo Completo -IncluirVerificacionSistema -AutoEliminarAlCerrar' }
        '3' = @{ Icon = '🌐'; Label = 'Auditoría de Red'; Desc = '(30 min - Muestreo de conexiones y tráfico TCP/ETL)'; Params = '-Modo Red -AutoEliminarAlCerrar' }
        '4' = @{ Icon = '🧹'; Label = 'Limpieza de Temporales'; Desc = '(Libera espacio en discos de caché antiguos)'; Params = '-Modo Limpieza -AutoEliminarAlCerrar' }
        '5' = @{ Icon = '🖨️ '; Label = 'Liberar Cola Impresión'; Desc = '(Cancela trabajos atascados y reinicia Spooler)'; Params = '-Modo Rapido -LimpiarColaImpresion -AutoEliminarAlCerrar' }
    }

    while ($true) {
        Clear-Host
        Write-Host ''
        Write-Titulo 'SISTEMA DE DIAGNOSTICO Y SOPORTE PC' -col Cyan
        Write-Host ''

        $colNum   = 'Cyan'
        $colIcon  = 'White'
        $colLabel = 'White'
        $colDesc  = 'Gray'

        foreach ($k in $opciones.Keys) {
            $item = $opciones[$k]
            Write-Host ('  {0:>2}.  ' -f $k) -NoNewline -ForegroundColor $colNum
            Write-Host ('{0}  ' -f $item.Icon) -NoNewline -ForegroundColor $colIcon
            Write-Host ('{0,-24}' -f $item.Label) -NoNewline -ForegroundColor $colLabel
            Write-Host $item.Desc -ForegroundColor $colDesc
        }

        Write-Host ''
        Write-Linea -c '─' -col DarkCyan
        Write-Host '   0.  ' -NoNewline -ForegroundColor $colNum
        Write-Host '🚪  Salir del Menú' -ForegroundColor $colLabel
        Write-Linea -c '─' -col DarkCyan
        Write-Host ''
        Write-Info 'Al finalizar, el informe HTML se abrirá automáticamente en su navegador.'
        Write-Info 'Los archivos de evidencias creados se eliminarán al presionar una tecla.'
        Write-Host ''

        Write-Host '  Seleccione una opción: ' -NoNewline -ForegroundColor Cyan
        $opc = (Read-Host).Trim()

        if ($opc -eq '0' -or $opc.ToLower() -eq 'q') {
            Write-Host ''
            Write-Info 'Cerrando sesión de soporte... ¡Hasta luego! 👋'
            Start-Sleep -Seconds 1
            break
        }

        if ($opciones.Contains($opc)) {
            $sel = $opciones[$opc]
            Write-Host ''
            Write-Linea -c '·' -col DarkCyan
            Write-Info ('Va a ejecutar: {0}' -f $sel.Label)
            Write-Linea -c '·' -col DarkCyan
            Write-Host ''

            if (-not (Test-Pregunta '¿Confirma?')) {
                Write-Warn 'Operación cancelada — volviendo al menú.'
                Write-Pausar
                continue
            }

            Clear-Host
            Write-Titulo ('EJECUTANDO: {0}' -f $sel.Label.ToUpper()) -col Yellow
            Write-Host ''

            try {
                $pList = $sel.Params -split ' '
                & $script @pList
                Write-Host ''
                Write-Ok 'Proceso completado exitosamente.'
            }
            catch {
                Write-Host ''
                Write-ErrorMsg ('Error al ejecutar: {0}' -f $_.Exception.Message)
            }

            Write-Pausar
        }
        else {
            Write-Host ''
            Write-Warn ('"{0}" no es una opción válida. Ingrese un número del 1 al 5, o 0 para salir.' -f $opc)
            Write-Pausar
        }
    }
}"
