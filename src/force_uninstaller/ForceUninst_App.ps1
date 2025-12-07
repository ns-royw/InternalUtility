#Force Remove NSClient utility
#Author: Roy Wang , 2025/Oct Netskope Inc.
#
#This script came from ENG-735239. Customer can't uninstall NSClient, used 3rd Party Tool to remove it.
#Support need a power shell script to resolve similar issue.
#
#[How to use]
#1. put this script under a folder, e.g. C:\Temp\ForceUninst_NSClient.ps1
#   note: also put ForceUninst_Lib.psm1 module file in the same folder.
#2. Open PowerShell as Administrator!
#3. Run the script:
#   Set-ExecutionPolicy Bypass -Scope Process -Force; .\ForceUninst_NSClient.ps1
#   or you can open a command prompt as admin, and run:
#   powershell -ExecutionPolicy Bypass -File C:\Temp\ForceUninst_NSClient.ps1
#[What this script will do]
#1. Kill NSClient processes: stAgentSvc.exe, stAgentUI.exe
#2. Stop and delete NSClient services: stAgentSvc, stadrv
#3. Remove NSClient install folders
#4. Remove NSClient registry keys
#5. Remove NSClient startup run entry
#6. Remove NSClient MSI registry entries, including uninstall info on Add/Remove Programs
#
#[Limitation]
#1. If SelfProtection is enabled, this script may not work. User have to disable SelfProtection first.
#2. This script only support Windows PowerShell 5.0 and above. (Win10 has built-in PS v5.1)

#handle "-Verbose" parameter of script execution.
#[NOTE]this switch should be first line of this script file.
param(
    [switch] $Verbose,
    [switch] $Debugging,
    [string] $AppDisplayName
)
if ($Verbose) { 
    $Global:VerbosePreference = 'Continue'
}
else {
    $Global:VerbosePreference = 'SilentlyContinue'
}

#PowerShell supports Class since v5.0
#Requires -Version 5.0
#Requires -RunAsAdministrator
Import-Module $PSScriptRoot\ForceUninst_Lib.psm1 -Force     #psm1 module file should be in the same folder as this script

Write-Host "App Force Uninstallation for '$AppDisplayName' Completed. Please reboot the system to take effect!!" -ForegroundColor Red -BackgroundColor Yellow
