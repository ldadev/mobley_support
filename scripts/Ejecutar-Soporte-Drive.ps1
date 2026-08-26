#requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$destino = Join-Path $env:LOCALAPPDATA 'SoportePC'
$archivos = @(
    [pscustomobject]@{
        Nombre = 'Auditar-Trafico.ps1'
        Id     = '10yeyeR9YoG6xZniVF4jlVPPAEz94Bzrc'
    },
    [pscustomobject]@{
        Nombre = 'Ejecutar-Soporte.cmd'
        Id     = '1RFpVdLPb7TYv7fD6F6c0u7lg0W5z5rWG'
    }
)

New-Item -ItemType Directory -Path $destino -Force | Out-Null

foreach ($archivo in $archivos) {
    $url = "https://drive.usercontent.google.com/download?id=$($archivo.Id)&export=download&confirm=t"
    $ruta = Join-Path $destino $archivo.Nombre

    Write-Host "Descargando $($archivo.Nombre)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $ruta -UseBasicParsing

    if (-not (Test-Path $ruta) -or (Get-Item $ruta).Length -eq 0) {
        throw "Google Drive no entregó correctamente $($archivo.Nombre)."
    }

    $inicioArchivo = Get-Content $ruta -TotalCount 5 -ErrorAction Stop
    if (($inicioArchivo -join ' ') -match '<!DOCTYPE|<html|accounts\.google\.com') {
        Remove-Item -LiteralPath $ruta -Force
        throw "Google Drive devolvió una página web en lugar de $($archivo.Nombre). Verifique que el enlace sea público."
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
    throw "El script descargado contiene errores de sintaxis: $($erroresSintaxis[0].Message)"
}

$lanzador = Join-Path $destino 'Ejecutar-Soporte.cmd'
Write-Host "Descarga finalizada en $destino" -ForegroundColor Green
Write-Host 'Abriendo el menú de soporte...' -ForegroundColor Cyan
Start-Process -FilePath $lanzador
