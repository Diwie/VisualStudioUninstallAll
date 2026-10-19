#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$Uninstall,
    [switch]$RegistryClean,
    [switch]$UninstallThenClean,
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
            # Explicit user-requested exact-version filter, scoped to WOW6432Node only.
            $isOldWowVersion = $root -eq 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -and
                [string]$info.DisplayVersion -in @('17.9.34714', '17.9.34511', '14.39.33519') -and
                $name -notmatch '2026'
            # Remaining legacy VS 2022 components can also be in the native 64-bit uninstall root.
            # Confirmed ClickOnce Bootstrapper orphan: VS 2026 setup error 1714 / MSI source 1612.
            $isBrokenClickOnce = $key.PSChildName -eq '{22E13608-4DB0-4977-A267-3AAFA09CD54A}' -and
                $name -eq 'ClickOnce Bootstrapper Package for Microsoft .NET Framework'
            $isOldVs17Component = [string]$info.DisplayVersion -in @('17.9.34511', '17.9.34714') -and
                $name -match '^(?i:vs_|icecap_)' -and
                $name -notmatch '2026'
            if (-not $isOldScriptDebug -and -not $isOldMinShell -and -not $isOldMinShellShared -and -not $isOldMinShellX64 -and -not $isOldFileHandler -and -not $isOldFileHandlerAmd64 -and -not $isOldWowVersion -and -not $isOldVs17Component -and -not $isBrokenClickOnce -and
                ($name -notmatch '(?i)Visual Studio' -or $name -match '2026' -or
                ([string]$info.DisplayVersion -notmatch '^17\.' -and $name -notmatch '^(?i:Microsoft Visual Studio 20(?:17|19|22))') -or
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

# Explicitly requested legacy versions for MSI UserData registrations.
# DisplayVersion is stored in each product's InstallProperties subkey.
$legacyUserDataVersions = @('14.39.33519', '17.9.34511', '17.9.34714')
$userDataRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products'
$userDataEntries = @(
    foreach ($key in Get-ChildItem -LiteralPath $userDataRoot -ErrorAction SilentlyContinue) {
        $props = Get-ItemProperty -LiteralPath (Join-Path $key.PSPath 'InstallProperties') -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $version = [string]$props.DisplayVersion
        $name = [string]$props.DisplayName
        if ($version -notin $legacyUserDataVersions -or $name -match '2026') { continue }
        [pscustomobject]@{
            Name = $name
            Version = $version
            RegistryPath = $key.PSPath
            NativePath = $key.Name
            ProductCode = if ([string]$props.UninstallString -match '\{[0-9A-Fa-f-]{36}\}') { $Matches[0].ToUpperInvariant() } else { $null }
        }
    }
)
# Explicit orphan confirmed by Visual Studio MSI logs (1714, underlying 1612).
# Its uninstall entry may be missing even though Windows Installer still registers the product.
$brokenCrtPackedKey = 'C711BE283D8F28A4C88C20DA4D1D8B48'
$brokenCrtProductGuid = '{82EB117C-F8D3-4A82-8CC8-02ADD4D1B884}'
$brokenCrtPath = Join-Path $userDataRoot $brokenCrtPackedKey
$brokenCrtProps = Get-ItemProperty -LiteralPath (Join-Path $brokenCrtPath 'InstallProperties') -ErrorAction SilentlyContinue
$brokenCrtMatch = (Test-Path -LiteralPath $brokenCrtPath) -and
    $null -ne $brokenCrtProps -and
    [string]$brokenCrtProps.DisplayName -eq 'Visual C++ Library CRT Appx Resource Package' -and
    [string]$brokenCrtProps.DisplayVersion -eq '14.39.33519' -and
    [string]$brokenCrtProps.UninstallString -match [regex]::Escape($brokenCrtProductGuid)
if ($brokenCrtMatch -and @($userDataEntries | Where-Object { $_.NativePath -eq ('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\' + $brokenCrtPackedKey) }).Count -eq 0) {
    $userDataEntries += [pscustomobject]@{
        Name = [string]$brokenCrtProps.DisplayName
        Version = [string]$brokenCrtProps.DisplayVersion
        RegistryPath = $brokenCrtPath
        NativePath = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\' + $brokenCrtPackedKey
        ProductCode = $brokenCrtProductGuid
    }
}
Write-Host "MSI UserData entries matching known legacy versions: $($userDataEntries.Count)"
$userDataEntries | Format-Table Name,Version,NativePath -AutoSize

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
            (([int64]$info.Version -shr 24) -band 255) -eq 17 -and
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
        # Generalized legacy Visual Studio MSI detection: major version 17 only.
        # Restrict dotted/underscored names to known VS component families;
        # a punctuation mark alone is not proof of Microsoft ownership.
        $msiVersion = [int64]$info.Version
        $isVersion17 = (($msiVersion -shr 24) -band 255) -eq 17
        $vsComponentName = $name -match '^(?i:vs_|icecap_|DiagnosticsHub_|windows_toolscorepkg$|Microsoft\.iOS\.|Microsoft\.MacCatalyst\.|Microsoft\.NET\.Sdk\.(?:iOS|MacCatalyst|tvOS)\.)' -or
            $name -in @('VS Immersive Activate Helper','VS JIT Debugger','VS Script Debugging Common','Xamarin Remoted iOS Simulator','Microsoft TestPlatform SDK Local Feed')
        $version17Match = $isVersion17 -and $vsComponentName
        if ($legacyMatch -or $normalMatch -or $scriptDebugMatch -or $minShellMatch -or $minShellSharedMatch -or $minShellX64Match -or $fileHandlerMatch -or $fileHandlerAmd64Match -or $version17Match) {
            [pscustomobject]@{ Name = $name; RegistryPath = $key.PSPath; NativePath = $key.Name; MsiVersion = [int64]$info.Version }
        }
    }
)
Write-Host "Windows Installer registrations matching the filter: $($msiEntries.Count)"
$msiEntries | Format-Table Name,NativePath -AutoSize

$entries | Sort-Object Name,RegistryPath | Format-Table Name,Version,ProductCode,RegistryPath -AutoSize
Write-Host "Found $($entries.Count) uninstall registry entries (excluding names containing 2026)."
if (-not $Uninstall -and -not $RegistryClean -and -not $UninstallThenClean) {
    Write-Host 'Preview only. Use -Uninstall or -RegistryClean; add -WhatIf to preview actions.'
    return
}
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $WhatIfPreference) { throw 'Run PowerShell as Administrator.' }
if (-not $WhatIfPreference) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }

$fallbackCodes = @{}
$successfulCodes = @(0, 1614, 3010)
if ($Uninstall -or $UninstallThenClean) {
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
            if ($UninstallThenClean -and $process.ExitCode -eq 1605) {
                # MSI says product is absent; remove only its stale uninstall entry after backup.
                $fallbackCodes[$item.ProductCode] = 'orphan'
                Write-Warning "MSI product absent (1605): orphaned uninstall entry eligible for cleanup: $($item.Name)"
            }
            if ($UninstallThenClean -and -not ($process.ExitCode -in $successfulCodes) -and $process.ExitCode -ne 1605) {
                $sourceMissing = $process.ExitCode -eq 1612 -or
                    ($process.ExitCode -eq 1603 -and (Test-Path -LiteralPath $log) -and
                        [bool](Select-String -LiteralPath $log -Pattern 'System Error 1612|Error 1714|SOURCEMGMT: Failed to resolve source' -Quiet))
                if ($sourceMissing) {
                    $fallbackCodes[$item.ProductCode] = 'source'
                    Write-Warning "Missing MSI source: RegistryClean fallback eligible for $($item.Name)"
                } else { Write-Warning "MSI exit $($process.ExitCode): no automatic registry cleanup for $($item.Name)" }
            }
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
# For internal MSI registrations without a normal Uninstall key, attempt uninstall first.
# Record failure before allowing any automatic fallback deletion.
$userDataFailedCodes = @{}
if ($UninstallThenClean) {
    foreach ($item in $userDataEntries) {
        if (-not $item.ProductCode -or $seen.ContainsKey($item.ProductCode)) { continue }
        $seen[$item.ProductCode] = $true
        if (-not $PSCmdlet.ShouldProcess("$($item.Name) ($($item.ProductCode))", 'Uninstall orphaned MSI product')) { continue }
        $log = Join-Path $LogDirectory ("userdata-msi-" + $item.ProductCode.Trim('{}') + '.log')
        $arguments = '/x ' + $item.ProductCode + ' /qn /norestart /L*v "' + $log + '"'
        $process = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $arguments -Wait -PassThru
        Write-Host "UserData MSI exit $($process.ExitCode): $($item.Name) | $log"
        if ($process.ExitCode -in @(1605,1612,1614)) {
            $userDataFailedCodes[$item.ProductCode] = $process.ExitCode
        } elseif ($process.ExitCode -eq 1603 -and (Test-Path -LiteralPath $log) -and
            [bool](Select-String -LiteralPath $log -Pattern 'System Error 1612|Error 1714|SOURCEMGMT: Failed to resolve source' -Quiet)) {
            $userDataFailedCodes[$item.ProductCode] = $process.ExitCode
        }
    }
}
if ($RegistryClean -or $UninstallThenClean) {
    # Version-based internal MSI UserData removal is explicit only for -RegistryClean.
    # -UninstallThenClean requires evidence of a failed MSI uninstall; avoid deleting
    # healthy products merely because their version matches a legacy version.
    if ($RegistryClean -or $UninstallThenClean) {
        foreach ($item in $userDataEntries) {
            # Combined mode cleans only registrations whose uninstall attempt failed with
            # a known missing-product/source code, never all matching versions blindly.
            if ($UninstallThenClean -and -not $RegistryClean -and
                (-not $item.ProductCode -or -not $userDataFailedCodes.ContainsKey($item.ProductCode))) { continue }
            $safeKey = Split-Path $item.NativePath -Leaf
            $backup = Join-Path $LogDirectory ("userdata-" + $safeKey + ".reg")
            if (-not $PSCmdlet.ShouldProcess($item.NativePath, "Export UserData registration to $backup, then delete exact-version key")) { continue }
            & "$env:WINDIR\System32\reg.exe" export $item.NativePath $backup /y | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) {
                Write-Warning "UserData backup failed; retained: $($item.NativePath)"
                continue
            }
            & "$env:WINDIR\System32\reg.exe" delete $item.NativePath /f | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-Warning "UserData deletion failed: $($item.NativePath)" }
            else { Write-Host "UserData registration removed: $($item.Name) ($($item.Version)) | backup: $backup" }
        }
    }

    # Export MSI product registration before any explicitly confirmed removal.
    foreach ($item in $msiEntries) {
        if ($UninstallThenClean -and -not $RegistryClean) {
            # A registry entry is eligible only when its corresponding uninstall failed due to missing MSI source.
            $matching = @($entries | Where-Object { $_.Name -eq $item.Name -and $_.ProductCode -and $fallbackCodes.ContainsKey($_.ProductCode) })
            $failedSource = @($matching | Where-Object { $fallbackCodes[$_.ProductCode] -eq 'source' }).Count -gt 0
            # No uninstall entry remains: remove only explicitly recognized version-17 VS registrations.
            $orphanInternal = @($entries | Where-Object { $_.Name -eq $item.Name }).Count -eq 0 -and
                ((($item.MsiVersion -shr 24) -band 255) -eq 17)
            if (-not $failedSource -and -not $orphanInternal) { continue }
        }
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
        if ($UninstallThenClean -and -not $RegistryClean -and
            (-not $item.ProductCode -or -not $fallbackCodes.ContainsKey($item.ProductCode))) { continue }
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

