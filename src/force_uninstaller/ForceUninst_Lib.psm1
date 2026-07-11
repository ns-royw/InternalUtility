#Requires -RunAsAdministrator

#Release Notes
# Author: Roy Wang , 2025/Oct Netskope Inc.
# This script provides MSI-related registry handling and app uninstall functions. 
# Its main purpose is to force-remove apps that have broken MSI information. 
# Before using this script, you must check that it has a Netskope signature.
#
# Release History:
# R0.7: 2025/Oct Roy Wang. first version
# R0.8: 2026/Jul Roy Wang. bug fixing and refactoring

#special notes:
#"product key" is a special order of GUID reprentation used by MSI installer internally.
#for example: 
# if GUID is : {3AA3847B-C582-48AF-AECC-2D9B05D87545}
# convert to byte array=>    7B84A33A 82C5 AF48 AECC 2D9B05D87545
# Product key in registry => B7483AA3 285C FA84 EACC D2B9508D5754
#

[string] $REGEX_PRODUCT_KEY = "([0-9A-Fa-f]{32})"   #hex string, EXAMPLE: 7B7C5F31CED5DDDFD7E984F495D8F0BB
[string] $REG_MSI_PRODUCT_KEY = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products"
[string] $REG_MSI_COMPONENTS_KEY = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Components"
[string] $REG_MSI_UPGRADE_KEY = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UpgradeCodes"
[string] $REG_MSI_INSTCLASS_KEY = "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\Installer"
[string] $REG_MSI_INSTCLASS_PRODUCT_KEY = "$REG_MSI_INSTCLASS_KEY\Products"
[string] $REG_MSI_INSTCLASS_UPGRADE_KEY = "$REG_MSI_INSTCLASS_KEY\UpgradeCodes"
[string] $REG_MSI_INSTCLASS_FEATURE_KEY = "$REG_MSI_INSTCLASS_KEY\Features"
[string] $REG_SYSTEM_SERVICE_KEY = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services"

#"installed folders of product" are values under this registry key
[string] $REG_MSI_INSTALL_FOLDERS_KEY= "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\Folders"

[string[]] $REG_MSI_UNINST_KEY = @("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
                                 "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")

#STARTUP_RUN stores application shortcuts which automatically run when user logon.
[string[]] $REG_STARTUP_RUN = @("HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                              "HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
                              "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")


