<#
.SYNOPSIS
    PowerShell Script for Monitoring RDP Logon Activities via Event ID 4624.

.DESCRIPTION
    This script generates a CSV report detailing Remote Desktop Protocol (RDP) logon activities based 
    on Event ID 4624. It helps monitor remote access and detect potential security risks.

.AUTHOR
    Luiz Hamilton Silva - @brazilianscriptguy

.VERSION
    Last Updated: October 22, 2024
#>

Param(
    [Bool]$AutoOpen = $false
)

# Hide the PowerShell console window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Hide() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 0); // 0 = SW_HIDE
    }
    public static void Show() {
        var handle = GetConsoleWindow();
        ShowWindow(handle, 5); // 5 = SW_SHOW
    }
}
"@

[Window]::Hide()

# Import necessary assemblies for Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name for logging purposes
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)

# Get the Domain Server Name
$DomainServerName = [System.Environment]::MachineName

# Set up logging
$logDir = 'C:\Logs-TEMP'
$logFileName = "${scriptName}.log"
$logPath = Join-Path $logDir $logFileName

# Ensure the log directory exists
if (-not (Test-Path $logDir)) {
    $null = New-Item -Path $logDir -ItemType Directory -ErrorAction SilentlyContinue
    if (-not (Test-Path $logDir)) {
        Write-Error "Failed to create log directory at $logDir. Logging will not be possible."
        return
    }
}

# Enhanced logging function with error handling
function Log-Message {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    try {
        Add-Content -Path $logPath -Value $logEntry -ErrorAction Stop
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Declare global variable to store selected log folder path
$global:LogFolderPath = ""

# Create the main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Generate .CSV EventID 4624 Logon Via RDP"
$form.Size = New-Object System.Drawing.Size @(450, 300)
$form.StartPosition = "CenterScreen"

# Create a label for the Browse button
$label = New-Object System.Windows.Forms.Label
$label.Text = "Select the folder containing the Windows Event Logs:"
$label.AutoSize = $true
$label.Location = New-Object System.Drawing.Point @(20, 20)
$form.Controls.Add($label)

# Create the Browse Folder button
$buttonBrowseFolder = New-Object System.Windows.Forms.Button
$buttonBrowseFolder.Text = "Browse"
$buttonBrowseFolder.Location = New-Object System.Drawing.Point @(20, 50)
$form.Controls.Add($buttonBrowseFolder)

# Create the Start Analysis button
$buttonStartAnalysis = New-Object System.Windows.Forms.Button
$buttonStartAnalysis.Text = "Start Analysis"
$buttonStartAnalysis.Enabled = $false
$buttonStartAnalysis.Location = New-Object System.Drawing.Point @(150, 50)
$form.Controls.Add($buttonStartAnalysis)

# Create a progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Location = New-Object System.Drawing.Point @(20, 100)
$progressBar.Size = New-Object System.Drawing.Size @(400, 20)
$form.Controls.Add($progressBar)

# Create a label to display messages
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = ""
$statusLabel.AutoSize = $true
$statusLabel.Location = New-Object System.Drawing.Point @(20, 130)
$form.Controls.Add($statusLabel)

# Function to process Event ID 4624 logs
function Process-EventID4624LogonViaRDP {
    param (
        [string]$LogFolderPath
    )

    Log-Message "Starting to process Event ID 4624 (Logons via RDP)"
    try {
        $progressBar.Value = 25
        $statusLabel.Text = "Processing the Security Event Logs..."
        $form.Refresh()

        $DefaultFolder = [Environment]::GetFolderPath("MyDocuments")
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $csvPath = "$DefaultFolder\$DomainServerName-EventID4624-LogonViaRDP_$timestamp.csv"
        $evtxFilePath = Join-Path $LogFolderPath "Security.evtx"

        if (-not (Test-Path $evtxFilePath)) {
            throw "Log file not found at $evtxFilePath."
        }

        $LogQuery = New-Object -ComObject "MSUtil.LogQuery"
        $InputFormat = New-Object -ComObject "MSUtil.LogQuery.EventLogInputFormat"
        $OutputFormat = New-Object -ComObject "MSUtil.LogQuery.CSVOutputFormat"

        $SQLQuery = @"
SELECT timegenerated AS EventTime, 
       Extract_token(strings, 5, '|') AS UserAccount, 
       Extract_token(strings, 6, '|') AS DomainName, 
       Extract_token(strings, 8, '|') AS LogonType, 
       Extract_token(strings, 10, '|') AS SubStatusCode, 
       Extract_token(strings, 11, '|') AS AccessedResource, 
       Extract_token(strings, 18, '|') AS SourceIP
INTO '$csvPath' 
FROM '$evtxFilePath' 
WHERE eventid = 4624 AND 
      UserAccount NOT IN ('SYSTEM', 'ANONYMOUS LOGON', 'LOCAL SERVICE', 'NETWORK SERVICE') AND 
      DomainName NOT IN ('NT AUTHORITY') AND 
      LogonType = '10'
"@

        $progressBar.Value = 50
        $rtnVal = $LogQuery.ExecuteBatch($SQLQuery, $InputFormat, $OutputFormat)

        $progressBar.Value = 75
        $statusLabel.Text = "Completed. Report exported to $csvPath"
        Log-Message "Report exported to $csvPath"

        if ($AutoOpen) {
            Start-Process $csvPath
        }
        [System.Windows.Forms.MessageBox]::Show("Report exported to $csvPath", 'Report Generated', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        $progressBar.Value = 100
    } catch {
        $errorMsg = "Error processing Event ID 4624: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($errorMsg, 'Error', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Log-Message $errorMsg
        $progressBar.Value = 0
        $statusLabel.Text = "Error occurred. Check log for details."
    } finally {
        $progressBar.Value = 0
    }
}

# Event handler for the Browse Folder button
$buttonBrowseFolder.Add_Click({
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    $folderBrowser.Description = "Select the folder where the Security Event Log is stored."
    if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $global:LogFolderPath = $folderBrowser.SelectedPath
        $statusLabel.Text = "Selected Folder: $global:LogFolderPath"
        Log-Message "Selected Folder for Security Event Logs: $global:LogFolderPath"
        $buttonStartAnalysis.Enabled = $true
    } else {
        $statusLabel.Text = "No folder selected."
        Log-Message "No folder selected."
    }
})

# Event handler for the Start Analysis button
$buttonStartAnalysis.Add_Click({
    Log-Message "Starting analysis of Security Event Log for Event ID 4624 (Logons via RDP)"
    $statusLabel.Text = "Processing..."
    $progressBar.Value = 0
    $form.Refresh()

    # Process the Security Event log
    Process-EventID4624LogonViaRDP -LogFolderPath $global:LogFolderPath

    # Reset progress bar
    $progressBar.Value = 0
})

# Show the main form
$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()

# End of script
