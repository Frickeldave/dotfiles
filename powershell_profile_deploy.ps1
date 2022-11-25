################################################################################################
#
# Author:           David Koenig
# Date:             2022-11-08
# Description:      Deployment script for profile scripts
#
################################################################################################

$MyDocs = [Environment]::GetFolderPath("MyDocuments")

if (-Not (Test-Path -Path "$MyDocs\WindowsPowerShell")) { New-Item -Path "$MyDocs\WindowsPowerShell" -ItemType Directory | Out-Null }
if (-Not (Test-Path -Path "$MyDocs\PowerShell")) { New-Item -Path "$MyDocs\PowerShell" -ItemType Directory | Out-Null }
if (-Not (Test-Path -Path "$MyDocs\PowerShell\dotfiles")) { New-Item -Path "$MyDocs\PowerShell\dotfiles" -ItemType Directory | Out-Null }

Copy-Item -Path "$PSScriptRoot/powershell_profile.ps1" -Destination "$MyDocs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" -Force
Copy-Item -Path "$PSScriptRoot/powershell_profile.ps1" -Destination "$MyDocs\WindowsPowerShell\Microsoft.VSCode_profile.ps1" -Force
Copy-Item -Path "$PSScriptRoot/powershell_profile.ps1" -Destination "$MyDocs\PowerShell\Microsoft.PowerShell_profile.ps1" -Force
Copy-Item -Path "$PSScriptRoot/powershell_profile.ps1" -Destination "$MyDocs\PowerShell\Microsoft.VSCode_profile.ps1" -Force

Copy-Item -Path "$PSScriptRoot/powershell_profile_wsl.ps1" -Destination "$MyDocs\PowerShell\dotfiles\powershell_profile_wsl.ps1" -Force
Copy-Item -Path "$PSScriptRoot/powershell_profile_ohmyposh.ps1" -Destination "$MyDocs\PowerShell\dotfiles\powershell_profile_ohmyposh.ps1" -Force
Copy-Item -Path "$PSScriptRoot/powershell_profile_gcp.ps1" -Destination "$MyDocs\PowerShell\dotfiles\powershell_profile_gcp.ps1" -Force

if (-Not (Test-Path -Path "$MyDocs\PowerShell\dotfiles\powershell_profile_custom.ps1")) {
    Copy-Item -Path "$PSScriptRoot/powershell_profile_custom.ps1" -Destination "$MyDocs\PowerShell\dotfiles\powershell_profile_custom.ps1" -Force
}