#in powershell, registry paths use PSDrive format, e.g. "HKLM:\...."
#User doesn't have to know PDDrive Format of registry path.
#I want future developers and users to use the registry key paths they get directly from regedit, 
#without needing to know about the psdrive format.
#So I build this function to convert normal registry path to PSDrive format.
#e.g. "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\" => "HKLM:\SOFTWARE\Microsoft\Windows\"
function ToPSDriveFormat() {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        #ProductRegKey example: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData\S-1-5-18\Products\7B7C5F31CED5DDDFD7E984F495D8F0BB
        [string]$Registry
    )
    
    $found = $Registry.IndexOf("HKEY_LOCAL_MACHINE")
    if($found -eq 0) {
        return $Registry.Replace("HKEY_LOCAL_MACHINE", "HKLM:")
    }
    
    $found = $Registry.IndexOf("HKEY_CURRENT_USER")
    if($found -eq 0) {
        return $Registry.Replace("HKEY_CURRENT_USER", "HKCU:")
    }

    $found = $Registry.IndexOf("HKEY_CLASSES_ROOT")
    if($found -eq 0) {
        return $Registry.Replace("HKEY_CLASSES_ROOT", "HKCR:")
    }

    $found = $Registry.IndexOf("HKEY_USERS")
    if($found -eq 0) {
        return $Registry.Replace("HKEY_USERS", "HKU:")
    }

    $found = $Registry.IndexOf("HKEY_CURRENT_CONFIG")
    if($found -eq 0) {
        return $Registry.Replace("HKEY_CURRENT_CONFIG", "HKCC:")
    }

    #return empty string if format is not recognized.
    return ""
}
function Get-FolderOwnership{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        #e.g. "C:\MyDir\Data"
        [string]$Fullpath
    )
    $currentUser = "$env:USERDOMAIN\$env:USERNAME"
    Write-Verbose "Taking ownership of: $Fullpath"

    takeown /F "$Fullpath" /R /D Y | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Ownership taken successfully via takeown.exe." -ForegroundColor Green
        return $true
    }
    else {
        Write-Verbose "takeown.exe failed. Trying Set-Acl method..."
        try {
            $owner = New-Object System.Security.Principal.NTAccount($currentUser)
            $acl = Get-Acl $Fullpath
            $acl.SetOwner($owner)
            Set-Acl -Path $Fullpath -AclObject $acl
            Write-Host "Ownership reassigned manually." -ForegroundColor Green
            return $true
        }
        catch {
            Write-Host "Failed to take ownership of $Fullpath" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor DarkRed
        }
    }

    return $false
}
function Grant-FolderFullControl() {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory=$true)]
        #e.g. "C:\MyDir\Data"
        [string]$FolderPath
    )

    $currentUser = "$env:USERDOMAIN\$env:USERNAME"
    $dir_rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $currentUser,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $file_rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $currentUser,
        "FullControl",
        "None",
        "None",
        "Allow"
    )

    Write-Host "`n=== Processing: $FolderPath ===" -ForegroundColor Magenta

	if(Test-Path $FolderPath)
	{
		try {
			$got_owner = Get-FolderOwnership $FolderPath

            if(!$got_owner) {
                Write-Error "Failed to take ownership of $FolderPath. Cannot apply FullControl."
                return $false
            }
			$acl = Get-Acl $FolderPath
			$acl.SetAccessRuleProtection($false, $false)  # disable inherited ACL protection if needed
			$acl.AddAccessRule($dir_rule)
			Set-Acl -Path $FolderPath -AclObject $acl
			Write-Host "Applied FullControl to $FolderPath folder." -ForegroundColor Green

			Get-ChildItem -LiteralPath $FolderPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
				try {
					$acl = Get-Acl $_.FullName
					$acl.AddAccessRule($file_rule)
					Set-Acl -Path $_.FullName -AclObject $acl
				}
				catch {
                    Write-Host "$($_.FullName): Failed to apply FullControl. Error: $($_.Exception.Message)" -ForegroundColor Red
                }
			}
            return $true
		}
		catch {
			Write-Error "Error applying ACLs to: $FolderPath"
			Write-Error $_.Exception.Message
		}
	}
	else{
		Write-Host "$FolderPath Doesn't exist"
	}
  return $false
}
function EnableProcessTokenPrivilege {
    [CmdletBinding()]
    param()
    $definition = @"
    using System;
    using System.Runtime.InteropServices;

    public class PrivilegeHelper {
    [DllImport("advapi32.dll", ExactSpelling=true, SetLastError=true)]
    internal static extern bool AdjustTokenPrivileges(IntPtr htoken, bool disable_all,
        ref TOKEN_PRIVILEGES new_state, int len, IntPtr prev_state, IntPtr retlen);
    
    [DllImport("advapi32.dll", ExactSpelling=true, SetLastError=true)]
    internal static extern bool OpenProcessToken(IntPtr handle, int desired_access, ref IntPtr token_handle);
    
    [DllImport("advapi32.dll", SetLastError=true)]
    internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);
    
    //only define 1 element in TOKEN_PRIVILEGES::Privileges so don't using array.
    [StructLayout(LayoutKind.Sequential, Pack=1)]
    internal struct TOKEN_PRIVILEGES {
        public int Count;
        public long Luid;
        public int Attr;
    }

    internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
    internal const int TOKEN_QUERY = 0x00000008;
    internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;
    public static bool Enable(string privilege) {
        IntPtr htoken = IntPtr.Zero;
        bool ok1 = OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle,
            TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htoken);
        TOKEN_PRIVILEGES tp;
        tp.Count = 1;
        tp.Luid = 0;
        tp.Attr = SE_PRIVILEGE_ENABLED;
        bool ok2 = LookupPrivilegeValue(null, privilege, ref tp.Luid);
        bool ok3 = AdjustTokenPrivileges(htoken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        return ok1 && ok2 && ok3;
    }
}
"@
    Add-Type $definition #-ErrorAction SilentlyContinue
