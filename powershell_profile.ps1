######################################################################################################
#
# Author:           David Koenig
# Date:             2022-09-07
# Description:      Central script for loading the powershell profile
#
######################################################################################################

$global:_profile_script_root = "{0}\PowerShell\dotfiles" -f [Environment]::GetFolderPath("MyDocuments")
$global:_profile_ohmyposh = "{0}\powershell_profile_ohmyposh.ps1" -f "$global:_profile_script_root"
$global:_profile_wsl = "{0}\powershell_profile_wsl.ps1" -f "$global:_profile_script_root"
$global:_profile_gcp = "{0}\powershell_profile_gcp.ps1" -f "$global:_profile_script_root"
$global:_profile_custom = "{0}\powershell_profile_custom.ps1" -f "$global:_profile_script_root"

Write-Output "Profile: Import oh-my-posh functions"
. $global:_profile_ohmyposh
Write-Output "Profile: Import wsl management functions"
. $global:_profile_wsl
Write-Output "Profile: Import GCP functions"
. $global:_profile_gcp
Write-Output "Profile: Import custom functions"
. $global:_profile_custom