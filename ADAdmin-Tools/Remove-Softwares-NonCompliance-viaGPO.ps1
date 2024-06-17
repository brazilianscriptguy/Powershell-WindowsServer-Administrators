﻿# PowerShell script to Uninstall Softwares non-Compliance by name via GPO
# Author: Luiz Hamilton Silva - luizhamilton.lhr@gmail.com
# Update: June 17, 2024.

param (
    [string[]]$SoftwareNames = @("ccleaner", "glary util", "broffice"),
    [string]$LogDir = 'C:\Logs-TEMP'
)

$ErrorActionPreference = "Continue"

# Setup the log file name based on the script's name
$scriptName = [System.IO.Path]::GetFileNameWithoutExtension($MyInvocation.MyCommand.Name)
$logFileName = "${scriptName}.log"
$logPath = Join-Path $LogDir $logFileName

# Function for logging messages with error handling
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
        Write-Error "Failed to log in $logPath. Error: $_"
    }
}

try {
    # Ensure the log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -ErrorAction Stop | Out-Null
        Log-Message "Log directory $LogDir created."
    }

    # Search for installed software in the registry
    $installedSoftwarePaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($path in $installedSoftwarePaths) {
        Get-ChildItem $path | ForEach-Object {
            $software = Get-ItemProperty $_.PsPath
            foreach ($name in $SoftwareNames) {
                if ($software.DisplayName -like "*$name*") {
                    $uninstallCommand = $software.UninstallString
                    if ($uninstallCommand -like "*msiexec*") {
                        $uninstallCommand = $uninstallCommand -replace "msiexec.exe", "msiexec.exe /quiet /norestart"
                        $processInfo = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCommand" -Wait -PassThru -NoNewWindow
                    } elseif ($uninstallCommand) {
                        # Assume the uninstallation can be executed silently
                        $processInfo = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $uninstallCommand /S" -Wait -PassThru -NoNewWindow
                    }
                    if ($processInfo -and $processInfo.ExitCode -ne 0) {
                        Log-Message "Error uninstalling $($software.DisplayName) with Exit Code: $($processInfo.ExitCode)"
                    } elseif ($processInfo) {
                        Log-Message "$($software.DisplayName) was uninstalled silently with success via executable command."
                    } else {
                        Log-Message "No uninstallation method found for $($software.DisplayName)."
                    }
                }
            }
        }
    }
} catch {
    Log-Message "An error occurred: $_"
}

# End of script
