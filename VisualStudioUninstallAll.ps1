#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [switch]$Uninstall,
    [switch]$RemoveOrphanedRegistryEntries,
    [switch]$CleanupLegacy,
    [switch]$IncludeMauiAndVsPackages,
    [string]$LogDirectory = (Join-Path $env:TEMP 'VisualStudioUninstallAll')
)
$ErrorActionPreference = 'Stop'
$roots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)
function Get-MsiProductCode([string]$Command) {
    # Only accept msiexec commands, never arbitrary executable uninstall strings.
    if ($Command -notmatch '(?i)^\s*(?:"[^"]*msiexec(?:\.exe)?"|(?:\S*\\)?msiexec(?:\.exe)?)\s+') {
        return $null
    }
    if ($Command -match '(?i)(?:^|\s)/(?:x|i|uninstall|package)\s*(\{[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\})') {
        return $Matches[1].ToUpperInvariant()
    }
    return $null
}
$found = foreach ($root in $roots) {
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Warning "Registry path unavailable: $root"
        continue
    }
    foreach ($entry in Get-ChildItem -LiteralPath $root -ErrorAction Continue) {
        $details = if ($root -like '*\Installer\UserData\*') {
            $props = Join-Path $entry.PSPath 'InstallProperties'
            if (-not (Test-Path -LiteralPath $props)) { continue }
            Get-ItemProperty -LiteralPath $props -ErrorAction SilentlyContinue
        } else {
            Get-ItemProperty -LiteralPath $entry.PSPath -ErrorAction SilentlyContinue
        }
        if (-not $details) { continue }
        $name = [string]$details.DisplayName
        if ($name -notmatch '(?i)Visual Studio' -and -not ($IncludeMauiAndVsPackages -and $name -match '(?i)^(vs_|Microsoft\.Maui\.)')) { continue }
        $cmd = [string]$details.UninstallString
        $guid = Get-MsiProductCode $cmd
        if (-not $guid -and $entry.PSChildName -match '^\{[0-9a-fA-F-]{36}\}$' -and $cmd -match '(?i)msiexec') {
            $guid = $entry.PSChildName.ToUpperInvariant()
        }
        [pscustomobject]@{
            Name = $name
            Version = [string]$details.DisplayVersion
            ProductCode = $guid
            UninstallString = $cmd
            Source = $root
            RegistryKey = $entry.PSChildName
        }
    }
}
# Merge duplicate MSI product codes across the three registry locations.
# Prefer a record with a recognized MSI uninstall command.
$seen = @{}
$packages = @(
    foreach ($item in ($found | Sort-Object @{Expression={if ($_.ProductCode -and (Get-MsiProductCode $_.UninstallString)) {0} else {1}}})) {
        $key = if ($item.ProductCode) { "MSI:$($item.ProductCode)" } else { "REG:$($item.Source)\$($item.RegistryKey)" }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $item
    }
)
$packages | Sort-Object Name | Format-Table Name,Version,ProductCode,Source -AutoSize
Write-Host "Found $($packages.Count) matching product(s) across $($roots.Count) registry paths."
if (-not $Uninstall -and -not $RemoveOrphanedRegistryEntries -and -not $CleanupLegacy) { Write-Host 'Preview only. Pass -Uninstall or -RemoveOrphanedRegistryEntries to take action.'; return }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run PowerShell as Administrator.' }
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$results = if ($Uninstall) { foreach ($p in $packages) {
    $guid = Get-MsiProductCode $p.UninstallString
    if (-not $guid) {
        Write-Warning "Skipped (no supported MSI uninstall command): $($p.Name)"
        continue
    }
    if (-not $PSCmdlet.ShouldProcess("$($p.Name) ($guid)", 'Uninstall MSI product')) { continue }
    $log = Join-Path $LogDirectory ("$($guid.Trim('{}')).log")
    $arguments = "/x $guid /qn /norestart /L*v " + '"' + $log + '"'
    $process = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $arguments -PassThru -Wait
    [pscustomobject]@{Name=$p.Name;ProductCode=$guid;ExitCode=$process.ExitCode;Log=$log}
} }
if ($results) {
    $report = Join-Path $LogDirectory 'results.csv'
    $results | Export-Csv -Path $report -NoTypeInformation -Encoding UTF8
    $results | Format-Table -AutoSize
    Write-Host "Results: $report"
}
Write-Warning 'MSI errors 1603/1612/1714 may require missing installation media. No registry keys are deleted.'

