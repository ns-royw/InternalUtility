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
# MIIpSQYJKoZIhvcNAQcCoIIpOjCCKTYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
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
# 71Uf8WbmC9J6cpjRjgziX/IOXy4nMYIZ1DCCGdACAQEwbDBcMQswCQYDVQQGEwJC
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
# Frswgha3BgorBgEEAYI3AwMBMYIWpzCCFqMGCSqGSIb3DQEHAqCCFpQwghaQAgED
# MQ0wCwYJYIZIAWUDBAIBMIHfBgsqhkiG9w0BCRABBKCBzwSBzDCByQIBAQYLKwYB
# BAGgMgIDAQIwMTANBglghkgBZQMEAgEFAAQgn5ZDVOVRIRzKbjhKX66A+LblpFF9
# Zvh0Pmiz0RXKmXsCFBPfScBnmafZu6ylQXjOpWV3noYzGA8yMDI1MTIwODEyMDgx
# NFowAwIBAaBYpFYwVDELMAkGA1UEBhMCQkUxGTAXBgNVBAoMEEdsb2JhbFNpZ24g
# bnYtc2ExKjAoBgNVBAMMIUdsb2JhbHNpZ24gVFNBIGZvciBDb2RlU2lnbjEgLSBS
# NqCCEkswggZjMIIES6ADAgECAhABAAsgBbOUB2LbPjZ5lJupMA0GCSqGSIb3DQEB
# DAUAMFsxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTEw
# LwYDVQQDEyhHbG9iYWxTaWduIFRpbWVzdGFtcGluZyBDQSAtIFNIQTM4NCAtIEc0
# MB4XDTI1MDQxMTE0NDczOVoXDTM0MTIxMDAwMDAwMFowVDELMAkGA1UEBhMCQkUx
# GTAXBgNVBAoMEEdsb2JhbFNpZ24gbnYtc2ExKjAoBgNVBAMMIUdsb2JhbHNpZ24g
# VFNBIGZvciBDb2RlU2lnbjEgLSBSNjCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCC
# AYoCggGBAKJbxKpNSeUjeD7ghevmqgo+1fKsqKdEYfeKy5mN+wp/Hq/NEpHys3SR
# yZN06mvUGOFMFeoXnV30m+YJNF8nctzDRI9ahPmaJjxHIwu7kbRnXwfz7Z4nlic4
# 7T1VJZhD61DLKBVO8KCUnEVdVuv+nn4tgckh17IWd9FdRA2dpSkNAyt6t2yOLCRP
# +Z/3UMvIi+IY02kvb9GEMuUSWPqNTVocT/x7Dbpuuzq+KxQ7BiBPOYYOa+INwlxb
# oqlr5TZj2wgVoHcafzwqmNC4ntOA7imw8EXep65uQB+aCESchVIy7xuBztC9VF2D
# LieidSczuN/EQNJiUb1NmcGyOsohR2ktMd0oBWpL4RCy5+LZsJ4GD4/hQ19y2lh5
# 54vzBiV0cZzdKUHWCahGISlJazB/ftipZ3XM//cl2BhMsE7fPHd8vk1Bb2ZQANAT
# DmDDK2BUBKbZUYNg2K8ebFrV9arws5OrBAS0VTxGxNIvidNSC5Qc0aXCbrGVEMhi
# tkVUjhX1zwIDAQABo4IBqDCCAaQwDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB/wQM
# MAoGCCsGAQUFBwMIMB0GA1UdDgQWBBSAQ0z8um0dE9J1EogJd2/bxk+VVDBWBgNV
# HSAETzBNMAgGBmeBDAEEAjBBBgkrBgEEAaAyAR4wNDAyBggrBgEFBQcCARYmaHR0
# cHM6Ly93d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wDAYDVR0TAQH/BAIw
# ADCBkAYIKwYBBQUHAQEEgYMwgYAwOQYIKwYBBQUHMAGGLWh0dHA6Ly9vY3NwLmds
# b2JhbHNpZ24uY29tL2NhL2dzdHNhY2FzaGEzODRnNDBDBggrBgEFBQcwAoY3aHR0
# cDovL3NlY3VyZS5nbG9iYWxzaWduLmNvbS9jYWNlcnQvZ3N0c2FjYXNoYTM4NGc0
# LmNydDAfBgNVHSMEGDAWgBTqFsZp5+PLV0U5M6TwQL7Qw71lljBBBgNVHR8EOjA4
# MDagNKAyhjBodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29tL2NhL2dzdHNhY2FzaGEz
# ODRnNC5jcmwwDQYJKoZIhvcNAQEMBQADggIBALemx0qZdnT9IGInvYl8Nwc+V88L
# L5omIrBI26MkWYp/o6h9uiBau30DCKzeVXV/ChpeaRHttW/LJD31HLYq6KOkEuaF
# hEpeJM2aMNoif6iZ++k5Ly/r9n+Jh6JRiwcMg5u+H16+vFut8bomEqZ23+zWD8gW
# hyO8yfxK0k+GwNNEwvn7T7bUvhvzITVGioN+MmifGegBDZz3QgfFSK7f7KnekdZP
# PTo8dYy9+kARD1K9nbSCJUtyou+AlNeWE7xvl8bfXMBPtBsf6kUL/GGxflHLHYGF
# OIzUWQdJE1dwbHd5ciFprfA0+EUI/S0NSCzqahvws8HfavRiS+o0iXkqtQAuGaHF
# TLqnGHfw/SaSDC/QUP8JOZYCZIFxHNYEYD7A7FPc89+icpjdfmIb8dFa+u469EH6
# pN1dM+v8VZhACSmn03iHw/YUHIY4hpMsNxCjYsh8jN+63SvwbE0sdKwdzB3ahPf3
# R0F+TVDkAllL4ZFstdLu9csxilp2wFkOjTbqvX7XMGBU5nMqOWGxcM35MkvmO/Pj
# vbraoIulaBNjc1SW7nKhi2bSRScxiQ+8Xv66lC8GB3kNxz0pzQmoG+o6gXhUp108
# dBm7mLpN4wOdXUDbbKIFQBlwqh7IetkFQJf4GnU33EWjKSFgHNwj7qd8dfXQwKbK
# Zkcjlc1wVLbIglrCMIIGWTCCBEGgAwIBAgINAewckkDe/S5AXXxHdDANBgkqhkiG
# 9w0BAQwFADBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBSNjETMBEG
# A1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjAeFw0xODA2MjAw
# MDAwMDBaFw0zNDEyMTAwMDAwMDBaMFsxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBH
# bG9iYWxTaWduIG52LXNhMTEwLwYDVQQDEyhHbG9iYWxTaWduIFRpbWVzdGFtcGlu
# ZyBDQSAtIFNIQTM4NCAtIEc0MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEA8ALiMCP64BvhmnSzr3WDX6lHUsdhOmN8OSN5bXT8MeR0EhmW+s4nYluuB4on
# 7lejxDXtszTHrMMM64BmbdEoSsEsu7lw8nKujPeZWl12rr9EqHxBJI6PusVP/zZB
# q6ct/XhOQ4j+kxkX2e4xz7yKO25qxIjw7pf23PMYoEuZHA6HpybhiMmg5ZninvSc
# TD9dW+y279Jlz0ULVD2xVFMHi5luuFSZiqgxkjvyen38DljfgWrhsGweZYIq1CHH
# lP5CljvxC7F/f0aYDoc9emXr0VapLr37WD21hfpTmU1bdO1yS6INgjcZDNCr6lrB
# 7w/Vmbk/9E818ZwP0zcTUtklNO2W7/hn6gi+j0l6/5Cx1PcpFdf5DV3Wh0MedMRw
# KLSAe70qm7uE4Q6sbw25tfZtVv6KHQk+JA5nJsf8sg2glLCylMx75mf+pliy1NhB
# EsFV/W6RxbuxTAhLntRCBm8bGNU26mSuzv31BebiZtAOBSGssREGIxnk+wU0ROoI
# rp1JZxGLguWtWoanZv0zAwHemSX5cW7pnF0CTGA8zwKPAf1y7pLxpxLeQhJN7Kkm
# 5XcCrA5XDAnRYZ4miPzIsk3bZPBFn7rBP1Sj2HYClWxqjcoiXPYMBOMp+kuwHNM3
# dITZHWarNHOPHn18XpbWPRmwl+qMUJFtr1eGfhA3HWsaFN8CAwEAAaOCASkwggEl
# MA4GA1UdDwEB/wQEAwIBhjASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBTq
# FsZp5+PLV0U5M6TwQL7Qw71lljAfBgNVHSMEGDAWgBSubAWjkxPioufi1xzWx/B/
# yGdToDA+BggrBgEFBQcBAQQyMDAwLgYIKwYBBQUHMAGGImh0dHA6Ly9vY3NwMi5n
# bG9iYWxzaWduLmNvbS9yb290cjYwNgYDVR0fBC8wLTAroCmgJ4YlaHR0cDovL2Ny
# bC5nbG9iYWxzaWduLmNvbS9yb290LXI2LmNybDBHBgNVHSAEQDA+MDwGBFUdIAAw
# NDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3Np
# dG9yeS8wDQYJKoZIhvcNAQEMBQADggIBAH/iiNlXZytCX4GnCQu6xLsoGFbWTL/b
# GwdwxvsLCa0AOmAzHznGFmsZQEklCB7km/fWpA2PHpbyhqIX3kG/T+G8q83uwCOM
# xoX+SxUk+RhE7B/CpKzQss/swlZlHb1/9t6CyLefYdO1RkiYlwJnehaVSttixtCz
# Asw0SEVV3ezpSp9eFO1yEHF2cNIPlvPqN1eUkRiv3I2ZOBlYwqmhfqJuFSbqtPl/
# KufnSGRpL9KaoXL29yRLdFp9coY1swJXH4uc/LusTN763lNMg/0SsbZJVU91naxv
# SsguarnKiMMSME6yCHOfXqHWmc7pfUuWLMwWaxjN5Fk3hgks4kXWss1ugnWl2o0e
# t1sviC49ffHykTAFnM57fKDFrK9RBvARxx0wxVFWYOh8lT0i49UKJFMnl4D6SIkn
# LHniPOWbHuOqhIKJPsBK9SH+YhDtHTD89szqSCd8i3VCf2vL86VrlR8EWDQKie2C
# UOTRe6jJ5r5IqitV2Y23JSAOG1Gg1GOqg+pscmFKyfpDxMZXxZ22PLCLsLkcMe+9
# 7xTYFEBsIB3CLegLxo1tjLZx7VIh/j72n585Gq6s0i96ILH0rKod4i0UnfqWah3G
# PMrz2Ry/U02kR1l8lcRDQfkl4iwQfoH5DZSnffK1CfXYYHJAUJUg1ENEvvqglecg
# WbZ4xqRqqiKbMIIFgzCCA2ugAwIBAgIORea7A4Mzw4VlSOb/RVEwDQYJKoZIhvcN
# AQEMBQAwTDEgMB4GA1UECxMXR2xvYmFsU2lnbiBSb290IENBIC0gUjYxEzARBgNV
# BAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMTQxMjEwMDAw
# MDAwWhcNMzQxMjEwMDAwMDAwWjBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3Qg
# Q0EgLSBSNjETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2ln
# bjCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJUH6HPKZvnsFMp7PPcN
# CPG0RQssgrRIxutbPK6DuEGSMxSkb3/pKszGsIhrxbaJ0cay/xTOURQh7ErdG1rG
# 1ofuTToVBu1kZguSgMpE3nOUTvOniX9PeGMIyBJQbUJmL025eShNUhqKGoC3GYEO
# fsSKvGRMIRxDaNc9PIrFsmbVkJq3MQbFvuJtMgamHvm566qjuL++gmNQ0PAYid/k
# D3n16qIfKtJwLnvnvJO7bVPiSHyMEAc4/2ayd2F+4OqMPKq0pPbzlUoSB239jLKJ
# z9CgYXfIWHSw1CM69106yqLbnQneXUQtkPGBzVeS+n68UARjNN9rkxi+azayOeSs
# JDa38O+2HBNXk7besvjihbdzorg1qkXy4J02oW9UivFyVm4uiMVRQkQVlO6jxTiW
# m05OWgtH8wY2SXcwvHE35absIQh1/OZhFj931dmRl4QKbNQCTXTAFO39OfuD8l4U
# oQSwC+n+7o/hbguyCLNhZglqsQY6ZZZZwPA1/cnaKI0aEYdwgQqomnUdnjqGBQCe
# 24DWJfncBZ4nWUx2OVvq+aWh2IMP0f/fMBH5hc8zSPXKbWQULHpYT9NLCEnFlWQa
# Yw55PfWzjMpYrZxCRXluDocZXFSxZba/jJvcE+kNb7gu3GduyYsRtYQUigAZcIN5
# kZeR1BonvzceMgfYFGM8KEyvAgMBAAGjYzBhMA4GA1UdDwEB/wQEAwIBBjAPBgNV
# HRMBAf8EBTADAQH/MB0GA1UdDgQWBBSubAWjkxPioufi1xzWx/B/yGdToDAfBgNV
# HSMEGDAWgBSubAWjkxPioufi1xzWx/B/yGdToDANBgkqhkiG9w0BAQwFAAOCAgEA
# gyXt6NH9lVLNnsAEoJFp5lzQhN7craJP6Ed41mWYqVuoPId8AorRbrcWc+ZfwFSY
# 1XS+wc3iEZGtIxg93eFyRJa0lV7Ae46ZeBZDE1ZXs6KzO7V33EByrKPrmzU+sQgh
# oefEQzd5Mr6155wsTLxDKZmOMNOsIeDjHfrYBzN2VAAiKrlNIC5waNrlU/yDXNOd
# 8v9EDERm8tLjvUYAGm0CuiVdjaExUd1URhxN25mW7xocBFymFe944Hn+Xds+qkxV
# /ZoVqW/hpvvfcDDpw+5CRu3CkwWJ+n1jez/QcYF8AOiYrg54NMMl+68KnyBr3TsT
# jxKM4kEaSHpzoHdpx7Zcf4LIHv5YGygrqGytXm3ABdJ7t+uA/iU3/gKbaKxCXcPu
# 9czc8FB10jZpnOZ7BN9uBmm23goJSFmH63sUYHpkqmlD75HHTOwY3WzvUy2MmeFe
# 8nI+z1TIvWfspA9MRf/TuTAjB0yPEL+GltmZWrSZVxykzLsViVO6LAUP5MSeGbEY
# NNVMnbrt9x+vJJUEeKgDu+6B5dpffItKoZB0JaezPkvILFa9x8jvOOJckvB595yE
# unQtYQEgfn7R8k8HWV+LLUNS60YMlOH1Zkd5d9VUWx+tJDfLRVpOoERIyNiwmcUV
# hAn21klJwGW45hpxbqCo8YLoRT5s1gLXCmeDBVrJpBAxggNJMIIDRQIBATBvMFsx
# CzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTEwLwYDVQQD
# EyhHbG9iYWxTaWduIFRpbWVzdGFtcGluZyBDQSAtIFNIQTM4NCAtIEc0AhABAAsg
# BbOUB2LbPjZ5lJupMAsGCWCGSAFlAwQCAaCCAS0wGgYJKoZIhvcNAQkDMQ0GCyqG
# SIb3DQEJEAEEMCsGCSqGSIb3DQEJNDEeMBwwCwYJYIZIAWUDBAIBoQ0GCSqGSIb3
# DQEBCwUAMC8GCSqGSIb3DQEJBDEiBCA1kjaNx56nuDqVMCKnxgy7mSWuirI8OjOs
# x39PgjHGGTCBsAYLKoZIhvcNAQkQAi8xgaAwgZ0wgZowgZcEIHJe8n9I4W5puWPY
# QmiMW8oHqIxpFwZCyP9aK3evYFz9MHMwX6RdMFsxCzAJBgNVBAYTAkJFMRkwFwYD
# VQQKExBHbG9iYWxTaWduIG52LXNhMTEwLwYDVQQDEyhHbG9iYWxTaWduIFRpbWVz
# dGFtcGluZyBDQSAtIFNIQTM4NCAtIEc0AhABAAsgBbOUB2LbPjZ5lJupMA0GCSqG
# SIb3DQEBCwUABIIBgAlgEABTeBvISZnQUc35/TLJn6KAOfpuVr1ejZUSPOEl9lr9
# og0Rn8v6H6m2l/zK1VwM6X4+VVmK9yzbIyssQJ/+k+3dS6avdTglDyPW276cyXeo
# dwlN4aS8HeGIeOIC54+tq4TUkwhLoH0bF0cNXglPZIClbKtY8adpnVj0BBqlLZkO
# JmyHbvghatv7rseXNJZWfkVEe2tVrzZJ4WaFx9Eyh2NFbrOrMoY/yXg96S9eVNna
# Pls2QV2EBwlhMDC2l6Bs6x9PlywG0Yv2gw0O0C0xOqasza/xFsfcTyxOAr9H5LWS
# PkD/nX09i5K3lyqdXhWnFfYS1I/N4lHjlTbmTgUT9qDQEIgZ2qJFuhXAOU2IV1AE
# BP7S+uAz5Ut9Bp6Xcpzf0x55pNiS1nXFTVKxcHn+HHB5dOFCRjBbSlnift75NN4A
# HUC5Rdp/3eYkSORdVSRYDs47E8w9tjLKZGQa8kNspBxmtH8GD0n3gWoMb5rwf+Ax
# HFLerdQsRFe+Qzyahw==
# SIG # End signature block
