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
    [switch] $Verbose
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


#Kill StagentSvc and StagntUI processes before stop stadrv driver service
KillProcesses -ProcessNames @($NS_PROCESS_SVC, $NS_PROCESS_UI, $NS_SVC_EPDLPSVC)

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

# SIG # Begin signature block
# MIIpSQYJKoZIhvcNAQcCoIIpOjCCKTYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBMq2tlTThdpAUx
# 1ur+9OIckP3ngKdlYE5UE9VpH0nqWaCCDsswggboMIIE0KADAgECAhB3vQ4Ft1kL
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
# SIb3DQEJBDEiBCD2oPan13jtVFZ12CmiTEJs0Q84NjvVwAwphJb03PIk2DANBgkq
# hkiG9w0BAQEFAASCAgAE7EnFVJ/LOywCYTpHvgVg7y200ULUMbsoMk8jSghWVHCs
# MjxcxhXAsSEMR9Kqj/J37SITZH6FDb4WTu9/DZ6n8+zAAd6Zzgb41Szl2vbXMxOk
# h1SL3UebO7j2mswpEI/efaQ/Drf484qxWNi9VBEXBMmj1x1BIGhGXttmhU+X01w7
# W0eaqKrt9kiz6zOH6pcjARyZ3jj+39p0lsBdn4c4viOVd2wgfXI10jz/1xqYVSvs
# 6Hrp+5Hib9MVdsnQzLBDiuKHKw+EScXeBrjKbVlMtw/JJHQaEcmuYthpPXKXTO+Y
# VnUtZ4yqPvEQmvBJUYEiKbUZwa+5uX6w6vpEYscnqgOA4wyg/bCBmAMXdFYYsVaU
# hfnGcTTMY9cxmz3z8/mcUJbDvCYqyHyfcYW0+IXYMUuE1twx+eNvxx6ivyyacRZ0
# x8MUJOIeNWd16uqT7ov+u4n897yuyjb1UeW/xo72KtnWhLooFDiBYFq4WL5IDYz2
# IcmUET2zdzQkWitf+BWKYP9WFR3z49AvzbB2GCBVoDGl2yipMObQB9Qc5C9Pf2ea
# /QAYoGQT0GsSEBvSUHv53b2tRI4+DaKXpvu2G8K44kTRKHzD4u8AZ5TSkbSt+wlh
# Wa/V0uXJj6Jk+C0rKQNYSMf8dZ3yOJE0sMiQcwUj0w32CthBaPsLxdOb8NzlXKGC
# Frswgha3BgorBgEEAYI3AwMBMYIWpzCCFqMGCSqGSIb3DQEHAqCCFpQwghaQAgED
# MQ0wCwYJYIZIAWUDBAIBMIHfBgsqhkiG9w0BCRABBKCBzwSBzDCByQIBAQYLKwYB
# BAGgMgIDAQIwMTANBglghkgBZQMEAgEFAAQgk0BsUgo9h5X8vlrV7itaUunwtIZB
# ON3ZNN1Yn8EqCuwCFHAC2pGqwkyImxgunujg1sOQ4YIyGA8yMDI1MTIwODEyMDgx
# OFowAwIBAaBYpFYwVDELMAkGA1UEBhMCQkUxGTAXBgNVBAoMEEdsb2JhbFNpZ24g
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
# DQEBCwUAMC8GCSqGSIb3DQEJBDEiBCAFaQPPf634W07PKMI3sNqQvnFq5pzst4+E
# S/+Aav31azCBsAYLKoZIhvcNAQkQAi8xgaAwgZ0wgZowgZcEIHJe8n9I4W5puWPY
# QmiMW8oHqIxpFwZCyP9aK3evYFz9MHMwX6RdMFsxCzAJBgNVBAYTAkJFMRkwFwYD
# VQQKExBHbG9iYWxTaWduIG52LXNhMTEwLwYDVQQDEyhHbG9iYWxTaWduIFRpbWVz
# dGFtcGluZyBDQSAtIFNIQTM4NCAtIEc0AhABAAsgBbOUB2LbPjZ5lJupMA0GCSqG
# SIb3DQEBCwUABIIBgDRFwh449BsW5ZGkRYc7q0S7wjZgs89tkQY5qzBRBE5jeWmJ
# IxW8Lx+PL5HBkZpFHIiaIsQ5OtKbiIYPjmdijoJEb3jmm/vnJqC9kFOyA7R3jkTW
# NGGufcgzDmO536LYHpQbkguo5xlsunxaaN5LoIg469pjpqC5Yh7DhGG+KNEwanx/
# e1LxYaJ0fNQyncrnMXt2BFJL2wWDngm+U0bVmDvxnI4icBggptTGo4sTll6VPlpo
# FpkxR/H2jAs8N4Nadbn9PKGPOuWBsJfU3tI4AC4qTpb3wJwV16PZ6w351SqU/2TF
# TfmmEFTbG+9NUd50Y7Z0c8giP8ANks5IYx36p6YkwZe/ZZXigzXCO64WWRLLYZVm
# N8HmxejGbO9DEVOmcKcNZsr90fbYCd3EjoQ/Pqi4ZyvZvammDfl0OyZQH60E8lyB
# /bD3mC7su4NvzpJNeqIUQfSOzFhCDEKnq7fk4mJYI1DTfBTUVofTDxZZlWKPjfoL
# tjMgRDK+ZOBzHxmS+Q==
# SIG # End signature block
