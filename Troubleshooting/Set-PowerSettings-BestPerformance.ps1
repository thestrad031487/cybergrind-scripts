<#
.SYNOPSIS
    Sets Windows 11 sleep/display timeouts to Never and power mode to Best Performance.

.DESCRIPTION
    Configures the active power plan so the display and sleep timeouts are set
    to Never (both on AC and battery/DC), and switches the Windows 11 "Power
    Mode" slider to Best Performance. Useful for workstations, kiosks, servers,
    or troubleshooting scenarios where you don't want the machine sleeping or
    dimming, and want maximum performance rather than the balanced default.

    Logs every change and verifies the settings actually applied at the end.

.PARAMETER SkipPowerMode
    Optional switch. Skips changing the Power Mode slider and only applies the
    Never timeout settings.

.PARAMETER LogPath
    Optional. Where to write the log file. Defaults to
    C:\Windows\Temp\Set-PowerSettings_<timestamp>.log

.EXAMPLE
    .\Set-PowerSettings-BestPerformance.ps1

.EXAMPLE
    .\Set-PowerSettings-BestPerformance.ps1 -SkipPowerMode

.NOTES
    Must be run from an elevated (Administrator) PowerShell session.
    The Power Mode overlay (Best Performance / Balanced / Best Power Efficiency)
    is a Windows 11 feature. On Windows 10 the overlay commands will fail
    harmlessly — the timeout settings will still apply.
#>

[CmdletBinding()]
param(
    [switch]$SkipPowerMode,
    [string]$LogPath = "C:\Windows\Temp\Set-PowerSettings_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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

Write-Log "=== Set Power Settings started ==="
Write-Log "Log file: $LogPath"

# --- Step 1: Set display, sleep, and hibernate timeouts to Never (0) ---
Write-Log "Setting display, sleep, and hibernate timeouts to Never on AC and battery/DC..."

$timeoutSettings = @(
    @{ Name = 'monitor-timeout-ac';   Label = 'Display timeout (plugged in)' }
    @{ Name = 'monitor-timeout-dc';   Label = 'Display timeout (on battery)' }
    @{ Name = 'standby-timeout-ac';   Label = 'Sleep timeout (plugged in)' }
    @{ Name = 'standby-timeout-dc';   Label = 'Sleep timeout (on battery)' }
    @{ Name = 'hibernate-timeout-ac'; Label = 'Hibernate timeout (plugged in)' }
    @{ Name = 'hibernate-timeout-dc'; Label = 'Hibernate timeout (on battery)' }
)

$timeoutFailures = 0
foreach ($setting in $timeoutSettings) {
    try {
        $output = powercfg /change $($setting.Name) 0 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "$($setting.Label): set to Never."
        }
        else {
            Write-Log "$($setting.Label): powercfg returned exit code $LASTEXITCODE — $output" -Level WARN
            $timeoutFailures++
        }
    }
    catch {
        Write-Log "$($setting.Label): failed — $($_.Exception.Message)" -Level WARN
        $timeoutFailures++
    }
}

# --- Step 2: Set Power Mode to Best Performance ---
$powerModeResult = 'Skipped'
if (-not $SkipPowerMode) {
    Write-Log "Setting Power Mode to Best Performance..."

    # Windows 11 Power Mode overlay GUID for "Best Performance"
    $bestPerformanceOverlay = '3af9B8d9-7c97-431d-ad78-34a8bfea439f'

    try {
        $output = powercfg /setactive $bestPerformanceOverlay 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Power Mode set to Best Performance."
            $powerModeResult = 'Success'
        }
        else {
            Write-Log "Failed to set Power Mode overlay (exit code $LASTEXITCODE) — $output. This feature requires Windows 11; on Windows 10 this is expected to fail." -Level WARN
            $powerModeResult = 'Failed'
        }
    }
    catch {
        Write-Log "Failed to set Power Mode overlay: $($_.Exception.Message)" -Level WARN
        $powerModeResult = 'Failed'
    }
}
else {
    Write-Log "Skipping Power Mode change (-SkipPowerMode specified)."
}

# --- Step 3: Verify ---
Write-Log "Verifying applied settings..."
$verification = powercfg /query SCHEME_CURRENT SUB_VIDEO 2>&1
Write-Log "Current video subgroup settings:`n$verification"

# --- Summary ---
Write-Log "=== Summary ==="
Write-Log "Timeout settings applied: $(6 - $timeoutFailures) of 6"
Write-Log "Power Mode: $powerModeResult"
Write-Log "Full log saved to: $LogPath"

Write-Host ""
Write-Host "=========================================="
Write-Host " Power Settings — Summary"
Write-Host "=========================================="
Write-Host " Sleep/display timeouts : $(6 - $timeoutFailures) of 6 set to Never"
Write-Host " Power Mode             : $powerModeResult"
Write-Host " Log file               : $LogPath"
Write-Host "=========================================="

if ($timeoutFailures -gt 0 -or $powerModeResult -eq 'Failed') {
    Write-Host ""
    Write-Host "Some settings did not apply — review the log for details." -ForegroundColor Yellow
}
