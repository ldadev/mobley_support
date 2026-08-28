#requires -Version 5.1

[CmdletBinding()]
param()

$script = Join-Path $PSScriptRoot 'Auditar-Trafico.ps1'
if (-not (Test-Path -LiteralPath $script)) { $script = '.\Auditar-Trafico.ps1' }

function Write-Linea([string]$c = '-', [string]$col = 'Cyan') {
    Write-Host ($c * 68) -ForegroundColor $col
}

function Write-Titulo([string]$txt, [string]$col = 'Cyan') {
    Write-Linea -c '-' -col $col
    $pad = [Math]::Max(0, [Math]::Floor((68 - $txt.Length) / 2))
    Write-Host ((' ' * $pad) + $txt) -ForegroundColor $col
    Write-Linea -c '-' -col $col
}

function Write-MobleyHeader {
    Write-Host '        ⠀⠀⠀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⠀⠀⠀⠀⠀⠀' -ForegroundColor Cyan
    Write-Host '    ⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀' -ForegroundColor Cyan
    Write-Host '    ⠀⠀⠀⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡇⠀⠀⠀⠀⠀' -ForegroundColor Cyan
    Write-Host '    ⠀⠀⠀⠀⠀⢸⡿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⠿⢿⣧⠀⠀⠀⠀⠀' -ForegroundColor Cyan
    Write-Host '    ⢀⣀⣀⣀⣀⣸⣇⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣀⣸⣿⣀⣀⣀⣀⠀' -ForegroundColor White
    Write-Host '    ⠸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠇' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⠉⢙⣿⡿⠿⠿⠿⠿⠿⢿⣿⣿⣿⠿⠿⠿⠿⠿⢿⣿⣛⠉⠁⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⣰⡟⠉⢰⣶⣶⣶⣶⣶⣶⡶⢶⣶⣶⣶⣶⣶⣶⡆⠉⠻⣧⠀⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⢻⣧⡀⠈⣿⣿⣿⣿⣿⡿⠁⠈⢿⣿⣿⣿⣿⣿⠁⠀⣠⡿⠀⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⠀⠙⣿⡆⠈⠉⠉⠉⠉⠀⠀⠀⠀⠉⠉⠉⠉⠁⢰⣿⠋⠀⠀⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⠀⠀⣿⡇⠀⠀⠀⣠⣶⣶⣶⣶⣶⣶⣄⠀⠀⠀⢸⣿⠀⠀⠀⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⠀⠀⠸⣷⡀⠀⠀⣿⠛⠉⠉⠉⠉⠛⣿⠀⠀⢀⾾⠇⠀⠀⠀⠀⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⠀⠀⠀⠘⢿⣦⡀⣿⣄⠀⾾⣷⠀⣠⣿⣀⣴⡟⠁⠀⠀⠀⠀⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⠀⠀⠀⠀⠀⠙⠻⣿⣿⣿⣿⣿⣿⣿⣿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀' -ForegroundColor Cyan
    Write-Host '    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠛⠛⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀' -ForegroundColor Cyan
}

function Write-Info([string]$txt) {
    Write-Host '  i  ' -NoNewline -ForegroundColor Cyan
    Write-Host $txt -ForegroundColor White
}

function Write-Ok([string]$txt) {
    Write-Host '  OK ' -NoNewline -ForegroundColor Green
    Write-Host $txt -ForegroundColor White
}

function Write-Warn([string]$txt) {
    Write-Host '  !  ' -NoNewline -ForegroundColor Yellow
    Write-Host $txt -ForegroundColor White
}

function Write-ErrorMsg([string]$txt) {
    Write-Host '  X  ' -NoNewline -ForegroundColor Red
    Write-Host $txt -ForegroundColor White
}

function Test-Pregunta([string]$txt) {
    Write-Host '  ?  ' -NoNewline -ForegroundColor Cyan
    $resp = Read-Host "$txt (s/n)"
    return ($resp.Trim().ToLower() -eq 's')
}

function Write-Pausar {
    Write-Host "`n  Presione Enter para continuar..." -ForegroundColor Gray
    [void](Read-Host)
}

function Start-CleanupDownloadedToolkit {
    $directorioToolkit = Split-Path -Parent $PSCommandPath
    $directorioDescargado = Join-Path $env:LOCALAPPDATA 'SoportePC'
    if ($directorioToolkit.TrimEnd('\') -ine $directorioDescargado.TrimEnd('\')) {
        return
    }

    $rutaLiteral = $directorioToolkit.Replace("'", "''")
    $comandoLimpieza = "Start-Sleep -Seconds 2; Remove-Item -LiteralPath '$rutaLiteral' -Recurse -Force -ErrorAction SilentlyContinue"
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        $comandoLimpieza
    ) | Out-Null
}

