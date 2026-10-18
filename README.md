# VisualStudioUninstallAll

PowerShell utility to find and optionally uninstall Windows Installer (MSI) products registered under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products` and both Windows uninstall registry locations (including `WOW6432Node`) whose `DisplayName` contains **Visual Studio**. Duplicate MSI product codes are consolidated.

For troubleshooting broken Visual Studio installations. **Independent community utility; not affiliated with Microsoft.** Back up your system before uninstalling. Read-only by default.

## Requirements

- Windows PowerShell 5.1+
- Administrator privileges for uninstalling

## Usage

Preview products (no changes):

```powershell
.\VisualStudioUninstallAll.ps1
```

Preview additional `vs_*` and `Microsoft.Maui.*` packages:

```powershell
.\VisualStudioUninstallAll.ps1 -IncludeMauiAndVsPackages
```

Uninstall with per-product confirmations:

```powershell
.\VisualStudioUninstallAll.ps1 -Uninstall
```

Uninstall the broader set without per-product confirmation (destructive; preview first):

```powershell
.\VisualStudioUninstallAll.ps1 -Uninstall -IncludeMauiAndVsPackages -Confirm:$false
```

MSI verbose logs and `results.csv` are stored in `%TEMP%\VisualStudioUninstallAll`. Exit code 0 generally means success; 3010 means success with restart required.

## Legacy cleanup (pre-2026)

Run \`.\VisualStudioUninstallAll.ps1 -CleanupLegacy -WhatIf\` to preview
legacy entries. \`-CleanupLegacy\` considers only machine-wide Uninstall keys
with a GUID-formatted key name and an **explicit Visual Studio year 2000–2025**
in their display name. It excludes Visual Studio Code, Installer and IDE editions.

For each candidate, Windows Installer ProductState is checked: state -1 means
a backup of the uninstall key is exported before removing that key; state 5
triggers a normal MSI uninstall (with confirmation); any other state is skipped.
No Installer\UserData or Classes\Installer keys are deleted.
Products with no explicit year in the name are intentionally excluded.

Run elevated and inspect the preview first:

\`\`\`powershell
.\VisualStudioUninstallAll.ps1 -CleanupLegacy -WhatIf
.\VisualStudioUninstallAll.ps1 -CleanupLegacy
\`\`\`

## Registry cleanup (advanced)

The optional \`-RemoveOrphanedRegistryEntries\` switch removes **only** machine-wide
Add/Remove Programs entries under the 64-bit and WOW6432Node Uninstall registry
branches, and only when Windows Installer reports \`ProductState=-1\` (unknown product).
Every selected key is exported as a \`.reg\` backup before deletion and requires
confirmation. Products with state 1 (advertised) or 5 (installed), including
the known Visual Studio Setup Configuration 3.9 case, are **not** deleted.
Windows Installer's internal \`Installer\UserData\` and \`Classes\Installer\`
databases are never modified.

Preview first, then run from an elevated PowerShell prompt:

\`\`\`powershell
.\VisualStudioUninstallAll.ps1 -RemoveOrphanedRegistryEntries -WhatIf
.\VisualStudioUninstallAll.ps1 -RemoveOrphanedRegistryEntries
\`\`\`

This is not a general MSI cache repair tool. Do not treat MSI error 1612 as proof
that a product is orphaned.

## Limitations

- Checks SYSTEM (`S-1-5-18`) MSI entries and 64-bit/32-bit machine-wide uninstall entries; per-user installations are not covered.
- Only recognized MSI uninstall commands are executed. Other EXE uninstallers are shown in the preview but skipped.
- Does not remove all Visual Studio installer metadata.
- Does not recover missing MSI caches. If the original source is unavailable, uninstall may fail with 1612 or 1714.
- Packages that mention Visual Studio might be shared; always review the preview first.
- Never deletes Windows Installer registry keys directly.

## License

GPL-3.0-or-later; see [LICENSE](LICENSE).
