#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$destino = Join-Path $env:LOCALAPPDATA 'SoportePC'
$repoRawBase = 'https://raw.githubusercontent.com/ldadev/mobley_support/main'

$archivos = @(
    [pscustomobject]@{
        Nombre = 'Auditar-Trafico.ps1'
        Url    = "$repoRawBase/scripts/Auditar-Trafico.ps1"
    },
    [pscustomobject]@{
        Nombre = 'Menu-Soporte.ps1'
        Url    = "$repoRawBase/scripts/Menu-Soporte.ps1"
    },
    [pscustomobject]@{
        Nombre = 'Ejecutar-Soporte.cmd'
        Url    = "$repoRawBase/scripts/Ejecutar-Soporte.cmd"
    }
)

New-Item -ItemType Directory -Path $destino -Force | Out-Null

foreach ($archivo in $archivos) {
    $url = $archivo.Url
    $ruta = Join-Path $destino $archivo.Nombre

    Write-Host "Descargando $($archivo.Nombre) desde GitHub..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $ruta -UseBasicParsing

    if (-not (Test-Path $ruta) -or (Get-Item $ruta).Length -eq 0) {
        throw "GitHub no entregó correctamente $($archivo.Nombre)."
    }

    $inicioArchivo = Get-Content $ruta -TotalCount 5 -ErrorAction Stop
    if (($inicioArchivo -join ' ') -match '<!DOCTYPE|<html|404: Not Found') {
        Remove-Item -LiteralPath $ruta -Force
        throw "GitHub devolvió un error o página web en lugar de $($archivo.Nombre). Verifique la URL raw."
    }
}

$scriptAuditoria = Join-Path $destino 'Auditar-Trafico.ps1'
$erroresSintaxis = $null
$tokens = $null
[void][Management.Automation.Language.Parser]::ParseFile(
    $scriptAuditoria,
    [ref]$tokens,
    [ref]$erroresSintaxis
)
if ($erroresSintaxis.Count -gt 0) {
    $primerError = $erroresSintaxis[0]
    throw "El script descargado contiene errores de sintaxis en línea $($primerError.Extent.StartLineNumber), columna $($primerError.Extent.StartColumnNumber): $($primerError.Message)"
}

$lanzador = Join-Path $destino 'Ejecutar-Soporte.cmd'
Write-Host "Descarga finalizada en $destino" -ForegroundColor Green
Write-Host 'Abriendo el menú de soporte...' -ForegroundColor Cyan
Start-Process -FilePath $lanzador
