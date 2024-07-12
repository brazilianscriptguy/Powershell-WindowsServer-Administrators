# PowerShell script to Synchronize all DCs in the Forest across All Sites
# Author: Luiz Hamilton Silva - luizhamilton.lhr@gmail.com
# Updated: July 12, 2024

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

# Import necessary modules
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Determine the script name and set up the logging path
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
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
        [string]$Message,
        [Parameter(Mandatory=$false)]
        [string]$MessageType = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$MessageType] $Message"
    try {
        Add-Content -Path $logPath -Value "$logEntry`r`n" -ErrorAction Stop
        $global:logBox.Items.Add($logEntry)
        $global:logBox.TopIndex = $global:logBox.Items.Count - 1
    } catch {
        Write-Error "Failed to write to log: $_"
    }
}

# Function to force synchronization on all DCs
function Sync-AllDCs {
    # Import the Active Directory module
    Import-Module ActiveDirectory

    Log-Message "Starting Active Directory synchronization process: $(Get-Date)"
    Log-Message ""  # Add blank line for better readability

    # Get a list of all domains in the forest
    try {
        $forest = Get-ADForest
        $allDomains = $forest.Domains
    } catch {
        Log-Message "Error retrieving forest domains: $_" -MessageType "ERROR"
        Log-Message ""  # Add blank line for better readability
        [System.Windows.Forms.MessageBox]::Show("Error retrieving forest domains. See log for details.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    # Collect all domain controllers from all domains
    $allDCs = @()
    foreach ($domain in $allDomains) {
        try {
            $domainDCs = Get-ADDomainController -Filter * -Server $domain
            $allDCs += $domainDCs
        } catch {
            Log-Message "Error retrieving domain controllers from ${domain}: $_" -MessageType "ERROR"
            Log-Message ""  # Add blank line for better readability
        }
    }

    # Force synchronization on all domain controllers
    foreach ($dc in $allDCs) {
        $dcName = $dc.HostName
        Write-Output "Forcing synchronization on $dcName"
        Log-Message "Forcing synchronization on ${dcName}: $(Get-Date)"
        try {
            # Perform the synchronization
            $syncResult = & repadmin /syncall /e /d /P /q $dcName
            # Log the result of the synchronization
            Log-Message "Synchronization result for ${dcName}: $syncResult"
        } catch {
            # Log any errors that occur
            Log-Message "Error synchronizing ${dcName}: $_" -MessageType "ERROR"
        }
        # Add blank line to separate DCs
        Log-Message ""  # Add blank line for better readability
    }

    Log-Message "Active Directory synchronization process completed: $(Get-Date)"
    Log-Message ""  # Add blank line after completion message
    [System.Windows.Forms.MessageBox]::Show("Synchronization process completed.", "Info", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# Function to display the log file
function Show-Log {
    notepad $logPath
}

# Create the form
$form = New-Object System.Windows.Forms.Form
$form.Text = "AD Forest Sync Tool"
$form.Size = New-Object System.Drawing.Size(800, 620)  # Increased size to fit content
$form.StartPosition = "CenterScreen"

# Create a ListBox to display log messages
$global:logBox = New-Object System.Windows.Forms.ListBox
$logBox.Location = New-Object System.Drawing.Point(10, 10)
$logBox.Size = New-Object System.Drawing.Size(760, 500)  # Adjusted size to fit form
$form.Controls.Add($logBox)

# Create a button to start synchronization
$syncButton = New-Object System.Windows.Forms.Button
$syncButton.Location = New-Object System.Drawing.Point(50, 520)
$syncButton.Size = New-Object System.Drawing.Size(150, 50)
$syncButton.Text = "Sync All Forest DCs"
$syncButton.Add_Click({
    Sync-AllDCs
})
$form.Controls.Add($syncButton)

# Create a button to view the log
$logButton = New-Object System.Windows.Forms.Button
$logButton.Location = New-Object System.Drawing.Point(250, 520)
$logButton.Size = New-Object System.Drawing.Size(150, 50)
$logButton.Text = "View Output Log"
$logButton.Add_Click({
    Show-Log
})
$form.Controls.Add($logButton)

# Show the form
$form.Add_Shown({$form.Activate()})
[void] $form.ShowDialog()

# End of script
