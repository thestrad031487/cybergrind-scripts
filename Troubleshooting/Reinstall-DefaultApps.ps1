<#
.SYNOPSIS
    Re-registers all default Windows 10/11 apps (Start Menu, File Explorer,
    Settings, Camera, Mail, Edge, etc.) to fix corruption without a full reinstall.

.DESCRIPTION
    Runs Get-AppxPackage -AllUsers and re-registers each installed app's
    AppxManifest.xml. This effectively "reinstalls" every built-in Windows app,
    which can resolve issues like a broken Start Menu, a crashing Settings app,
    a non-functional taskbar, or other basic Windows features misbehaving.

    Errors during individual package registrations are common and often benign
    (a resource in use, a system package that can't be re-registered by design)
    — this script logs them but keeps going rather than stopping on the first
    failure, then summarizes success/failure counts at the end.

.PARAMETER LogPath
    Optional. Where to write the log file. Defaults to
    C:\Windows\Temp\Reinstall-DefaultApps_<timestamp>.log

.EXAMPLE
    .\Reinstall-DefaultApps.ps1

.NOTES
    Must be run from an elevated (Administrator) PowerShell session.
    A restart is recommended after running, even if some packages logged errors.
#>

[CmdletBinding()]
param(
    [string]$LogPath = "C:\Windows\Temp\Reinstall-DefaultApps_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $line
    switch ($Level) {
        'WARN'  { Write-Warning $Message }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
}

# --- Admin check ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Right-click PowerShell and choose 'Run as administrator', then re-run this script."
    exit 1
}

Write-Log "=== Reinstall Default Windows Apps started ==="
Write-Log "Log file: $LogPath"

$packages = Get-AppxPackage -AllUsers
Write-Log "Found $($packages.Count) installed app packages to re-register."

$successCount = 0
$failCount = 0
$failedPackages = @()

foreach ($package in $packages) {
    $manifestPath = Join-Path $package.InstallLocation 'AppxManifest.xml'

    if (-not (Test-Path $manifestPath)) {
        Write-Log "Skipping $($package.PackageFullName) — manifest not found at $manifestPath (install location may be missing)." -Level WARN
        $failCount++
        $failedPackages += $package.PackageFullName
        continue
    }

    try {
        Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop
        Write-Log "Re-registered: $($package.PackageFullName)"
        $successCount++
    }
    catch {
        Write-Log "Failed to re-register $($package.PackageFullName): $($_.Exception.Message)" -Level WARN
        $failCount++
        $failedPackages += $package.PackageFullName
    }
}

# --- Summary ---
Write-Log "=== Summary ==="
Write-Log "Total packages processed: $($packages.Count)"
Write-Log "Successfully re-registered: $successCount"
Write-Log "Failed or skipped: $failCount"

Write-Host ""
Write-Host "=========================================="
Write-Host " Reinstall Default Windows Apps — Summary"
Write-Host "=========================================="
Write-Host " Total packages   : $($packages.Count)"
Write-Host " Re-registered OK : $successCount"
Write-Host " Failed / skipped : $failCount"
Write-Host " Log file         : $LogPath"
Write-Host "=========================================="

if ($failCount -gt 0) {
    Write-Host ""
    Write-Host "Note: Failures are common and often benign (a resource in use, or a" -ForegroundColor Yellow
    Write-Host "system package that isn't meant to be re-registered this way). Review" -ForegroundColor Yellow
    Write-Host "the log if problems persist after restarting." -ForegroundColor Yellow
}

# --- Restart prompt ---
$answer = Read-Host "It's recommended to restart the PC to complete this process. Restart now? (Y/N)"
if ($answer -match '^[Yy]') {
    Write-Log "User confirmed restart."
    Restart-Computer -Force
}
else {
    Write-Log "User declined restart. Remember to restart the PC manually to complete the process."
}