# Enable necessary privileges
    $action_ok = [PrivilegeHelper]::Enable("SeTakeOwnershipPrivilege")
    if(!$action_ok) {
        Write-Warning "Failed to enable SeTakeOwnershipPrivilege"
    }
    $action_ok = [PrivilegeHelper]::Enable("SeRestorePrivilege")
    if(!$action_ok) {
        Write-Warning "Failed to enable SeRestorePrivilege"
    }
    $action_ok = [PrivilegeHelper]::Enable("SeBackupPrivilege")
    if(!$action_ok) {
        Write-Warning "Failed to enable SeBackupPrivilege"
    }
}
function SearchMsiProductReg {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$false)]
        #$DisplayName example: "MSI Development Tools"
        [string]$DisplayName
    )

    $regpath = ToPSDriveFormat($REG_MSI_PRODUCT_KEY)
    #Normally we shouldn't get an empty string here, but let's check it just to be safe.
    if([string]::IsNullOrEmpty($regpath)) {
        Write-Warning "Failed to convert registry path to PSDrive format: $REG_MSI_PRODUCT_KEY"
        return ""
    }
    $found = Get-Childitem -path $regpath | SELECT *
    ForEach($item in $found) {
        $pspth = ToPSDriveFormat("$($item.Name)\InstallProperties\")
        
        #Normally we shouldn't get an empty string here, but let's check it just to be safe.
        if([string]::IsNullOrEmpty($pspth)) {
            continue
        }
        $values = Get-ItemProperty -path  $pspth -ErrorAction SilentlyContinue
        if(!$values) {
            continue
        }
        if($DisplayName -eq $values.DisplayName) {
            Write-Host "Product($DisplayName) registry => $regpath"
            return "$($item.Name)\InstallProperties\"
        }
    }
}
function SearchMsiComponentByProduct {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory=$true)]
        #example: 7B7C5F31CED5DDDFD7E984F495D8F0BB
        [string]$ProductCode
    )
    
    Write-Host "Search Component by ProductKey($ProductCode) starting..."
    $counter = 0
    [string[]] $ret = @()
    
    $pspath = ToPSDriveFormat($REG_MSI_COMPONENTS_KEY)
    #Normally we shouldn't get an empty string here, but let's check it just to be safe.
    if([string]::IsNullOrEmpty($pspath)) {
        Write-Warning "Failed to convert registry path to PSDrive format: $REG_MSI_COMPONENTS_KEY"
        return $ret
    }
    Get-Childitem -path $pspath |
        ForEach-Object {
            $item = $_
            $counter++
            if(($counter % 100) -eq 0) {
                Write-Verbose "Searched ($counter)Components, found ($($ret.Length))) matched comonents..."
            }
            
            $found_keys = $item.Property
            ForEach($key in $found_keys) {
                #each component could map to multiple products.
                if($ProductCode -eq $key) {
                    $ret = @($ret + $($item.Name))
                    Write-Verbose "Found Component=>$($item.Name)"
                }
            }
        }
    Write-Verbose "Searched ($counter)Components, found ($($ret.Length)) matched ..."
    return $ret
}
function SearchUpgradeCodeByProduct {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        #example: 7B7C5F31CED5DDDFD7E984F495D8F0BB
        [string]$ProductCode
    )
    
    [string] $ret = ""
    Write-Host "Search UpgradeCode by ProductCode($ProductCode) starting..."
    $pspath = ToPSDriveFormat($REG_MSI_UPGRADE_KEY)
    #Normally we shouldn't get an empty string here, but let's check it just to be safe.
    if(![string]::IsNullOrEmpty($pspath)) {
        $found_regs = (Get-Childitem -path $pspath | SELECT *)
        ForEach($item in $found_regs) {
            $key = $($item.Property)
            if($ProductCode -eq $key) {
                $ret = $($item.Name)
                Write-Verbose "Found UpgradeCode Reg=$ret"
                break
            }
        }
    }
    return $ret
}
function SearchFeatureTreeByProduct {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        #example: 7B7C5F31CED5DDDFD7E984F495D8F0BB
        [string]$ProductCode
    )
    
    Write-Host "Search Feature Tree by ProductCode($ProductCode) starting..."
    [string] $ret = ""
    $pspath = ToPSDriveFormat($REG_MSI_INSTCLASS_FEATURE_KEY)
    #Normally we shouldn't get an empty string here, but let's check it just to be safe.
    if(![string]::IsNullOrEmpty($pspath)) {
        $found_regs = (Get-Childitem -path $pspath | SELECT *)
        ForEach($item in $found_regs) {
            $found_prodkey = $item.PsChildName
            if($ProductCode -eq $found_prodkey) {
                $ret = $item.Name
                Write-Verbose "Found Feature ($ret) "
                break
            }
        }
    }
    return $ret
}
function SearchMsiUninstKeyByProduct {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$DisplayName
    )

    Write-Host "Search MSI uninstall keys by Product DisplayName($DisplayName) starting..."
    [string[]] $ret = @()
    foreach($item in $REG_MSI_UNINST_KEY) {
        $pspath = ToPSDriveFormat($item)

        #Normally we shouldn't get an empty string here, but let's check it just to be safe.
        if([string]::IsNullOrEmpty($pspath)) {
            continue
        }
        
        $found_regs = (Get-Childitem -path $pspath | SELECT *)
        ForEach($item in $found_regs) {
            $pspath = ToPSDriveFormat($($item.Name))
            #Normally we shouldn't get an empty string here, but let's check it just to be safe.
            if([string]::IsNullOrEmpty($pspath)) {
                continue
            }
            $values = Get-itemProperty -path $pspath -ErrorAction SilentlyContinue
            if(!$values) {
                continue
            }
            if($DisplayName -eq $values.DisplayName) {
                Write-Verbose "Found uninstall key=> $($item.Name)"
                $ret = @($ret + $($item.Name))
            }
        }
    }
    return $ret;
}
function SearchMsiInstClassProductCode {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProductName
    )
    
    Write-Host "Search MSI install class key by Product Name($ProductName) starting..."
    [string] $ret = ""
    $pspath = ToPSDriveFormat($REG_MSI_INSTCLASS_PRODUCT_KEY)
    #Normally we shouldn't get an empty string here, but let's check it just to be safe.
    if(![string]::IsNullOrEmpty($pspath)) {
        $found_regs = (Get-Childitem -path $pspath | SELECT *)
        ForEach($item in $found_regs) {
            $pspath = ToPSDriveFormat($($item.Name))
            $values = Get-itemProperty -path $pspath -ErrorAction SilentlyContinue
            if(!$values) {
                continue
            }
            if($ProductName -eq $values.ProductName) {
                $ret = $($item.Name)
                Write-Verbose "Found Product($ProductName) install class registry => $ret"
                break;
            }
        }
    }
    return $ret;
}
function StopDriver() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$DriverSvcName
    )
    #driver is treat as a special windows service.
    #to stop a driver, we need to use "sc stop" command.
    StopService -SvcName $DriverSvcName
}
function StopService() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$SvcName
    )
    foreach($name in $SvcName) {
        Write-Verbose "Stopping [$SvcName] services..."
        Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
    }
}
function KillProcesses() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$ProcessNames       #without fileext, e.g. "notepad" not "notepad.exe"
    )

    Write-Host "Stop [$($ProcessNames.Length)] processes starting..."
    foreach($name in $ProcessNames) {
        Write-Verbose "Stopping process: $name"
        $proc = Get-Process -Name "$name" -ErrorAction SilentlyContinue
        if($proc)
        {
            Stop-Process -Name "$name" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $proc = Get-Process -Name "$name" -ErrorAction SilentlyContinue
            if(!$proc) {
                Write-Verbose "process [$name] stopped."
            } else {
                Write-Warning "Failed to stop process[$name]."
            }
        }
        else {
            Write-Verbose "process [$name] not found."
        }
    }
}

