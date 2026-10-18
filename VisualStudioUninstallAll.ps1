#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [switch]$Uninstall,
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
    if ($Command -match '(?i)^\s*(?:"[^"]*\\)?msiexec(?:\.exe)?"?|(?:[^\s"]*\\)?msiexec(?:\.exe)?)\s+(?:/[ix]\s*|/package\s+|/uninstall\s+)(\{[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\})') {
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
if (-not $Uninstall) { Write-Host 'Preview only. Pass -Uninstall to attempt removal.'; return }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run PowerShell as Administrator.' }
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$results = foreach ($p in $packages) {
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
}
if ($results) {
    $report = Join-Path $LogDirectory 'results.csv'
    $results | Export-Csv -Path $report -NoTypeInformation -Encoding UTF8
    $results | Format-Table -AutoSize
    Write-Host "Results: $report"
}
Write-Warning 'MSI errors 1603/1612/1714 may require missing installation media. No registry keys are deleted.'