if ($RemoveOrphanedRegistryEntries) {
    # Only machine-wide Add/Remove Programs entries; never modify Installer\UserData or Classes\Installer.
    # A product must be explicitly absent from Windows Installer (ProductState=-1).
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $candidates = @($found | Where-Object {
        $_.Source -in @($roots[1], $roots[2]) -and
        $_.Name -notmatch '(?i)Visual Studio (?:Community|Professional|Enterprise|Installer|Code)(?:\s|$)' -and
        $_.ProductCode -and
        $_.RegistryKey -match '^\{[0-9a-fA-F-]{36}\}$'
    } | Sort-Object Source,RegistryKey -Unique)
    foreach ($p in $candidates) {
        $state = $null
        try { $state = [int]$installer.ProductState($p.ProductCode) }
        catch { Write-Warning "Cannot verify MSI state for $($p.Name): $($_.Exception.Message)"; continue }
        if ($state -ne -1) {
            Write-Host "Keeping $($p.Name): Windows Installer ProductState=$state (not proven orphaned)."
            continue
        }
        $registryPath = Join-Path $p.Source $p.RegistryKey
        if (-not (Test-Path -LiteralPath $registryPath)) { continue }
        $nativePath = $registryPath -replace '^HKLM:\\','HKEY_LOCAL_MACHINE\'
        $backup = Join-Path $LogDirectory ("registry-" + $p.ProductCode.Trim('{}') + ".reg")
        if (-not $PSCmdlet.ShouldProcess($registryPath, 'Export registry backup and remove orphaned uninstall entry')) { continue }
        & "$env:WINDIR\System32\reg.exe" export $nativePath $backup /y | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) {
            Write-Warning "Backup failed, leaving registry entry unchanged: $registryPath"
            continue
        }
        Remove-Item -LiteralPath $registryPath -Recurse -Force -ErrorAction Stop
        Write-Host "Removed orphaned uninstall entry: $registryPath (backup: $backup)"
    }
}

if ($CleanupLegacy) {
    # Explicit year in product name, 2000..2025. Never infer age from DisplayVersion.
    # Does not touch Windows Installer internal registry, and never targets 2026+.
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $legacy = @($found | Where-Object {
        $_.Name -match '(?i)\bVisual Studio\b' -and
        $_.Name -match '\b20(?:0[0-9]|1[0-9]|2[0-5])\b' -and
        $_.Name -notmatch '(?i)Visual Studio (?:Code|Installer|Community|Professional|Enterprise)(?:\s|$)' -and
        $_.Source -in @($roots[1],$roots[2]) -and
        $_.RegistryKey -match '^\{[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\}$'
    } | Sort-Object Source,RegistryKey -Unique)
    foreach ($p in $legacy) {
        $guid = $p.RegistryKey.ToUpperInvariant()
        $state = $null
        try { $state = [int]$installer.ProductState($guid) }
        catch { Write-Warning "State check failed: $($p.Name): $($_.Exception.Message)"; continue }
        if ($state -eq -1) {
            $key = Join-Path $p.Source $p.RegistryKey
            $native = $key -replace '^HKLM:\\','HKEY_LOCAL_MACHINE\'
            $backup = Join-Path $LogDirectory ("legacy-" + $guid.Trim('{}') + ".reg")
            if (-not $PSCmdlet.ShouldProcess($key, 'Back up and remove orphaned uninstall registry entry')) { continue }
            & "$env:WINDIR\System32\reg.exe" export $native $backup /y | Out-Null
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backup)) {
                Write-Warning "Backup failed; no deletion: $key"
                continue
            }
            Remove-Item -LiteralPath $key -Recurse -Force
            Write-Host "Removed orphaned entry: $($p.Name); backup: $backup"
        }
        elseif ($state -eq 5) {
            if (-not $PSCmdlet.ShouldProcess("$($p.Name) ($guid)", 'Uninstall installed legacy MSI product')) { continue }
            $log = Join-Path $LogDirectory ("legacy-" + $guid.Trim('{}') + ".log")
            $arguments = "/x $guid /qn /norestart /L*v " + '"' + $log + '"'
            $proc = Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $arguments -PassThru -Wait
            Write-Host "Uninstall $($p.Name): exit $($proc.ExitCode); log: $log"
        }
        else {
            Write-Warning "Keeping $($p.Name): ProductState=$state; no safe automated cleanup."
        }
    }
    Write-Host "Legacy candidates with explicit pre-2026 year: $($legacy.Count)"
}
