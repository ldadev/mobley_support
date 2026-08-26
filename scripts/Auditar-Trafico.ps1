#requires -Version 5.1
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [ValidateSet('Rapido', 'Completo', 'Red', 'Limpieza')]
    [string]$Modo = 'Completo',

    [ValidateRange(1, 1440)]
    [int]$DuracionMinutos = 30,

    [ValidateRange(1, 300)]
    [int]$IntervaloSegundos = 5,

    [ValidateRange(10, 100000)]
    [int]$UmbralDestinosUnicos = 100,

    [ValidateRange(10, 100000)]
    [int]$UmbralConexionesConcurrentes = 200,

    [ValidateRange(5, 100000)]
    [int]$UmbralSynPendientes = 30,

    [ValidateRange(64, 65535)]
    [int]$BytesPorPaquete = 128,

    [ValidateRange(1, 3650)]
    [int]$DiasTemporalAntiguo = 30,

    [ValidateRange(1, 365)]
    [int]$DiasEventos = 7,

    [ValidateRange(1, 3650)]
    [int]$DiasAvisoCertificado = 60,

    [string]$DirectorioSalida = '',

    [switch]$SinCapturaPktmon,

    [switch]$IncluirVerificacionSistema,

    [switch]$EliminarTemporales,

    [switch]$LimpiarColaImpresion,

    [switch]$AutoEliminarAlCerrar,

    [switch]$NoAutoAbrirReporte
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($Modo -eq 'Rapido' -and -not $PSBoundParameters.ContainsKey('DuracionMinutos')) {
    $DuracionMinutos = 5
}
if ($Modo -eq 'Limpieza') {
    $EliminarTemporales = $true
    $SinCapturaPktmon = $true
}

function Test-Administrador {
    $identidad = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identidad)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IPPublica {
    param([Parameter(Mandatory)][string]$Direccion)

    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Direccion, [ref]$ip)) {
        return $false
    }

    if ($ip.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
        $bytes = $ip.GetAddressBytes()
        return -not (
            $bytes[0] -eq 10 -or
            $bytes[0] -eq 127 -or
            ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or
            ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
            ($bytes[0] -ge 224)
        )
    }

    return -not (
        $ip.Equals([Net.IPAddress]::IPv6Loopback) -or
        $ip.IsIPv6LinkLocal -or
        $ip.IsIPv6Multicast -or
        (($ip.GetAddressBytes()[0] -band 0xFE) -eq 0xFC)
    )
}

function Convertir-FragmentoHtml {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Datos,
        [Parameter(Mandatory)][string]$Titulo,
        [string]$Vacio = 'Sin datos.'
    )

    if ($Datos.Count -eq 0) {
        return "<h2>$Titulo</h2><p>$Vacio</p>"
    }
    return ($Datos | ConvertTo-Html -Fragment -PreContent "<h2>$Titulo</h2>")
}

function Get-ResumenDirectorio {
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][int]$DiasAntiguo
    )

    $cantidad = 0L
    $bytes = 0L
    $cantidadAntiguos = 0L
    $bytesAntiguos = 0L
    $erroresLectura = @()
    $limite = (Get-Date).AddDays(-$DiasAntiguo)

    if (-not (Test-Path -LiteralPath $Ruta)) {
        return [pscustomobject]@{
            Ruta             = $Ruta
            Existe           = $false
            Archivos         = 0
            TamanoMB         = 0
            ArchivosAntiguos = 0
            AntiguosMB       = 0
            ErroresAcceso    = 0
        }
    }

    Get-ChildItem -LiteralPath $Ruta -File -Force -Recurse -ErrorAction SilentlyContinue `
        -ErrorVariable erroresLectura | ForEach-Object {
        $cantidad++
        $bytes += $_.Length
        if ($_.LastWriteTime -lt $limite) {
            $cantidadAntiguos++
            $bytesAntiguos += $_.Length
        }
    }

    return [pscustomobject]@{
        Ruta             = $Ruta
        Existe           = $true
        Archivos         = $cantidad
        TamanoMB         = [Math]::Round($bytes / 1MB, 2)
        ArchivosAntiguos = $cantidadAntiguos
        AntiguosMB       = [Math]::Round($bytesAntiguos / 1MB, 2)
        ErroresAcceso    = @($erroresLectura).Count
    }
}

function Remove-ArchivosTemporalesAntiguos {
    param(
        [Parameter(Mandatory)][string]$Ruta,
        [Parameter(Mandatory)][int]$DiasAntiguo
    )

    $eliminados = 0L
    $bytesLiberados = 0L
    $fallidos = 0L
    $limite = (Get-Date).AddDays(-$DiasAntiguo)

    if (-not (Test-Path -LiteralPath $Ruta -PathType Container)) {
        return [pscustomobject]@{
            Ruta        = $Ruta
            Eliminados  = 0
            LiberadosMB = 0
            Fallidos    = 0
            Limite      = $limite
        }
    }

    $raiz = [IO.Path]::GetFullPath((Get-Item -LiteralPath $Ruta).FullName)
    $separador = [IO.Path]::DirectorySeparatorChar
    $prefijoRaiz = $raiz.TrimEnd($separador) + $separador
    $pendientes = New-Object 'System.Collections.Generic.Stack[string]'
    $pendientes.Push($raiz)

    while ($pendientes.Count -gt 0) {
        $directorio = $pendientes.Pop()
        $elementos = @(Get-ChildItem -LiteralPath $directorio -Force -ErrorAction SilentlyContinue)
        foreach ($elemento in $elementos) {
            if (($elemento.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }
            if ($elemento.PSIsContainer) {
                $pendientes.Push($elemento.FullName)
                continue
            }
            if ($elemento.LastWriteTime -ge $limite) {
                continue
            }

            $archivo = [IO.Path]::GetFullPath($elemento.FullName)
            if (-not $archivo.StartsWith($prefijoRaiz, [StringComparison]::OrdinalIgnoreCase)) {
                $fallidos++
                continue
            }

            $tamano = $elemento.Length
            try {
                Remove-Item -LiteralPath $archivo -Force -ErrorAction Stop
                $eliminados++
                $bytesLiberados += $tamano
            }
            catch {
                $fallidos++
            }
        }
    }

    return [pscustomobject]@{
        Ruta        = $Ruta
        Eliminados  = $eliminados
        LiberadosMB = [Math]::Round($bytesLiberados / 1MB, 2)
        Fallidos    = $fallidos
        Limite      = $limite
    }
}

function Finalizar-InformeYLimpiar {
    param(
        [Parameter(Mandatory)][string]$RutaInforme,
        [Parameter(Mandatory)][string]$CarpetaAuditoria,
        [bool]$AutoEliminar = $false,
        [bool]$AbrirReporte = $true
    )

    if ($AbrirReporte -and (Test-Path -LiteralPath $RutaInforme)) {
        try {
            Start-Process -FilePath $RutaInforme -ErrorAction SilentlyContinue
        }
        catch {}
    }

    if ($AutoEliminar) {
        Write-Host ''
        Write-Titulo 'INFORME Y DIAGNOSTICO FINALIZADOS' -Color Yellow
        Write-Info 'El informe HTML se ha abierto en su navegador web:'
        Write-Host "     -> $RutaInforme" -ForegroundColor Green
        Write-Host ''
        Write-Warn 'NOTA: Los archivos de evidencias e informe son TEMPORALES.'
        Write-Warn 'Permaneceran disponibles MIENTRAS esta ventana continue abierta.'
        Write-Host ''
        Write-Linea -Caracter '-' -Color Cyan
        Write-Host '  >>> PRESIONE ENTER (O CUALQUIER TECLA) PARA SALIR Y ELIMINAR' -ForegroundColor Cyan
        Write-Host '      TODOS LOS ARCHIVOS TEMPORALES DE DIAGNOSTICO DE ESTE EQUIPO...' -ForegroundColor Cyan
        Write-Linea -Caracter '-' -Color Cyan
        Write-Host ''

        try {
            $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        }
        catch {
            Read-Host '  Presione Enter para salir y eliminar temporales'
        }

        Write-Warn 'Eliminando archivos temporales de auditoria...'
        Remove-Item -LiteralPath $CarpetaAuditoria -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok 'Limpieza completada exitosamente.'
    }
}

function Clear-ColaImpresionSpooler {
    Write-Etapa 'Deteniendo servicio de cola de impresion (Spooler)...'
    try {
        Stop-Service -Name Spooler -Force -ErrorAction Stop
    }
    catch {
        Registrar-ErrorAuditoria 'Spooler Stop' $_.Exception.Message
    }

    $rutaSpoolPrinters = Join-Path $env:windir 'System32\spool\PRINTERS'
    $eliminadosSpool = 0
    if (Test-Path $rutaSpoolPrinters) {
        $archivosSpool = @(Get-ChildItem -LiteralPath $rutaSpoolPrinters -File -Force -ErrorAction SilentlyContinue)
        foreach ($f in $archivosSpool) {
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                $eliminadosSpool++
            }
            catch {}
        }
    }

    Write-Etapa 'Reiniciando servicio de cola de impresion (Spooler)...'
    try {
        Start-Service -Name Spooler -ErrorAction Stop
    }
    catch {
        Registrar-ErrorAuditoria 'Spooler Start' $_.Exception.Message
    }

    $estadoSpooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    $statusText = if ($null -ne $estadoSpooler) { [string]$estadoSpooler.Status } else { 'Desconocido' }

    Write-Host "Cola de impresion liberada. Trabajos/archivos eliminados: $eliminadosSpool. Estado de Spooler: $statusText" -ForegroundColor Green
    return [pscustomobject]@{
        Fecha              = Get-Date
        ArchivosEliminados = $eliminadosSpool
        EstadoSpooler      = $statusText
    }
}

if (-not (Test-Administrador)) {
    throw 'Ejecute PowerShell como administrador para recopilar toda la evidencia.'
}

if ([string]::IsNullOrWhiteSpace($DirectorioSalida)) {
    if ($AutoEliminarAlCerrar) {
        $DirectorioSalida = $env:TEMP
    }
    else {
        $DirectorioSalida = 'C:\AuditoriaRed'
    }
}

$inicio = Get-Date
$marca = $inicio.ToString('yyyyMMdd-HHmmss')
$carpeta = Join-Path $DirectorioSalida "Auditoria-$env:COMPUTERNAME-$marca"
New-Item -ItemType Directory -Path $carpeta -Force | Out-Null

$errores = New-Object 'System.Collections.Generic.List[object]'
$conexiones = New-Object 'System.Collections.Generic.List[object]'
$estadisticasRed = New-Object 'System.Collections.Generic.List[object]'
$rendimiento = New-Object 'System.Collections.Generic.List[object]'
$sistemaOperativo = @()
$pktmonActivo = $false
$archivoEtl = Join-Path $carpeta 'captura.etl'
$archivoPcapng = Join-Path $carpeta 'captura.pcapng'
$resultadoLimpiezaSpooler = $null

function Registrar-ErrorAuditoria {
    param(
        [Parameter(Mandatory)][string]$Componente,
        [Parameter(Mandatory)][string]$Mensaje
    )
    $errores.Add([pscustomobject]@{
        Fecha      = Get-Date
        Componente = $Componente
        Mensaje    = $Mensaje
    })
}

function Write-Linea {
    param([string]$Caracter = '-', [string]$Color = 'Cyan')
    Write-Host ($Caracter * 72) -ForegroundColor $Color
}

function Write-Titulo {
    param([string]$Texto, [string]$Color = 'Cyan')
    Write-Linea -Caracter '-' -Color $Color
    $pad = [Math]::Max(0, [Math]::Floor((72 - $Texto.Length) / 2))
    Write-Host ((' ' * $pad) + $Texto) -ForegroundColor $Color
    Write-Linea -Caracter '-' -Color $Color
}

function Write-Info {
    param([string]$Texto)
    Write-Host '  i  ' -NoNewline -ForegroundColor Cyan
    Write-Host $Texto -ForegroundColor White
}

function Write-Ok {
    param([string]$Texto)
    Write-Host '  OK ' -NoNewline -ForegroundColor Green
    Write-Host $Texto -ForegroundColor White
}

function Write-Warn {
    param([string]$Texto)
    Write-Host '  !  ' -NoNewline -ForegroundColor Yellow
    Write-Host $Texto -ForegroundColor White
}

function Write-ErrorMsg {
    param([string]$Texto)
    Write-Host '  X  ' -NoNewline -ForegroundColor Red
    Write-Host $Texto -ForegroundColor White
}

function Write-Etapa {
    param([Parameter(Mandatory)][string]$Mensaje)
    Write-Host "  i  [$((Get-Date).ToString('HH:mm:ss'))] " -NoNewline -ForegroundColor Cyan
    Write-Host $Mensaje -ForegroundColor White
}

if ($Modo -eq 'Limpieza') {
    Write-Etapa 'Buscando archivos temporales y cachés...'
    $rutasLimpieza = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rutaTemporal in @($env:TEMP, (Join-Path $env:windir 'Temp'))) {
        if ($rutaTemporal -and -not $rutasLimpieza.Contains($rutaTemporal)) {
            $rutasLimpieza.Add($rutaTemporal)
        }
    }

    $datosChromeLimpieza = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
    if (Test-Path $datosChromeLimpieza) {
        $perfilesLimpieza = @(Get-ChildItem $datosChromeLimpieza -Directory |
            Where-Object Name -Match '^(Default|Profile \d+)$')
        foreach ($perfilLimpieza in $perfilesLimpieza) {
            foreach ($subruta in @('Cache', 'Code Cache', 'GPUCache')) {
                $rutaCache = Join-Path $perfilLimpieza.FullName $subruta
                if (-not $rutasLimpieza.Contains($rutaCache)) {
                    $rutasLimpieza.Add($rutaCache)
                }
            }
        }
    }

    $estadoAntes = @($rutasLimpieza | ForEach-Object {
        Get-ResumenDirectorio -Ruta $_ -DiasAntiguo $DiasTemporalAntiguo
    })
    Write-Etapa "Eliminando archivos temporales con más de $DiasTemporalAntiguo días..."
    $resultadoLimpieza = @($rutasLimpieza | ForEach-Object {
        Remove-ArchivosTemporalesAntiguos -Ruta $_ -DiasAntiguo $DiasTemporalAntiguo
    })
    Write-Etapa 'Comprobando el espacio liberado...'
    $estadoDespues = @($rutasLimpieza | ForEach-Object {
        Get-ResumenDirectorio -Ruta $_ -DiasAntiguo $DiasTemporalAntiguo
    })

    $estadoAntes |
        Export-Csv (Join-Path $carpeta 'archivos-temporales-antes.csv') -NoTypeInformation -Encoding UTF8
    $resultadoLimpieza |
        Export-Csv (Join-Path $carpeta 'limpieza-temporales.csv') -NoTypeInformation -Encoding UTF8
    $estadoDespues |
        Export-Csv (Join-Path $carpeta 'archivos-temporales-despues.csv') -NoTypeInformation -Encoding UTF8

    $eliminadosTotal = ($resultadoLimpieza | Measure-Object Eliminados -Sum).Sum
    $liberadosTotal = ($resultadoLimpieza | Measure-Object LiberadosMB -Sum).Sum
    $fallidosTotal = ($resultadoLimpieza | Measure-Object Fallidos -Sum).Sum
    $resumenLimpieza = @([pscustomobject]@{
        Equipo       = $env:COMPUTERNAME
        Usuario      = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Fecha        = Get-Date
        Antiguedad   = "Más de $DiasTemporalAntiguo días"
        Eliminados   = $eliminadosTotal
        LiberadosMB  = [Math]::Round($liberadosTotal, 2)
        NoEliminados = $fallidosTotal
    })

    $estiloLimpieza = @'
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 32px; color: #1f2937; }
h1, h2 { color: #17365d; }
table { border-collapse: collapse; width: 100%; margin-bottom: 24px; }
th, td { border: 1px solid #cbd5e1; padding: 6px; text-align: left; }
th { background: #e2e8f0; }
.nota { background: #fff7d6; border-left: 4px solid #d69e2e; padding: 12px; }
</style>
'@
    $contenidoLimpieza = @(
        '<h1>Informe de soporte - Limpieza del equipo</h1>'
        "<p class='nota'>Se eliminaron únicamente archivos con más de $DiasTemporalAntiguo días dentro de rutas temporales conocidas. No se eliminaron carpetas, descargas ni documentos del usuario, y no se siguieron enlaces.</p>"
        (Convertir-FragmentoHtml $resumenLimpieza 'Resultado')
        (Convertir-FragmentoHtml $estadoAntes 'Estado antes de la limpieza')
        (Convertir-FragmentoHtml $resultadoLimpieza 'Acciones realizadas')
        (Convertir-FragmentoHtml $estadoDespues 'Estado después de la limpieza')
    ) -join "`r`n"

    $archivoInformeLimpieza = Join-Path $carpeta 'informe-de-soporte.html'
    Write-Etapa 'Generando el informe de limpieza...'
    ConvertTo-Html -Title 'Informe de soporte - Limpieza' -Head $estiloLimpieza `
        -Body $contenidoLimpieza |
        Out-File $archivoInformeLimpieza -Encoding utf8

    $hashesLimpieza = @(Get-ChildItem $carpeta -File |
        Where-Object Name -ne 'hashes-sha256.csv' |
        Get-FileHash -Algorithm SHA256 |
        Select-Object Path, Algorithm, Hash)
    $hashesLimpieza |
        Export-Csv (Join-Path $carpeta 'hashes-sha256.csv') -NoTypeInformation -Encoding UTF8

    Write-Host "Limpieza finalizada. Informe: $archivoInformeLimpieza" -ForegroundColor Green
    Write-Host "Archivos eliminados: $eliminadosTotal; espacio liberado: $([Math]::Round($liberadosTotal, 2)) MB"
    Finalizar-InformeYLimpiar -RutaInforme $archivoInformeLimpieza -CarpetaAuditoria $carpeta -AutoEliminar $AutoEliminarAlCerrar -AbrirReporte (-not $NoAutoAbrirReporte)
    return
}

