---
name: windows-support-diagnostic
description: Create, deploy, run, troubleshoot, and interpret the Windows 10 support diagnostic toolkit bundled with this skill. Use for integral PC diagnostics, unusual network traffic audits, safe temporary-file cleanup, Kaspersky/Chrome checks, driver and printer diagnostics, software inventory, or support report generation.
---

# Windows Support Diagnostic

Use the bundled toolkit to diagnose Windows 10 workstations without silently
changing system configuration.

## Bundled files

- `scripts/Auditar-Trafico.ps1`: diagnostic and reporting engine.
- `scripts/Ejecutar-Soporte.cmd`: elevated interactive launcher.
- `scripts/Ejecutar-Soporte-Drive.ps1`: Google Drive downloader and launcher.
- `scripts/Ejecutar-Soporte-GitHub.ps1`: GitHub downloader and launcher.
- `references/drive.txt`: current Drive links and direct execution command.
- `references/github.txt`: current GitHub links and direct execution command.
- `references/USAGE.md`: operating and deployment guide.

Keep the PowerShell script and CMD launcher in the same directory.

## Modes

Select the mode that matches the request:

- `Rapido`: five-minute sampling plus essential support checks.
- `Completo`: extended security, hardware, SMART, update, certificate,
  reliability, software, driver, printer, domain, and network checks.
- `Red`: timed traffic, DNS, gateway, adapter, process, and Fortinet-oriented
  evidence collection.
- `Limpieza`: no timed network audit; safely removes only old files from known
  temporary and Chrome cache locations.

Run directly when needed:

```powershell
.\Auditar-Trafico.ps1 -Modo Rapido
.\Auditar-Trafico.ps1 -Modo Red -DuracionMinutos 60
.\Auditar-Trafico.ps1 -Modo Completo -IncluirVerificacionSistema
.\Auditar-Trafico.ps1 -Modo Limpieza -DiasTemporalAntiguo 30
```

Prefer `Ejecutar-Soporte.cmd` for end users because it requests elevation,
shows a menu, preserves errors, and keeps the console open.

## Required behavior

1. Require Windows PowerShell 5.1 and administrator privileges.
2. Show stage messages and progress during long operations.
3. Write evidence under `C:\AuditoriaRed\Auditoria-EQUIPO-FECHA`.
4. Generate `informe-de-soporte.html` and `hashes-sha256.csv`.
5. Treat automatic findings as indicators requiring review, not proof of
   malware.
6. Correlate network findings with FortiGate/FortiNAC logs by timestamp, IP,
   MAC, destination, port, protocol, rule, and security event.
7. State that Windows cannot determine licensing for every third-party product.
8. Capture only packet headers by default to reduce exposure of personal data.

## Cleanup safety

Never delete downloads, documents, user profiles, arbitrary directories, or
files newer than `DiasTemporalAntiguo`.

The cleanup implementation must:

- Enumerate specific known temporary directories.
- Delete files individually by literal path.
- Reject paths outside the resolved temporary root.
- Skip reparse points and never recursively remove a directory.
- Count locked or inaccessible files as failures.
- Produce before/after measurements and an action summary.

## Troubleshooting

When the user supplies `errores.txt`:

1. Read the complete file.
2. Identify the first terminating error and its script line.
3. Fix the root cause without suppressing unrelated failures.
4. Preserve detailed error output in `Ejecutar-Soporte.cmd`.
5. Parse the updated script with a PowerShell parser before delivery.

Account for Windows PowerShell 5.1 behavior, especially native stderr,
`$ErrorActionPreference = 'Stop'`, generic lists, empty-array parameter
binding, COM objects, and cmdlet availability.

## Distribution

For Google Drive, use the IDs documented in `references/drive.txt`.
For GitHub (`https://github.com/ldadev/mobley_support.git`), use the URLs documented in `references/github.txt` or prefer raw URLs:

```text
https://raw.githubusercontent.com/ldadev/mobley_support/main/PATH/FILE
```

PowerShell direct execution command from GitHub:

```powershell
irm "https://raw.githubusercontent.com/ldadev/mobley_support/main/scripts/Ejecutar-Soporte-GitHub.ps1" | iex
```

Do not put credentials or private-repository tokens in scripts. When using a
short remote command, make it clear that `irm URL | iex` executes the retrieved
content in memory and is appropriate only for an explicitly trusted endpoint.

## Updating the toolkit

When changing any bundled operational file:

1. Keep the source and skill copies synchronized.
2. Preserve all four modes and report compatibility.
3. Validate PowerShell syntax.
4. Re-upload changed Drive artifacts if Drive deployment is in use.
5. Confirm that the direct download returns the expected file rather than an
   HTML login or confirmation page.

