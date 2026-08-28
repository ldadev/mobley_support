```text
												 .-""""-.
											 .'  .--.  '.
											/   /    \   \
										 |   |  ()  |   |
										 |   | .--. |   |
											\   \____/   /
											 '.        .'
												 '-.__.-'

	__  __  ____  ____  _____  _______   __  _______  ____  ____
 |  \/  |/ __ \|  _ \| ____| |__   __| |  \/  | ____|/ ___||  _ \
 | |\/| | |  | | |_) | |__      | |    | |\/| |  _|  \___ \| | | |
 | |  | | |__| |  _ <|___ \     | |    | |  | | |___  ___) | |_| |
 |_|  |_|\____/|_| \_\_____|    |_|    |_|  |_|_____| |____/|____/
												 T O O L K I T
```

# Mobley Toolkit

Toolkit Mobley de diagnóstico y soporte para equipos con Windows 10/11. Reúne
información de red, procesos, servicios, hardware, eventos y almacenamiento,
y genera un informe HTML con evidencias complementarias.

## Requisitos

- Windows PowerShell 5.1 o superior.
- Ejecutar como administrador.
- Para el modo de red, permitir el tiempo necesario para el muestreo.
- Cerrar Chrome antes de usar el modo de limpieza para reducir archivos bloqueados.

## Comandos de PowerShell

### Opción recomendada: menú de soporte

Si ya tienes los archivos del proyecto en el equipo, abre PowerShell en la
carpeta `scripts` y ejecuta:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Menu-Soporte.ps1"
```

También puedes ejecutar `Ejecutar-Soporte.cmd` con doble clic. El lanzador
solicita permisos de administrador y abre el menú interactivo.

### Ejecución directa del diagnóstico

Desde la carpeta `scripts`:

```powershell
.\Auditar-Trafico.ps1 -Modo Rapido
.\Auditar-Trafico.ps1 -Modo Red -DuracionMinutos 60
.\Auditar-Trafico.ps1 -Modo Completo -IncluirVerificacionSistema
.\Auditar-Trafico.ps1 -Modo Limpieza -DiasTemporalAntiguo 30
```

También se puede llamar explícitamente con PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Auditar-Trafico.ps1" -Modo Rapido
```

### Descargar y ejecutar desde GitHub

Abre PowerShell y ejecuta:

```powershell
irm "https://raw.githubusercontent.com/ldadev/mobley_support/main/scripts/Ejecutar-Soporte-GitHub.ps1" | iex
```

El comando descarga los archivos actuales en:

```text
%LOCALAPPDATA%\SoportePC
```

> Los comandos `irm ... | iex` descargan y ejecutan contenido en memoria.
> Úsalos únicamente con las URLs oficiales y de confianza del proyecto.

## Modos disponibles

| Modo | Uso |
| --- | --- |
| `Rapido` | Diagnóstico general en aproximadamente cinco minutos. |
| `Completo` | Revisión extendida de seguridad, hardware, eventos, actualizaciones y software. |
| `Red` | Muestreo de tráfico, DNS, puerta de enlace, adaptadores y procesos. |
| `Limpieza` | Limpieza de temporales, caché de Chrome, DNS y Papelera de reciclaje. |

Acciones independientes disponibles en `Auditar-Trafico.ps1`:

```powershell
.\Auditar-Trafico.ps1 -LimpiarColaImpresion
.\Auditar-Trafico.ps1 -OptimizarSistema
.\Auditar-Trafico.ps1 -ActualizarWindows
.\Auditar-Trafico.ps1 -DesfragmentarDiscos
.\Auditar-Trafico.ps1 -MostrarLicencias
```

## Resultados

Por defecto, los resultados se guardan en:

```text
C:\AuditoriaRed\Auditoria-EQUIPO-FECHA
```

Cada auditoría puede incluir:

- `informe-de-soporte.html`: informe principal para revisión.
- Archivos CSV, registros de ejecución y evidencias técnicas.
- `hashes-sha256.csv`: manifiesto de integridad.
- Un paquete ZIP junto a la carpeta de evidencias.

Con `-AutoEliminarAlCerrar`, las evidencias temporales se guardan en `%TEMP%`
y se eliminan al cerrar; el paquete ZIP se conserva.

Para evitar que se abra el navegador automáticamente:

```powershell
.\Auditar-Trafico.ps1 -Modo Rapido -NoAutoAbrirReporte
```

## Archivos principales

- `scripts/Auditar-Trafico.ps1`: motor de diagnóstico y generación de informes.
- `scripts/Menu-Soporte.ps1`: menú interactivo.
- `scripts/Ejecutar-Soporte.cmd`: lanzador para Windows con elevación.
- `scripts/Ejecutar-Soporte-GitHub.ps1`: descarga desde GitHub.
- `Soporte-PC.exe`: lanzador ejecutable para usuarios que prefieren doble clic.

## Documentación adicional

- [Guía de uso](references/USAGE.md)
- [Enlaces de GitHub](references/github.txt)
- [Instrucciones del toolkit](SKILL.md)