Set-Alias -Name DeleteDriver -Value DeleteService
function DeleteService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceName,       #service name which used in "sc start" and "sc stop" commands
        [switch]$Force
    )
    
    #use "sc delete" command to delete a windows service.
    #don't delete registry directly, it may cause system unstable.
    Write-Host "Deleting service: $ServiceName"
    sc.exe delete $ServiceName
    if($Force) {
        $regpath = $REG_SYSTEM_SERVICE_KEY + "\" + $ServiceName
        RemoveRegistryKey -Path $regpath
    }
}
function RemoveFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$PathList,       #FullPath string array of folders which user want to delete.
        [Parameter()]
        [switch] $TakeOwner
    )
    
    Write-Verbose "Remove [$($PathList.Length)] Folders starting..."
    foreach($path in $PathList) {
        if(Test-Path $path -PathType Container)
        {
            if($TakeOwner){
                $ret = Grant-FolderFullControl -FolderPath "$path"
                if(!$ret){
                    Write-Error "Failed to take ownership of folder: $path"
                }
                else{
                    Write-Verbose "Succeeded to take ownership of folder: $path"
                }
            }

            Write-Verbose "Removing folder: $path"
            Remove-Item -Path "$path" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
function RemoveRegistryKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$PathList    #RegistryPath string array of registry paths which user want to delete.
    )
    
    Write-Host "Remove [$($PathList.Length)] Registries starting..."
    foreach($path in $PathList) {
        RemoveRegistryKey -Path $path
    }
}
function RemoveRegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path    #RegistryPath string array of registry paths which user want to delete.
    )
    
    $pspath = ToPSDriveFormat($Path)
    #Normally we shouldn't get an empty string here, but let's check it just to be safe.
    if(![string]::IsNullOrEmpty($pspath)){
        Write-Verbose "Removing [$Path]"
        Remove-Item -Path $pspath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
function RemoveRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$ValueName
    )
    
    $pspath = ToPSDriveFormat($Path)
    #Normally we shouldn't get an empty string here, but let's check it just to be safe.
    if(![string]::IsNullOrEmpty($pspath)) {
        Write-Verbose "Remove value [$ValueName] under [$Path] Registry starting..."
        Remove-ItemProperty -Path $pspath -Name $ValueName -ErrorAction SilentlyContinue
    }
}
function RemoveAppStartupRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )
    
    Write-Host "Remove App [$Name] in Startup Run Registry starting..."

    foreach($path in $REG_STARTUP_RUN){
        Write-Verbose "Removing Startup Run value [$Name] under [$path]"
        RemoveRegistryValue -Path $path -ValueName $Name
    }
}
function RemoveMSIRegistryForApp {
    [CmdletBinding()]
    param(
#note: product name sometimes is different from display name. so input in different parameters.
#for example, display name is "My Tool", product name is "My Toolset Application"
        [Parameter(Mandatory=$true)]
        [string]$DisplayName,
        [Parameter(Mandatory=$true)]
        [string]$ProductName
    )
    
    Write-Host "RemoveMSIRegistryForApp for Product [$DisplayName/$ProductName] starting..."
    #STEPS:
    #1. Search ProductCode by DisplayName
    $product_reg = $(SearchMsiProductReg -DisplayName "$DisplayName")
    $product_code = $product_reg | Select-String -Pattern "$REGEX_PRODUCT_KEY" | %{$_.Matches.Groups[1].value}
    if([string]::IsNullOrEmpty($product_reg)) {
        Write-Error "Product [$DisplayName] not found in MSI registry."
        return
    }
    Write-Verbose "[$DisplayName] ProductCode=$product_code"

    #2. Search Components by ProductKey
    if(![string]::IsNullOrEmpty($product_code)) {
        $components = SearchMsiComponentByProduct -ProductCode "$product_code"
    }
    #3. Search UpgradeCode by ProductKey
    if(![string]::IsNullOrEmpty($product_code)) {
        $upg_code = SearchUpgradeCodeByProduct -ProductCode "$product_code"
    }
    #4. Search Feature Tree by ProductKey
    if(![string]::IsNullOrEmpty($product_code)) {
        $feature_tree = SearchFeatureTreeByProduct -ProductCode "$product_code"
    }
    #5. Search InstallClassKey by ProductName
    $inst_class = SearchMsiInstClassProductCode -ProductName "$ProductName"
    #6. Search Uninstall Keys by Product DisplayName
    $uninst_keys = SearchMsiUninstKeyByProduct -DisplayName "$DisplayName"

    #7. Remove Uninstall Keys
    if($uninst_keys.Length -gt 0) {
        RemoveRegistryKeys -PathList $uninst_keys
    }
    #8. Remove InstallClassKey registry
    if(![string]::IsNullOrEmpty($inst_class)) {
        RemoveRegistryKeys -PathList @($inst_class)
    }
    #9. Remove Feature Tree registry
    if(![string]::IsNullOrEmpty($feature_tree)) {
        RemoveRegistryKeys -PathList @($feature_tree)
    }
    #10. Remove UpgradeCode registry
    if(![string]::IsNullOrEmpty($upg_code)) {
        RemoveRegistryKeys -PathList @($upg_code)
    }
    #11. Remove Components registry
    if($components.Length -gt 0) {
        RemoveRegistryKeys -PathList $components
    }
    #12. Remove Product registry
    if(![string]::IsNullOrEmpty($product_reg)) {
        RemoveRegistryKeys -PathList @($product_reg)
    }
    Write-Host "CleanupMSIRegistry for Product [$DisplayName] done."
}
# Search registry keys by regex in key names, value names, and value data.
# If no switches are specified, all three (key names, value names, and value data) will be searched.
# returns matching registry key paths as strings.
#Note: this function only search 1 level of registry keys under the specified path(s).
function SearchRegistryKeysByRegex { 
    [CmdletBinding()] 
    [OutputType([string[]])]
    param( 
        [Parameter(Mandatory, Position=0, ValueFromPipelineByPropertyName)] 
        [Alias("PsPath")] 
        # Registry path to search 
        [string[]] $Path, 
        # Specifies whether or not all subkeys should also be searched 
        [switch] $Recursive, 
        [Parameter(ParameterSetName="SingleSearchString", Mandatory)] 
        # A regular expression that will be checked against key names, value names, and value data (depending on the specified switches) 
        [string] $SearchRegex, 
        [Parameter(ParameterSetName="SingleSearchString")] 
        # When the -SearchRegex parameter is used, this switch means that key names will be tested (if none of the three switches are used, keys will be tested) 
        [switch] $KeyName, 
        [Parameter(ParameterSetName="SingleSearchString")] 
        # When the -SearchRegex parameter is used, this switch means that the value names will be tested (if none of the three switches are used, value names will be tested) 
        [switch] $ValueName, 
        [Parameter(ParameterSetName="SingleSearchString")] 
        # When the -SearchRegex parameter is used, this switch means that the value data will be tested (if none of the three switches are used, value data will be tested) 
        [switch] $ValueData, 
        [Parameter(ParameterSetName="MultipleSearchStrings")] 
        # Specifies a regex that will be checked against key names only 
        [string] $KeyNameRegex,
        [Parameter(ParameterSetName="MultipleSearchStrings")] 
        # Specifies a regex that will be checked against value names only 
        [string] $ValueNameRegex, 
        [Parameter(ParameterSetName="MultipleSearchStrings")] 
        # Specifies a regex that will be checked against value data only 
        [string] $ValueDataRegex 
    ) 

    begin { 
        switch ($PSCmdlet.ParameterSetName) { 
            SingleSearchString { 
                $NoSwitchesSpecified = -not ($PSBoundParameters.ContainsKey("KeyName") -or $PSBoundParameters.ContainsKey("ValueName") -or $PSBoundParameters.ContainsKey("ValueData")) 
                if ($KeyName -or $NoSwitchesSpecified) { $KeyNameRegex = $SearchRegex } 
                if ($ValueName -or $NoSwitchesSpecified) { $ValueNameRegex = $SearchRegex } 
                if ($ValueData -or $NoSwitchesSpecified) { $ValueDataRegex = $SearchRegex } 
            } 
            MultipleSearchStrings { 
                # No extra work needed 
            } 
        }
        Write-Host "SearchRegistryKeysByRegex=> Path:"
        foreach ($CurrentPath in $Path) { 
            Write-Host "  [$CurrentPath]"
        }
        Write-Verbose "SearchRegex=$SearchRegex, KeyNameRegex=$KeyNameRegex, ValueNameRegex=$ValueNameRegex, ValueDataRegex=$ValueDataRegex"
        $counter = 0
    } 

    process { 
        foreach ($CurrentPath in $Path) { 
            $pspath = ToPSDriveFormat($CurrentPath)
            #Normally we shouldn't get an empty string here, but let's check it just to be safe.
            if([string]::IsNullOrEmpty($pspath)) {
                continue
            }
            Write-Verbose ("=>{0}" -f $pspath)

            Get-ChildItem -Path "$pspath" -Recurse:$Recursive |  
                ForEach-Object { 
                    $Key = $_ 

                    if ($KeyNameRegex) {  
                        if ($Key.PSChildName -match $KeyNameRegex) {  
                            Write-Verbose ("{0}: matched KeyNamesRegex" -f $Key.PSChildName)  
                            $counter++
                            return [string] $Key
                        }  
                    } 

                    if ($ValueNameRegex) {
                        $matchedNames = $Key.GetValueNames() | Where-Object { $_ -match $ValueNameRegex }
                        if ($matchedNames) {
                            foreach ($vname in $matchedNames) {
                                Write-Verbose ("{0}: matched ValueNameRegex, {1} = {2}" -f $Key, $vname, $Key.GetValue($vname))
                            }
                            $counter++
                            return [string] $Key
                        }
                    }

                    if ($ValueDataRegex) {
                        $matchedNames = $Key.GetValueNames() | Where-Object { $Key.GetValue($_) -match $ValueDataRegex }
                        if ($matchedNames) {
                            foreach ($vname in $matchedNames) {
                                Write-Verbose ("{0}: matched ValueDataRegex, {1} = {2}" -f $Key, $vname, $Key.GetValue($vname))
                            }
                            $counter++
                            return [string] $Key
                        }
                    }
                } 
        } 
    } 

    end{
        Write-Host "Total matched registry keys: $counter"
    }
}

