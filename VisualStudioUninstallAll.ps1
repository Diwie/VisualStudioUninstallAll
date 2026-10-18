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
# Known legacy VS 17.10 MSI registrations (packed MSI product GUIDs).
# Match both the key and product name to avoid selecting newer replacements.
$legacyMsiKeys = @{
    '3B552180DA46F284BBBC222E497BBE3D' = 'vs_vswebprotocolselectormsires'
    'E7F6FA80B1E194041B980B1A900EEC50' = 'vs_vswebprotocolselectormsi'
    '07ECC0D64A38E8343874DFCDBC0568F8' = 'vs_githubprotocolhandlermsi'
}
$scriptDebugOldGuid = '{D56DC014-C4C1-4330-B32B-D9785DAE7BCB}'
$scriptDebugPackedKey = '410CD65D1C4C03343BB29D87D5EAB7BC'
$scriptDebugOldVersion = '17.0.125.0'
$minShellOldGuid = '{621BEEFB-6EB5-4525-A73B-FFE906367055}'
$minShellPackedKey = 'BFEEB1265BE652547AB3FF9E60630755'
$minShellOldVersion = '17.9.34511'
$minShellSharedOldGuid = '{7E298CFB-5829-4903-98BA-F3F70E7CEB09}'
$minShellSharedPackedKey = 'BFC892E79285309489AB3F7FE0C7BE90'
$minShellX64OldGuid = '{072326E8-D76B-4137-8DAC-45D5D58777EF}'
$minShellX64PackedKey = '8E623270B67D7314D8CA545D5D7877FE'
$fileHandlerOldGuid = '{8F6810F6-45F1-4D41-9BE1-FE3828602B93}'
$fileHandlerPackedKey = '6F0186F81F5414D4B91EEF838206B239'
$fileHandlerAmd64OldGuid = '{377C68AC-F3B1-4B7F-B0F8-72446D60E99E}'
$fileHandlerAmd64PackedKey = 'CA86C7731B3FF7B40B8F2744D6069EE9'
$guidPattern = '^\{[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\}$'
$entries = @(
    foreach ($root in $roots) {
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $info = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
            $name = [string]$info.DisplayName
            $isOldScriptDebug = $name -eq 'VS Script Debugging Common' -and
                $key.PSChildName -eq $scriptDebugOldGuid -and
                [string]$info.DisplayVersion -eq $scriptDebugOldVersion
            $isOldMinShell = $name -eq 'vs_minshellmsires' -and
                $key.PSChildName -eq $minShellOldGuid -and
                [string]$info.DisplayVersion -eq $minShellOldVersion
            $isOldMinShellShared = $name -eq 'vs_minshellsharedmsi' -and
                $key.PSChildName -eq $minShellSharedOldGuid -and
                [string]$info.DisplayVersion -eq $minShellOldVersion
            $isOldMinShellX64 = $name -eq 'vs_minshellx64msi' -and
                $key.PSChildName -eq $minShellX64OldGuid -and
                [string]$info.DisplayVersion -eq '17.9.34714'
            $isOldFileHandler = $name -eq 'vs_filehandler_x86' -and
                $key.PSChildName -eq $fileHandlerOldGuid -and
                [string]$info.DisplayVersion -eq '17.9.34714'
            $isOldFileHandlerAmd64 = $name -eq 'vs_filehandler_amd64' -and
                $key.PSChildName -eq $fileHandlerAmd64OldGuid -and
                [string]$info.DisplayVersion -eq '17.9.34714'
            if (-not $isOldScriptDebug -and -not $isOldMinShell -and -not $isOldMinShellShared -and -not $isOldMinShellX64 -and -not $isOldFileHandler -and -not $isOldFileHandlerAmd64 -and
                ($name -notmatch '(?i)Visual Studio' -or $name -match '2026' -or
                ($name -match '^Microsoft Visual Studio Setup (?:Configuration|WMI Provider)$' -and [version]$info.DisplayVersion -ge [version]'4.8'))) { continue }
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

# Inspect internal MSI registrations, including three confirmed legacy VS packages.
$msiRegistryRoot = 'Registry::HKEY_CLASSES_ROOT\Installer\Products'
$msiEntries = @(
    foreach ($key in Get-ChildItem -LiteralPath $msiRegistryRoot -ErrorAction SilentlyContinue) {
        $info = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        $name = [string]$info.ProductName
        $packedKey = $key.PSChildName.ToUpperInvariant()
        $legacyMatch = $legacyMsiKeys.ContainsKey($packedKey) -and
            $name -eq $legacyMsiKeys[$packedKey] -and
            [int64]$info.Version -eq 285837007
        $normalMatch = $name -match '(?i)Visual Studio' -and
            $name -notmatch '2026' -and
            $name -notmatch '^Microsoft Visual Studio Setup (?:Configuration|WMI Provider)$'
        $scriptDebugMatch = $packedKey -eq $scriptDebugPackedKey -and
            $name -eq 'VS Script Debugging Common' -and
            [int64]$info.Version -eq 285212797
        $minShellMatch = $packedKey -eq $minShellPackedKey -and
            $name -eq 'vs_minshellmsires' -and
            [int64]$info.Version -eq 285837007
        $minShellSharedMatch = $packedKey -eq $minShellSharedPackedKey -and
            $name -eq 'vs_minshellsharedmsi' -and
            [int64]$info.Version -eq 285837007
        $minShellX64Match = $packedKey -eq $minShellX64PackedKey -and
            $name -eq 'vs_minshellx64msi' -and
            [int64]$info.Version -eq 285837210
        $fileHandlerMatch = $packedKey -eq $fileHandlerPackedKey -and
            $name -eq 'vs_filehandler_x86' -and
            [int64]$info.Version -eq 285837210
        $fileHandlerAmd64Match = $packedKey -eq $fileHandlerAmd64PackedKey -and
            $name -eq 'vs_filehandler_amd64' -and
            [int64]$info.Version -eq 285837210
        if ($legacyMatch -or $normalMatch -or $scriptDebugMatch -or $minShellMatch -or $minShellSharedMatch -or $minShellX64Match -or $fileHandlerMatch -or $fileHandlerAmd64Match) {
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

    # Export MSI product registration before any explicitly confirmed removal.
    foreach ($item in $msiEntries) {
        $safeKey = Split-Path $item.NativePath -Leaf
        $backup = Join-Path $LogDirectory ("msi-registration-" + $safeKey + ".reg")
        if (-not $PSCmdlet.ShouldProcess($item.NativePath, "Export MSI registration backup to $backup, then delete registry key")) { continue }
        & "$env:WINDIR\System32\reg.exe" export $item.NativePath $backup /y | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "MSI registration backup failed: $($item.Name)" }
        elseif (Test-Path -LiteralPath $backup) {
            & "$env:WINDIR\System32\reg.exe" delete $item.NativePath /f | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Warning "Deletion failed: $($item.NativePath)" }
            else { Write-Host "MSI registration removed: $($item.Name) | backup: $backup" }
        }
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
Write-Warning 'Deleting internal MSI registration can affect repair and uninstall; this is not a complete Windows Installer database repair.'

