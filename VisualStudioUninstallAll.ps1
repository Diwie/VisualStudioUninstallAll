#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
    [switch]$Uninstall,
    [switch]$IncludeMauiAndVsPackages,
    [string]$LogDirectory = (Join-Path $env:TEMP 'VisualStudioUninstallAll')
)
$ErrorActionPreference='Stop'
$root='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products'
if (-not (Test-Path $root)) { throw "Registry path not found: $root" }
$packages = @(foreach ($p in Get-ChildItem -LiteralPath $root) {
    $key = Join-Path $p.PSPath 'InstallProperties'
    if (-not (Test-Path -LiteralPath $key)) { continue }
    $info = Get-ItemProperty -LiteralPath $key
    $name = [string]$info.DisplayName
    if ($name -notmatch '(?i)Visual Studio' -and -not ($IncludeMauiAndVsPackages -and $name -match '(?i)^(vs_|Microsoft\.Maui\.)')) { continue }
    [pscustomobject]@{Name=$name;Version=[string]$info.DisplayVersion;UninstallString=[string]$info.UninstallString;RegistryKey=$p.PSChildName}
})
$packages | Sort-Object Name | Format-Table Name,Version,UninstallString -AutoSize
Write-Host "Found $($packages.Count) matching MSI product(s)."
if (-not $Uninstall) { Write-Host 'Preview only. Pass -Uninstall to attempt removal.'; return }
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run PowerShell as Administrator.' }
New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null
$results = foreach ($p in $packages) {
    $cmd = $p.UninstallString.Trim()
    $guid = $null
    if ($cmd -match '(?i)^\s*"?(?:[^"\s]*\\)?msiexec(?:\.exe)?"?\s+/[ix]\s*(\{[0-9a-f-]{36}\})') { $guid=$Matches[1] }
    if (-not $guid) { Write-Warning "Skipped unsupported command: $($p.Name): $cmd"; continue }
    if (-not $PSCmdlet.ShouldProcess("$($p.Name) ($guid)",'Uninstall MSI product')) { continue }
    $log = Join-Path $LogDirectory ("$($guid.Trim('{}')).log")
    $args = "/x $guid /qn /norestart /L*v `"$log`""
    $proc=Start-Process -FilePath "$env:WINDIR\System32\msiexec.exe" -ArgumentList $args -PassThru -Wait
    [pscustomobject]@{Name=$p.Name;ProductCode=$guid;ExitCode=$proc.ExitCode;Log=$log}
}
if ($results) {
    $report=Join-Path $LogDirectory 'results.csv'
    $results | Export-Csv -Path $report -NoTypeInformation -Encoding UTF8
    $results | Format-Table -AutoSize
    Write-Host "Results: $report"
}
Write-Warning 'MSI errors 1603/1612/1714 may require restoring missing installation media. This tool does not delete registry keys.'
