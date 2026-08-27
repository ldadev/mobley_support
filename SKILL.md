---
name: windows-support-diagnostic
description: Create, deploy, run, troubleshoot, and interpret the Windows 10 support diagnostic toolkit bundled with this skill. Use for integral PC diagnostics, unusual network traffic audits, safe temporary-file cleanup, Chrome/DNS/Recycle Bin maintenance, Kaspersky/Chrome checks, driver and printer diagnostics, software inventory, and professional support report generation.
---

# Windows Support Diagnostic

Use the bundled toolkit to diagnose Windows 10 workstations without silently
changing system configuration.

The toolkit is intended to behave like a professional support tool: robust,
non-destructive, evidential, and safe by default. It collects forensic-quality
support artifacts, identifies indicators requiring review, and supports a low-risk
cleanup workflow for temporary files and browser cache without touching user
personal documents or download folders.

## Bundled files

- `scripts/Auditar-Trafico.ps1`: diagnostic and reporting engine.
- `scripts/Ejecutar-Soporte.cmd`: elevated interactive launcher with a styled
  menu (icons, confirm prompts, colored status markers).
- `scripts/Ejecutar-Soporte-Drive.ps1`: Google Drive downloader and launcher.
- `scripts/Ejecutar-Soporte-GitHub.ps1`: GitHub downloader and launcher.
- `scripts/launcher.c`: C source for `Soporte-PC.exe`, a native Windows binary
  that runs the GitHub bootstrap command without opening PowerShell manually.
- `Soporte-PC.exe`: compiled double-clickable launcher (repo root).
- `references/drive.txt`: current Drive links and direct execution command.
- `references/github.txt`: current GitHub links and direct execution command.
- `references/USAGE.md`: operating and deployment guide.

Keep the PowerShell script and CMD launcher in the same directory.

## Publication workflow

Any change to `scripts/Auditar-Trafico.ps1` must be published to GitHub after
validation. Review the diff, run the available syntax or behavior checks, then
create a descriptive commit and push it to `origin/main`. Confirm that the
working tree is clean and that the local `main` branch matches `origin/main`
before reporting the change as complete. Do not leave changes to this script
only in the local workspace.

Recompile `Soporte-PC.exe` after changing `launcher.c`:

```bash
x86_64-w64-mingw32-gcc -O2 scripts/launcher.c -o Soporte-PC.exe
```

## Modes

Select the mode that matches the request:

- `Rapido`: five-minute sampling plus essential support checks.
- `Completo`: extended security, hardware, SMART, update, certificate,
  reliability, software, driver, printer, domain, and network checks.
- `Red`: timed traffic, DNS, gateway, adapter, process, and Fortinet-oriented
  evidence collection.
- `Limpieza`: safe, professional cleanup mode with temporary files, Chrome
  cache folders, DNS cache, and Recycle Bin cleanup, while preserving user
  documents, downloads, and recent files. No timed network audit is run.

Run directly when needed:

```powershell
.\Auditar-Trafico.ps1 -Modo Rapido
.\Auditar-Trafico.ps1 -Modo Red -DuracionMinutos 60
.\Auditar-Trafico.ps1 -Modo Completo -IncluirVerificacionSistema
.\Auditar-Trafico.ps1 -Modo Limpieza -DiasTemporalAntiguo 30
```

Prefer `Ejecutar-Soporte.cmd` (or `Soporte-PC.exe` for end users without
PowerShell familiarity) because it requests elevation, shows a menu with a
print-queue option, preserves errors, and keeps the console open.

Extra switches available on `Auditar-Trafico.ps1`:

- `-LimpiarColaImpresion`: standalone action. Stops the Spooler service,
  deletes stuck spool files, restarts the service, writes a short report,
  and returns immediately without running the rest of the diagnostic.
- `-OptimizarSistema`: standalone action. Empties the Recycle Bin, clears
  the DNS client cache, clears Explorer thumbnail/icon cache files, runs
  `DISM /Online /Cleanup-Image /StartComponentCleanup`, writes a short
  report, and returns immediately without running the rest of the
  diagnostic. Low-risk, performance-oriented maintenance only.
- `-Modo Limpieza`: the professional cleanup workflow for the end user. It
  targets temporary directories, old Chrome cache subfolders, the DNS cache,
  and the Recycle Bin, while intentionally preserving the user profile,
  documents, and downloads. It then exports a summary and HTML report.
