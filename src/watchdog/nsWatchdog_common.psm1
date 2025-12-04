[string] $WATCHDOG_SCRIPT = "nsWatchdog.ps1"
[string] $TASK_NAME = "nsWatchdog"
[string] $TASK_DESCRIPTION = "Monitor NSClient Service and restart if not running"
[int] $WATCHDOG_INTERVAL_SECONDS = 60
[string] $SERVICE_NAME = "stAgentSvc"
[string] $UPGRADE_MONITOR_NAME = "stAgentSvcMon"
[string] $UPGRADE_REG_PATH = "HKLM:\SOFTWARE\Netskope"
[string] $UPGRADE_VALUE_NAME = "UpgradeInProgress"

#current folder of this script, without tail backslash
#Write-Host "Root = $PSScriptRoot"

#fullpath of current script
#$PSCommandPath = "$PSScriptRoot\$WATCHDOG_SCRIPT"
#Write-Host "CmdPath = $PSCommandPath"

function StartService() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$SvcName
    )

    Write-Host "Starting [$SvcName] services..."
    Start-Service -Name $SvcName -ErrorAction SilentlyContinue
}
function IsServiceRunning() {
    [CmdletBinding()]
    [OutputType([boolean])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SvcName
        # #if true == $RunningStateOnly, this function only checks if the service is running
        # #if false == $RunningStateOnly, this function checks if the service is stopped(start pending and stop pending also return true)
        # [Parameter(Mandatory=$false)]
        # [boolean]$RunningStateOnly = $true
    )

    $service = Get-Service -Name $SvcName -ErrorAction SilentlyContinue    
    if ($null -eq $service) {
        Write-Verbose "Service '$SvcName' not found."
        return $false
    }

    $svc_status = $($service.Status)
    # if($svc_status -eq "Running") {
    #     Write-Verbose "Service '$SvcName' is running."
    #     return $true
    # } elseif((-not $RunningStateOnly) -and ($svc_status -ne "Stopped")) {
    #     Write-Verbose "Service '$SvcName' is running (not stopped). Current state: '$svc_status'."
    #     return $true
    # }
    
    # Write-Verbose "Service '$SvcName' is not running. Current state: '$svc_status'."
    # return $false
    if($svc_status -eq "Stopped") {
        Write-Verbose "Service '$SvcName' is stopped."
        return $false
    }
    Write-Verbose "Service '$SvcName' is running. Current state: '$svc_status'."
    return $true
}

function IsServiceAbnormalStopped{
    [CmdletBinding()]
    [OutputType([boolean])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SvcName
    )
    $is_running = IsServiceRunning -SvcName $SvcName
    if(-not $is_running) {
        $svc_exitcode = $(Get-CimInstance Win32_Service -Filter "Name='$SvcName'" | Select-Object Exitcode | Out-String)
        Write-Verbose "Service '$SvcName' Exitcode: $svc_exitcode"
        if ($svc_exitcode -ne "0") {
            Write-Verbose "Service '$SvcName' is abnormally stopped."
            return $true
        }
        Write-Verbose "Service '$SvcName' win32_exit_code=$win32_exit_code"
    }

    Write-Verbose "Service '$SvcName' state '$is_running'"
    return $false
}

function IsNSClientInUpgrade() {
    [CmdletBinding()]
    [OutputType([boolean])]
    param()
    $is_upgrading = $false
    try {
        $upgrade_value = Get-ItemProperty -Path $UPGRADE_REG_PATH -Name $UPGRADE_VALUE_NAME -ErrorAction Stop
        Write-Verbose "Upgrade registry value found: $($upgrade_value.$UPGRADE_VALUE_NAME)"
        if ($upgrade_value.$UPGRADE_VALUE_NAME -eq 1) {
            $is_upgrading = $true
        }
    } catch {
        # If the registry key or value does not exist, assume no upgrade is in progress
        Write-Verbose "Upgrade registry key or value not found. Assuming no upgrade in progress."
        $is_upgrading = $false
    }
    $monitor_running = IsServiceRunning -SvcName $UPGRADE_MONITOR_NAME
    $result = $is_upgrading -or $monitor_running
    Write-Verbose "NSClient upgrade status: $result"
    return $result
}

Export-ModuleMember -Variable *
Export-ModuleMember -Function *
