# VisualStudioUninstallAll

PowerShell utility to find and optionally uninstall Windows Installer (MSI) products registered under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products` whose `DisplayName` contains **Visual Studio**.

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

## Limitations

- Only checks the SYSTEM (`S-1-5-18`) Windows Installer registry scope, not all per-user installations.
- Does not remove all Visual Studio installer metadata.
- Does not recover missing MSI caches. If the original source is unavailable, uninstall may fail with 1612 or 1714.
- Packages that mention Visual Studio might be shared; always review the preview first.
- Never deletes Windows Installer registry keys directly.

## License

GPL-3.0-only; see [LICENSE](LICENSE).
