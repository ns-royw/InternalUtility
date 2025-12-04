#Requires -Version 5.0
#Requires -RunAsAdministrator
Import-Module $PSScriptRoot\nsWatchdog_common.psm1 -Force

#current folder of this script, without tail backslash
#Write-Host "Root = $PSScriptRoot"

#fullpath of current script
#$PSCommandPath = "$PSScriptRoot\$WATCHDOG_SCRIPT"
#Write-Host "CmdPath = $PSCommandPath"

Write-Host "Uninstalling Scheduled Task '$TASK_NAME' monitoring NSClient Service..."
Unregister-ScheduledTask -TaskName "$TASK_NAME" -Confirm:$false
Write-Host "Scheduled Task '$TASK_NAME' has been uninstalled successfully."