Write-Host ''
Write-Host "Modo: $Modo | Duración del muestreo: $DuracionMinutos minuto(s)" -ForegroundColor Yellow

if ($LimpiarColaImpresion) {
    $resultadoLimpiezaSpooler = Clear-ColaImpresionSpooler
    if ($null -ne $resultadoLimpiezaSpooler) {
        @($resultadoLimpiezaSpooler) |
            Export-Csv (Join-Path $carpeta 'limpieza-cola-impresion.csv') -NoTypeInformation -Encoding UTF8
    }
}

Write-Etapa 'Recopilando configuración inicial del equipo...'
try {
    & ipconfig.exe /all | Out-File (Join-Path $carpeta 'ipconfig.txt') -Encoding utf8
    & route.exe print | Out-File (Join-Path $carpeta 'rutas.txt') -Encoding utf8
    & arp.exe -a | Out-File (Join-Path $carpeta 'arp.txt') -Encoding utf8
    & netsh.exe winhttp show proxy |
        Out-File (Join-Path $carpeta 'proxy-winhttp.txt') -Encoding utf8
    Get-Content (Join-Path $env:windir 'System32\drivers\etc\hosts') |
        Out-File (Join-Path $carpeta 'archivo-hosts.txt') -Encoding utf8

    $sistemaOperativo = @(Get-CimInstance Win32_OperatingSystem |
        Select-Object Caption, Version, BuildNumber, LastBootUpTime)
    $sistemaOperativo |
        Export-Csv (Join-Path $carpeta 'sistema-operativo.csv') -NoTypeInformation -Encoding UTF8

    Get-NetIPConfiguration -Detailed |
        Format-List * |
        Out-File (Join-Path $carpeta 'configuracion-red.txt') -Encoding utf8

    if (-not $SinCapturaPktmon) {
        $pktmon = Get-Command pktmon.exe -ErrorAction SilentlyContinue
        if ($null -eq $pktmon) {
            Registrar-ErrorAuditoria 'pktmon' 'pktmon.exe no está disponible; se continuó con la auditoría de conexiones.'
        }
        else {
            $preferenciaErrorPktmon = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                # Detener sin captura activa produce un aviso benigno en stderr.
                & $pktmon.Source stop 2>$null | Out-Null
                & $pktmon.Source filter remove 2>$null | Out-Null
                # Solo se conservan encabezados para reducir la captura de contenido sensible.
                $salidaPktmon = & $pktmon.Source start --etw -p $BytesPorPaquete -f $archivoEtl 2>&1
                $codigoInicioPktmon = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $preferenciaErrorPktmon
            }
            if ($codigoInicioPktmon -eq 0) {
                $pktmonActivo = $true
            }
            else {
                Registrar-ErrorAuditoria 'pktmon' ($salidaPktmon -join ' ')
            }
        }
    }

    $finProgramado = $inicio.AddMinutes($DuracionMinutos)
    $numeroMuestra = 0
    Write-Etapa 'Iniciando el muestreo de red y rendimiento...'

    while ((Get-Date) -lt $finProgramado) {
        $numeroMuestra++
        $fechaMuestra = Get-Date
        $procesos = @{}

        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            $procesos[[int]$_.Id] = $_.ProcessName
        }

        try {
            Get-NetTCPConnection | ForEach-Object {
                $pidConexion = [int]$_.OwningProcess
                $nombreProceso = if ($procesos.ContainsKey($pidConexion)) {
                    $procesos[$pidConexion]
                }
                else {
                    '[proceso finalizado o protegido]'
                }

                $conexiones.Add([pscustomobject]@{
                    Fecha          = $fechaMuestra
                    Muestra        = $numeroMuestra
                    Proceso        = $nombreProceso
                    PID            = $pidConexion
                    Estado         = [string]$_.State
                    IPLocal        = $_.LocalAddress
                    PuertoLocal    = $_.LocalPort
                    IPRemota       = $_.RemoteAddress
                    PuertoRemoto   = $_.RemotePort
                    DestinoPublico = Test-IPPublica ([string]$_.RemoteAddress)
                })
            }
        }
        catch {
            Registrar-ErrorAuditoria 'Get-NetTCPConnection' $_.Exception.Message
        }

        try {
            Get-NetAdapterStatistics | ForEach-Object {
                $estadisticasRed.Add([pscustomobject]@{
                    Fecha              = $fechaMuestra
                    Muestra            = $numeroMuestra
                    Adaptador          = $_.Name
                    BytesRecibidos     = $_.ReceivedBytes
                    BytesEnviados      = $_.SentBytes
                    PaquetesRecibidos  = $_.ReceivedUnicastPackets
                    PaquetesEnviados   = $_.SentUnicastPackets
                    ErroresRecepcion   = $_.ReceivedPacketErrors
                    ErroresTransmision = $_.OutboundPacketErrors
                })
            }
        }
        catch {
            Registrar-ErrorAuditoria 'Get-NetAdapterStatistics' $_.Exception.Message
        }

        try {
            $estadoOs = Get-CimInstance Win32_OperatingSystem
            $procesadores = @(Get-CimInstance Win32_Processor)
            $cargaCpu = ($procesadores | Measure-Object LoadPercentage -Average).Average
            $memoriaTotalMB = [Math]::Round($estadoOs.TotalVisibleMemorySize / 1KB, 2)
            $memoriaLibreMB = [Math]::Round($estadoOs.FreePhysicalMemory / 1KB, 2)
            $rendimiento.Add([pscustomobject]@{
                Fecha             = $fechaMuestra
                Muestra           = $numeroMuestra
                CpuPorcentaje     = [Math]::Round($cargaCpu, 2)
                MemoriaTotalMB    = $memoriaTotalMB
                MemoriaLibreMB    = $memoriaLibreMB
                MemoriaUsadaPct   = if ($memoriaTotalMB -gt 0) {
                    [Math]::Round((1 - ($memoriaLibreMB / $memoriaTotalMB)) * 100, 2)
                }
                else {
                    0
                }
            })
        }
        catch {
            Registrar-ErrorAuditoria 'Muestreo de rendimiento' $_.Exception.Message
        }

        $restante = ($finProgramado - (Get-Date)).TotalSeconds
        $totalSegundos = $DuracionMinutos * 60
        $transcurrido = [Math]::Max(0, $totalSegundos - $restante)
        $porcentaje = [Math]::Min(99, [Math]::Floor(($transcurrido / $totalSegundos) * 100))
        $tiempoRestante = [TimeSpan]::FromSeconds([Math]::Max(0, [Math]::Ceiling($restante)))

        Write-Progress -Id 1 -Activity "Diagnostico $Modo" `
            -Status "Muestreando red y rendimiento - faltan $($tiempoRestante.ToString('mm\:ss'))" `
            -PercentComplete $porcentaje

        $anchoBarra = 20
        $completado = [Math]::Max(0, [Math]::Min($anchoBarra, [Math]::Floor(($porcentaje / 100) * $anchoBarra)))
        $pendiente = $anchoBarra - $completado
        $barraStr = ('#' * $completado) + ('-' * $pendiente)
        $statusStr = "`r [$barraStr] $porcentaje% | Muestra $numeroMuestra | Restante: $($tiempoRestante.ToString('mm\:ss')) | ['Q' para parar]"
        Write-Host $statusStr -NoNewline -ForegroundColor Cyan

        if ([System.Console]::KeyAvailable) {
            $teclaInfo = [System.Console]::ReadKey($true)
            if ($teclaInfo.Key -eq 'Q' -or $teclaInfo.Key -eq 'Escape') {
                Write-Host "`r`n`n[!] Muestreo detenido por el usuario. Generando informe con las muestras obtenidas..." -ForegroundColor Yellow
                break
            }
        }

        if ($restante -gt 0) {
            Start-Sleep -Seconds ([Math]::Min($IntervaloSegundos, [Math]::Ceiling($restante)))
        }
    }
    Write-Host ''
}
finally {
    if ($pktmonActivo) {
        $preferenciaErrorPktmon = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $salidaDetencion = & pktmon.exe stop 2>&1
            $codigoDetencionPktmon = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $preferenciaErrorPktmon
        }
        if ($codigoDetencionPktmon -ne 0) {
            Registrar-ErrorAuditoria 'pktmon stop' ($salidaDetencion -join ' ')
        }
        elseif (Test-Path $archivoEtl) {
            $preferenciaErrorPktmon = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $salidaConversion = & pktmon.exe pcapng $archivoEtl -o $archivoPcapng 2>&1
                $codigoConversionPktmon = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $preferenciaErrorPktmon
            }
            if ($codigoConversionPktmon -ne 0) {
                Registrar-ErrorAuditoria 'pktmon pcapng' ('No se pudo convertir a PCAPNG. Se conserva el ETL. ' + ($salidaConversion -join ' '))
            }
        }
    }
}

