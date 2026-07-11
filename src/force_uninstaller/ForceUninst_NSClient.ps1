#Force Remove NSClient utility
#Author: Roy Wang , 2025 Netskope Inc.
#
#This script came from ENG-735239. Customer can't uninstall NSClient, used 3rd Party Tool to remove it.
#Support need a power shell script to resolve similar issue.
#
#[How to use]
#1. put this script under a folder, e.g. C:\Temp\ForceUninst_NSClient.ps1
#   note: also put ForceUninst_Lib.psm1 module file in the same folder.
#2. Open PowerShell as Administrator!
#3. Run the script:
#   powershell -ExecutionPolicy Bypass -File C:\Temp\ForceUninst_NSClient.ps1
#
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
#3. When SelfProtection is enabled, executing this script twice would delete service/driver entry but files left.

# Release History:
# R0.7: 2025/Oct Roy Wang. first version
# R0.8: 2026/Jul Roy Wang. bug fixing and refactoring


param(
    [switch] $Verbose,
    [switch] $DryRun,       #only display target registry keys, values, folders, services, drivers, processes to be removed. Do not actually remove them.
    [switch] $BruteForce    #perform brute-force cleanup of abandoned MSI components registry keys. This may cause some errors if the components are still in use. Use this switch with caution.
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

[string] $NETSCKOPE_DISPLAY_NAME = "Netskope Client"        #APP NAME you saw on Add/Remove Programs
[string] $NETSCKOPE_PRODUCT_NAME = $NETSCKOPE_DISPLAY_NAME
[string[]] $REG_NSCLIENT_INSTALL = @("HKEY_LOCAL_MACHINE\SOFTWARE\Netskope\Provisioning", 
                                    "HKEY_LOCAL_MACHINE\SOFTWARE\NetskopeProductVersions", 
                                    "HKEY_LOCAL_MACHINE\SOFTWARE\NetSkope", 
                                    "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\NetSkope", 
                                    "HKEY_CURRENT_USER\SOFTWARE\NetSkope")
[string[]] $NS_INSTDIR_KEYWORDS = @("\\Netskope") #@("\\Netskope\\STAgent\\", "\\Netskope\\EPDLP", "\\Netskope")
[string[]] $NS_COMPONENT_PATH_KEYWORDS = $NS_INSTDIR_KEYWORDS
[string[]] $INSTALL_FOLDERS = @("$env:ProgramFiles\Netskope", 
                                "${env:ProgramFiles(x86)}\Netskope", 
                                "$env:ProgramData\Netskope")
[string] $NS_PROCESS_SVC = "stAgentSvc"
[string] $NS_PROCESS_UI = "stAgentUI"
[string] $NS_STARTUP_RUN_NAME = $NS_PROCESS_UI
[string] $NS_SVC_STAGENTSVC = "stAgentSvc"
[string] $NS_SVC_STADRV = "stadrv"
[string] $NS_SVC_EPDLPSVC = "epdlp"
[string] $NS_SVC_EPDLPDRV = "epdlpdrv"

$RegKeysToRemove = @()
$RegValuesToRemove = @()
$ProductReg = ""
$ProductCode = ""

Write-Host "Starting Force Uninstallation for '$NETSCKOPE_DISPLAY_NAME'..."
Write-Host "Collecting information from registry and system..."

#brute force cleanup MSI registry entries
$ProductReg = SearchMsiProductReg -DisplayName $NETSCKOPE_DISPLAY_NAME
if([string]::IsNullOrEmpty($ProductReg)){
    Write-Host "Product Registry Key not found! Please use -BruteForce switch to remove abandoned MSI components registry keys."
}
else {
    Write-Host "Product Registry Key=$ProductReg"
    $ProductCode = $($ProductReg | Select-String -Pattern "$REGEX_PRODUCT_KEY" | %{$_.Matches.Groups[1].value})
}

if([string]::IsNullOrEmpty($ProductCode)){
    Write-Error "Product Code is empty! Please use -BruteForce switch to remove abandoned MSI components registry keys."
}
else {
    Write-Host "Product Code=$ProductCode"
    $RegKeysToRemove += $ProductReg
}

Write-Host "Scanning MSI Install Folders Registry Values"
foreach ($keyword in $NS_INSTDIR_KEYWORDS) {
    SearchRegistryValuesByRegex -Path $REG_MSI_INSTALL_FOLDERS_KEY -SearchRegex $keyword | 
    ForEach-Object {
        $item = $_
        if([string]::IsNullOrEmpty($item)){
            return
        }
        $RegValuesToRemove += $item
    }
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

if([string]::IsNullOrEmpty($ProductCode)){
    Write-Host "Product Code is empty, skipping scanning MSI Class Installer Feature Registry Keys"
}
else{
    Write-Host "Scanning MSI Class Installer Feature Registry Keys"
    SearchRegistryKeysByRegex -Path $REG_MSI_INSTCLASS_FEATURE_KEY -SearchRegex $ProductCode | 
    ForEach-Object {
        $item = $_
        if([string]::IsNullOrEmpty($item)){
            return
        }
        $RegKeysToRemove += $item
    }
}

if([string]::IsNullOrEmpty($ProductCode)){
    Write-Host "Product Code is empty, skipping scanning MSI Class Installer UpgradeCode Registry Keys"
}
else{
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

if([string]::IsNullOrEmpty($ProductCode)){
    Write-Host "Product Code is empty, skipping scanning MSI Components Registry Keys"
}
else{
    Write-Host "Scanning MSI Components Registry Keys"
    SearchRegistryKeysByRegex -Path $REG_MSI_COMPONENTS_KEY -SearchRegex $ProductCode | 
        ForEach-Object {
            $item = $_
            if([string]::IsNullOrEmpty($item)){
                return
            }
            $RegKeysToRemove += $item
        }
}

Write-Host "`n`n====================================`n"
#Kill StagentSvc and StagntUI processes before stop stadrv driver service
if(-not $DryRun) {
    #stop service then kill service processes again. It is make sure the service is stopped before deleting the service and driver.
    Write-Host "Stopping NSClient services..."
    Stop-Service -Name $NS_SVC_STAGENTSVC -Force -ErrorAction SilentlyContinue
    Stop-Service -Name $NS_SVC_EPDLPSVC -Force -ErrorAction SilentlyContinue
    
    Write-Host "Killing NSClient processes..."
    KillProcesses -ProcessNames @($NS_PROCESS_SVC, $NS_PROCESS_UI, $NS_SVC_EPDLPSVC)
    
    Write-Host "Deleting NSClient services..."
    DeleteService -ServiceName $NS_SVC_STAGENTSVC -Force
    DeleteService -ServiceName $NS_SVC_EPDLPSVC -Force

    Write-Host "Deleting NSClient drivers..."
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
else{
    Write-Host "[DryRun]Killing NSClient processes: $NS_PROCESS_SVC, $NS_PROCESS_UI, $NS_SVC_EPDLPSVC"
    Write-Host "[DryRun]Deleting NSClient services: $NS_SVC_STAGENTSVC, $NS_SVC_EPDLPSVC"
    Write-Host "[DryRun]Deleting NSClient drivers: $NS_SVC_STADRV, $NS_SVC_EPDLPDRV"

    Write-Host "[DryRun]Removing Install Folders: `n$($INSTALL_FOLDERS -join "  `n")"
    Write-Host "[DryRun]Removing Registry Keys: `n$($REG_NSCLIENT_INSTALL -join "  `n")"
    Write-Host "[DryRun]Removing Startup Run Entry: $NS_STARTUP_RUN_NAME"
}

if(-not $DryRun) {
    Write-Host "Removing Collected Registry Keys"
    foreach ($regKey in $RegKeysToRemove) {
        RemoveRegistryKey -Path $regKey
    }

    Write-Host "Removing Collected Registry Values from $REG_MSI_INSTALL_FOLDERS_KEY"
    foreach ($regValue in $RegValuesToRemove) {
        RemoveRegistryValue -Path "$REG_MSI_INSTALL_FOLDERS_KEY" -ValueName "$regValue"
    }

#brute-force cleanup abandoned components
    if ($BruteForce) {
        Write-Host "Brute-Force Removing Abandoned MSI Components Registry Keys"
        foreach ($keyword in $NS_COMPONENT_PATH_KEYWORDS) {
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
}
else {
    Write-Host "[DryRun] Collected Registry Keys to be remove:"
    foreach ($regKey in $RegKeysToRemove) {
        Write-Host "  => $regKey"
    }
    
    Write-Host "[DryRun] Collected Registry Values from $REG_MSI_INSTALL_FOLDERS_KEY to be removed"
    foreach ($regValue in $RegValuesToRemove) {
        Write-Host "  => $regValue from $REG_MSI_INSTALL_FOLDERS_KEY"
    }

    if ($BruteForce) {
        Write-Host "[DryRun]Brute-Force Removing Abandoned MSI Components Registry Keys"
        foreach ($keyword in $NS_COMPONENT_PATH_KEYWORDS) {
            SearchRegistryKeysByRegex -Path $REG_MSI_COMPONENTS_KEY -SearchRegex $keyword | 
                ForEach-Object {
                    $item = $_
                    if([string]::IsNullOrEmpty($item)){
                        return
                    }
                    Write-Host "[DryRun]Abandoned Components Key=>$item"
                }
        }
    }
}

Write-Host "NSClient Force Uninstallation Completed. Please reboot the system to take effect!!" -ForegroundColor Red -BackgroundColor Yellow