- `-AutoEliminarAlCerrar`: writes evidence to `%TEMP%` instead of
  `C:\AuditoriaRed`, opens the HTML report automatically, and deletes the
  temporary evidence folder only after the user presses a key to exit.
- `-NoAutoAbrirReporte`: skip auto-opening the HTML report.

## Required behavior

1. Require Windows PowerShell 5.1 and administrator privileges.
2. Show stage messages and a live percentage progress bar during long
   sampling operations; allow the user to press `Q`/`Esc` to stop sampling
   early and still generate a report from the partial data.
3. Write evidence under `C:\AuditoriaRed\Auditoria-EQUIPO-FECHA` by default,
   or under `%TEMP%` when `-AutoEliminarAlCerrar` is used.
4. Generate `informe-de-soporte.html` and `hashes-sha256.csv`, and open the
   HTML report automatically unless `-NoAutoAbrirReporte` is set.
5. Treat automatic findings as indicators requiring review, not proof of
   malware.
6. Correlate network findings with FortiGate/FortiNAC logs by timestamp, IP,
   MAC, destination, port, protocol, rule, and security event.
7. State that Windows cannot determine licensing for every third-party product.
8. Capture only packet headers by default to reduce exposure of personal data.
9. Diagnose network printers (TCP/IP, WSD, SMB shares): resolve the host/IP,
   ping it, and probe the print port (9100) or SMB port (445) for
   reachability; report inconclusive results as `Revisar`.
10. Offer a dedicated print-queue recovery action that stops the Spooler
    service, clears stuck `.SPL`/`.SHD` files, and restarts the service.
11. Offer a dedicated low-risk optimization action (Recycle Bin, DNS cache,
    Explorer thumbnail/icon cache, DISM component cleanup) that never
    touches user documents, downloads, or installed applications.

## Cleanup safety

Never delete downloads, documents, user profiles, arbitrary directories, or
files newer than `DiasTemporalAntiguo`.

The cleanup implementation must:

- Enumerate specific known temporary directories.
- Target Chrome cache folders by profile and cache subdirectory, not the whole
  browser profile.
- Delete files individually by literal path.
- Reject paths outside the resolved temporary root.
- Skip reparse points and never recursively remove a directory.
- Count locked or inaccessible files as failures.
- Produce before/after measurements and an action summary.
- Keep the cleanup low risk by only removing old files and cache artifacts,
  while preserving user documents, downloads, and recent files.

Professional cleanup categories in this toolkit include:

- system temp folders
- Chrome cache and GPU/media cache
- DNS client cache
- Recycle Bin
- old print-spool files when explicitly requested

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

To parse-check a script on Linux without root, download a portable
PowerShell build instead of guessing at syntax:

```bash
curl -sL -o /tmp/pwsh.tar.gz "https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-linux-x64.tar.gz"
mkdir -p /tmp/pwsh && tar -xzf /tmp/pwsh.tar.gz -C /tmp/pwsh
chmod +x /tmp/pwsh/pwsh
/tmp/pwsh/pwsh -NoProfile -Command '
  $tokens = $null; $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile("scripts/Auditar-Trafico.ps1", [ref]$tokens, [ref]$errors)
  $errors | ForEach-Object { "Line $($_.Extent.StartLineNumber): $($_.Message)" }
'
```

Known PS 5.1 parser pitfalls seen in this toolkit:

- `"$var: texto"` inside a double-quoted string is read as a scope/drive
  reference (like `$env:`) and fails with "Missing type name after '['" or
  "Variable reference is not valid". Use `"${var}: texto"` instead.
- Avoid unqualified BCL type literals (e.g. `[ConsoleColor]`) as function
  parameter defaults; prefer `[string]` with a color name, since `Write-Host
  -ForegroundColor` accepts plain color-name strings.
- `raw.githubusercontent.com` is served through a CDN that can cache briefly;
  `curl` the raw URL to confirm the pushed fix is actually being served
  before assuming a caching issue.

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

Or share the compiled `Soporte-PC.exe` (built from `scripts/launcher.c`) for
users who prefer a double-clickable file over pasting a PowerShell command.
Expect Windows SmartScreen to warn on first run because the binary is
unsigned; the toolkit does not use a paid code-signing certificate.

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