Write-Progress -Id 1 -Activity "Diagnóstico $Modo" -Completed
Write-Etapa 'Muestreo finalizado. Analizando seguridad y aplicaciones...'
$fin = Get-Date
$archivoConexiones = Join-Path $carpeta 'conexiones.csv'
$archivoEstadisticas = Join-Path $carpeta 'estadisticas-red.csv'
$conexiones | Export-Csv $archivoConexiones -NoTypeInformation -Encoding UTF8
$estadisticasRed | Export-Csv $archivoEstadisticas -NoTypeInformation -Encoding UTF8
$rendimiento |
    Export-Csv (Join-Path $carpeta 'rendimiento.csv') -NoTypeInformation -Encoding UTF8

$dns = @()
try {
    $dns = @(Get-DnsClientCache |
        Select-Object Entry, RecordName, RecordType, Status, Section, TimeToLive, Data)
    $dns | Export-Csv (Join-Path $carpeta 'cache-dns.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Get-DnsClientCache' $_.Exception.Message
}

$amenazas = @()
try {
    $amenazas = @(Get-MpThreatDetection |
        Where-Object { $_.InitialDetectionTime -ge $inicio } |
        Select-Object InitialDetectionTime, ThreatID, ActionSuccess, Resources)
    $amenazas | Export-Csv (Join-Path $carpeta 'amenazas-defender.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Microsoft Defender' $_.Exception.Message
}

$productosAntivirus = @()
try {
    $productosAntivirus = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntivirusProduct |
        Select-Object displayName, pathToSignedProductExe, pathToSignedReportingExe, productState,
            timestamp)
    $productosAntivirus |
        Export-Csv (Join-Path $carpeta 'productos-antivirus.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'SecurityCenter2/AntivirusProduct' $_.Exception.Message
}

$componentesKaspersky = @()
try {
    $componentesKaspersky = @(Get-CimInstance Win32_Service |
        Where-Object {
            $_.Name -match 'Kaspersky|(^|[^a-z])kes([^a-z]|$)|(^|[^a-z])avp([^a-z]|$)' -or
            $_.DisplayName -match 'Kaspersky'
        } |
        Select-Object Name, DisplayName, State, StartMode, PathName)
    $componentesKaspersky |
        Export-Csv (Join-Path $carpeta 'servicios-kaspersky.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Servicios de Kaspersky' $_.Exception.Message
}

$eventosKaspersky = New-Object 'System.Collections.Generic.List[object]'
try {
    $eventosAplicacion = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'Application'
        StartTime = $inicio
        EndTime   = $fin
    } -ErrorAction SilentlyContinue | Where-Object ProviderName -Match 'Kaspersky')

    foreach ($evento in $eventosAplicacion) {
        $eventosKaspersky.Add([pscustomobject]@{
            Fecha     = $evento.TimeCreated
            Registro  = $evento.LogName
            Proveedor = $evento.ProviderName
            Nivel     = $evento.LevelDisplayName
            Id        = $evento.Id
            Mensaje   = $evento.Message
        })
    }

    $registrosKaspersky = @(Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
        Where-Object LogName -Match 'Kaspersky')
    foreach ($registro in $registrosKaspersky) {
        $eventos = @(Get-WinEvent -FilterHashtable @{
            LogName   = $registro.LogName
            StartTime = $inicio
            EndTime   = $fin
        } -ErrorAction SilentlyContinue)
        foreach ($evento in $eventos) {
            $eventosKaspersky.Add([pscustomobject]@{
                Fecha     = $evento.TimeCreated
                Registro  = $evento.LogName
                Proveedor = $evento.ProviderName
                Nivel     = $evento.LevelDisplayName
                Id        = $evento.Id
                Mensaje   = $evento.Message
            })
        }
    }
    $eventosKaspersky |
        Export-Csv (Join-Path $carpeta 'eventos-kaspersky.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Eventos de Kaspersky' $_.Exception.Message
}

$versionesChrome = New-Object 'System.Collections.Generic.List[object]'
$rutasChrome = @(
    (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique

foreach ($rutaChrome in $rutasChrome) {
    $version = (Get-Item $rutaChrome).VersionInfo
    $versionesChrome.Add([pscustomobject]@{
        Producto = $version.ProductName
        Version  = $version.ProductVersion
        Ruta     = $rutaChrome
    })
}
$versionesChrome |
    Export-Csv (Join-Path $carpeta 'versiones-chrome.csv') -NoTypeInformation -Encoding UTF8

$politicasChrome = New-Object 'System.Collections.Generic.List[object]'
foreach ($raizPolitica in @(
    'HKLM:\SOFTWARE\Policies\Google\Chrome',
    'HKCU:\SOFTWARE\Policies\Google\Chrome'
)) {
    if (Test-Path $raizPolitica) {
        $claves = @((Get-Item $raizPolitica)) + @(Get-ChildItem $raizPolitica -Recurse)
        foreach ($clave in $claves) {
            foreach ($nombreValor in $clave.GetValueNames()) {
                $politicasChrome.Add([pscustomobject]@{
                    Clave  = $clave.Name
                    Nombre = $nombreValor
                    Valor  = [string]$clave.GetValue($nombreValor)
                })
            }
        }
    }
}
$politicasChrome |
    Export-Csv (Join-Path $carpeta 'politicas-chrome.csv') -NoTypeInformation -Encoding UTF8

$extensionesChrome = New-Object 'System.Collections.Generic.List[object]'
$datosChrome = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
$perfilesChrome = @()
if (Test-Path $datosChrome) {
    $perfilesChrome = @(Get-ChildItem $datosChrome -Directory |
        Where-Object Name -Match '^(Default|Profile \d+)$')
    foreach ($perfil in $perfilesChrome) {
        $directorioExtensiones = Join-Path $perfil.FullName 'Extensions'
        if (-not (Test-Path $directorioExtensiones)) {
            continue
        }
        foreach ($extension in Get-ChildItem $directorioExtensiones -Directory) {
            $manifiesto = Get-ChildItem $extension.FullName -Filter 'manifest.json' -File -Recurse |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($null -eq $manifiesto) {
                continue
            }
            try {
                $datosManifiesto = Get-Content $manifiesto.FullName -Raw | ConvertFrom-Json
                $extensionesChrome.Add([pscustomobject]@{
                    Perfil  = $perfil.Name
                    Id      = $extension.Name
                    Nombre  = [string]$datosManifiesto.name
                    Version = [string]$datosManifiesto.version
                    Ruta    = $manifiesto.DirectoryName
                })
            }
            catch {
                Registrar-ErrorAuditoria "Extensión Chrome $($extension.Name)" $_.Exception.Message
            }
        }
    }
}
$extensionesChrome |
    Export-Csv (Join-Path $carpeta 'extensiones-chrome.csv') -NoTypeInformation -Encoding UTF8

Write-Etapa 'Revisando firewall, cifrado, actualizaciones y almacenamiento...'
$controlesSeguridad = New-Object 'System.Collections.Generic.List[object]'
$perfilesFirewall = @()
try {
    $perfilesFirewall = @(Get-NetFirewallProfile |
        Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction,
            NotifyOnListen)
    foreach ($perfilFirewall in $perfilesFirewall) {
        $controlesSeguridad.Add([pscustomobject]@{
            Area      = 'Firewall'
            Control   = "Perfil $($perfilFirewall.Name)"
            Resultado = if ($perfilFirewall.Enabled) { 'Cumple' } else { 'Revisar' }
            Detalle   = "Habilitado=$($perfilFirewall.Enabled); entrada=$($perfilFirewall.DefaultInboundAction); salida=$($perfilFirewall.DefaultOutboundAction)"
        })
    }
    $perfilesFirewall |
        Export-Csv (Join-Path $carpeta 'firewall-perfiles.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Perfiles de Windows Firewall' $_.Exception.Message
}

if ($productosAntivirus.Count -eq 0) {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Antivirus'
        Control   = 'Producto registrado'
        Resultado = 'Revisar'
        Detalle   = 'Windows Security Center no reportó un antivirus.'
    })
}
else {
    foreach ($productoAntivirus in $productosAntivirus) {
        $controlesSeguridad.Add([pscustomobject]@{
            Area      = 'Antivirus'
            Control   = $productoAntivirus.displayName
            Resultado = 'Informativo'
            Detalle   = "Registrado en Security Center; productState=$($productoAntivirus.productState)"
        })
    }
}

$bitLocker = @()
try {
    $bitLocker = @(Get-BitLockerVolume |
        Select-Object MountPoint, VolumeStatus, ProtectionStatus, EncryptionPercentage,
            EncryptionMethod)
    foreach ($volumenBitLocker in $bitLocker) {
        $controlesSeguridad.Add([pscustomobject]@{
            Area      = 'Cifrado'
            Control   = "BitLocker $($volumenBitLocker.MountPoint)"
            Resultado = if ([string]$volumenBitLocker.ProtectionStatus -eq 'On') { 'Cumple' } else { 'Revisar' }
            Detalle   = "Protección=$($volumenBitLocker.ProtectionStatus); cifrado=$($volumenBitLocker.EncryptionPercentage)%; método=$($volumenBitLocker.EncryptionMethod)"
        })
    }
    $bitLocker |
        Export-Csv (Join-Path $carpeta 'bitlocker.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'BitLocker' $_.Exception.Message
}

try {
    $secureBoot = Confirm-SecureBootUEFI
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Arranque'
        Control   = 'Secure Boot'
        Resultado = if ($secureBoot) { 'Cumple' } else { 'Revisar' }
        Detalle   = "Habilitado=$secureBoot"
    })
}
catch {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Arranque'
        Control   = 'Secure Boot'
        Resultado = 'Revisar'
        Detalle   = "No se pudo confirmar Secure Boot: $($_.Exception.Message)"
    })
}

