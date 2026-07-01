#Requires -RunAsAdministrator

#special notes:
#"product key" is a special order of GUID reprentation used by MSI installer internally.
#for example: 
# if GUID is : {3AA3847B-C582-48AF-AECC-2D9B05D87545}
# convert to byte array=>    7B84A33A 82C5 AF48 AECC 2D9B05D87545
# Product key in registry => B7483AA3 285C FA84 EACC D2B9508D5754
#

[string] $REGEX_PRODUCT_KEY = "([0-9A-Fa-f]{32})"   #EXAMPLE: 7B7C5F31CED5DDDFD7E984F495D8F0BB
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
    try {
        takeown /F "$Fullpath" /R /D Y | Out-Null
        Write-Host "Ownership taken successfully via takeown.exe." -ForegroundColor Green
        return $true
    }
    catch {
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
            Write-Host "Failed to take ownership of $Path" -ForegroundColor Red
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
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $currentUser,
        "FullControl",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )

    Write-Host "`n=== Processing: $FolderPath ===" -ForegroundColor Magenta

	if(Test-Path $FolderPath)
	{
		try {
			Get-FolderOwnership $FolderPath

			$acl = Get-Acl $FolderPath
			$acl.SetAccessRuleProtection($false, $false)  # disable inherited ACL protection if needed
			$acl.AddAccessRule($rule)
			Set-Acl -Path $FolderPath -AclObject $acl
			Write-Host "Applied FullControl to $FolderPath folder." -ForegroundColor Green

			Get-ChildItem -LiteralPath $FolderPath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
				try {
					$acl = Get-Acl $_.FullName
					$acl.AddAccessRule($rule)
					Set-Acl -Path $_.FullName -AclObject $acl
				}
				catch {
					  }
			}
		}
		catch {
			Write-Error "Error applying ACLs to: $FolderPath" -ForegroundColor Red
			Write-Error $_.Exception.Message -ForegroundColor DarkRed
		}
	}
	else{
		Write-Host "$FolderPath Doesn't exist"
	}
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
    public static void Enable(string privilege) {
        IntPtr htoken = IntPtr.Zero;
        OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle,
            TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htoken);
        TOKEN_PRIVILEGES tp;
        tp.Count = 1;
        tp.Luid = 0;
        tp.Attr = SE_PRIVILEGE_ENABLED;
        LookupPrivilegeValue(null, privilege, ref tp.Luid);
        AdjustTokenPrivileges(htoken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    }
}
"@
    Add-Type $definition #-ErrorAction SilentlyContinue
