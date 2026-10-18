# VisualStudioUninstallAll

PowerShell 5.1+ utility to find Windows uninstall registry entries whose **DisplayName contains "Visual Studio" but not "2026"**.

Searches both machine-wide registry paths:
- `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall`
- `HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall`

## Usage

Run in elevated PowerShell for changes:

```powershell
.\VisualStudioUninstallAll.ps1
.\VisualStudioUninstallAll.ps1 -Uninstall -WhatIf
.\VisualStudioUninstallAll.ps1 -Uninstall
.\VisualStudioUninstallAll.ps1 -RegistryClean -WhatIf
.\VisualStudioUninstallAll.ps1 -RegistryClean
```

**`-Uninstall`** attempts regular removal via MSI product GUID or a direct EXE uninstaller. It reports exit codes and skips unsupported commands. It does not delete registry keys.

**`-RegistryClean`** exports each matching Uninstall registry key to a unique `.reg` backup in the log directory and then deletes the key after confirmation. It does not check whether the software is still installed. Use only after reviewing the preview and trying `-Uninstall`.

No action is taken without an action parameter. Both actions support `-WhatIf` and PowerShell confirmations. Do not combine `-Uninstall` and `-RegistryClean` unless you explicitly intend both actions in one run.

**Caution:** The name filter also includes Visual Studio Code, Visual Studio Installer, and any Visual Studio product without 2026 in its name. `-RegistryClean` may hide installed programs from Apps & Features and can interfere with maintenance. It does not remove internal Windows Installer records or fix MSI error 1714.

## License

GPL-3.0-or-later. Copyright (C) 2026 Steve Jüstel.