try {
    $tpm = Get-Tpm
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Hardware'
        Control   = 'TPM'
        Resultado = if ($tpm.TpmPresent -and $tpm.TpmReady) { 'Cumple' } else { 'Revisar' }
        Detalle   = "Presente=$($tpm.TpmPresent); listo=$($tpm.TpmReady); habilitado=$($tpm.TpmEnabled)"
    })
}
catch {
    Registrar-ErrorAuditoria 'TPM' $_.Exception.Message
}

try {
    $uac = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Cuentas'
        Control   = 'Control de cuentas de usuario (UAC)'
        Resultado = if ($uac.EnableLUA -eq 1) { 'Cumple' } else { 'Revisar' }
        Detalle   = "EnableLUA=$($uac.EnableLUA); ConsentPromptBehaviorAdmin=$($uac.ConsentPromptBehaviorAdmin)"
    })
}
catch {
    Registrar-ErrorAuditoria 'UAC' $_.Exception.Message
}

try {
    $smb = Get-SmbServerConfiguration
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Protocolos'
        Control   = 'SMB 1.0'
        Resultado = if ($smb.EnableSMB1Protocol) { 'Revisar' } else { 'Cumple' }
        Detalle   = "SMB1=$($smb.EnableSMB1Protocol); SMB2/3=$($smb.EnableSMB2Protocol); cifrado requerido=$($smb.EncryptData)"
    })
}
catch {
    Registrar-ErrorAuditoria 'Configuración SMB' $_.Exception.Message
}

try {
    $terminalServer = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $rdpHabilitado = $terminalServer.fDenyTSConnections -eq 0
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Acceso remoto'
        Control   = 'Escritorio remoto (RDP)'
        Resultado = if ($rdpHabilitado) { 'Revisar' } else { 'Cumple' }
        Detalle   = "Habilitado=$rdpHabilitado. Si es necesario, confirme que esté autorizado y restringido por firewall."
    })
}
catch {
    Registrar-ErrorAuditoria 'Configuración RDP' $_.Exception.Message
}

