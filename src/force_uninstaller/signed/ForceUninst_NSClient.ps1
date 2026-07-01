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
[string] $NS_INSTDIR_KEYWORD = "Netskope"

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
SearchRegistryValuesByRegex -Path $REG_MSI_INSTALL_FOLDERS_KEY -SearchRegex $NS_INSTDIR_KEYWORD | 
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
# MIIwewYJKoZIhvcNAQcCoIIwbDCCMGgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDnTMbwjV6D8FoY
# +e9fpoGGGOZS6XThNwLthzeqttbXqKCCDsswggboMIIE0KADAgECAhB3vQ4Ft1kL
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
# SIb3DQEJBDEiBCBEyYsBoN0ysrj+CuIZx3Vpk1HDruRlb3/L3zTAfzSDGzANBgkq
# hkiG9w0BAQEFAASCAgDV77T/6vZ6SufmXLxDqYoa53ki8QS9Dr3Hmkarv/H0Qv3z
# LAFMxwlxFy8m9dXTop3mp1DNvrjB4a8j/dXBqZlo0OyAe7T5LVofuRZlWetB5ENB
# TnEKg1NW/aSW6l3+3kZbjxLog2NYNaAfQxfh2Tvw/xNraoYZK3cucQGSoaF3C/+X
# DjgvTu+61Xszue3qpWYTMMZdBCjloymbXLBhz/Nz8BCbqGoLoTyMwVkV2nNH3ZiR
# JRuwX5kAubPWVtziUt2qfZ2lMd55ztYIqCtiqhEUjXk0Ne/cwPzADGqnOjKTtVyj
# du0teRovutsfx3A3VnopOFbauYhtNRDwzV4Mx+h3QAE6WSqTBOqAShLxoj6AhxPE
# csSPovgB7+NAvkZgkfyeJ4NRFu4Ogf0RLVG6VQzh0HV2ROXN+jMMUiPJtNf/DMSq
# SA/WyCD1lIeXa0xaZw30X5wkO4mr8c4+tib1Hsz29Ycsd2Q9pk/p8rWUBUgziZId
# 4jFlCOd1jN6mVdH8MTRp8NBKLXgVif0PQHKpovXwHEAbbrJWKV9ZW0/5tMl6TbYg
# fcTS0WB7LFlI6x3XPwp6Jz55hxDyYs70y/6Y1QP0mHGS/tCb/AcrJYkUW+387hQQ
# Wyo/4prmfJJqN4uuIPrnZ1LERw7OB02WSskEKDmRK3Hx02eVUKXzVMorfZ/J8aGC
# He0wgh3pBgorBgEEAYI3AwMBMYId2TCCHdUGCSqGSIb3DQEHAqCCHcYwgh3CAgED
# MQ0wCwYJYIZIAWUDBAICMIHkBgsqhkiG9w0BCRABBKCB1ASB0TCBzgIBAQYLKwYB
# BAGgMgIDAgIwMTANBglghkgBZQMEAgEFAAQgsTW5uwXLgwo+DcXlGZwsI2lyFxP2
# 0nXY/T02jXKwO/cCFBFK2pOwr6EBTB1woCEk/30krkHJGA8yMDI2MDYzMDIxNDYx
# MlowAwIBAaBdpFswWTELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24g
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
# AQwFADA/BgkqhkiG9w0BCQQxMgQw2PxEhb/27WllkyyY/UC9TOwxFrvWnr2j1+JR
# dlnaIzFTjl/2m6HO+Y/l/6mRsWmJMIG0BgsqhkiG9w0BCRACLzGBpDCBoTCBnjCB
# mwQggyrXLlI/3qyD+kaUvOfGzCYXZIgoZlZliMityjqDhVEwdzBipGAwXjELMAkG
# A1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExNDAyBgNVBAMTK0ds
# b2JhbFNpZ24gT2ZmbGluZSBSNDUgVGltZXN0YW1waW5nIENBIDIwMjUCEQCEcj/B
# lcwW8dsrovZg3yvkMA0GCSqGSIb3DQEBDAUABIIBgLfImILSMiBCudKbf2c3T+a2
# 2ZxEf+j+sAjWM/uM+ixOx9DX41nE1jm5d+hA5YxHb+LAG9WrPhA03NUYFng/9GsK
# ex3bVmgwbV6I5W8KBKRJDqbXe5QJklxqxHRR8XS2yfwcfGFiL0UvpbEGjdobxAWA
# vp8YGIwjoWLh3qzqGPOJL8IXmVfMHV9gg1dvzdDoV9ycQFZXzCaGh3bmrB32w17c
# ll7hRVOOS1o+z/KrB5RWGdusCSiam09C053ULDPW6j9JlDOm8vQnCIgH3fitN+/u
# CIBVq90ZeYktyjR64x7pCIcbEl/0nDebdl6QURhTD5shSMQu8bB2MG82CpuFt1u+
# RJxWU3ySwpHMY+hG1xXu7OjcC2jPolruSqQeAbZmAc50nIE984gW/blwhEIMc7xk
# LjNbDlQfLD8hJw+vmWHz6gXHCBAZRSE5SgdpgQ/GmrqXW5IWuDSfWpOHEcA1GZpX
# 75bmTV9Q/YTXtrWj0ZnMKlnClDzeaacnl6Qz/LmXWg==
# SIG # End signature block