# Enable necessary privileges
    [PrivilegeHelper]::Enable("SeTakeOwnershipPrivilege")
    [PrivilegeHelper]::Enable("SeRestorePrivilege")
    [PrivilegeHelper]::Enable("SeBackupPrivilege")
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
        Write-Warn "Failed to convert registry path to PSDrive format: $REG_MSI_PRODUCT_KEY"
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
        Write-Verbose "Removing Startup Run value [$Name] under [$pspath]"
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
        $components = SearchMsiComponentByProduct -ProductKey "$product_code"
    }
    #3. Search UpgradeCode by ProductKey
    if(![string]::IsNullOrEmpty($product_code)) {
        $upg_code = SearchUpgradeCodeByProduct -ProductKey "$product_code"
    }
    #4. Search Feature Tree by ProductKey
    if(![string]::IsNullOrEmpty($product_code)) {
        $feature_tree = SearchFeatureTreeByProduct -ProductKey "$product_code"
    }
    #5. Search InstallClassKey by ProductName
    $inst_class = SearchMsiInstClassProductKey -ProductName "$ProductName"
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
# Search registry keys by regex in key names, value names, and/or value data.
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
        Write-Host "SearchRegistryKeysByRegex=> Path[$Path]"
        Write-Verbose "SearchRegex=$SearchRegex, KeyNameRegex=$KeyNameRegex, ValueNameRegex=$ValueNameRegex, ValueDataRegex=$ValueDataRegex"
        $counter = 0
    } 

    process { 
        foreach ($CurrentPath in $Path) { 
            Write-Verbose ("Searching in path: {0}" -f $CurrentPath)
            $pspath = ToPSDriveFormat($CurrentPath)
            #Normally we shouldn't get an empty string here, but let's check it just to be safe.
            if([string]::IsNullOrEmpty($pspath)) {
                continue
            }

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
                        if ($Key.GetValueNames() -match $ValueNameRegex) {  
                            Write-Verbose ("{0}: has value names matched ValueNameRegex" -f $Key)  
                            $counter++
                            return [string] $Key
                        }  
                    } 

                    if ($ValueDataRegex) {  
                        if (($Key.GetValueNames() | % { $Key.GetValue($_) }) -match $ValueDataRegex) {  
                            Write-Verbose ("{0}: value matched ValueDataRegex" -f $Key)
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

# Search registry keys by regex in value names, and/or value data.
# If no switches are specified, all two (value names, and value data) will be searched.
# returns matching value name as strings.
function SearchRegistryValuesByRegex { 
    [CmdletBinding()] 
    [OutputType([string[]])]
    param( 
        [Parameter(Mandatory, Position=0, ValueFromPipelineByPropertyName)] 
        [Alias("PsPath")] 
        # Registry path to search 
        [string[]] $Path, 
        # A regular expression that will be checked against key names, value names, and value data.
        # this argument also can be a keyword.
        [string] $SearchRegex
    ) 

    begin { 
        Write-Host "SearchRegistryValuesByRegex=> Path[$Path]"
        Write-Verbose "SearchRegex=$SearchRegex"
    } 

    process { 
        foreach($CurrentPath in $Path) {
            Write-Verbose ("Searching in path: {0}" -f $CurrentPath)
            $pspath = ToPSDriveFormat($CurrentPath)
            #Normally we shouldn't get an empty string here, but let's check it just to be safe.
            if([string]::IsNullOrEmpty($pspath)) {
                continue
            }

            Get-ItemProperty -Path $pspath | 
                ForEach-Object {   
                    $item = $_ 
                    $ret = ($item.PSObject.Properties | Where-Object {
                            $_.Name -match $SearchRegex -or $_.Value -match $SearchRegex }).Name
                    return $ret
                } 
        }
    } 
    end{
        Write-Host "Total matched values: $($ret.Count)"
    }
}

Export-ModuleMember -Function *
Export-ModuleMember -Alias *
Export-ModuleMember -Variable *

# SIG # Begin signature block
# MIIwewYJKoZIhvcNAQcCoIIwbDCCMGgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDeUFXPw2CJJqZW
# dIVsQtBhXdFnA78+qTopcDHk0MX7lqCCDsswggboMIIE0KADAgECAhB3vQ4Ft1kL
# th1HYVMeP3XtMA0GCSqGSIb3DQEBCwUAMFMxCzAJBgNVBAYTAkJFMRkwFwYDVQQK
# ExBHbG9iYWxTaWduIG52LXNhMSkwJwYDVQQDEyBHbG9iYWxTaWduIENvZGUgU2ln
# bmluZyBSb290IFI0NTAeFw0yMDA3MjgwMDAwMDBaFw0zMDA3MjgwMDAwMDBaMFwx
# CzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQD
# EylHbG9iYWxTaWduIEdDQyBSNDUgRVYgQ29kZVNpZ25pbmcgQ0EgMjAyMDCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAMsg75ceuQEyQ6BbqYoj/SBerjgS
# i8os1P9B2BpV1BlTt/2jF+d6OVzA984Ro/ml7QH6tbqT76+T3PjisxlMg7BKRFAE
# eIQQaqTWlpCOgfh8qy+1o1cz0lh7lA5tD6WRJiqzg09ysYp7ZJLQ8LRVX5YLEeWa
# tSyyEc8lG31RK5gfSaNf+BOeNbgDAtqkEy+FSu/EL3AOwdTMMxLsvUCV0xHK5s2z
# BZzIU+tS13hMUQGSgt4T8weOdLqEgJ/SpBUO6K/r94n233Hw0b6nskEzIHXMsdXt
# HQcZxOsmd/KrbReTSam35sOQnMa47MzJe5pexcUkk2NvfhCLYc+YVaMkoog28vmf
# vpMusgafJsAMAVYS4bKKnw4e3JiLLs/a4ok0ph8moKiueG3soYgVPMLq7rfYrWGl
# r3A2onmO3A1zwPHkLKuU7FgGOTZI1jta6CLOdA6vLPEV2tG0leis1Ult5a/dm2tj
# IF2OfjuyQ9hiOpTlzbSYszcZJBJyc6sEsAnchebUIgTvQCodLm3HadNutwFsDeCX
# pxbmJouI9wNEhl9iZ0y1pzeoVdwDNoxuz202JvEOj7A9ccDhMqeC5LYyAjIwfLWT
# yCH9PIjmaWP47nXJi8Kr77o6/elev7YR8b7wPcoyPm593g9+m5XEEofnGrhO7izB
# 36Fl6CSDySrC/blTAgMBAAGjggGtMIIBqTAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0l
# BAwwCgYIKwYBBQUHAwMwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUJZ3Q
# /FkJhmPF7POxEztXHAOSNhEwHwYDVR0jBBgwFoAUHwC/RoAK/Hg5t6W0Q9lWULvO
# ljswgZMGCCsGAQUFBwEBBIGGMIGDMDkGCCsGAQUFBzABhi1odHRwOi8vb2NzcC5n
# bG9iYWxzaWduLmNvbS9jb2Rlc2lnbmluZ3Jvb3RyNDUwRgYIKwYBBQUHMAKGOmh0
# dHA6Ly9zZWN1cmUuZ2xvYmFsc2lnbi5jb20vY2FjZXJ0L2NvZGVzaWduaW5ncm9v
# dHI0NS5jcnQwQQYDVR0fBDowODA2oDSgMoYwaHR0cDovL2NybC5nbG9iYWxzaWdu
# LmNvbS9jb2Rlc2lnbmluZ3Jvb3RyNDUuY3JsMFUGA1UdIAROMEwwQQYJKwYBBAGg
# MgECMDQwMgYIKwYBBQUHAgEWJmh0dHBzOi8vd3d3Lmdsb2JhbHNpZ24uY29tL3Jl
# cG9zaXRvcnkvMAcGBWeBDAEDMA0GCSqGSIb3DQEBCwUAA4ICAQAldaAJyTm6t6E5
# iS8Yn6vW6x1L6JR8DQdomxyd73G2F2prAk+zP4ZFh8xlm0zjWAYCImbVYQLFY4/U
# ovG2XiULd5bpzXFAM4gp7O7zom28TbU+BkvJczPKCBQtPUzosLp1pnQtpFg6bBNJ
# +KUVChSWhbFqaDQlQq+WVvQQ+iR98StywRbha+vmqZjHPlr00Bid/XSXhndGKj0j
# fShziq7vKxuav2xTpxSePIdxwF6OyPvTKpIz6ldNXgdeysEYrIEtGiH6bs+XYXvf
# cXo6ymP31TBENzL+u0OF3Lr8psozGSt3bdvLBfB+X3Uuora/Nao2Y8nOZNm9/Lws
# 80lWAMgSK8YnuzevV+/Ezx4pxPTiLc4qYc9X7fUKQOL1GNYe6ZAvytOHX5OKSBoR
# HeU3hZ8uZmKaXoFOlaxVV0PcU4slfjxhD4oLuvU/pteO9wRWXiG7n9dqcYC/lt5y
# A9jYIivzJxZPOOhRQAyuku++PX33gMZMNleElaeEFUgwDlInCI2Oor0ixxnJpsoO
# qHo222q6YV8RJJWk4o5o7hmpSZle0LQ0vdb5QMcQlzFSOTUpEYck08T7qWPLd0jV
# +mL8JOAEek7Q5G7ezp44UCb0IXFl1wkl1MkHAHq4x/N36MXU4lXQ0x72f1LiSY25
# EXIMiEQmM2YBRN/kMw4h3mKJSAfa9TCCB9swggXDoAMCAQICDAfAcTao81JOF/v0
# qzANBgkqhkiG9w0BAQsFADBcMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFs
# U2lnbiBudi1zYTEyMDAGA1UEAxMpR2xvYmFsU2lnbiBHQ0MgUjQ1IEVWIENvZGVT
# aWduaW5nIENBIDIwMjAwHhcNMjQwMjAxMTUzNDAzWhcNMjcwMzE3MTEwOTQxWjCC
# ARwxHTAbBgNVBA8MFFByaXZhdGUgT3JnYW5pemF0aW9uMRAwDgYDVQQFEwc1MjE4
# MDY3MRMwEQYLKwYBBAGCNzwCAQMTAlVTMRkwFwYLKwYBBAGCNzwCAQITCERlbGF3
# YXJlMQswCQYDVQQGEwJVUzETMBEGA1UECBMKQ2FsaWZvcm5pYTEUMBIGA1UEBxML
# U2FudGEgQ2xhcmExKDAmBgNVBAkTHzI0NDUgQXVndXN0aW5lIERyaXZlLCBTdWl0
# ZSAzMDExFzAVBgNVBAoTDm5ldFNrb3BlLCBJbmMuMRcwFQYDVQQDEw5uZXRTa29w
# ZSwgSW5jLjElMCMGCSqGSIb3DQEJARYWY2VydGFkbWluQG5ldHNrb3BlLmNvbTCC
# AiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAO/JVgJAa79Y991Xco97hrJY
# mjFenSmT3Szal1JtYEU4uA59QBLRlBnrKMllr3NudI3MkQGrKj1jzmBSiL3OS5Wx
# mfClDlqKT3CXedaf8upRR//0IXvvXTG2sMTH8X2q5UDXtluL1HkDs7fmlF88VKtz
# EdToQIq4hX/PlF9SMcEYa98BCFTKLtvFOlWE+aiaxgOz7lN6MbwuibRpBjieQAsR
# lBwCaZaEy8By7hpUAuZEHvKRJWGpqeu36xKtHKLW2r5cJzFJsE9yZxZijx6Dpufw
# wDY/pi2hnSOPv/m6/KhxRVFKBZJ0v9lwBrSQsuqFSWZi0ExTM+JM1/HR12VaeGYI
# ijxsw7V+1PufQWZQzUmPxtp5Zhyw5FxQ96R4eMduUCS7ApCe6+T5ToynJk5+vKTv
# iJVJ31RO6lTnpbmkdJzBodLzpsuEccoz0LlvOGQu9WDUlBu69JAgsbqD3SCBGweW
# 74QMwAhcfsgt/kFg8TXwjuQe87KdeV1JUZlO/gwu/JeJ2HHmSofSw4DAfvLkFNfZ
# O78+gF0VR8yndkcu7ZFAz041EIpfjIFJaefD383Q3LKQvdSpIxtvVcbX1vLDMBA6
# HrofrVtJDs06gcdsG2sYt4FfwdOZXo/YQNOCzTpwUeNbaBi7Se9o71Z3PtrfP/92
# 8h3sUm3avADPtkgFYtGvAgMBAAGjggHZMIIB1TAOBgNVHQ8BAf8EBAMCB4AwgZ8G
# CCsGAQUFBwEBBIGSMIGPMEwGCCsGAQUFBzAChkBodHRwOi8vc2VjdXJlLmdsb2Jh
# bHNpZ24uY29tL2NhY2VydC9nc2djY3I0NWV2Y29kZXNpZ25jYTIwMjAuY3J0MD8G
# CCsGAQUFBzABhjNodHRwOi8vb2NzcC5nbG9iYWxzaWduLmNvbS9nc2djY3I0NWV2
# Y29kZXNpZ25jYTIwMjAwVQYDVR0gBE4wTDBBBgkrBgEEAaAyAQIwNDAyBggrBgEF
# BQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wBwYF
# Z4EMAQMwCQYDVR0TBAIwADBHBgNVHR8EQDA+MDygOqA4hjZodHRwOi8vY3JsLmds
# b2JhbHNpZ24uY29tL2dzZ2NjcjQ1ZXZjb2Rlc2lnbmNhMjAyMC5jcmwwIQYDVR0R
# BBowGIEWY2VydGFkbWluQG5ldHNrb3BlLmNvbTATBgNVHSUEDDAKBggrBgEFBQcD
# AzAfBgNVHSMEGDAWgBQlndD8WQmGY8Xs87ETO1ccA5I2ETAdBgNVHQ4EFgQUOVFj
# GF/a65FsH5Y6TXMrwTIAJiwwDQYJKoZIhvcNAQELBQADggIBAEtHJMtPS+ik01lo
# I8vcJKAT3IumW3LYngEruNEXv/RsASdbJuHO0IVDmLcqXFbwSUANHkzj5GqUBpl6
# 2S/thhWhmYqb5Q7pE3NM2gpXs2rn/oFvbqpMmu+Bh14vMOhddMVrnFQZsvxXoVSd
# fu+OE0YsUtx+o4TEvBpPR9oOaSFyWAItoMDSvI3hgsgzxjqxnndPnDhoyKOiCICU
# sqYecABUwjxCvJeZBtAgDokTc6AXP2UkDlWdIZLwvhWGO7fCdRMnggt4lhGbTPRs
# 4N93CMBwsQh6WPq1I12N7KZfgdEx5TTWjEFhw3NhKKZyHxiLbKOIwDAUVcjPdHp/
# 3tw7SkyMVFyFCNzz46Xek+eG1hQ8r9GY+jD6D4D/lkTshlG5gXa8yI/5UQiKThKu
# v4dFefN/7A2ZZDuyaXg0IMGsrlNIwe75Ahk2YyXhstu95yBV+APQGz9F/YrIqzZE
# OJclb+S9VTqAiwyH+jv35YJoagQk3CXqXsOewiXR3T2uj8GEi1rPetdY9A0nYOv4
# jBeDhXhkRVmPDt5lz8RhxjZYekHubQdk6vSnYdc391nkgPGivJY620CJtqr1G/De
# gLLpAr67RXfuClWO5NcjZkp+/FGVgW5MLCwSue6SbOrO/MVUZ6xx9VtBibiyyvCa
# 71Uf8WbmC9J6cpjRjgziX/IOXy4nMYIhBjCCIQICAQEwbDBcMQswCQYDVQQGEwJC
# RTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEyMDAGA1UEAxMpR2xvYmFsU2ln
# biBHQ0MgUjQ1IEVWIENvZGVTaWduaW5nIENBIDIwMjACDAfAcTao81JOF/v0qzAN
# BglghkgBZQMEAgEFAKB8MBAGCisGAQQBgjcCAQwxAjAAMBkGCSqGSIb3DQEJAzEM
# BgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqG
# SIb3DQEJBDEiBCBNNJjNJ2nGk06mQv35rSEX6z4U2XwzLtejkCBVEX7qrDANBgkq
# hkiG9w0BAQEFAASCAgACoHLvhybjDT7JwD3sjFVZaAk5gz0Vh/9GHnSeo4k6Hu30
# ipY6R4paEjrlzbGbqc6hogqXJR2f5zFFTs7IgwlBcFY45FgqzPZxpwEWow1Dg2sW
# f1/EVBONK2uneWz/DGX/36LRDbv0ZjRjowdOBbHIjVfh2YdEiVfx8f5bGevMdy7i
# rx0QyZpy4LGn7WhWicQWjIgeGrDD1EhUEjxZMaXrfy4PH15qH1p6J9dWq8UuRYwq
# 1PtXiz7jgJ2GqcTmLHLa9raqSbrNuwiF2Bfr65IZXMTX6BPjULicBBRVi8vPtF+Y
# RxXhWEVWmLBF7YEe4+XcPj7fNMMS2vyG/syR2MlZr//WX+uLAyiPkQiMLYfn+4++
# eS/W6m/pYDRNlgYV18ILFmzZSGo+O1lzJ1De+BYLplKqq2VbZGvKp8mi//ECK58E
# EwkdAWVdAHtMSpJ3/EhueVH+7EVNoxWaj3QVWW5LpH1Y6PtO+qtvS5xUK7m9ilPD
# GLrDiPLasoRgUPzmpxasdgM1OBd0lBXC2SHfnoHKvUrplLL/gpevkX6WJ1eeKNwf
# Lv7cnpi3e0Yrl2ZSO/+zA5xEEadQyrisp8scYixTW10j/L3qApk3W7QSm7YCfgKH
# fOJjWaxn7TE4Q+/ZbH43jfO7dxuTPLxKfrQKLUid5oJIC1tUrLMSI1HBOCl9KaGC
# He0wgh3pBgorBgEEAYI3AwMBMYId2TCCHdUGCSqGSIb3DQEHAqCCHcYwgh3CAgED
# MQ0wCwYJYIZIAWUDBAICMIHkBgsqhkiG9w0BCRABBKCB1ASB0TCBzgIBAQYLKwYB
# BAGgMgIDAgIwMTANBglghkgBZQMEAgEFAAQgn5ZDVOVRIRzKbjhKX66A+LblpFF9
# Zvh0Pmiz0RXKmXsCFEOmjQjDLB3LdFjymHauzmSPRPTQGA8yMDI2MDYzMDIxNDYw
# OVowAwIBAaBdpFswWTELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24g
# bnYtc2ExLzAtBgNVBAMTJkdsb2JhbHNpZ24gUjQ1IFRTQSBmb3IgQ29kZVNpZ24g
# MjAyNTEwoIIZYDCCBoowggRyoAMCAQICEQCEcj/BlcwW8dsrovZg3yvkMA0GCSqG
# SIb3DQEBDAUAMF4xCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52
# LXNhMTQwMgYDVQQDEytHbG9iYWxTaWduIE9mZmxpbmUgUjQ1IFRpbWVzdGFtcGlu
# ZyBDQSAyMDI1MB4XDTI1MTAxNTA3MjUwNFoXDTM3MDExMDAwMDAwMFowWTELMAkG
# A1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExLzAtBgNVBAMTJkds
# b2JhbHNpZ24gUjQ1IFRTQSBmb3IgQ29kZVNpZ24gMjAyNTEwMIIBojANBgkqhkiG
# 9w0BAQEFAAOCAY8AMIIBigKCAYEA0UqNoY2GQEgoowkEnNkTEDzyqIxP8X+FIo2t
# iZ7Ce0p5doA6MSo0PR3FOq1Q/KYMtbASnVcbSyxYWN4M2PzwNosCLOmcwp8bIbY0
# obDdUcs0a83OBavtMUMeqgA1DJ/epqhxP9KJOdwz25qQZJFA8rRjO/Z0H8PVlcpm
# IAPk5GwNP0DpjzTSSGego19Ld8CX4S9HGol7YQQTBFisU+b9lO2UWwqvw1Q1wPaF
# 9YhVQVWgaceezCy9NJ8h7sdCJ2Eu0a+eDN7TYZu/tJmsackxWudbmNTx7UyTLqf5
# d0RqKEOWMHgh9oQ6FDcCjgu0JBW5JYT3atuxF5LnoPKizp0Q5lTta/gdcjAG5ekL
# ldC/jjwdUigQD6ZiBZJZidEqIm21KsbE83o43SPssEC1HF4paIMClrCeOoesI5VO
# QFak+xRAWM1gk7eoX+0i0GzxrNNgWvKGmjX6NEi/mgKTfeJbhAf8LhNZYKba3JC8
# 20JQqeejoJACWKamLrovk37ngiFNAgMBAAGjggHGMIIBwjAOBgNVHQ8BAf8EBAMC
# B4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDAYDVR0TAQH/BAIwADAdBgNVHQ4E
# FgQUMvrT4QdoJ5BrCNI/HTyMZTYoBhkwHwYDVR0jBBgwFoAUdwI7ATEPHnR3w0jI
# wwdjVYilO6IwgaUGCCsGAQUFBwEBBIGYMIGVMEIGCCsGAQUFBzABhjZodHRwOi8v
# b2NzcC5nbG9iYWxzaWduLmNvbS9nc29mZmxpbmVyNDV0aW1lc3RhbXBjYTIwMjUw
# TwYIKwYBBQUHMAKGQ2h0dHA6Ly9zZWN1cmUuZ2xvYmFsc2lnbi5jb20vY2FjZXJ0
# L2dzb2ZmbGluZXI0NXRpbWVzdGFtcGNhMjAyNS5jcnQwSgYDVR0fBEMwQTA/oD2g
# O4Y5aHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS9nc29mZmxpbmVyNDV0aW1lc3Rh
# bXBjYTIwMjUuY3JsMFYGA1UdIARPME0wCAYGZ4EMAQQCMEEGCSsGAQQBoDIBHjA0
# MDIGCCsGAQUFBwIBFiZodHRwczovL3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0
# b3J5LzANBgkqhkiG9w0BAQwFAAOCAgEAjq5wpo9HhpGKbp4s+v1hZvdbOio54ZDC
# mJW3H7YKTAbZYcrFZ4hDnwb4XL6BUMOADhxvTUVb2aZAZ2oOQ7dRzNyYNtYEVQgc
# Bcj9RE/CA8aH5WMeTg+EgjSx7OrwoOqxZDU/Nb/WcvLtMV8t1m6DeYiv0m05ixqg
# qwBiYoSy63yIb3XcFa3Qcoh7Xi8YI7oE+iUKIAkqARdiaph9GQQpedeW7W07lmS6
# 0FLOb75dqPfDHY7vcsiUVi8z1XFJEZPXfMQQYut/BQTgLqN33Mk4RnJ3u8FDmvk4
# IYcCB22d6cU2KYKOXAsRGbB/BF8Ik1E8B39KnrLLIP9l3XBh+7NAEeE8jidkJwGs
# mDgDP1zgcTc1EUIOJoTHTy/xfFQjCo95KCWlXMdmpIdAfNpXv2gVPKtjmvvjsDsI
# hxeXvn/ZvsocmG8BkqIFiFd4YEZflciq3IfIL9+RR6/3Fc/J9PwjxkVxomCWez9c
# DjoGHZDA9ogylWEG8uSMf8QgdP5Uii56hKBXs35pwiWxoAAlbMDLMYSRFI7cRHEH
# PWn2pZ3viDrbNL/8gkYpCbJ5lW0tMedA5Njh/lQolPbP18s4Hwu1s67UOXYiHXNi
# rItyTEyZuGtC4hCGVorQ+fuj6JDpEPPt+U7BzsFIbPOyP8siY5SGaQFeDn9fyTfG
# 1lQdxHZuFs4wggagMIIEiKADAgECAhEAg9qGN7efDIQMlHuEClJ4HzANBgkqhkiG
# 9w0BAQwFADBTMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1z
# YTEpMCcGA1UEAxMgR2xvYmFsU2lnbiBUaW1lc3RhbXBpbmcgUm9vdCBSNDUwHhcN
# MjUwNzE2MDMwNTA0WhcNNDEwNzE2MDAwMDAwWjBeMQswCQYDVQQGEwJCRTEZMBcG
# A1UEChMQR2xvYmFsU2lnbiBudi1zYTE0MDIGA1UEAxMrR2xvYmFsU2lnbiBPZmZs
# aW5lIFI0NSBUaW1lc3RhbXBpbmcgQ0EgMjAyNTCCAiIwDQYJKoZIhvcNAQEBBQAD
# ggIPADCCAgoCggIBAKR3FvjtfYvi3QKGRWM0vuV/lmL51qBalwH4q9Ycp4VE3R+E
# VtQ2/sjpq0Nu+Y5bEOm86Gd5zdAjJ3GV+BNEIaaekL8du/n5aX83jEGnA+1XIllI
# hd0y4ru8E9mwQkhDVJ94XxjBuDyb2BbzuaOAwNYjbx4RuKEs3LaHaCX2+HPBI1Wo
# QsPzS4swd62vjVntoGQUmmSq2jMRbeu+sqse0XEJ42xeEdDixqL7Gbdt71OvQOQX
# aD8XQPc7vazPqkwbDw1VCXsWMBFVNBmOwSeZlFlp4sgDx1tFr+AM5ObeyNF1CIwN
# /tjhpK9HVQV1QQ8hHhgVa2FxHYX1S8LoehwRiRXSKxGOSqBpaaE/uAQUHuFwh+bL
# 9eVKPjO9lSlozwORMd53xSQuD+RVtUkeqJQkmiK7Z2c3Ps4JqUsog/hnBNrnUEUB
# 2w4u+Hp14Gs5NPpLaR2dWfKE70mkiERKL10i2x9ygvLhSJF7nJe1zx+2RiK5hfXh
# eM7qKORSFJ7L1etJC6hQ8z5PlGy5oGQ1Aj5RRQQXoWmjb4sRMpsfTjdil3r/jHyu
# jmQoahm6zgtsL7wBR8ipU2W1R3ajYrtLuWtk9QvXUk0Z8tf4cS8HMS/QVj80C8Ib
# Isl6lMzO7g9JQ/fj2DGsVGIKFUsam+MbzwolaizWmyPlrYxM2H0ND/urQUxbAgMB
# AAGjggFiMIIBXjAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwgw
# EgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUdwI7ATEPHnR3w0jIwwdjVYil
# O6IwHwYDVR0jBBgwFoAURrIcd+F7FfClOaFw3tHELuptst4wgY4GCCsGAQUFBwEB
# BIGBMH8wNwYIKwYBBQUHMAGGK2h0dHA6Ly9vY3NwLmdsb2JhbHNpZ24uY29tL3Rp
# bWVzdGFtcHJvb3RyNDUwRAYIKwYBBQUHMAKGOGh0dHA6Ly9zZWN1cmUuZ2xvYmFs
# c2lnbi5jb20vY2FjZXJ0L3RpbWVzdGFtcHJvb3RyNDUuY3J0MD8GA1UdHwQ4MDYw
# NKAyoDCGLmh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20vdGltZXN0YW1wcm9vdHI0
# NS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4ICAQAyo+5+
# 0W7kZjGWWF6pTD0SaEel9Z//6rlxi1XzqRaEfWGtOS/eMNMsAY3pchhn/pwAfgmR
# UO4FDndmtm6X6VvF8OQKzPmIzxH/ALQuBOmK9dOVNWDY5U0hEaFiSnNYZEjeZuHa
# bGLXhcpMxUFcF+dIWCh98melXLuh2tBAOaH8y6Ytoyto20Qwl2xTS4uZjtcSkXQd
# gMwBdH+QtNG+B93ebAjgfJ407wMGkzBhDHk5C1jOGfWPt1DrTqaNULsV2w6V1ZC1
# 62htuYi9Vbb48RAMuOd+J1CDQfcITkYnCSUky22unzitn/9UBlhHXsFixwMxPjea
# B9EKDUQC6SeSYyH3iJ7zvrEHQYnZz7iyifeR04+18jLyYRWY7WxyRpRFseFICnLj
# Siwy11gC38EAzdg3st5E33eMsOJ0HZNT3LSyytxeC9p5y7/eATJKWPkX5ed6DhDe
# Mk77cAmD/lQ7ma5LXOzWnKE1cWZyhpL/GtWpHJHTsEGQvovAMtVcszAF/02+Pq93
# OuQe3KQLatzqFIo11CYL2cXIuk1+/LJi9k2MtrVp/vBuJK5178thC0dl2JyhDkuD
# FZq0grIzOZ8Uq4IRNdFQ10GxH2vd5YYpHxaCLiDSs1gy6r7vGbnJsRLn8aR4zZ50
# VV1/2b+SkKvKbvzEKDs+gwu+J+fjuW0sL0+bIDCCBqMwggSLoAMCAQICEHhKqoFz
# ZpyQCVTkIclH68AwDQYJKoZIhvcNAQEMBQAwTDEgMB4GA1UECxMXR2xvYmFsU2ln
# biBSb290IENBIC0gUjYxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkds
# b2JhbFNpZ24wHhcNMjAxMjA5MDAwMDAwWhcNMzQxMjEwMDAwMDAwWjBTMQswCQYD
# VQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEpMCcGA1UEAxMgR2xv
# YmFsU2lnbiBUaW1lc3RhbXBpbmcgUm9vdCBSNDUwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQC6dDPsJ9wSOCEbxdNhKNZavE/fi8yRhEMkV7xkIbw7HB89
# T4ytB7fzxdcC6REUgpqqtJRyO3ENGu9oa4V5jq9m6liYDbrBfHnS/82zbzFF0AV0
# BAByaid+uDc/Oojtl4P1qzVND59ZO/Uv31nFfKUydmCWyO3u+AR+GVFyqL9EQXq8
# ex47AJu8uuCWv5D+jZvDcosAEvggOmA498HMhYr7h3kuoSsg5sughZEjtsQoB1Qo
# 3uwQMU+K8s0UHx7dVRzqKDFM+SFqqM3zlmf6AUGbzQ8LaH+73vFD6hflsNxwIrNp
# Nll0a8bliSp85QuBXas/j7jRdnLzfKKp4pdBv8yMRf5hyfZsBwsABOgVI0+CKi32
# 78P6ETZIodH9ejk6NF2jLA6bd1AgNEDdsQMxrV/pYodzlgNh95Sw2VxsT+cUxeHx
# ew0jnM1wjB1q3kotiyq720IUBQeq+xTcMdP2H2zLvmhmRHBNbRf5cesFc46RknXr
# aFwe9kRhGCli3RdmiOwouklv2z53/rkxH3UcGKKmR73Y7kiFO/2z4g8/KpjGmvqC
# b7GlpYYdWjr6pGx0D3dSYWp/hyneOZuL7rNFYDAklxUSKoUwkyaslqYt6HBtC6ky
# rSybKAp2QvJVYVGYlN7t9sUXbzwVELAOrbDexRb0ZdHML1pWCM+ZxPBVkcIseQID
# AQABo4IBeDCCAXQwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMI
# MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFEayHHfhexXwpTmhcN7RxC7qbbLe
# MB8GA1UdIwQYMBaAFK5sBaOTE+Ki5+LXHNbH8H/IZ1OgMHsGCCsGAQUFBwEBBG8w
# bTAuBggrBgEFBQcwAYYiaHR0cDovL29jc3AyLmdsb2JhbHNpZ24uY29tL3Jvb3Ry
# NjA7BggrBgEFBQcwAoYvaHR0cDovL3NlY3VyZS5nbG9iYWxzaWduLmNvbS9jYWNl
# cnQvcm9vdC1yNi5jcnQwNgYDVR0fBC8wLTAroCmgJ4YlaHR0cDovL2NybC5nbG9i
# YWxzaWduLmNvbS9yb290LXI2LmNybDBHBgNVHSAEQDA+MDwGBFUdIAAwNDAyBggr
# BgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8w
# DQYJKoZIhvcNAQEMBQADggIBAItIujZXPHLF2nX57zL1hr3cEijjiC5PNl8mmewP
# ASEQlpI4xnBrbfOu1A69Je+Gf+KJjZWlfilEA02qmKjxt9zqKWMh3O3NiArLEGlh
# eSlCDCO86cXvUh4vMzfVT2Z6ZqlHVDOx3Rby2GRxozGU5W/2TUvihGzQySVnT8hL
# 0M5LBdY9+31B+oqxwCHgfgiw2WQr+eryxwr0zy4MNGDubLuS8D/xe1ISaHdZgfUc
# LqQ6jDkDDe3lzK9mSHlj1Um4/0vSJU9ITpM7k3ewmkhstqAds3SeX70iBDt8Nw2F
# tcOau92cWgONtA2fTHY01YWtRXu1n7suibusyL+SY0jGP8oXqg28ABFfi+jjQ4SK
# QzTN/TvAonvbH7hnyIwV3j+mf8co76Fvb7JBzwIi6wH4S8jSdm8l317aaGg9e0QE
# wkFuSTunmFYE7dEmKwSU2+TtZo49gJ2kpFV5UF7j+BofwBZvkBU8iqZIoQx7uirg
# samHBUab7SVVPTdpmO1GmZiFRwoeYtv9nOXBQ0KOvc9v9oyR/YLkn+yt45VVBfNJ
# L2009/9n7plAu9OagEJA2iOJYB+DcZK16ebKCvndx2yyWEGcZo2bKm8fb1cEQ1yD
# XTtpnN45+oRNNfN7G22L8W8DwSlS4pS/e1SL30B6C3ACdz8viAcCAHXSr8bWIjIZ
# ozvoMIIFgzCCA2ugAwIBAgIORea7A4Mzw4VlSOb/RVEwDQYJKoZIhvcNAQEMBQAw
# TDEgMB4GA1UECxMXR2xvYmFsU2lnbiBSb290IENBIC0gUjYxEzARBgNVBAoTCkds
# b2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMTQxMjEwMDAwMDAwWhcN
# MzQxMjEwMDAwMDAwWjBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBS
# NjETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJUH6HPKZvnsFMp7PPcNCPG0RQss
# grRIxutbPK6DuEGSMxSkb3/pKszGsIhrxbaJ0cay/xTOURQh7ErdG1rG1ofuTToV
# Bu1kZguSgMpE3nOUTvOniX9PeGMIyBJQbUJmL025eShNUhqKGoC3GYEOfsSKvGRM
# IRxDaNc9PIrFsmbVkJq3MQbFvuJtMgamHvm566qjuL++gmNQ0PAYid/kD3n16qIf
# KtJwLnvnvJO7bVPiSHyMEAc4/2ayd2F+4OqMPKq0pPbzlUoSB239jLKJz9CgYXfI
# WHSw1CM69106yqLbnQneXUQtkPGBzVeS+n68UARjNN9rkxi+azayOeSsJDa38O+2
# HBNXk7besvjihbdzorg1qkXy4J02oW9UivFyVm4uiMVRQkQVlO6jxTiWm05OWgtH
# 8wY2SXcwvHE35absIQh1/OZhFj931dmRl4QKbNQCTXTAFO39OfuD8l4UoQSwC+n+
# 7o/hbguyCLNhZglqsQY6ZZZZwPA1/cnaKI0aEYdwgQqomnUdnjqGBQCe24DWJfnc
# BZ4nWUx2OVvq+aWh2IMP0f/fMBH5hc8zSPXKbWQULHpYT9NLCEnFlWQaYw55PfWz
# jMpYrZxCRXluDocZXFSxZba/jJvcE+kNb7gu3GduyYsRtYQUigAZcIN5kZeR1Bon
# vzceMgfYFGM8KEyvAgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8E
# BTADAQH/MB0GA1UdDgQWBBSubAWjkxPioufi1xzWx/B/yGdToDAfBgNVHSMEGDAW
# gBSubAWjkxPioufi1xzWx/B/yGdToDANBgkqhkiG9w0BAQwFAAOCAgEAgyXt6NH9
# lVLNnsAEoJFp5lzQhN7craJP6Ed41mWYqVuoPId8AorRbrcWc+ZfwFSY1XS+wc3i
# EZGtIxg93eFyRJa0lV7Ae46ZeBZDE1ZXs6KzO7V33EByrKPrmzU+sQghoefEQzd5
# Mr6155wsTLxDKZmOMNOsIeDjHfrYBzN2VAAiKrlNIC5waNrlU/yDXNOd8v9EDERm
# 8tLjvUYAGm0CuiVdjaExUd1URhxN25mW7xocBFymFe944Hn+Xds+qkxV/ZoVqW/h
# pvvfcDDpw+5CRu3CkwWJ+n1jez/QcYF8AOiYrg54NMMl+68KnyBr3TsTjxKM4kEa
# SHpzoHdpx7Zcf4LIHv5YGygrqGytXm3ABdJ7t+uA/iU3/gKbaKxCXcPu9czc8FB1
# 0jZpnOZ7BN9uBmm23goJSFmH63sUYHpkqmlD75HHTOwY3WzvUy2MmeFe8nI+z1TI
# vWfspA9MRf/TuTAjB0yPEL+GltmZWrSZVxykzLsViVO6LAUP5MSeGbEYNNVMnbrt
# 9x+vJJUEeKgDu+6B5dpffItKoZB0JaezPkvILFa9x8jvOOJckvB595yEunQtYQEg
# fn7R8k8HWV+LLUNS60YMlOH1Zkd5d9VUWx+tJDfLRVpOoERIyNiwmcUVhAn21klJ
# wGW45hpxbqCo8YLoRT5s1gLXCmeDBVrJpBAxggNhMIIDXQIBATBzMF4xCzAJBgNV
# BAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTQwMgYDVQQDEytHbG9i
# YWxTaWduIE9mZmxpbmUgUjQ1IFRpbWVzdGFtcGluZyBDQSAyMDI1AhEAhHI/wZXM
# FvHbK6L2YN8r5DALBglghkgBZQMEAgKgggFBMBoGCSqGSIb3DQEJAzENBgsqhkiG
# 9w0BCRABBDArBgkqhkiG9w0BCTQxHjAcMAsGCWCGSAFlAwQCAqENBgkqhkiG9w0B
# AQwFADA/BgkqhkiG9w0BCQQxMgQw4tYV5Vb0s1HuCM3Wkc6m2b0d+MkIWLIdrWi4
# zwxbmjpdSjAOxRlxqwOgrh2rnPAmMIG0BgsqhkiG9w0BCRACLzGBpDCBoTCBnjCB
# mwQggyrXLlI/3qyD+kaUvOfGzCYXZIgoZlZliMityjqDhVEwdzBipGAwXjELMAkG
# A1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExNDAyBgNVBAMTK0ds
# b2JhbFNpZ24gT2ZmbGluZSBSNDUgVGltZXN0YW1waW5nIENBIDIwMjUCEQCEcj/B
# lcwW8dsrovZg3yvkMA0GCSqGSIb3DQEBDAUABIIBgFP2Qwr7DLvEZ7KUwb14bt7K
# 2FAjm9ilm0X0Zu7YKu+awQb1ny3sWZlpI1go/v/zToFVwECAGrQybUSW7T/TeF7G
# JDC+xs+AtGt6BkadUXWs5bVnnJPMfdf2SnQ8r9+jeGI0+nbDcceD0j7Fec2MnWpQ
# 8qvY954j4lW34oP6K2a2vBhi8jTJRe0EbD7BMO7GCz2+z17HO8sNy368sU8oHZUD
# ls2eEQR7tAbnUI3MNJ29nDWvgfAOMXDOVI6Pw+yQP87Ty3dRH0WQ3siKwRMUgSVW
# ple+ua11zXk9hZel9GGjrh/PQlHk2CTHKABjVjpGFV5ChsUPPjr21w7Z7YaUPEID
# SHGkuu/BU9Q4YVx+Z83ThmfEZ09V6pOsEzhD2HeP6qBJmJvb1W0QuZ9GaW4Y512l
# XWbFuH4JantPszXw5cGPZ6FPaQTpuob+5ZR/vILFcA4KsMKcbampeDMl8Ku7B2dj
# aKy5Sh9ZIV9ZYxSb5/j/gO5V2Tt3O687Y/E3Xd652Q==
# SIG # End signature block