$cambiosArchivoPendientes = Get-ItemPropertyValue `
    'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
    -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
$reinicioPendiente = (
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
    (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
    ($null -ne $cambiosArchivoPendientes)
)
$controlesSeguridad.Add([pscustomobject]@{
    Area      = 'Mantenimiento'
    Control   = 'Reinicio pendiente'
    Resultado = if ($reinicioPendiente) { 'Revisar' } else { 'Cumple' }
    Detalle   = "Pendiente=$reinicioPendiente"
})

$actualizaciones = @()
try {
    $actualizaciones = @(Get-HotFix |
        Sort-Object InstalledOn -Descending |
        Select-Object HotFixID, Description, InstalledBy, InstalledOn)
    $actualizaciones |
        Export-Csv (Join-Path $carpeta 'actualizaciones-instaladas.csv') -NoTypeInformation -Encoding UTF8
    $ultimaActualizacion = $actualizaciones |
        Where-Object InstalledOn |
        Select-Object -First 1
    $diasUltimaActualizacion = if ($null -ne $ultimaActualizacion) {
        [Math]::Floor(((Get-Date) - $ultimaActualizacion.InstalledOn).TotalDays)
    }
    else {
        $null
    }
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Actualizaciones'
        Control   = 'Última actualización registrada'
        Resultado = if ($null -ne $diasUltimaActualizacion -and $diasUltimaActualizacion -le 45) { 'Cumple' } else { 'Revisar' }
        Detalle   = if ($null -eq $diasUltimaActualizacion) { 'No se pudo determinar.' } else { "Hace $diasUltimaActualizacion días ($($ultimaActualizacion.HotFixID))." }
    })
}
catch {
    Registrar-ErrorAuditoria 'Actualizaciones instaladas' $_.Exception.Message
}

if (@($sistemaOperativo | Where-Object Caption -Match 'Windows 10').Count -gt 0) {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Ciclo de vida'
        Control   = 'Soporte de Windows 10'
        Resultado = 'Revisar'
        Detalle   = 'Verifique que la edición tenga LTSC o cobertura ESU vigente; el soporte general de Windows 10 finalizó.'
    })
}

$volumenes = @()
try {
    $volumenes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' |
        ForEach-Object {
            $porcentajeLibre = if ($_.Size -gt 0) {
                [Math]::Round(($_.FreeSpace / $_.Size) * 100, 2)
            }
            else {
                0
            }
            [pscustomobject]@{
                Unidad          = $_.DeviceID
                Etiqueta        = $_.VolumeName
                TamanoGB        = [Math]::Round($_.Size / 1GB, 2)
                LibreGB         = [Math]::Round($_.FreeSpace / 1GB, 2)
                PorcentajeLibre = $porcentajeLibre
                SistemaArchivos = $_.FileSystem
            }
        })
    foreach ($volumen in $volumenes) {
        $controlesSeguridad.Add([pscustomobject]@{
            Area      = 'Almacenamiento'
            Control   = "Espacio libre $($volumen.Unidad)"
            Resultado = if ($volumen.PorcentajeLibre -ge 15) { 'Cumple' } else { 'Revisar' }
            Detalle   = "$($volumen.LibreGB) GB libres ($($volumen.PorcentajeLibre)%)."
        })
    }
    $volumenes |
        Export-Csv (Join-Path $carpeta 'volumenes.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Volúmenes de almacenamiento' $_.Exception.Message
}

$discosFisicos = @()
try {
    $discosFisicos = @(Get-PhysicalDisk |
        Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus, Size)
    foreach ($discoFisico in $discosFisicos) {
        $controlesSeguridad.Add([pscustomobject]@{
            Area      = 'Almacenamiento'
            Control   = "Salud del disco $($discoFisico.FriendlyName)"
            Resultado = if ([string]$discoFisico.HealthStatus -eq 'Healthy') { 'Cumple' } else { 'Revisar' }
            Detalle   = "Salud=$($discoFisico.HealthStatus); estado=$($discoFisico.OperationalStatus); tipo=$($discoFisico.MediaType)"
        })
    }
    $discosFisicos |
        Export-Csv (Join-Path $carpeta 'discos-fisicos.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Estado de discos físicos' $_.Exception.Message
}

$administradoresLocales = @()
try {
    $grupoAdministradores = Get-LocalGroup -SID 'S-1-5-32-544'
    $administradoresLocales = @(Get-LocalGroupMember -Group $grupoAdministradores |
        Select-Object Name, ObjectClass, PrincipalSource)
    $administradoresLocales |
        Export-Csv (Join-Path $carpeta 'administradores-locales.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Administradores locales' $_.Exception.Message
}

$inicioEventos = (Get-Date).AddDays(-$DiasEventos)
$eventosSistema = @()
try {
    $eventosSistema = @(@('System', 'Application') | ForEach-Object {
        Get-WinEvent -FilterHashtable @{
            LogName   = $_
            Level     = @(1, 2)
            StartTime = $inicioEventos
        } -ErrorAction SilentlyContinue
    } | Group-Object LogName, ProviderName, Id, LevelDisplayName | ForEach-Object {
        $ultimo = $_.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        [pscustomobject]@{
            Registro  = $ultimo.LogName
            Proveedor = $ultimo.ProviderName
            Id        = $ultimo.Id
            Nivel     = $ultimo.LevelDisplayName
            Cantidad  = $_.Count
            Ultimo    = $ultimo.TimeCreated
            Mensaje   = $ultimo.Message
        }
    } | Sort-Object Cantidad -Descending)
    $eventosSistema |
        Export-Csv (Join-Path $carpeta 'errores-eventos-sistema.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Eventos críticos del sistema' $_.Exception.Message
}

$serviciosAutomaticosDetenidos = @()
try {
    $serviciosAutomaticosDetenidos = @(Get-CimInstance Win32_Service |
        Where-Object { $_.StartMode -eq 'Auto' -and $_.State -ne 'Running' } |
        Select-Object Name, DisplayName, State, StartMode, ExitCode)
    $serviciosAutomaticosDetenidos |
        Export-Csv (Join-Path $carpeta 'servicios-automaticos-detenidos.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Servicios automáticos' $_.Exception.Message
}

$inicioWindows = @()
try {
    $inicioWindows = @(Get-CimInstance Win32_StartupCommand |
        Select-Object Name, Command, Location, User)
    $inicioWindows |
        Export-Csv (Join-Path $carpeta 'programas-inicio.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Programas de inicio' $_.Exception.Message
}

$rutasTemporales = New-Object 'System.Collections.Generic.List[string]'
foreach ($rutaTemporal in @($env:TEMP, (Join-Path $env:windir 'Temp'))) {
    if ($rutaTemporal -and -not $rutasTemporales.Contains($rutaTemporal)) {
        $rutasTemporales.Add($rutaTemporal)
    }
}
foreach ($perfilChrome in @($perfilesChrome)) {
    foreach ($subruta in @('Cache', 'Code Cache', 'GPUCache')) {
        $rutaCache = Join-Path $perfilChrome.FullName $subruta
        if (-not $rutasTemporales.Contains($rutaCache)) {
            $rutasTemporales.Add($rutaCache)
        }
    }
}
$temporales = @($rutasTemporales | ForEach-Object {
    Get-ResumenDirectorio -Ruta $_ -DiasAntiguo $DiasTemporalAntiguo
})
$temporales |
    Export-Csv (Join-Path $carpeta 'archivos-temporales-antes.csv') -NoTypeInformation -Encoding UTF8

$limpiezaTemporales = @()
$temporalesDespues = @()
if ($EliminarTemporales) {
    $limpiezaTemporales = @($rutasTemporales | ForEach-Object {
        Remove-ArchivosTemporalesAntiguos -Ruta $_ -DiasAntiguo $DiasTemporalAntiguo
    })
    $limpiezaTemporales |
        Export-Csv (Join-Path $carpeta 'limpieza-temporales.csv') -NoTypeInformation -Encoding UTF8
    $temporalesDespues = @($rutasTemporales | ForEach-Object {
        Get-ResumenDirectorio -Ruta $_ -DiasAntiguo $DiasTemporalAntiguo
    })
    $temporalesDespues |
        Export-Csv (Join-Path $carpeta 'archivos-temporales-despues.csv') -NoTypeInformation -Encoding UTF8
}

Write-Etapa 'Revisando controladores, impresoras, software y licencias...'
$controladoresProblema = @()
$controladoresInstalados = @()
try {
    $controladoresProblema = @(Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.ConfigManagerErrorCode -ne 0 } |
        Select-Object Name, Manufacturer, PNPClass, Status, ConfigManagerErrorCode,
            DeviceID)
    $controladoresProblema |
        Export-Csv (Join-Path $carpeta 'dispositivos-con-problemas.csv') -NoTypeInformation -Encoding UTF8

    $controladoresInstalados = @(Get-CimInstance Win32_PnPSignedDriver |
        Select-Object DeviceName, DeviceClass, Manufacturer, DriverProviderName,
            DriverVersion, DriverDate, IsSigned, InfName |
        Sort-Object DeviceClass, DeviceName)
    $controladoresInstalados |
        Export-Csv (Join-Path $carpeta 'controladores-instalados.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Controladores y dispositivos PnP' $_.Exception.Message
}

$eventosControladores = @()
try {
    $eventosControladores = @(Get-WinEvent -FilterHashtable @{
        LogName      = 'System'
        ProviderName = @('Microsoft-Windows-Kernel-PnP', 'Microsoft-Windows-DriverFrameworks-UserMode')
        StartTime    = $inicioEventos
    } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Sort-Object TimeCreated -Descending)
    $eventosControladores |
        Export-Csv (Join-Path $carpeta 'eventos-controladores.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Eventos de controladores' $_.Exception.Message
}

$impresoras = @()
$impresorasRed = New-Object 'System.Collections.Generic.List[object]'
$controladoresImpresora = @()
$trabajosImpresion = @()
$servicioImpresion = @()
try {
    $impresoras = @(Get-Printer |
        Select-Object Name, DriverName, PortName, Type, PrinterStatus, Shared,
            Published, WorkOffline)
    $controladoresImpresora = @(Get-PrinterDriver |
        Select-Object Name, Manufacturer, MajorVersion, DriverVersion, InfPath)
    $trabajosImpresion = @($impresoras | ForEach-Object {
        Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue |
            Select-Object PrinterName, ID, DocumentName, JobStatus, SubmittedTime,
                Size
    })
    $servicioImpresion = @(Get-Service Spooler |
        Select-Object Name, DisplayName, Status, StartType)

    $puertosImpresora = @{}
    try {
        Get-PrinterPort -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name) { $puertosImpresora[$_.Name] = $_ }
        }
    }
    catch {}

    foreach ($imp in $impresoras) {
        $esRed = $false
        $hostRed = $null
        $tipoConexion = 'Local'
        $puertoRaw = [string]$imp.PortName

        if ([string]$imp.Type -eq 'Network' -or $imp.Name -like '\\*' -or $puertoRaw -like '\\*') {
            $esRed = $true
            $tipoConexion = 'Compartida (SMB/UNC)'
            if ($imp.Name -like '\\*') {
                $hostRed = ($imp.Name -split '\\')[2]
            }
            elseif ($puertoRaw -like '\\*') {
                $hostRed = ($puertoRaw -split '\\')[2]
            }
        }
        elseif ($puertosImpresora.ContainsKey($puertoRaw)) {
            $pObj = $puertosImpresora[$puertoRaw]
            if ($pObj.PrinterHostAddress) {
                $esRed = $true
                $tipoConexion = 'TCP/IP o WSD'
                $hostRed = [string]$pObj.PrinterHostAddress
            }
            elseif ($pObj.Description -match 'TCP/IP|WSD|Standard TCP' -or $puertoRaw -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                $esRed = $true
                $tipoConexion = 'TCP/IP'
                $hostRed = $puertoRaw
            }
        }
        elseif ($puertoRaw -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            $esRed = $true
            $tipoConexion = 'TCP/IP Directo'
            $hostRed = $puertoRaw
        }
        elseif ($puertoRaw -like 'WSD-*' -or $puertoRaw -like 'IP_*') {
            $esRed = $true
            $tipoConexion = 'WSD / IP Port'
            if ($puertoRaw -match '(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})') {
                $hostRed = $Matches[1]
            }
        }

        if ($esRed) {
            $pingOk = $false
            $pingMs = $null
            $puertoImpAbierto = $false
            $puertoAProbar = if ($tipoConexion -like '*SMB*') { 445 } else { 9100 }

            if ($hostRed) {
                $pingTest = @(Test-Connection -ComputerName $hostRed -Count 2 -ErrorAction SilentlyContinue)
                if ($pingTest.Count -gt 0) {
                    $pingOk = $true
                    $pingMs = [Math]::Round(($pingTest | Measure-Object ResponseTime -Average).Average, 2)
                }

                try {
                    $client = New-Object System.Net.Sockets.TcpClient
                    $ar = $client.BeginConnect($hostRed, $puertoAProbar, $null, $null)
                    $wait = $ar.AsyncWaitHandle.WaitOne(1500, $false)
                    if ($wait -and $client.Connected) {
                        $puertoImpAbierto = $true
                        $client.EndConnect($ar)
                    }
                    $client.Close()
                }
                catch {
                    $puertoImpAbierto = $false
                }
            }

            $estadoRedDetalle = if (-not $hostRed) {
                "Host/IP no identificado en puerto $($puertoRaw)"
            }
            elseif ($pingOk -and $puertoImpAbierto) {
                "Alcanzable (Ping $pingMs ms | Puerto $puertoAProbar Abierto)"
            }
            elseif ($pingOk) {
                "Responde Ping ($pingMs ms) pero puerto $puertoAProbar cerrado"
            }
            else {
                "Inalcanzable (Sin respuesta ICMP/Ping en $hostRed)"
            }

            $impresorasRed.Add([pscustomobject]@{
                Nombre          = $imp.Name
                TipoConexion    = $tipoConexion
                Puerto          = $puertoRaw
                HostIP          = if ($hostRed) { $hostRed } else { 'Desconocido' }
                PingExitoso     = $pingOk
                LatenciaMs      = if ($null -ne $pingMs) { $pingMs } else { '-' }
                PuertoImpresion = "${puertoAProbar}: " + (if ($puertoImpAbierto) { 'Abierto' } else { 'Cerrado' })
                ModoSinConexion = $imp.WorkOffline
                DiagnosticoRed  = $estadoRedDetalle
            })
        }
    }

    $impresoras |
        Export-Csv (Join-Path $carpeta 'impresoras-instaladas.csv') -NoTypeInformation -Encoding UTF8
    if ($impresorasRed.Count -gt 0) {
        $impresorasRed |
            Export-Csv (Join-Path $carpeta 'impresoras-red.csv') -NoTypeInformation -Encoding UTF8
    }
    $controladoresImpresora |
        Export-Csv (Join-Path $carpeta 'controladores-impresora.csv') -NoTypeInformation -Encoding UTF8
    $trabajosImpresion |
        Export-Csv (Join-Path $carpeta 'trabajos-impresion.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Subsistema de impresión' $_.Exception.Message
}

$eventosImpresion = @()
try {
    $eventosImpresion = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'Microsoft-Windows-PrintService/Admin'
        StartTime = $inicioEventos
    } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, Id, LevelDisplayName, Message |
        Sort-Object TimeCreated -Descending)
    $eventosImpresion |
        Export-Csv (Join-Path $carpeta 'eventos-impresion.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Eventos de impresión' $_.Exception.Message
}

$softwareInstalado = New-Object 'System.Collections.Generic.List[object]'
foreach ($origenSoftware in @(
    [pscustomobject]@{ Alcance = 'Equipo 64-bit'; Ruta = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' },
    [pscustomobject]@{ Alcance = 'Equipo 32-bit'; Ruta = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' },
    [pscustomobject]@{ Alcance = 'Usuario'; Ruta = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' }
)) {
    try {
        Get-ItemProperty $origenSoftware.Ruta | Where-Object DisplayName | ForEach-Object {
            $softwareInstalado.Add([pscustomobject]@{
                Nombre          = $_.DisplayName
                Version         = $_.DisplayVersion
                Fabricante      = $_.Publisher
                FechaInstalacion = $_.InstallDate
                Alcance         = $origenSoftware.Alcance
                EstadoLicencia  = 'No expuesto por Windows'
            })
        }
    }
    catch {
        Registrar-ErrorAuditoria "Inventario de software: $($origenSoftware.Alcance)" $_.Exception.Message
    }
}
$softwareInstalado = @($softwareInstalado |
    Sort-Object Nombre, Version, Alcance -Unique)
$softwareInstalado |
    Export-Csv (Join-Path $carpeta 'software-instalado.csv') -NoTypeInformation -Encoding UTF8

$estadosLicencia = @{
    0 = 'Sin licencia'
    1 = 'Con licencia'
    2 = 'Periodo de gracia inicial'
    3 = 'Periodo de gracia adicional'
    4 = 'Periodo de gracia no genuino'
    5 = 'Modo notificación'
    6 = 'Periodo de gracia extendido'
}
$licenciasMicrosoft = @()
try {
    $licenciasMicrosoft = @(Get-CimInstance SoftwareLicensingProduct |
        Where-Object PartialProductKey |
        ForEach-Object {
            [pscustomobject]@{
                Producto         = $_.Name
                Descripcion      = $_.Description
                Estado           = $estadosLicencia[[int]$_.LicenseStatus]
                UltimosCaracteres = $_.PartialProductKey
                Id               = $_.ID
            }
        } |
        Sort-Object Producto)
    $licenciasMicrosoft |
        Export-Csv (Join-Path $carpeta 'licencias-microsoft.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Licenciamiento de Windows y Microsoft' $_.Exception.Message
}

if ($controladoresProblema.Count -gt 0) {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Controladores'
        Control   = 'Dispositivos con errores PnP'
        Resultado = 'Revisar'
        Detalle   = "$($controladoresProblema.Count) dispositivo(s) reportan un código de error."
    })
}
else {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Controladores'
        Control   = 'Dispositivos con errores PnP'
        Resultado = 'Cumple'
        Detalle   = 'No se encontraron códigos de error activos.'
    })
}

if ($servicioImpresion.Count -gt 0) {
    $spoolerActivo = [string]$servicioImpresion[0].Status -eq 'Running'
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Impresión'
        Control   = 'Servicio de cola de impresión'
        Resultado = if ($spoolerActivo) { 'Cumple' } else { 'Revisar' }
        Detalle   = "Estado=$($servicioImpresion[0].Status); inicio=$($servicioImpresion[0].StartType)"
    })
}

if ($null -ne $resultadoLimpiezaSpooler) {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Impresión'
        Control   = 'Liberación de cola de impresión (Spooler)'
        Resultado = if ([string]$resultadoLimpiezaSpooler.EstadoSpooler -eq 'Running') { 'Cumple' } else { 'Revisar' }
        Detalle   = "Trabajos/archivos eliminados: $($resultadoLimpiezaSpooler.ArchivosEliminados); Estado Spooler: $($resultadoLimpiezaSpooler.EstadoSpooler)"
    })
}

foreach ($impRed in $impresorasRed) {
    $resImp = if ($impRed.PingExitoso -and -not $impRed.ModoSinConexion) { 'Cumple' } else { 'Revisar' }
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Impresión de Red'
        Control   = "Impresora de red: $($impRed.Nombre)"
        Resultado = $resImp
        Detalle   = "Host/IP=$($impRed.HostIP); SinConexion=$($impRed.ModoSinConexion); Diagnóstico=$($impRed.DiagnosticoRed)"
    })
}

if ($EliminarTemporales) {
    $fallosLimpieza = ($limpiezaTemporales | Measure-Object Fallidos -Sum).Sum
    $liberadoLimpieza = ($limpiezaTemporales | Measure-Object LiberadosMB -Sum).Sum
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Mantenimiento'
        Control   = 'Limpieza de archivos temporales'
        Resultado = if ($fallosLimpieza -eq 0) { 'Cumple' } else { 'Revisar' }
        Detalle   = "Liberados=$([Math]::Round($liberadoLimpieza, 2)) MB; archivos no eliminados=$fallosLimpieza."
    })
}

$licenciaWindows = @($licenciasMicrosoft | Where-Object {
    $_.Producto -Match '^Windows' -and $_.Descripcion -Match 'Operating System'
})
if ($licenciaWindows.Count -gt 0) {
    $windowsLicenciado = @($licenciaWindows | Where-Object Estado -eq 'Con licencia').Count -gt 0
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Licenciamiento'
        Control   = 'Activación de Windows'
        Resultado = if ($windowsLicenciado) { 'Cumple' } else { 'Revisar' }
        Detalle   = ($licenciaWindows.Estado | Sort-Object -Unique) -join ', '
    })
}

Write-Etapa 'Revisando rendimiento, estabilidad, dominio y conectividad...'
$procesosConsumo = @()
try {
    $procesosConsumo = @(Get-Process |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 30 Name, Id,
            @{ Name = 'MemoriaMB'; Expression = { [Math]::Round($_.WorkingSet64 / 1MB, 2) } },
            @{ Name = 'CpuTotalSegundos'; Expression = { if ($null -eq $_.CPU) { 0 } else { [Math]::Round($_.CPU, 2) } } },
            Handles, Threads)
    $procesosConsumo |
        Export-Csv (Join-Path $carpeta 'procesos-mayor-consumo.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Procesos con mayor consumo' $_.Exception.Message
}

$volcadosSistema = @()
foreach ($rutaVolcados in @(
    (Join-Path $env:windir 'Minidump'),
    (Join-Path $env:LOCALAPPDATA 'CrashDumps')
)) {
    if (Test-Path $rutaVolcados) {
        $volcadosSistema += @(Get-ChildItem $rutaVolcados -File -ErrorAction SilentlyContinue |
            Where-Object LastWriteTime -ge $inicioEventos |
            Select-Object Name, Length, LastWriteTime, FullName)
    }
}
$volcadosSistema |
    Export-Csv (Join-Path $carpeta 'volcados-fallos.csv') -NoTypeInformation -Encoding UTF8

$eventosAplicaciones = @()
try {
    $eventosAplicaciones = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'Application'
        Id        = @(1000, 1001, 1002)
        StartTime = $inicioEventos
    } -ErrorAction SilentlyContinue |
        Select-Object TimeCreated, ProviderName, Id, LevelDisplayName, Message |
        Sort-Object TimeCreated -Descending)
    $eventosAplicaciones |
        Export-Csv (Join-Path $carpeta 'fallos-aplicaciones.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Fallos de aplicaciones' $_.Exception.Message
}

$equipoDominio = @()
try {
    $equipoDominio = @(Get-CimInstance Win32_ComputerSystem |
        Select-Object Name, Manufacturer, Model, Domain, PartOfDomain,
            DomainRole, TotalPhysicalMemory)
    $equipoDominio |
        Export-Csv (Join-Path $carpeta 'equipo-y-dominio.csv') -NoTypeInformation -Encoding UTF8

    & w32tm.exe /query /status |
        Out-File (Join-Path $carpeta 'sincronizacion-hora.txt') -Encoding utf8
    & gpresult.exe /r /scope computer |
        Out-File (Join-Path $carpeta 'gpo-equipo.txt') -Encoding utf8
    & gpresult.exe /r /scope user |
        Out-File (Join-Path $carpeta 'gpo-usuario.txt') -Encoding utf8

    if ($equipoDominio.Count -gt 0 -and $equipoDominio[0].PartOfDomain) {
        & nltest.exe /sc_verify:$($equipoDominio[0].Domain) |
            Out-File (Join-Path $carpeta 'confianza-dominio.txt') -Encoding utf8
    }
}
catch {
    Registrar-ErrorAuditoria 'Dominio, GPO y sincronización horaria' $_.Exception.Message
}

$adaptadoresRed = @()
$pruebasRed = New-Object 'System.Collections.Generic.List[object]'
if ($Modo -in @('Completo', 'Red')) {
    try {
        $adaptadoresRed = @(Get-NetAdapter |
            Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress,
                DriverInformation, DriverVersion)
        $adaptadoresRed |
            Export-Csv (Join-Path $carpeta 'adaptadores-red.csv') -NoTypeInformation -Encoding UTF8

        & netsh.exe wlan show interfaces |
            Out-File (Join-Path $carpeta 'estado-wifi.txt') -Encoding utf8

        $rutaPredeterminada = Get-NetRoute -DestinationPrefix '0.0.0.0/0' |
            Sort-Object RouteMetric |
            Select-Object -First 1
        if ($null -ne $rutaPredeterminada) {
            $respuestasGateway = @(Test-Connection -ComputerName $rutaPredeterminada.NextHop `
                -Count 4 -ErrorAction SilentlyContinue)
            $pruebasRed.Add([pscustomobject]@{
                Prueba        = 'Puerta de enlace'
                Destino       = $rutaPredeterminada.NextHop
                Exitosas      = $respuestasGateway.Count
                Intentos      = 4
                PromedioMs    = if ($respuestasGateway.Count -gt 0) {
                    [Math]::Round(($respuestasGateway | Measure-Object ResponseTime -Average).Average, 2)
                }
                else {
                    $null
                }
                Detalle       = 'ICMP'
            })
        }

        $resolucionUnivalle = @(Resolve-DnsName 'www.univalle.edu.co' -DnsOnly `
            -ErrorAction SilentlyContinue)
        $pruebasRed.Add([pscustomobject]@{
            Prueba     = 'Resolución DNS institucional'
            Destino    = 'www.univalle.edu.co'
            Exitosas   = @($resolucionUnivalle).Count
            Intentos   = 1
            PromedioMs = $null
            Detalle    = ($resolucionUnivalle.IPAddress | Where-Object { $_ }) -join ', '
        })
        $pruebasRed |
            Export-Csv (Join-Path $carpeta 'pruebas-red.csv') -NoTypeInformation -Encoding UTF8
    }
    catch {
        Registrar-ErrorAuditoria 'Pruebas de red' $_.Exception.Message
    }
}

$recursosCompartidos = @()
try {
    $recursosCompartidos = @(Get-SmbShare |
        Select-Object Name, Path, Description, ScopeName, EncryptData,
            FolderEnumerationMode, Special)
    $recursosCompartidos |
        Export-Csv (Join-Path $carpeta 'recursos-compartidos.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Recursos compartidos SMB' $_.Exception.Message
}

$cuentasLocales = @()
try {
    $cuentasLocales = @(Get-LocalUser |
        Select-Object Name, Enabled, LastLogon, PasswordRequired,
            PasswordExpires, UserMayChangePassword)
    $cuentasLocales |
        Export-Csv (Join-Path $carpeta 'cuentas-locales.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Cuentas locales' $_.Exception.Message
}

$certificadosProximos = @()
try {
    $limiteCertificado = (Get-Date).AddDays($DiasAvisoCertificado)
    $certificadosProximos = @(
        Get-ChildItem Cert:\LocalMachine\My, Cert:\CurrentUser\My -ErrorAction SilentlyContinue |
            Where-Object NotAfter -le $limiteCertificado |
            Select-Object Subject, Issuer, Thumbprint, NotBefore, NotAfter,
                @{ Name = 'DiasRestantes'; Expression = { [Math]::Floor(($_.NotAfter - (Get-Date)).TotalDays) } },
                PSParentPath
    )
    $certificadosProximos |
        Export-Csv (Join-Path $carpeta 'certificados-proximos-vencer.csv') -NoTypeInformation -Encoding UTF8
}
catch {
    Registrar-ErrorAuditoria 'Certificados digitales' $_.Exception.Message
}

$actualizacionesPendientes = @()
$tareasProgramadas = @()
$hardware = @()
$confiabilidadDiscos = @()
$registrosConfiabilidad = @()
if ($Modo -eq 'Completo') {
    try {
        $sesionActualizacion = New-Object -ComObject Microsoft.Update.Session
        $buscadorActualizacion = $sesionActualizacion.CreateUpdateSearcher()
        $resultadoActualizacion = $buscadorActualizacion.Search('IsInstalled=0 and IsHidden=0')
        for ($indice = 0; $indice -lt $resultadoActualizacion.Updates.Count; $indice++) {
            $actualizacion = $resultadoActualizacion.Updates.Item($indice)
            $actualizacionesPendientes += [pscustomobject]@{
                Titulo       = $actualizacion.Title
                KB           = ($actualizacion.KBArticleIDs -join ', ')
                Severidad    = $actualizacion.MsrcSeverity
                Reinicio     = $actualizacion.RebootRequired
                Descargada   = $actualizacion.IsDownloaded
            }
        }
        $actualizacionesPendientes |
            Export-Csv (Join-Path $carpeta 'actualizaciones-pendientes.csv') -NoTypeInformation -Encoding UTF8
    }
    catch {
        Registrar-ErrorAuditoria 'Búsqueda de actualizaciones pendientes' $_.Exception.Message
    }

    try {
        $tareasProgramadas = @(Get-ScheduledTask |
            Where-Object TaskPath -NotLike '\Microsoft\*' |
            ForEach-Object {
                $informacionTarea = $_ | Get-ScheduledTaskInfo
                [pscustomobject]@{
                    Nombre        = $_.TaskName
                    Ruta          = $_.TaskPath
                    Estado        = $_.State
                    Autor         = $_.Author
                    Acciones      = ($_.Actions.Execute -join '; ')
                    Argumentos    = ($_.Actions.Arguments -join '; ')
                    UltimaEjecucion = $informacionTarea.LastRunTime
                    UltimoResultado = $informacionTarea.LastTaskResult
                    ProximaEjecucion = $informacionTarea.NextRunTime
                }
            })
        $tareasProgramadas |
            Export-Csv (Join-Path $carpeta 'tareas-programadas-no-microsoft.csv') -NoTypeInformation -Encoding UTF8
    }
    catch {
        Registrar-ErrorAuditoria 'Tareas programadas' $_.Exception.Message
    }

    try {
        $bios = Get-CimInstance Win32_BIOS
        $baterias = @(Get-CimInstance Win32_Battery)
        $memorias = @(Get-CimInstance Win32_PhysicalMemory)
        $hardware = @(
            [pscustomobject]@{
                Tipo    = 'BIOS'
                Nombre  = $bios.Manufacturer
                Detalle = "Versión=$($bios.SMBIOSBIOSVersion); fecha=$($bios.ReleaseDate); serie=$($bios.SerialNumber)"
            }
        )
        foreach ($bateria in $baterias) {
            $hardware += [pscustomobject]@{
                Tipo    = 'Batería'
                Nombre  = $bateria.Name
                Detalle = "Estado=$($bateria.Status); carga=$($bateria.EstimatedChargeRemaining)%; autonomía=$($bateria.EstimatedRunTime) min"
            }
        }
        foreach ($memoria in $memorias) {
            $hardware += [pscustomobject]@{
                Tipo    = 'Memoria'
                Nombre  = $memoria.DeviceLocator
                Detalle = "Capacidad=$([Math]::Round($memoria.Capacity / 1GB, 2)) GB; velocidad=$($memoria.Speed) MHz; fabricante=$($memoria.Manufacturer)"
            }
        }
        $hardware |
            Export-Csv (Join-Path $carpeta 'hardware.csv') -NoTypeInformation -Encoding UTF8
    }
    catch {
        Registrar-ErrorAuditoria 'Inventario de hardware' $_.Exception.Message
    }

    try {
        $confiabilidadDiscos = @(Get-PhysicalDisk | ForEach-Object {
            $disco = $_
            $contador = $_ | Get-StorageReliabilityCounter
            [pscustomobject]@{
                Disco                  = $disco.FriendlyName
                TemperaturaC           = $contador.Temperature
                TemperaturaMaximaC     = $contador.TemperatureMax
                HorasEncendido         = $contador.PowerOnHours
                ErroresLectura         = $contador.ReadErrorsTotal
                ErroresEscritura       = $contador.WriteErrorsTotal
                DesgastePorcentaje     = $contador.Wear
            }
        })
        $confiabilidadDiscos |
            Export-Csv (Join-Path $carpeta 'smart-discos.csv') -NoTypeInformation -Encoding UTF8
    }
    catch {
        Registrar-ErrorAuditoria 'SMART y confiabilidad de discos' $_.Exception.Message
    }

    try {
        $registrosConfiabilidad = @(Get-CimInstance Win32_ReliabilityRecords |
            Where-Object TimeGenerated -ge $inicioEventos |
            Select-Object TimeGenerated, SourceName, ProductName, EventIdentifier,
                Message |
            Sort-Object TimeGenerated -Descending)
        $registrosConfiabilidad |
            Export-Csv (Join-Path $carpeta 'historial-confiabilidad.csv') -NoTypeInformation -Encoding UTF8
    }
    catch {
        Registrar-ErrorAuditoria 'Historial de confiabilidad' $_.Exception.Message
    }
}

$resumenRendimiento = @()
if ($rendimiento.Count -gt 0) {
    $cpu = $rendimiento | Measure-Object CpuPorcentaje -Average -Maximum
    $memoria = $rendimiento | Measure-Object MemoriaUsadaPct -Average -Maximum
    $resumenRendimiento = @([pscustomobject]@{
        CpuPromedioPct     = [Math]::Round($cpu.Average, 2)
        CpuMaximoPct       = [Math]::Round($cpu.Maximum, 2)
        MemoriaPromedioPct = [Math]::Round($memoria.Average, 2)
        MemoriaMaximaPct   = [Math]::Round($memoria.Maximum, 2)
        Muestras           = $rendimiento.Count
    })
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Rendimiento'
        Control   = 'Uso promedio de CPU'
        Resultado = if ($cpu.Average -lt 85) { 'Cumple' } else { 'Revisar' }
        Detalle   = "Promedio=$([Math]::Round($cpu.Average, 2))%; máximo=$([Math]::Round($cpu.Maximum, 2))%."
    })
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Rendimiento'
        Control   = 'Uso promedio de memoria'
        Resultado = if ($memoria.Average -lt 90) { 'Cumple' } else { 'Revisar' }
        Detalle   = "Promedio=$([Math]::Round($memoria.Average, 2))%; máximo=$([Math]::Round($memoria.Maximum, 2))%."
    })
}

if ($volcadosSistema.Count -gt 0) {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Estabilidad'
        Control   = 'Volcados de fallos recientes'
        Resultado = 'Revisar'
        Detalle   = "$($volcadosSistema.Count) archivo(s) de volcado durante el periodo consultado."
    })
}

if ($pruebasRed.Count -gt 0) {
    foreach ($pruebaRed in $pruebasRed) {
        $controlesSeguridad.Add([pscustomobject]@{
            Area      = 'Red'
            Control   = $pruebaRed.Prueba
            Resultado = if ($pruebaRed.Exitosas -gt 0) { 'Cumple' } else { 'Revisar' }
            Detalle   = "Destino=$($pruebaRed.Destino); respuestas=$($pruebaRed.Exitosas)/$($pruebaRed.Intentos); promedio=$($pruebaRed.PromedioMs) ms."
        })
    }
}

if ($actualizacionesPendientes.Count -gt 0) {
    $criticasPendientes = @($actualizacionesPendientes |
        Where-Object Severidad -Match 'Critical|Important').Count
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Actualizaciones'
        Control   = 'Actualizaciones pendientes'
        Resultado = if ($criticasPendientes -gt 0) { 'Revisar' } else { 'Informativo' }
        Detalle   = "Pendientes=$($actualizacionesPendientes.Count); críticas/importantes=$criticasPendientes."
    })
}

$certificadosVencidos = @($certificadosProximos | Where-Object DiasRestantes -lt 0)
if ($certificadosVencidos.Count -gt 0) {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Certificados'
        Control   = 'Certificados personales vencidos'
        Resultado = 'Revisar'
        Detalle   = "$($certificadosVencidos.Count) certificado(s) vencidos en los almacenes personales consultados."
    })
}

$cuentasSinContrasena = @($cuentasLocales |
    Where-Object { $_.Enabled -and -not $_.PasswordRequired })
if ($cuentasSinContrasena.Count -gt 0) {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Cuentas'
        Control   = 'Cuentas locales sin contraseña requerida'
        Resultado = 'Revisar'
        Detalle   = ($cuentasSinContrasena.Name -join ', ')
    })
}

$discosConErrores = @($confiabilidadDiscos | Where-Object {
    ($null -ne $_.ErroresLectura -and $_.ErroresLectura -gt 0) -or
    ($null -ne $_.ErroresEscritura -and $_.ErroresEscritura -gt 0)
})
if ($discosConErrores.Count -gt 0) {
    $controlesSeguridad.Add([pscustomobject]@{
        Area      = 'Almacenamiento'
        Control   = 'Contadores SMART con errores'
        Resultado = 'Revisar'
        Detalle   = ($discosConErrores.Disco -join ', ')
    })
}

$verificacionSistema = New-Object 'System.Collections.Generic.List[object]'
if ($IncluirVerificacionSistema) {
    $salidaDism = Join-Path $carpeta 'dism-scanhealth.txt'
    & dism.exe /Online /Cleanup-Image /ScanHealth 2>&1 |
        Out-File $salidaDism -Encoding utf8
    $verificacionSistema.Add([pscustomobject]@{
        Herramienta = 'DISM ScanHealth'
        Codigo      = $LASTEXITCODE
        Evidencia   = $salidaDism
    })

    $salidaSfc = Join-Path $carpeta 'sfc-verifyonly.txt'
    & sfc.exe /verifyonly 2>&1 |
        Out-File $salidaSfc -Encoding utf8
    $verificacionSistema.Add([pscustomobject]@{
        Herramienta = 'SFC VerifyOnly'
        Codigo      = $LASTEXITCODE
        Evidencia   = $salidaSfc
    })

    foreach ($verificacion in $verificacionSistema) {
        $controlesSeguridad.Add([pscustomobject]@{
            Area      = 'Integridad del sistema'
            Control   = $verificacion.Herramienta
            Resultado = if ($verificacion.Codigo -eq 0) { 'Cumple' } else { 'Revisar' }
            Detalle   = "Código de salida=$($verificacion.Codigo); evidencia=$($verificacion.Evidencia)"
        })
    }
}
$controlesSeguridad |
    Export-Csv (Join-Path $carpeta 'controles-seguridad.csv') -NoTypeInformation -Encoding UTF8

$resumenProcesos = @($conexiones |
    Where-Object { $_.Estado -ne 'Listen' -and $_.IPRemota -notin @('0.0.0.0', '::') } |
    Group-Object Proceso, PID |
    ForEach-Object {
        $grupo = @($_.Group)
        $maxConcurrentes = ($grupo | Group-Object Muestra | Measure-Object Count -Maximum).Maximum
        [pscustomobject]@{
            Proceso                = $grupo[0].Proceso
            PID                    = $grupo[0].PID
            Observaciones          = $grupo.Count
            DestinosUnicos         = @($grupo.IPRemota | Sort-Object -Unique).Count
            DestinosPublicosUnicos = @($grupo | Where-Object DestinoPublico | Select-Object -ExpandProperty IPRemota -Unique).Count
            PuertosRemotosUnicos   = @($grupo.PuertoRemoto | Sort-Object -Unique).Count
            MaximoConcurrentes     = $maxConcurrentes
        }
    } |
    Sort-Object DestinosPublicosUnicos, MaximoConcurrentes -Descending)

$puertosEscucha = @($conexiones |
    Where-Object Estado -eq 'Listen' |
    Group-Object Proceso, PID, IPLocal, PuertoLocal |
    ForEach-Object {
        [pscustomobject]@{
            Proceso     = $_.Group[0].Proceso
            PID         = $_.Group[0].PID
            IPLocal     = $_.Group[0].IPLocal
            PuertoLocal = $_.Group[0].PuertoLocal
        }
    } |
    Sort-Object PuertoLocal, Proceso)
$puertosEscucha |
    Export-Csv (Join-Path $carpeta 'puertos-en-escucha.csv') -NoTypeInformation -Encoding UTF8

$resumenChrome = @($conexiones |
    Where-Object {
        $_.Proceso -eq 'chrome' -and
        $_.Estado -ne 'Listen' -and
        $_.IPRemota -notin @('0.0.0.0', '::')
    } |
    Group-Object IPRemota, PuertoRemoto |
    ForEach-Object {
        [pscustomobject]@{
            IPRemota       = $_.Group[0].IPRemota
            PuertoRemoto   = $_.Group[0].PuertoRemoto
            DestinoPublico = $_.Group[0].DestinoPublico
            Observaciones  = $_.Count
            Estados        = ($_.Group.Estado | Sort-Object -Unique) -join ', '
        }
    } |
    Sort-Object Observaciones -Descending)
$resumenChrome |
    Export-Csv (Join-Path $carpeta 'conexiones-chrome-resumen.csv') -NoTypeInformation -Encoding UTF8

$indicadores = New-Object 'System.Collections.Generic.List[object]'
foreach ($control in @($controlesSeguridad | Where-Object Resultado -eq 'Revisar')) {
    $indicadores.Add([pscustomobject]@{
        Severidad = 'Revisar'
        Proceso   = $control.Area
        PID       = '-'
        Indicador = $control.Control
        Valor     = $control.Detalle
        Umbral    = 'Política institucional'
    })
}
foreach ($item in $resumenProcesos) {
    if ($item.DestinosPublicosUnicos -ge $UmbralDestinosUnicos) {
        $indicadores.Add([pscustomobject]@{
            Severidad = 'Revisar'
            Proceso   = $item.Proceso
            PID       = $item.PID
            Indicador = 'Cantidad elevada de destinos públicos únicos'
            Valor     = $item.DestinosPublicosUnicos
            Umbral    = $UmbralDestinosUnicos
        })
    }
    if ($item.MaximoConcurrentes -ge $UmbralConexionesConcurrentes) {
        $indicadores.Add([pscustomobject]@{
            Severidad = 'Revisar'
            Proceso   = $item.Proceso
            PID       = $item.PID
            Indicador = 'Cantidad elevada de conexiones TCP concurrentes'
            Valor     = $item.MaximoConcurrentes
            Umbral    = $UmbralConexionesConcurrentes
        })
    }
}

$synPorProceso = @($conexiones |
    Where-Object { $_.Estado -eq 'SynSent' } |
    Group-Object Proceso, PID |
    ForEach-Object {
        [pscustomobject]@{
            Proceso = $_.Group[0].Proceso
            PID     = $_.Group[0].PID
            Total   = $_.Count
        }
    })

foreach ($syn in $synPorProceso) {
    if ($syn.Total -ge $UmbralSynPendientes) {
        $indicadores.Add([pscustomobject]@{
            Severidad = 'Revisar'
            Proceso   = $syn.Proceso
            PID       = $syn.PID
            Indicador = 'Observaciones repetidas de conexiones en estado SYN-SENT'
            Valor     = $syn.Total
            Umbral    = $UmbralSynPendientes
        })
    }
}

foreach ($amenaza in $amenazas) {
    $indicadores.Add([pscustomobject]@{
        Severidad = 'Alta'
        Proceso   = 'Microsoft Defender'
        PID       = '-'
        Indicador = "Amenaza detectada: ID $($amenaza.ThreatID)"
        Valor     = $amenaza.InitialDetectionTime
        Umbral    = 'Cualquier detección'
    })
}

$metadatos = [pscustomobject]@{
    Equipo                         = $env:COMPUTERNAME
    Usuario                        = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Modo                           = $Modo
    Inicio                         = $inicio
    Fin                            = $fin
    DuracionSolicitadaMinutos      = $DuracionMinutos
    IntervaloSegundos              = $IntervaloSegundos
    NumeroMuestras                 = ($conexiones | Select-Object -ExpandProperty Muestra -Unique).Count
    UmbralDestinosPublicosUnicos   = $UmbralDestinosUnicos
    UmbralConexionesConcurrentes   = $UmbralConexionesConcurrentes
    UmbralObservacionesSynSent     = $UmbralSynPendientes
    BytesCapturadosPorPaquete      = $BytesPorPaquete
    DiasAntiguedadTemporales       = $DiasTemporalAntiguo
    DiasHistorialEventos           = $DiasEventos
    DiasAvisoCertificado           = $DiasAvisoCertificado
    CapturaPktmonSolicitada        = -not $SinCapturaPktmon
    CapturaPcapngDisponible        = Test-Path $archivoPcapng
    VerificacionSfcDismSolicitada  = [bool]$IncluirVerificacionSistema
    LimpiezaTemporalesSolicitada   = [bool]$EliminarTemporales
}
$metadatos | ConvertTo-Json | Out-File (Join-Path $carpeta 'metadatos.json') -Encoding utf8

$conclusion = if ($indicadores.Count -eq 0) {
    'No se superaron los umbrales automáticos durante el periodo observado. Esto no descarta actividad anómala fuera de la ventana de captura.'
}
else {
    "Se generaron $($indicadores.Count) indicadores que requieren revisión. Los hallazgos de red deben correlacionarse con FortiGate/FortiNAC."
}

$estilo = @'
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 32px; color: #1f2937; }
h1, h2 { color: #17365d; }
table { border-collapse: collapse; width: 100%; margin-bottom: 24px; }
th, td { border: 1px solid #cbd5e1; padding: 6px; text-align: left; }
th { background: #e2e8f0; }
.nota { background: #fff7d6; border-left: 4px solid #d69e2e; padding: 12px; }
.conclusion { background: #edf7ed; border-left: 4px solid #2e7d32; padding: 12px; }
</style>
'@

$contenido = @(
    '<h1>Informe de soporte</h1>'
    "<p class='conclusion'><strong>Resultado:</strong> $conclusion</p>"
    "<p class='nota'><strong>Alcance:</strong> los indicadores se basan en conexiones visibles desde el equipo y no constituyen por sí solos una confirmación de incidente. Deben correlacionarse por fecha, IP, MAC, puerto y aplicación con los registros institucionales de Fortinet.</p>"
    "<p class='nota'><strong>Chrome:</strong> las extensiones corresponden al perfil de Windows que ejecutó el script. Una cantidad alta de conexiones de Chrome puede ser normal por pestañas, extensiones y redes CDN; debe contrastarse con los destinos y eventos del firewall.</p>"
    $(if ($EliminarTemporales) {
        "<p class='nota'><strong>Temporales:</strong> se solicitó eliminar únicamente archivos con más de $DiasTemporalAntiguo días dentro de las rutas temporales inventariadas. No se eliminan carpetas ni se siguen enlaces.</p>"
    }
    else {
        "<p class='nota'><strong>Temporales:</strong> el script únicamente cuenta y mide archivos; no elimina ni modifica contenido.</p>"
    })
    (Convertir-FragmentoHtml @($metadatos) 'Datos de la auditoría')
    (Convertir-FragmentoHtml @($sistemaOperativo) 'Sistema operativo')
    (Convertir-FragmentoHtml ($indicadores.ToArray()) 'Indicadores que requieren revisión' 'No se detectaron indicadores que superaran los umbrales configurados.')
    (Convertir-FragmentoHtml ($controlesSeguridad.ToArray()) 'Diagnóstico de seguridad de Windows')
    (Convertir-FragmentoHtml @($temporales) "Archivos temporales antes de la limpieza (antiguos: más de $DiasTemporalAntiguo días)")
    (Convertir-FragmentoHtml @($limpiezaTemporales) 'Resultado de la limpieza de temporales' 'No se solicitó eliminar archivos temporales.')
    (Convertir-FragmentoHtml @($temporalesDespues) 'Archivos temporales después de la limpieza' 'No se solicitó eliminar archivos temporales.')
    (Convertir-FragmentoHtml @($volumenes) 'Capacidad de almacenamiento')
    (Convertir-FragmentoHtml @($discosFisicos) 'Estado de discos físicos')
    (Convertir-FragmentoHtml @($controladoresProblema) 'Dispositivos y controladores con problemas' 'No se encontraron dispositivos con códigos de error activos.')
    (Convertir-FragmentoHtml @($eventosControladores | Select-Object -First 100) 'Eventos recientes de controladores' 'No se encontraron eventos de controladores en el periodo consultado.')
    (Convertir-FragmentoHtml @($impresoras) 'Impresoras instaladas' 'No se encontraron impresoras instaladas.')
    (Convertir-FragmentoHtml ($impresorasRed.ToArray()) 'Estado y diagnóstico de impresoras de red' 'No se detectaron impresoras de red instaladas o no hay puertos de red asociados.')
    (Convertir-FragmentoHtml @($servicioImpresion) 'Estado del servicio de impresión')
    (Convertir-FragmentoHtml @($resultadoLimpiezaSpooler) 'Resultado de la liberación de la cola de impresión' 'No se solicitó reiniciar o liberar la cola de impresión.')
    (Convertir-FragmentoHtml @($trabajosImpresion) 'Trabajos en las colas de impresión' 'No hay trabajos pendientes.')
    (Convertir-FragmentoHtml @($eventosImpresion | Select-Object -First 100) 'Eventos recientes de impresión' 'No se encontraron eventos de impresión en el periodo consultado.')
    (Convertir-FragmentoHtml @($licenciasMicrosoft) 'Licencias Microsoft publicadas por Windows' 'No se encontraron productos Microsoft con clave parcial registrada.')
    (Convertir-FragmentoHtml @($softwareInstalado) 'Inventario de software instalado')
    "<p class='nota'><strong>Licencias de terceros:</strong> Windows no publica un estado de licencia universal para todo el software. El inventario no demuestra que Kaspersky, Chrome u otros productos estén licenciados; deben comprobarse en la consola o portal de cada fabricante.</p>"
    (Convertir-FragmentoHtml @($actualizaciones | Select-Object -First 30) 'Actualizaciones instaladas recientemente')
    (Convertir-FragmentoHtml @($actualizacionesPendientes) 'Actualizaciones pendientes' 'No se encontraron actualizaciones pendientes o el modo seleccionado no realiza esta búsqueda.')
    (Convertir-FragmentoHtml @($resumenRendimiento) 'Resumen de rendimiento')
    (Convertir-FragmentoHtml @($procesosConsumo) 'Procesos con mayor consumo de memoria')
    (Convertir-FragmentoHtml @($volcadosSistema) 'Volcados de fallos recientes' 'No se encontraron volcados recientes.')
    (Convertir-FragmentoHtml @($eventosAplicaciones | Select-Object -First 100) 'Fallos recientes de aplicaciones' 'No se encontraron eventos recientes de fallos de aplicaciones.')
    (Convertir-FragmentoHtml @($registrosConfiabilidad | Select-Object -First 100) 'Historial de confiabilidad' 'No se recopiló historial de confiabilidad o no hubo registros.')
    (Convertir-FragmentoHtml @($confiabilidadDiscos) 'SMART y confiabilidad de discos' 'El dispositivo no publicó contadores SMART o el modo seleccionado no los consulta.')
    (Convertir-FragmentoHtml @($hardware) 'Inventario de hardware avanzado' 'El modo seleccionado no recopila el inventario avanzado.')
    (Convertir-FragmentoHtml @($equipoDominio) 'Equipo y pertenencia al dominio')
    (Convertir-FragmentoHtml ($pruebasRed.ToArray()) 'Pruebas de conectividad y DNS' 'El modo seleccionado no ejecuta pruebas activas de red.')
    (Convertir-FragmentoHtml @($adaptadoresRed) 'Adaptadores de red')
    (Convertir-FragmentoHtml @($certificadosProximos) "Certificados personales vencidos o próximos a vencer en $DiasAvisoCertificado días" 'No se encontraron certificados dentro del periodo de aviso.')
    (Convertir-FragmentoHtml @($cuentasLocales) 'Cuentas locales')
    (Convertir-FragmentoHtml @($recursosCompartidos) 'Recursos compartidos SMB')
    (Convertir-FragmentoHtml @($tareasProgramadas) 'Tareas programadas no pertenecientes a Microsoft' 'El modo seleccionado no recopila tareas o no se encontraron.')
    (Convertir-FragmentoHtml @($administradoresLocales) 'Administradores locales')
    (Convertir-FragmentoHtml @($serviciosAutomaticosDetenidos) 'Servicios automáticos detenidos' 'No se encontraron servicios automáticos detenidos.')
    (Convertir-FragmentoHtml @($inicioWindows) 'Programas configurados para iniciar con Windows' 'No se encontraron programas de inicio.')
    (Convertir-FragmentoHtml @($eventosSistema | Select-Object -First 100) "Errores críticos de los últimos $DiasEventos días" 'No se encontraron errores críticos en el periodo consultado.')
    (Convertir-FragmentoHtml ($verificacionSistema.ToArray()) 'Verificación de integridad DISM/SFC' 'No se solicitó la verificación opcional DISM/SFC.')
    (Convertir-FragmentoHtml @($resumenProcesos | Select-Object -First 50) 'Resumen de conexiones por proceso')
    (Convertir-FragmentoHtml @($puertosEscucha) 'Puertos TCP en escucha')
    (Convertir-FragmentoHtml @($resumenChrome | Select-Object -First 100) 'Principales conexiones de Google Chrome' 'No se observaron conexiones de Chrome durante la auditoría.')
    (Convertir-FragmentoHtml ($versionesChrome.ToArray()) 'Versiones instaladas de Google Chrome' 'No se encontró una instalación estándar de Google Chrome.')
    (Convertir-FragmentoHtml ($extensionesChrome.ToArray()) 'Extensiones instaladas en Google Chrome' 'No se encontraron extensiones en los perfiles del usuario que ejecutó la auditoría.')
    (Convertir-FragmentoHtml ($politicasChrome.ToArray()) 'Políticas aplicadas a Google Chrome' 'No se encontraron políticas de Chrome en HKLM o HKCU.')
    (Convertir-FragmentoHtml @($productosAntivirus) 'Productos antivirus registrados en Windows' 'Windows Security Center no reportó productos antivirus.')
    (Convertir-FragmentoHtml @($componentesKaspersky) 'Servicios de Kaspersky' 'No se encontraron servicios de Kaspersky.')
    (Convertir-FragmentoHtml @($eventosKaspersky | Select-Object -First 100) 'Eventos de Kaspersky durante la auditoría' 'No se encontraron eventos de Kaspersky en los registros disponibles.')
    (Convertir-FragmentoHtml @($amenazas) 'Detecciones de Microsoft Defender' 'No se encontraron detecciones de Defender dentro del periodo auditado.')
    (Convertir-FragmentoHtml ($errores.ToArray()) 'Limitaciones y errores de recopilación' 'No se registraron errores de recopilación.')
    '<h2>Evidencias</h2>'
    '<p>La carpeta contiene conexiones.csv, estadísticas de interfaces, caché DNS, configuración de red y, cuando Windows lo permite, captura ETL/PCAPNG. El archivo hashes-sha256.csv permite comprobar su integridad.</p>'
) -join "`r`n"

$archivoInforme = Join-Path $carpeta 'informe-de-soporte.html'
Write-Etapa 'Generando el informe y calculando hashes de evidencias...'
ConvertTo-Html -Title 'Informe de soporte' -Head $estilo -Body $contenido |
    Out-File $archivoInforme -Encoding utf8

$errores |
    Export-Csv (Join-Path $carpeta 'errores-recopilacion.csv') -NoTypeInformation -Encoding UTF8
$hashes = @(Get-ChildItem $carpeta -File |
    Where-Object Name -ne 'hashes-sha256.csv' |
    Get-FileHash -Algorithm SHA256 |
    Select-Object Path, Algorithm, Hash)
$hashes | Export-Csv (Join-Path $carpeta 'hashes-sha256.csv') -NoTypeInformation -Encoding UTF8

Write-Host "Auditoría finalizada. Informe: $archivoInforme" -ForegroundColor Green
Write-Host "Indicadores para revisión: $($indicadores.Count)"
Finalizar-InformeYLimpiar -RutaInforme $archivoInforme -CarpetaAuditoria $carpeta -AutoEliminar $AutoEliminarAlCerrar -AbrirReporte (-not $NoAutoAbrirReporte)