function Install-OfficeToolkit {
    $directorioRaiz = Split-Path -Parent $PSScriptRoot
    $instalador = Join-Path $directorioRaiz 'office\setup.exe'
    $configuracion = Join-Path $directorioRaiz 'office\configuration-Office-x64.xml'

    if (-not (Test-Path -LiteralPath $instalador) -or -not (Test-Path -LiteralPath $configuracion)) {
        throw 'No se encontraron office\setup.exe y office\configuration-Office-x64.xml. Use la copia completa del toolkit.'
    }

    Write-Info 'Iniciando instalacion de Office con la configuracion incluida...'
    $proceso = Start-Process -FilePath $instalador -WorkingDirectory (Split-Path -Parent $instalador) -ArgumentList @('/configure', $configuracion) -Wait -PassThru
    if ($proceso.ExitCode -ne 0) {
        throw "El instalador de Office termino con codigo $($proceso.ExitCode)."
    }
    Write-Ok 'Instalacion de Office finalizada correctamente.'
}

$opciones = [ordered]@{
    '1' = @{ Icon = '[R]'; Label = 'Diagnostico Rapido'; Desc = '(5 min - Estado general, red basica y hardware)'; Params = @{ Modo = 'Rapido'; AutoEliminarAlCerrar = $true } }
    '2' = @{ Icon = '[C]'; Label = 'Diagnostico Completo'; Desc = '(Extenso - SMART, parches, DISM/SFC, eventos)'; Params = @{ Modo = 'Completo'; IncluirVerificacionSistema = $true; AutoEliminarAlCerrar = $true } }
    '3' = @{ Icon = '[N]'; Label = 'Auditoria de Red'; Desc = '(30 min - Muestreo de conexiones y trafico TCP/ETL)'; Params = @{ Modo = 'Red'; AutoEliminarAlCerrar = $true } }
    '4' = @{ Icon = '[L]'; Label = 'Limpieza de Temporales'; Desc = '(Libera espacio en discos de cache antiguos)'; Params = @{ Modo = 'Limpieza'; AutoEliminarAlCerrar = $true } }
    '5' = @{ Icon = '[P]'; Label = 'Liberar Cola Impresion'; Desc = '(Solo: cancela trabajos atascados y reinicia Spooler)'; Params = @{ LimpiarColaImpresion = $true; AutoEliminarAlCerrar = $true } }
    '6' = @{ Icon = '[O]'; Label = 'Optimizacion Rapida'; Desc = '(Papelera, cache DNS/iconos y limpieza de WinSxS)'; Params = @{ OptimizarSistema = $true; AutoEliminarAlCerrar = $true } }
    '7' = @{ Icon = '[U]'; Label = 'Actualizar Windows'; Desc = '(Busca, instala y puede reiniciar el equipo)'; Params = @{ ActualizarWindows = $true; AutoEliminarAlCerrar = $true } }
    '8' = @{ Icon = '[D]'; Label = 'Desfragmentar Discos'; Desc = '(Optimiza las unidades fijas detectadas)'; Params = @{ DesfragmentarDiscos = $true; AutoEliminarAlCerrar = $true } }
    '9' = @{ Icon = '[L]'; Label = 'Licencias'; Desc = '(Consulta activacion oficial de Windows y Microsoft)'; Params = @{ MostrarLicencias = $true; AutoEliminarAlCerrar = $true } }
    '10' = @{ Icon = '[B]'; Label = 'Comparar Auditoria'; Desc = '(Compara red, puertos, servicios y DNS con otra auditoria)'; Params = $null }
    '11' = @{ Icon = '[F]'; Label = 'Instalar Office'; Desc = '(Usa el instalador incluido en la carpeta office)'; Params = $null }
}

