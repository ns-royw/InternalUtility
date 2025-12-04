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
    [switch] $NSClient,
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

[string] $NETSCKOPE_DISPLAY_NAME = "Netskope Client"  #APP NAME you saw on Add/Remove Programs
[string] $NETSCKOPE_PRODUCT_NAME = $NETSCKOPE_DISPLAY_NAME
[string[]] $REG_NSCLIENT_INSTALL = @("HKEY_LOCAL_MACHINE\SOFTWARE\Netskope\Provisioning", 
                                    "HKEY_LOCAL_MACHINE\SOFTWARE\NetskopeProductVersions", 
                                    "HKEY_LOCAL_MACHINE\SOFTWARE\NetSkope", 
                                    "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\NetSkope", 
                                    "HKEY_CURRENT_USER\SOFTWARE\NetSkope")
[string[]] $NSCLIENT_INSTDIR_KEYWORDS = @("\\Netskope") #@("\\Netskope\\STAgent\\", "\\Netskope\\EPDLP", "\\Netskope")
[string[]] $NSCLIENT_COMPONENT_PATH_KEYWORDS = $NSCLIENT_INSTDIR_KEYWORDS
[STRING[]] $INSTALL_FOLDERS = @("$env:ProgramFiles\Netskope", 
                                "${env:ProgramFiles(x86)}\Netskope", 
                                "$env:ProgramData\Netskope")
[string] $NS_PROCESS_SVC = "stAgentSvc"
[string] $NS_PROCESS_UI = "stAgentUI"
[string] $NS_STARTUP_RUN_NAME = $NS_PROCESS_UI
[string] $NS_SVC_STAGENTSVC = "stAgentSvc"
[string] $NS_SVC_STADRV = "stadrv"
[string] $NS_SVC_EPDLPSVC = "epdlp"
[string] $NS_SVC_EPDLPDRV = "epdlpdrv"


if($NSClient -and ![string]::IsNullOrEmpty($AppDisplayName))
{
    Write-Error "Please don’t use options 'NSClient' and 'AppName' at the same time."
    return -1
}
elseif (!$NSClient -and [string]::IsNullOrEmpty($AppDisplayName))
{
    Write-Error "No options assigned. Please assign an option 'NSClient' OR 'AppName'."
    return -2
}

