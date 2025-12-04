#Requires -Version 5.0
#Requires -RunAsAdministrator
Import-Module $PSScriptRoot\nsWatchdog_common.psm1 -Force

$need_restart = IsServiceAbnormalStopped -SvcName $SERVICE_NAME -Verbose
if(-not $need_restart) {
    Write-Host "No need to restart Service '$SERVICE_NAME'. Exiting watchdog."
    exit 0
}

$in_upgrade = IsNSClientInUpgrade -Verbose
if ($in_upgrade) {
    Write-Host "NSClient is currently in upgrade process. Exiting watchdog."
    exit 0
}

Write-Host "Service($SERVICE_NAME) Need restart"
StartService -SvcName $SERVICE_NAME
$running = IsServiceRunning -SvcName $SERVICE_NAME -Verbose
write-Host "Service($SERVICE_NAME) Running after restart: $running"