# Search registry keys by regex in value names, and value data.
# If no switches are specified, all two (value names, and value data) will be searched.
# returns matching value name as strings.
function SearchRegistryValueNamesByRegex { 
    [CmdletBinding()] 
    [OutputType([string[]])]
    param( 
        [Parameter(Mandatory, Position=0, ValueFromPipelineByPropertyName)] 
        # Registry path to search 
        [string[]] $Path, 
        # A regular expression that will be checked against value names, and value data.
        # this argument also can be a keyword.
        [string] $SearchRegex
    ) 

    begin { 
        Write-Host "SearchRegistryValueNamesByRegex=> Path[$Path]"
        Write-Verbose "SearchRegex=$SearchRegex"
        $counter = 0
    } 

    process { 
            foreach ($CurrentPath in $Path) {
                if ([string]::IsNullOrEmpty($CurrentPath)) {
                    Write-Warning "CurrentPath is empty, skipping..."
                    continue
                }

                $pspath = ToPSDriveFormat($CurrentPath)
                $key = Get-Item -Path "$pspath" -ErrorAction SilentlyContinue
                if (!$key) {
                    Write-Warning "Failed to get registry key for path: $CurrentPath"
                    continue
                }
                $key.GetValueNames() | ForEach-Object {
                    $vname = $_
                    $vdata = $key.GetValue($vname)
                    if($vname -match $SearchRegex -or $vdata -match $SearchRegex) {
                        Write-Verbose ("found {0}={1} matched" -f $vname, $vdata)
                        $counter++
                        return [string] $vname
                    }
                }
            }
    } 
    end{
        Write-Host "Total matched values: $counter"
    }
}

# Get all child values (value names and value data) under a specified registry key.
# Note: only search specified registry key path, no searching subkeys.
function DoesRegistryKeyHasOnlyOneValue {
    [CmdletBinding()] 
    [OutputType([bool])]
    param( 
        [Parameter(Mandatory, Position=0, ValueFromPipelineByPropertyName)] 
        # Registry path to search 
        [string] $Path
    ) 
    begin { 
        Write-Host "DoesRegistryKeyHasOnlyOneValue=> Path[$Path]"
        $counter = 0
    } 
    process { 
        $pspath = ToPSDriveFormat($Path)
        $key = Get-Item -Path "$pspath" -ErrorAction SilentlyContinue
        if (!$key) {
            Write-Warning "Failed to get registry key for path: $Path"
            return $false
        }
        return $key.GetValueNames().Count -eq 1
    }

    end{
    }
}

Export-ModuleMember -Function *
Export-ModuleMember -Alias *
Export-ModuleMember -Variable *