while ($true) {
    Clear-Host
    Write-Host ''
    Write-MobleyHeader
    Write-Titulo 'DIAGNOSTICO Y SOPORTE PC' -col Cyan
    Write-Host ''

    $colNum = 'Cyan'
    $colIcon = 'White'
    $colLabel = 'White'
    $colDesc = 'Gray'

    foreach ($k in $opciones.Keys) {
        $item = $opciones[$k]
        Write-Host ('  {0}.  ' -f $k) -NoNewline -ForegroundColor $colNum
        Write-Host ('{0}  ' -f $item.Icon) -NoNewline -ForegroundColor $colIcon
        Write-Host ('{0,-24}' -f $item.Label) -NoNewline -ForegroundColor $colLabel
        Write-Host $item.Desc -ForegroundColor $colDesc
    }

    Write-Host ''
    Write-Linea -c '-' -col DarkCyan
    Write-Host '   0.  ' -NoNewline -ForegroundColor $colNum
    Write-Host 'Salir del Menu' -ForegroundColor $colLabel
    Write-Linea -c '-' -col DarkCyan
    Write-Host ''
    Write-Info 'Al finalizar, el informe HTML se abrira automaticamente en su navegador.'
    Write-Info 'Los archivos de evidencias creados se eliminaran al presionar una tecla.'
    Write-Host ''

    Write-Host '  Seleccione una opcion: ' -NoNewline -ForegroundColor Cyan
    $opc = (Read-Host).Trim()

    if ($opc -eq '0' -or $opc.ToLower() -eq 'q') {
        Write-Host ''
        Write-Info 'Cerrando sesion de soporte... Hasta luego.'
        Start-CleanupDownloadedToolkit
        Start-Sleep -Seconds 1
        break
    }

    if ($opciones.Contains($opc)) {
        $sel = $opciones[$opc]

        if ($opc -eq '10') {
            $carpetaSalida = 'C:\AuditoriaRed'
            $auditorias = @(Get-ChildItem -LiteralPath $carpetaSalida -Directory -Filter 'Auditoria-*' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending)
            if ($auditorias.Count -eq 0) {
                Write-Warn 'No hay auditorias anteriores disponibles en C:\AuditoriaRed.'
                Write-Pausar
                continue
            }
            Write-Host ''
            Write-Info 'Seleccione la auditoria anterior:'
            for ($indiceAuditoria = 0; $indiceAuditoria -lt $auditorias.Count; $indiceAuditoria++) {
                Write-Host ('  {0}. {1} ({2})' -f ($indiceAuditoria + 1), $auditorias[$indiceAuditoria].Name, $auditorias[$indiceAuditoria].LastWriteTime)
            }
            $seleccionAuditoria = 0
            if (-not [int]::TryParse((Read-Host 'Numero de auditoria'), [ref]$seleccionAuditoria) -or
                $seleccionAuditoria -lt 1 -or $seleccionAuditoria -gt $auditorias.Count) {
                Write-Warn 'Seleccion no valida.'
                Write-Pausar
                continue
            }
            $sel.Params = @{ Modo = 'Red'; AuditoriaAnterior = $auditorias[$seleccionAuditoria - 1].FullName; AutoEliminarAlCerrar = $true }
        }

        Write-Host ''
        Write-Linea -c '.' -col DarkCyan
        Write-Info ('Va a ejecutar: {0}' -f $sel.Label)
        Write-Linea -c '.' -col DarkCyan
        Write-Host ''

        if (-not (Test-Pregunta 'Confirma?')) {
            Write-Warn 'Operacion cancelada, volviendo al menu.'
            Write-Pausar
            continue
        }

        Clear-Host
        Write-Titulo ('EJECUTANDO: {0}' -f $sel.Label.ToUpper()) -col Yellow
        Write-Host ''

        try {
            if ($opc -eq '11') {
                Install-OfficeToolkit
            }
            else {
                $paramsSplat = $sel.Params
                & $script @paramsSplat
                Write-Host ''
                Write-Ok 'Proceso completado exitosamente.'
            }
        }
        catch {
            Write-Host ''
            Write-ErrorMsg ('Error al ejecutar: {0}' -f $_.Exception.Message)
            if ($_.Exception.InnerException) {
                Write-Host ('  Detalle interno: {0}' -f $_.Exception.InnerException.Message) -ForegroundColor Yellow
            }
            if ($_.InvocationInfo.ScriptLineNumber) {
                $archivoError = if ($_.InvocationInfo.ScriptName) { $_.InvocationInfo.ScriptName } else { $script }
                Write-Host ('  Archivo: {0}' -f $archivoError) -ForegroundColor Yellow
                Write-Host ('  Línea: {0} | Comando: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) -ForegroundColor Yellow
            }
            if ($_.ScriptStackTrace) {
                Write-Host ('  Pila: {0}' -f $_.ScriptStackTrace) -ForegroundColor DarkYellow
            }
        }

        Write-Pausar
    }
    else {
        Write-Host ''
        Write-Warn ('"{0}" no es una opcion valida. Ingrese un numero del 1 al 11, o 0 para salir.' -f $opc)
        Write-Pausar
    }
}
