#r "System.Windows.Forms"
#r "System.Drawing"

using namespace System.Windows.Forms
using namespace System.Drawing

# 1. Self-elevate
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "powershell.exe"
    $startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $startInfo.Verb = "runas"
    [System.Diagnostics.Process]::Start($startInfo) | Out-Null
    exit
}

# Add types
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$LogFile = Join-Path $PSScriptRoot "CM-PROB-DISABLED-Fixer_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$global:foundDrivers = @()

function Log-Write {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Message"
    Out-File -FilePath $LogFile -InputObject $line -Append
}

Log-Write "Tool started with Administrator privileges."

# GUI Setup
$form = New-Object Form
$form.Text = "CM_PROB_DISABLED Fixer"
$form.Size = New-Object Size(600, 500)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$txtOutput = New-Object TextBox
$txtOutput.Multiline = $true
$txtOutput.ReadOnly = $true
$txtOutput.ScrollBars = "Vertical"
$txtOutput.Location = New-Object Point(10, 10)
$txtOutput.Size = New-Object Size(560, 300)
$txtOutput.Font = New-Object Font("Consolas", 9)
$form.Controls.Add($txtOutput)

$btnDiagnose = New-Object Button
$btnDiagnose.Text = "Diagnose"
$btnDiagnose.Location = New-Object Point(10, 320)
$btnDiagnose.Size = New-Object Size(120, 40)
$form.Controls.Add($btnDiagnose)

$btnApplyFix = New-Object Button
$btnApplyFix.Text = "Apply Fix"
$btnApplyFix.Location = New-Object Point(140, 320)
$btnApplyFix.Size = New-Object Size(120, 40)
$btnApplyFix.Enabled = $false
$form.Controls.Add($btnApplyFix)

$btnDDU = New-Object Button
$btnDDU.Text = "Download DDU"
$btnDDU.Location = New-Object Point(300, 320)
$btnDDU.Size = New-Object Size(120, 40)
$btnDDU.Visible = $false
$form.Controls.Add($btnDDU)

$btnAMD = New-Object Button
$btnAMD.Text = "AMD Drivers"
$btnAMD.Location = New-Object Point(430, 320)
$btnAMD.Size = New-Object Size(120, 40)
$btnAMD.Visible = $false
$form.Controls.Add($btnAMD)

function Print-Msg {
    param([string]$Message)
    $txtOutput.AppendText($Message + "`r`n")
    Log-Write $Message
}

function Run-Diagnostic {
    $txtOutput.Clear()
    Print-Msg "=== Starting Diagnosis ==="
    $global:foundDrivers = @()
    $matchFound = $false

    # Check PnP Devices
    Print-Msg "Checking Display Adapters..."
    $devices = Get-PnpDevice -Class Display -PresentOnly
    $disabledCount = 0
    foreach ($dev in $devices) {
        $status = $dev.Status
        $errCode = $dev.ConfigManagerErrorCode
        Print-Msg "Found: $($dev.FriendlyName) | Status: $status | ErrorCode: $errCode"
        if ($errCode -eq "CM_PROB_DISABLED") {
            $disabledCount++
        }
    }

    if ($disabledCount -eq 0) {
        Print-Msg "`nNo devices found with CM_PROB_DISABLED."
    } else {
        Print-Msg "`nFound $disabledCount device(s) with CM_PROB_DISABLED."
    }

    # Check Event Log
    Print-Msg "`nChecking Event Log for ID 411 in the last 7 days..."
    $events = Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Kernel-PnP/Device Configuration'; Id=411; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue
    
    if ($events) {
        $drivers = @()
        foreach ($evt in $events) {
            if ($evt.Message -match "Driver Name:\s*(oem\d+\.inf)") {
                $driver = $matches[1]
                if ($driver -notin $drivers) {
                    $drivers += $driver
                }
            }
        }
        
        if ($drivers.Count -gt 0) {
            Print-Msg "Found problematic driver(s) from Event 411: $($drivers -join ', ')"
            $global:foundDrivers = $drivers
            if ($disabledCount -gt 0) {
                $matchFound = $true
            }
        } else {
            Print-Msg "No broken OEM drivers identified from Event 411."
        }
    } else {
        Print-Msg "No Event 411 entries found."
    }

    Print-Msg "`n=== Verdict ==="
    if ($matchFound) {
        Print-Msg "This matches the known issue."
        $btnApplyFix.Enabled = $true
    } elseif ($disabledCount -eq 0) {
        Print-Msg "This does NOT match — do not proceed, see README."
        $btnApplyFix.Enabled = $false
    } else {
        Print-Msg "Inconclusive. Devices are disabled but no driver identified in logs."
        $btnApplyFix.Enabled = $false
    }
}

$btnDiagnose.Add_Click({
    Run-Diagnostic
})

$btnApplyFix.Add_Click({
    if ($global:foundDrivers.Count -eq 0) { return }

    $commands = @()
    foreach ($drv in $global:foundDrivers) {
        $commands += "pnputil /delete-driver $drv /uninstall /force"
    }

    $msg = "The following commands will be executed:`n`n" + ($commands -join "`n") + "`n`nYes, proceed?"
    $result = [MessageBox]::Show($msg, "Confirm Action", [MessageBoxButtons]::YesNo, [MessageBoxIcon]::Warning)
    
    if ($result -eq [DialogResult]::Yes) {
        Print-Msg "`n=== Applying Fix ==="
        foreach ($cmd in $commands) {
            Print-Msg "Running: $cmd"
            $cmdParts = $cmd -split " "
            try {
                $proc = Start-Process -FilePath $cmdParts[0] -ArgumentList ($cmdParts[1..$cmdParts.Length] -join " ") -Wait -NoNewWindow -PassThru
                Print-Msg "Exit code: $($proc.ExitCode)"
            } catch {
                Print-Msg "Failed to run command: $_"
            }
        }

        Print-Msg "`nApplying Windows Update Registry Key (ExcludeWUDriversInQualityUpdate)..."
        try {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ExcludeWUDriversInQualityUpdate" -Value 1 -Type DWord
            Print-Msg "Registry key applied successfully."
        } catch {
            Print-Msg "Failed to apply registry key: $_"
        }

        Print-Msg "`nRe-running diagnostic to confirm..."
        Run-Diagnostic

        $stillDisabled = $false
        $devices = Get-PnpDevice -Class Display -PresentOnly
        foreach ($dev in $devices) {
            if ($dev.ConfigManagerErrorCode -eq "CM_PROB_DISABLED") {
                $stillDisabled = $true
            }
        }

        if ($stillDisabled) {
            Print-Msg "`nAutomatic fix insufficient — manual DDU cleanup required."
            $btnDDU.Visible = $true
            $btnAMD.Visible = $true
        } else {
            Print-Msg "`nFix successful. Please reinstall your graphics drivers if necessary."
        }
    } else {
        Print-Msg "`nFix cancelled by user."
    }
})

$btnDDU.Add_Click({
    Start-Process "https://www.wagnardsoft.com/"
})

$btnAMD.Add_Click({
    Start-Process "https://www.amd.com/en/support/download/drivers.html"
})

$form.ShowDialog() | Out-Null
