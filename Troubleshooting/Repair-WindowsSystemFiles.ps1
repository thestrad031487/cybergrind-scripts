<#
.SYNOPSIS
    Automates the DISM + SFC Windows system file repair workflow.

.DESCRIPTION
    Runs DISM /Online /Cleanup-Image /RestoreHealth to repair the component store,
    then runs SFC /scannow to scan and repair corrupted Windows system files.
    Logs all output with timestamps and prints a summary at the end. Optionally
    prompts to restart the machine if repairs were made.

.PARAMETER Source
    Optional. Path to recovery media or a mounted Windows image to use as the
    repair source, for cases where Windows Update is broken and DISM can't pull
    files online. Example: -Source D:\  or  -Source E:\RepairSource\ExtraFolder

.PARAMETER SkipDism
    Optional switch. Skips the DISM step and runs SFC only.

.PARAMETER LogPath
    Optional. Where to write the log file. Defaults to
    C:\Windows\Temp\Repair-WindowsSystemFiles_<timestamp>.log

.EXAMPLE
    .\Repair-WindowsSystemFiles.ps1

.EXAMPLE
    .\Repair-WindowsSystemFiles.ps1 -Source D:\ -Verbose

.EXAMPLE
    .\Repair-WindowsSystemFiles.ps1 -SkipDism

.NOTES
    Must be run from an elevated (Administrator) PowerShell session.
    DISM can take a long time and may appear to sit at 50-70% for a while —
    this is normal. Do not close the window.
#>

[CmdletBinding()]
param(
    [string]$Source,
    [switch]$SkipDism,
    [string]$LogPath = "C:\Windows\Temp\Repair-WindowsSystemFiles_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
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
        'ERROR' { Write-Error $Message }
        default { Write-Host $line }
    }
}

# --- Admin check ---
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Right-click PowerShell and choose 'Run as administrator', then re-run this script."
    exit 1
}

Write-Log "=== Windows System File Repair started ==="
Write-Log "Log file: $LogPath"

$results = [ordered]@{
    DismRan       = $false
    DismExitCode  = $null
    SfcExitCode   = $null
    CorruptionFound = $null
    RepairsMade   = $null
}

# --- Step 1: DISM RestoreHealth ---
if (-not $SkipDism) {
    Write-Log "Starting DISM /Online /Cleanup-Image /RestoreHealth. This can take a long time and may sit at 50-70% for a while — that is normal."

    $dismArgs = @('/Online', '/Cleanup-Image', '/RestoreHealth')
    if ($Source) {
        $dismArgs += "/Source:$Source"
        $dismArgs += '/LimitAccess'
        Write-Log "Using repair source: $Source"
    }

    try {
        $dismProcess = Start-Process -FilePath 'DISM.exe' -ArgumentList $dismArgs -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput "$env:TEMP\dism_stdout.log" -RedirectStandardError "$env:TEMP\dism_stderr.log"
        $results.DismRan = $true
        $results.DismExitCode = $dismProcess.ExitCode

        Get-Content "$env:TEMP\dism_stdout.log" -ErrorAction SilentlyContinue | ForEach-Object { Write-Log "DISM: $_" }

        if ($dismProcess.ExitCode -eq 0) {
            Write-Log "DISM completed successfully (exit code 0)."
        }
        else {
            Write-Log "DISM finished with exit code $($dismProcess.ExitCode). This may indicate DISM could not fully repair the component store, or Windows Update is unreachable — consider re-running with -Source pointing at installation media." -Level WARN
        }
    }
    catch {
        Write-Log "DISM failed to run: $($_.Exception.Message)" -Level ERROR
        $results.DismExitCode = -1
    }
}
else {
    Write-Log "Skipping DISM step (-SkipDism specified)."
}

# --- Step 2: SFC scan ---
Write-Log "Starting SFC /scannow. This can take a while depending on system speed — it may pause at points, this is normal."

try {
    # sfc.exe output is UTF-16LE and Start-Process redirection can mangle it,
    # so we capture it directly via cmd /c and parse the text output.
    $sfcOutput = & cmd.exe /c "sfc /scannow" 2>&1
    $results.SfcExitCode = $LASTEXITCODE

    $sfcOutput | ForEach-Object { Write-Log "SFC: $_" }

    $sfcText = $sfcOutput -join "`n"
    if ($sfcText -match 'did not find any integrity violations') {
        $results.CorruptionFound = $false
        $results.RepairsMade = $false
        Write-Log "SFC found no integrity violations."
    }
    elseif ($sfcText -match 'successfully repaired') {
        $results.CorruptionFound = $true
        $results.RepairsMade = $true
        Write-Log "SFC found corruption and successfully repaired it."
    }
    elseif ($sfcText -match 'found corrupt files but was unable to fix') {
        $results.CorruptionFound = $true
        $results.RepairsMade = $false
        Write-Log "SFC found corruption it could NOT repair. Check CBS.log (C:\Windows\Logs\CBS\CBS.log) for details, or consider re-running DISM with -Source pointing at installation media." -Level WARN
    }
    else {
        Write-Log "Could not parse a definitive result from SFC output — review the log for details." -Level WARN
    }
}
catch {
    Write-Log "SFC failed to run: $($_.Exception.Message)" -Level ERROR
    $results.SfcExitCode = -1
}

# --- Summary ---
Write-Log "=== Summary ==="
Write-Log "DISM exit code: $($results.DismExitCode)"
Write-Log "SFC exit code: $($results.SfcExitCode)"
Write-Log "Corruption found: $($results.CorruptionFound)"
Write-Log "Repairs made: $($results.RepairsMade)"
Write-Log "Full log saved to: $LogPath"

Write-Host ""
Write-Host "=========================================="
Write-Host " Windows System File Repair — Summary"
Write-Host "=========================================="
Write-Host " DISM exit code : $($results.DismExitCode)"
Write-Host " SFC exit code   : $($results.SfcExitCode)"
Write-Host " Corruption found: $($results.CorruptionFound)"
Write-Host " Repairs made    : $($results.RepairsMade)"
Write-Host " Log file        : $LogPath"
Write-Host "=========================================="

# --- Optional restart prompt ---
if ($results.RepairsMade -eq $true) {
    $answer = Read-Host "Repairs were made. It's recommended to restart the PC now. Restart now? (Y/N)"
    if ($answer -match '^[Yy]') {
        Write-Log "User confirmed restart."
        Restart-Computer -Force
    }
    else {
        Write-Log "User declined restart. Remember to restart the PC manually to complete the repair."
    }
}
