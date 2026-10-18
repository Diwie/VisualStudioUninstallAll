#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$Uninstall,
    [switch]$RegistryClean,
    [string]$LogDirectory = (Join-Path $env:TEMP 'VisualStudioUninstallAll')
)
$ErrorActionPreference = 'Stop'
$roots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
$guidPattern = '^\{[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\}$'
$entries = @(
    foreach ($root in $roots) {
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $info = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $name = [string]$info.DisplayName
            if ($name -notmatch '(?i)Visual Studio' -or $name -match '2026') { continue }
            $command = [string]$info.UninstallString
            $productCode = $null
            if ($key.PSChildName -match $guidPattern -and $info.WindowsInstaller -eq 1) {
                $productCode = $key.PSChildName.ToUpperInvariant()
            } elseif ($command -match '(?i)\{[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\}' -and $command -match '(?i)\bmsiexec(?:\.exe)?\b') {
                $productCode = $Matches[0].ToUpperInvariant()
            }
            [pscustomobject]@{
                Name = $name
                Version = [string]$info.DisplayVersion
                ProductCode = $productCode
                Command = $command
                RegistryPath = Join-Path $root $key.PSChildName
            }
        }
    }
)

# Inspect Windows Installer product registrations separately. These are not
# ordinary Add/Remove Programs entries and are never deleted by this script.
$msiRegistryRoot = 'Registry::HKEY_CLASSES_ROOT\Installer\Products'
$msiEntries = @(
    foreach ($key in Get-ChildItem -LiteralPath $msiRegistryRoot -ErrorAction SilentlyContinue) {
        $info = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        $name = [string]$info.ProductName
        if ($name -match '(?i)Visual Studio' -and $name -notmatch '2026') {
            [pscustomobject]@{ Name = $name; RegistryPath = $key.PSPath; NativePath = $key.Name }
        }
    }
)
Write-Host "Windows Installer registrations matching the filter: $($msiEntries.Count)"
$msiEntries | Format-Table Name,NativePath -AutoSize

$entries | Sort-Object Name,RegistryPath | Format-Table Name,Version,ProductCode,RegistryPath -AutoSize
Write-Host "Found $($entries.Count) uninstall registry entries (excluding names containing 2026)."
if (-not $Uninstall -and -not $RegistryClean) {
    Write-Host 'Preview only. Use -Uninstall or -RegistryClean; add -WhatIf to preview actions.'
    return
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $WhatIfPreference) { throw 'Run PowerShell as Administrator.' }
if (-not $WhatIfPreference) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }

if ($Uninstall) {
    $seen = @{}
    foreach ($item in $entries) {
        if ($item.ProductCode) {
            if ($seen.ContainsKey($item.ProductCode)) { continue }
            $seen[$item.ProductCode] = $true
            if (-not $PSCmdlet.ShouldProcess("$($item.Name) ($($item.ProductCode))", 'Uninstall MSI product')) { continue }
            $log = Join-Path $LogDirectory ("msi-" + $item.ProductCode.Trim('{}') + '.log')
            $arguments = '/x ' + $item.ProductCode + ' /qn /norestart /L*v "' + $log + '"'
            $process = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
            Write-Host "MSI exit $($process.ExitCode): $($item.Name) | $log"
            continue
        }
        # Execute only directly parseable EXE commands, never cmd.exe, scripts or shell operators.
        $command = $item.Command.Trim()
        $exe = $null
        $arguments = ''
        if ($command -match '^"([^"]+\.exe)"(?:\s+(.*))?$') {
            $exe = $Matches[1]; $arguments = $Matches[2]
        } elseif ($command -match '^(.+?\.exe)(?:\s+(.*))?$') {
            $exe = $Matches[1]; $arguments = $Matches[2]
        }
        if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf) -or
            (Split-Path $exe -Leaf) -match '^(?i:cmd|powershell|pwsh|wscript|cscript|rundll32|regsvr32|msiexec)\.exe$') {
            Write-Warning "No supported uninstall command: $($item.Name)"
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($item.Name, "Run uninstaller: $exe $arguments")) { continue }
        $startParams = @{ FilePath = $exe; Wait = $true; PassThru = $true }
        if (-not [string]::IsNullOrWhiteSpace($arguments)) {
            $startParams.ArgumentList = $arguments
        }
        $process = Start-Process @startParams
        Write-Host "EXE exit $($process.ExitCode): $($item.Name)"
    }
}
if ($RegistryClean) {

    # Export internal MSI product registrations for diagnosis; do not remove them.
    foreach ($item in $msiEntries) {
        $nameHash = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($item.NativePath)).GetHashCode()
        $safeKey = Split-Path $item.NativePath -Leaf
        $backup = Join-Path $LogDirectory ("msi-registration-" + $safeKey + ".reg")
        if (-not $PSCmdlet.ShouldProcess($item.NativePath, "Export MSI registration backup to $backup (no deletion)")) { continue }
        & "$env:WINDIR\System32\reg.exe" export $item.NativePath $backup /y | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "MSI registration backup failed: $($item.Name)" }
        else { Write-Host "MSI registration saved: $backup" }
    }
    foreach ($item in $entries) {
        $path = $item.RegistryPath
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $native = $path -replace '^HKLM:\\','HKEY_LOCAL_MACHINE\'
        $bytes = [Text.Encoding]::UTF8.GetBytes($native)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $id = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').Substring(0,16) }
        finally { $sha.Dispose() }
        $backup = Join-Path $LogDirectory ("registry-$id.reg")
        if (-not $PSCmdlet.ShouldProcess($path, "Export backup to $backup, then delete uninstall registry key")) { continue }
        & "$env:WINDIR\System32\reg.exe" export $native $backup /y | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) {
            Write-Warning "Backup failed, key retained: $path"
            continue
        }
        Remove-Item -LiteralPath $path -Recurse -Force
        Write-Host "Registry entry removed: $($item.Name) | backup: $backup"
    }
}
Write-Warning 'RegistryClean removes only Uninstall registry keys; it does not repair Windows Installer product registration or missing MSI sources.'