if(![string]::IsNullOrEmpty($AppDisplayName))
{
    RemoveMSIRegistryForApp -DisplayName $AppDisplayName -ProductName $AppDisplayName
}
elseif($NSClient){
    #Kill StagentSvc and StagntUI processes before stop stadrv driver service
    KillProcesses -ProcessNames @($NS_PROCESS_SVC, $NS_PROCESS_UI, $NS_SVC_EPDLPSVC)

    if(!$Debugging)
    {
        DeleteService -ServiceName $NS_SVC_STAGENTSVC -Force
        DeleteService -ServiceName $NS_SVC_EPDLPSVC -Force
        
        StopDriver -DriverSvcName $NS_SVC_STADRV 
        DeleteDriver -ServiceName $NS_SVC_STADRV 
        
        StopDriver -DriverSvcName $NS_SVC_EPDLPDRV 
        DeleteDriver -ServiceName $NS_SVC_EPDLPDRV 

        EnableProcessTokenPrivilege

        # #cleanup registry, install folders, startup run
        RemoveFolders -PathList $INSTALL_FOLDERS -TakeOwner
        RemoveRegistryKeys -PathList $REG_NSCLIENT_INSTALL 
        RemoveAppStartupRun -Name $NS_STARTUP_RUN_NAME 
    }

    $RegKeysToRemove = @()
    $RegValuesToRemove = @()

    #brute force cleanup MSI registry entries
    $ProductReg = SearchMsiProductReg -DisplayName $NETSCKOPE_DISPLAY_NAME
    if([string]::IsNullOrEmpty($ProductReg)){
        $ProductReg = "empty..."
    }
    $ProductCode = $($ProductReg | Select-String -Pattern "$REGEX_PRODUCT_KEY" | %{$_.Matches.Groups[1].value})
    if([string]::IsNullOrEmpty($ProductCode)){
        $ProductCode = "empty..."
    }
    Write-Host "Product Registry Key=$ProductReg, Product Code=$ProductCode"
    $RegKeysToRemove += $ProductReg

    Write-Host "Scanning MSI Install Folders Registry Values"
    SearchRegistryValuesByRegex -Path $REG_MSI_INSTALL_FOLDERS_KEY -SearchRegex $keyword | 
        ForEach-Object {
            $item = $_
            if([string]::IsNullOrEmpty($item)){
                return
            }
            $RegValuesToRemove += $item
        }

    Write-Host "Scanning MSI Class Installer Product Registry Keys"
    SearchRegistryKeysByRegex -Path $REG_MSI_INSTCLASS_PRODUCT_KEY -SearchRegex $NETSCKOPE_PRODUCT_NAME | 
        ForEach-Object {
            $item = $_
            if([string]::IsNullOrEmpty($item)){
                return
            }
            Write-Host "Product Key=>$item"
            $RegKeysToRemove += $item
        }
    
    Write-Host "Scanning MSI Class Installer Feature Registry Keys"
    SearchRegistryKeysByRegex -Path $REG_MSI_INSTCLASS_FEATURE_KEY -SearchRegex $ProductCode | 
        ForEach-Object {
            $item = $_
            if([string]::IsNullOrEmpty($item)){
                return
            }
            $RegKeysToRemove += $item
        }

    Write-Host "Scanning MSI Class Installer UpgradeCodes Registry Keys"
    SearchRegistryKeysByRegex -Path $REG_MSI_INSTCLASS_UPGRADE_KEY -SearchRegex $ProductCode | 
        ForEach-Object {
            $item = $_
            if([string]::IsNullOrEmpty($item)){
                return
            }
            Write-Host "UpgradeCodes Key=>$item"
            $RegKeysToRemove += $item
        }

    Write-Host "Scanning MSI Uninstall Registry Keys"
    SearchRegistryKeysByRegex -Path $REG_MSI_UNINST_KEY -SearchRegex $NETSCKOPE_PRODUCT_NAME | 
        ForEach-Object {
            $item = $_
            if([string]::IsNullOrEmpty($item)){
                return
            }
            $RegKeysToRemove += $item
        }

    Write-Host "Scanning MSI Components Registry Keys"
    SearchRegistryKeysByRegex -Path $REG_MSI_COMPONENTS_KEY -SearchRegex $ProductCode | 
        ForEach-Object {
            $item = $_
            if([string]::IsNullOrEmpty($item)){
                return
            }
            $RegKeysToRemove += $item
        }

    if(!$Debugging)
    {
        Write-Host "Removing Collected Registry Keys and Values..."
        foreach ($regKey in $RegKeysToRemove) {
            RemoveRegistryKey -Path $regKey
        }
        foreach ($regValue in $RegValuesToRemove) {
            RemoveRegistryValue -Path "$REG_MSI_INSTALL_FOLDERS_KEY" -ValueName "$regValue"
        }
    }

    if(!$Debugging)
    {
    #brute-force cleanup abandoned components
        Write-Host "Brute-Force Removing Abandoned MSI Components Registry Keys"
        foreach ($keyword in $NSCLIENT_COMPONENT_PATH_KEYWORDS) {
            SearchRegistryKeysByRegex -Path $REG_MSI_COMPONENTS_KEY -SearchRegex $keyword | 
                ForEach-Object {
                    $item = $_
                    if([string]::IsNullOrEmpty($item)){
                        return
                    }
                    Write-Host "Abandoned Components Key=>$item"
                    RemoveRegistryKey -Path $item
                }
            }
    }

    Write-Host "NSClient Force Uninstallation Completed. Please reboot the system to take effect!!" -ForegroundColor Red -BackgroundColor Yellow
}
