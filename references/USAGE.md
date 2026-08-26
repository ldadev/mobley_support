# Windows Support Toolkit

## End-user execution

Place these files together:

```text
Auditar-Trafico.ps1
Ejecutar-Soporte.cmd
```

Double-click `Ejecutar-Soporte.cmd` and select:

```text
1. Diagnostico rapido
2. Diagnostico completo
3. Auditoria de red
4. Limpieza de temporales
```

The launcher requests administrator privileges and leaves the console open so
errors remain visible.

## Direct PowerShell execution

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\Auditar-Trafico.ps1" -Modo Rapido
```

`ExecutionPolicy Bypass` applies only to that process. It does not permanently
change the machine policy.

## Current GitHub bootstrap

```powershell
irm "https://raw.githubusercontent.com/ldadev/mobley_support/main/scripts/Ejecutar-Soporte-GitHub.ps1" | iex
```

The bootstrap downloads the current PowerShell engine and CMD launcher from GitHub into:

```text
%LOCALAPPDATA%\SoportePC
```

## Current Google Drive bootstrap

```powershell
irm "https://drive.usercontent.google.com/download?id=1bjnSDTcG5xNiTndMOcVQKj8CqXnhqU3h&export=download&confirm=t" | iex
```

The bootstrap downloads the current PowerShell engine and CMD launcher into:

```text
%LOCALAPPDATA%\SoportePC
```

## Output

Reports and supporting CSV, text, ETL/PCAPNG, and hash evidence are written to:

```text
C:\AuditoriaRed\Auditoria-EQUIPO-FECHA
```

The primary report is:

```text
informe-de-soporte.html
```

## Operational notes

- Close Chrome before cleanup to reduce locked cache files.
- DISM and SFC can substantially extend complete-mode runtime.
- Kaspersky may be the active antivirus, so an empty Defender section is not
  automatically a problem.
- High Chrome connection counts can be normal because of tabs, extensions,
  QUIC, and content delivery networks.
- Third-party license status must be confirmed in the vendor console when
  Windows does not publish it.
