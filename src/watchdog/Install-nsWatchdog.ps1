#Requires -Version 5.0
#Requires -RunAsAdministrator
Import-Module $PSScriptRoot\nsWatchdog_common.psm1 -Force

Write-Host "Installing Scheduled Task '$TASK_NAME' to monitor NSClient Service..."
#Trigger right now and repeat every WATCHDOG_INTERVAL_SECONDS
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Seconds $WATCHDOG_INTERVAL_SECONDS)

#run spcified script with hidden window and bypass execution policy.
#this script must be placed in the same folder as this installer script.
#TODO: when script are signed, remove -ExecutionPolicy Bypass
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-ExecutionPolicy RemoteSigned -NoProfile -WindowStyle Hidden -File `"$PSScriptRoot\$WATCHDOG_SCRIPT`""

#Settings: allow start on battery power, don't stop if going on battery power
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

#Run as SYSTEM user with highest privileges, no matter who is logged in.
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

Write-Verbose "Script=$PSScriptRoot\$WATCHDOG_SCRIPT"
Write-Verbose "TASK_NAME=$TASK_NAME"
Write-Verbose "WATCH INTERVAL=$WATCHDOG_INTERVAL_SECONDS seconds"

#if register failed, let it throw error. don't set "-ErrorAction SilentlyContinue"
Register-ScheduledTask -TaskName "$TASK_NAME" -Trigger $trigger -Action $action -Description "$TASK_DESCRIPTION" -Principal $principal -Settings $settings
Write-Host "Scheduled Task '$TASK_NAME' has been installed successfully."

exit 0