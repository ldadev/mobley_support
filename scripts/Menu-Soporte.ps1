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
    Write-Host '    ⠀⠀⠀⠀⠀⠸⣷⡀⠀⠀⣿⠛⠉⠉⠉⠉⠛⣿⠀⠀⢀⣾⠇⠀⠀⠀⠀⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⠀⠀⠀⠘⢿⣦⡀⣿⣄⠀⣾⣷⠀⣠⣿⣀⣴⡟⠁⠀⠀⠀⠀⠀⠀' -ForegroundColor White
    Write-Host '    ⠀⠀⠀⠀⠀⠀⠀⠀⠙⠻⣿⣿⣿⣿⣿⣿⣿⣿⠟⠁⠀⠀⠀⠀⠀⠀⠀⠀' -ForegroundColor Cyan
    Write-Host '    ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠛⠛⠋⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀' -ForegroundColor Cyan
    Write-Host ''
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
}

while ($true) {
    Clear-Host
    Write-Host ''
    Write-MobleyHeader
    Write-Titulo 'MOBLEY TOOLKIT' -col Cyan
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
            $paramsSplat = $sel.Params
            & $script @paramsSplat
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
        Write-Warn ('"{0}" no es una opcion valida. Ingrese un numero del 1 al 10, o 0 para salir.' -f $opc)
        Write-Pausar
    }
}
