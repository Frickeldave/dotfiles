################################################################################################
#
# Author:           David Koenig
# Date:             2022-11-08
# Description:      WSL management script
#
################################################################################################


# $script:_installWslScript = "{0}\powershell-profile-wsl-install.ps1" -f $PSScriptRoot
# if (-not (Test-Path $script:_installWslScript)) { Write-Output "Failed to load ""$($script:_installWslScript)"""; Exit 1; }
# . $script:_installWslScript 
$script:_wslKernelMajor = 0
$script:_wslKernelMinor = 0
$script:_wslMinMajorVersion = 5
$script:_wslMinMinorVersion = 10
$script:_wslBasePath = "${env:localappdata}\dotfile"
$script:_wslBaseImagePath = "$($script:_wslBasePath)\cache"
$script:_wslDistroPath = "wsl"
$script:_wslDisableKernelCheck = $False # This is for an emergency case and allows you to disable the kernel version
$script:_wslLocalDistributionFile="ubuntu-20.04.03-x64" #.tar.gz" #TODO: In the next release we have to change that to an parameter
$script:_wslDefaultPassword = "Start123"

function Invoke-WSLCommand {
    <#
        .SYNOPSIS
        Function to invoke a command against the WSL 
    #>
    param(
        $Distribution=$null,
        $Command=$null,
        $User
    )

    if([string]::IsNullOrEmpty($Distribution)) {
       throw "No distribution set. Leaving."
    }

    if([string]::IsNullOrEmpty($Command)) {
       throw "No command given. Leaving."
    }

    Write-Verbose "Execute command: $Command"
    $_wslProcess=(Start-Process -FilePath "wsl.exe" -ArgumentList "--distribution $Distribution --user $User -- $Command" -Wait -NoNewWindow -PassThru)

    if($_wslProcess.ExitCode -ne 0) {
        throw "Failed to execute command (Returncode: $($_wslProcess.ExitCode)). Command Details: ""$Command"". Leaving."
    }
}

function Convert-WSLPath {
    <#
        .SYNOPSIS
        Convert a given local path to a WSL path ("C:\..\.." to "/mnt/c/../..")
    #>
    param(
        [string]$LocalPath
    )

    # Replace all backslashes with forward slashes
    $WSLPath=$LocalPath.Replace('\', '/')
    
    # Extract driveletter
    if($WSLPath.Substring(0,3) -like "?:/") { $_driveLetter=$WSLPath.Substring(0,1).ToLower() }

    # Replace "C:" with "/mnt/c"
    $WSLPath=$WSLPath.Replace($WSLPath.Substring(0,2), "/mnt/$_driveLetter")

    if(([string]::IsNullOrEmpty($WSLPath)) -or (-not ($WSLPath.StartsWith("/mnt/")))) {
        throw "Failed to get WSL path from local path."
    }
    return $WSLPath
}

function Copy-WSLFolderToTarget {
    <#
        .SYNOPSIS
        Copy a folder to target system
    #>
    param(
        [string]$Distribution=$null,
        [string]$LocalPath,
        [string]$TargetPath,
        [string]$User
    )

    Write-Verbose "Convert local path to WSL path"
    $_wslSourcePath = Convert-WSLPath -LocalPath "$LocalPath"
    Invoke-WSLCommand -Distribution $Distribution -Command "cp -r ""$_wslSourcePath""/* ""$TargetPath""" -User $User
}

function Copy-WSLFileToTarget {
    <#
        .SYNOPSIS
        Copy a file to target system
    #>
    param(
        [string]$Distribution=$null,
        [string]$LocalPath,
        [string]$TargetPath,
        [string]$User
    )

    Write-Verbose "Convert local path to WSL path"
    $_wslSourcePath = Convert-WSLPath -LocalPath "$LocalPath"
    Invoke-WSLCommand -Distribution $Distribution -Command "cp ""$_wslSourcePath"" ""$TargetPath"" -r" -User $User

}

function Test-WSLLocalAdmin {
    <#
        .SYNOPSIS
        Check local permissions
    #>
    if ($True -eq ([Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544')) {
        throw "Script must run as normal user. Do NOT run in administrative context"
    } else {
        Write-Verbose "Script runs in normal user context. Thats fine. Going forward."
    }
}

function Get-KernelVersion {
    <#
        .SYNOPSIS
        Extract kernel version from cmdline output (not the best method, but the only one i found) and test version
    #>

    if($False -eq $_wslDisableKernelCheck) {
        $_wslKernelVersion=(((wsl.exe --status).Replace("`0","")).trim() | ForEach-Object { if (![string]::IsNullOrEmpty($_) -and ($_ -like "Kernel?Version:*")){Write-Output "$_"} })

        if(![string]::IsNullOrEmpty($_wslKernelVersion)) {
            $_wslKernelVersion=$_wslKernelVersion.split(":")[1].Trim()
            $script:_wslKernelMajor = $_wslKernelVersion.split(".")[0]
            $script:_wslKernelMinor = $_wslKernelVersion.split(".")[1]
            if(($script:_wslKernelMajor -ge $script:_wslMinMajorVersion) -and ($script:_wslKernelMinor -ge $script:_wslMinMinorVersion)) {
            } else { 
                throw "You need at minimum kernel version $script:_wslMinMajorVersion.$script:_wslMinMinorVersion. Installed version is $script:_wslKernelMajor.$script:_wslKernelMinor."
            }
        } else {
            throw "Cannot identify kernel version. Exiting. "
        }
    } else {
        Write-Host "Kernel version check is disabled. Use this script on your own risk."
    }
}

function Get-WSLBinary {
    <#
        .SYNOPSIS
        Download the binaries for WSL
    #>
    if (-Not (Test-Path "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).tar.gz")) {
        Write-Output "AppX-Image doesn't exist. Create it."

        if (-Not (Test-Path -Path "$($script:_wslBaseImagePath)")) {
            Write-Output "Create base image path ($($script:_wslBaseImagePath))"
            New-Item -Path "$($script:_wslBaseImagePath)" -ItemType Directory  | Out-Null 
        }

        if (-Not (Test-Path -Path "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).appx")) { 
            Write-Output "Download the image"
            Invoke-WebRequest -Uri https://aka.ms/wslubuntu2004 -OutFile "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).appx" -UseBasicParsing
        }

        Write-Output "Extract the image (phase 1)"
        Rename-Item "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).appx" "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).zip"
        Expand-Archive -Path "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).zip" -DestinationPath "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile)" -Force | Out-Null

        Write-Output "Extract the image (phase 2)"
        Rename-Item "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile)\Ubuntu_2004.2021.825.0_x64.appx" "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile)\$($script:_wslLocalDistributionFile).zip"
        Expand-Archive -Path "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile)\$($script:_wslLocalDistributionFile).zip" -DestinationPath "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile)\$($script:_wslLocalDistributionFile)" -Force | Out-Null
        Move-Item "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile)\$($script:_wslLocalDistributionFile)\install.tar.gz" "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).tar.gz"
        
        Write-Output "Cleanup"
        Remove-Item -Path "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile)" -Recurse -Force
        Remove-Item -Path "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).zip" -Recurse -Force
    }
}

function Add-WSLInstance {
    <#
        .SYNOPSIS
            Install a WSL on your local maschine.

        .PARAMETER WslName
            The name of the WSL-image you want to create.
    #>
    [CmdletBinding()]
    param(
        [string]$WslName = "MyProject"
    )

    Write-Output "WSL instance ""$WslName"" not found. Create it."
    if (-Not (Test-Path -Path "$($script:_wslBasePath)\$($script:_wslDistroPath)")) { 
        Write-Output "Create WSL distro directory"
        New-Item -Name $($script:_wslDistroPath) -ItemType Directory -Path $($script:_wslBasePath) | Out-Null
    }

    if (-Not (Test-Path -Path "$($script:_wslBasePath)\$($script:_wslDistroPath)\$WslName")) { 
        Write-Output "Create WSL directory"
        New-Item -Name $WslName -ItemType Directory -Path "$($script:_wslBasePath)\$($script:_wslDistroPath)\$WslName" | Out-Null 
    } 
    Write-Output "Create the WSL environment"
    wsl --import $WslName "$($script:_wslBasePath)\$($script:_wslDistroPath)\$WslName" "$($script:_wslBaseImagePath)\$($script:_wslLocalDistributionFile).tar.gz" --version 2
    $_wslCmdReturn=$?

    if($_wslCmdReturn -ne $True) {
        throw "Failed to import. Leaving."
    }
}

function Initialize-Wsl {
    <#
        .SYNOPSIS
            Install a WSL on your local maschine.

        .DESCRIPTION
            Install a WSL on your local maschine which will be well-configured and has 2 users. 
            You can execute the script with parameters or with an given configuration file (-WslConfigPath).

        .PARAMETER WslName
            The name of the WSL-image you want to create.

        .PARAMETER WslReset
            If true, a WSL image with the given name will be deleted first. Otherwise the existing image will be updated.

        .PARAMETER WslUpdate
            If true, an existing WSL image will be updated.
            
        .PARAMETER WslRootPwd
            The root password.

        .PARAMETER WslWorkUser
            A user which you can use for daily work.

        .PARAMETER WslWorkUserPwd
            The password for the work user. 
        
        .PARAMETER WslWorkUserDefault
            If set, the work user will get the default user of the WSL. 

        .EXAMPLE
            .\Initialize-WSL.ps1 -WslName MyWsl

        .EXAMPLE
            .\Initialize-WSL.ps1 -WslName MyWsl -WslReset -WslWorkUser work -WslRootPwd "Start123" -WslWorkUserPwd "Start123" -Verbose
    #>
    [CmdletBinding()]
    param(
        [string]$WslName = "MyProject",
        [switch]$WslReset,
        [switch]$WslUpdate,
        [string]$WslRootPwd = "",
        [string]$WslWorkUser = "",
        [switch]$WslWorkUserDefault,
        [string]$WslWorkUserPwd = ""
    )

    # Show header
    # Generated with https://textkool.com/en/ascii-art-generator?hl=default&vl=default&font=Standard&text=WSL
    Write-Output "__        ______  _     "
    Write-Output "\ \      / / ___|| |    "
    Write-Output " \ \ /\ / /\___ \| |    "
    Write-Output "  \ V  V /  ___) | |___ "
    Write-Output "   \_/\_/  |____/|_____|"
    Write-Output "Installation script for a WSL image"                       

    ##################################################################################
    # Control variables and prerequisites
    ##################################################################################
    $_wslImageExist = $False
    if(((wsl.exe -l).Replace("`0","")) -like "${WslName}*") {$_wslImageExist=$true}


    # Check admin permissions. Will fail if process runs "as admin"
    Test-WSLLocalAdmin

    # Check the kernel version
    Get-KernelVersion

    # Set default passwords
    if ([string]::IsNullOrEmpty($WslRootPwd)) { $WslRootPwd = $script:_wslDefaultPassword }
    if ([string]::IsNullOrEmpty($WslWorkUserDefault)) {$WslWorkUserDefault = $script:_wslDefaultPassword }

    # Output for debugging
    Write-Output "Print variables:"
    Write-Output "Base storage path for wsl:                 $($script:_wslBasePath)"
    Write-Output "Sub folder for your wsl images:            $($script:_wslDistroPath)"
    Write-Output "Folder for caching distribution files:     $($script:_wslBaseImagePath)"
    Write-Output "Name for the wsl image:                    $WslName"
    Write-Output "Remove existing wsl image:                 $WslReset"
    Write-Output "Update existing wsl image:                 $WslUpdate"
    Write-Output "Work user:                                 $WslWorkUser"
    Write-Output "Set work user as default:                  $WslWorkUserDefault"
    Write-Output "Linux kernel version:                      $($script:_wslKernelMajor).$($script:_wslKernelMinor)"
    Write-Output "WSL image exist:                           $_wslImageExist"

    # Remove existing WSL if needed
    if($WslReset -and $_wslImageExist) {
        Write-Output "Image exist. Unregister existing WSL image."
        wsl --unregister ${WslName}
        $_wslCmdReturn=$?
        if($_wslCmdReturn -ne $True) {
            throw "Failed to unregister. Leaving."
        }

        if (Test-Path "$($script:_wslBasePath)\$($script:_wslDistroPath)\$WslName") {
            Write-Output "Remove existing image files."
            Remove-Item -Path "$($script:_wslBasePath)\$($script:_wslDistroPath)\$WslName" -Recurse -Force
        }
    } else {
        Write-Output "Image exist and will just be update. Skipping refresh process."
    }

    # If image doesn't exist or previous version should be removed, lets download the sources and create the WSL image
    if(-not ($WslReset -or (-not $_wslImageExist))) {
        Write-Output "Image exist and should not be refreshed. Skipping download and installation process."
    } else { 

        # Get Binary (if needed)
        Get-WSLBinary
        
        # Create the distribution
        Add-WSLinstance -WslName $WslName
    }


    # Manage the WSL instance (update and all that shit)
    if($WslUpdate) {
        Write-Output "Update packages"
        Invoke-WSLCommand -Distribution $WslName -Command "sudo apt update -y 2>&1>> /tmp/install-wsl.log" -User root

        Write-Output "Upgrade packages (Please be patient, this can take a while)"
        Invoke-WSLCommand -Distribution $WslName -Command "sudo apt upgrade -y 2>&1>> /tmp/install-wsl.log" -User root

        Write-Output "Removing packages that are not needed anymore"
        Invoke-WSLCommand -Distribution $WslName -Command "sudo apt autoremove -y 2>&1>> /tmp/install-wsl.log" -User root
    }
    Write-Output "Set hostname to wsl name"
    Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""echo ""[network]"" >> /etc/wsl.conf""" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""echo ""hostname=$WslName"" >> /etc/wsl.conf""" -User root

    # Manage the users in WSL image #TODO: Currently just Ubuntu tested.
    Write-Output "Set root password"
    Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""sudo echo root:$WslRootPwd | chpasswd""" -User root

    if((-Not [string]::IsNullOrEmpty($WslWorkUser))) {
        Write-Output "Create user for work"
        Invoke-WSLCommand -Distribution $WslName -Command "if ( ! getent passwd $WslWorkUser >> /dev/null); then adduser --force-badname --home /home/$WslWorkUser --disabled-password --gecos """" --shell /bin/bash $WslWorkUser; fi" -User root
        Invoke-WSLCommand -Distribution $WslName -Command "if ( getent passwd $WslWorkUser >> /dev/null); then echo $($WslWorkUser):$($WslWorkUser) | chpasswd; fi" -User root
        Invoke-WSLCommand -Distribution $WslName -Command "if ( getent passwd $WslWorkUser >> /dev/null); then usermod -aG sudo $WslWorkUser; fi" -User root
    }

    # Configure the wsl.conf. Just set items that are changed from default. 
    # https://learn.microsoft.com/en-us/windows/wsl/wsl-config
    Write-Output "Reset wsl-conf"
    $_wslInstallationDate=$(Get-Date -Format 'yyyy-mm-dd_HH:MM:ss')
    Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""echo ""[info]"" > /etc/wsl.conf""" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""echo ""changedate=$_wslInstallationDate"" >> /etc/wsl.conf""" -User root
    
    Write-Output "Enable systemd to have fun with docker and similar shit (needs wsl version 0.67.6+)"
    Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""echo ""[boot]"" >> /etc/wsl.conf""" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""echo ""systemd=true"" >> /etc/wsl.conf""" -User root

    if($WslWorkUserDefault) {
        Write-Output "Make work user the default user"
        Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""echo ""[user]"" >> /etc/wsl.conf""" -User root
        Invoke-WSLCommand -Distribution $WslName -Command "bash -c ""echo ""default=$WslWorkUser"" >> /etc/wsl.conf""" -User root
    }

    # Disable IPv6
    Write-Output "Disable IPv6"
    Invoke-WSLCommand -Distribution $WslName -Command "sysctl -w net.ipv6.conf.all.disable_ipv6=1" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "sysctl -w net.ipv6.conf.default.disable_ipv6=1" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "sysctl -w net.ipv6.conf.lo.disable_ipv6=1" -User root

    Write-Output "Shutdown WSL to enable settings done in wsl.conf"
    wsl --shutdown --distribution $WslName
    $_wslCmdReturn=$?
    if($_wslCmdReturn -ne $True) {
        throw "Failed to import. Leaving."
    }
}

function Initialize-WSLAnsible {
    param(
        [Parameter(Position=0, mandatory=$true)]
        [string]$WslName,
        [Parameter(Position=1, mandatory=$false)]
        [switch]$WslReset,
        [Parameter(Position=2, mandatory=$false)]
        [switch]$WslUpdate,
        [Parameter(Position=3, mandatory=$false)]
        [string]$WslRootPwd = "",
        [Parameter(Position=4, mandatory=$false)]
        [string]$WslWorkUser="ansible",
        [Parameter(Position=5, mandatory=$false)]
        [string]$WslWorkUserPwd="Start123",
        [Parameter(Position=6, mandatory=$false)]
        [string]$AnsibleVersion="2.13.1",
        [Parameter(Position=7, mandatory=$false)]
        [string]$InitialPlaybook="./playbooks/Baseline.yaml",
        [Parameter(Position=8, mandatory=$false)]
        [string]$AnsiblePlaybook="./playbooks/single-app-plays/Ansible-WSL.yaml",
        [Parameter(Position=9, mandatory=$false)]
        [string]$LocalAnsiblePath="",
        [Parameter(Position=10, mandatory=$false)]
        [string]$KeySourcePath=""
    )

    $_sw = [Diagnostics.Stopwatch]::StartNew()

    # Set default value, because didn't found out, how to set document in params section
    if([string]::IsNullOrEmpty($LocalAnsiblePath)) { $LocalAnsiblePath="{0}\Ansible" -f [Environment]::GetFolderPath("MyDocuments") }

    # Set default value, because didn't found out, how to set document in params section
    if([string]::IsNullOrEmpty($KeySourcePath)) { $KeySourcePath="{0}\.ssh\ansible" -f [Environment]::GetFolderPath("USERPROFILE") }

    Write-Output "Check for an existing ansible installation with name ""$WslName""" 
    $_testAnsConfig=0
    if(((wsl.exe -l).Replace("`0","")) -like "${WslName}*") {
        Write-Output "...exist. Get ansible information from maschine" 
        $_testAnsConfig = Invoke-WSLCommand -Distribution $WslName -Command "if [ -f /home/$WslWorkUser/ansible_wsl.cfg ]; then echo 1; else echo 0; fi" -User root
    }

    if($_testAnsConfig -eq 0 -or $WslReset -eq $true -or $WslUpdate -eq $true) {
        Write-Output "Create new WSL environment" 
        Initialize-Wsl -WslName $WslName `
                -WslReset:$WslReset `
                -WslUpdate:$WslUpdate `
                -WslRootPwd $WslRootPwd `
                -WslWorkUser $WslWorkUser `
                -WslWorkUserDefault `
                -WslWorkUserPwd $WslWorkUserwd `

        Write-Output "Update system (Because of newly installed WSL)"
        Invoke-WSLCommand -Distribution $WslName -Command "sudo apt-get update 2>&1>> /tmp/install-wsl.log" -User root
        Write-Output "Install tools"
        Invoke-WSLCommand -Distribution $WslName -Command "sudo apt install -y curl sudo apt-transport-https ca-certificates git python3 python3-pip python3-apt software-properties-common 2>&1>> /tmp/install-wsl.log" -User root

        Write-Output "Install ansible core"
        Invoke-WSLCommand -Distribution $WslName -Command "sudo python3 -m pip install ansible-core==2.13.1 2>&1>> /tmp/install-wsl.log" -User root
    }

    Write-Output "Check if ""av.secret"" exists in $LocalAnsiblePath"
    if(Test-Path $LocalAnsiblePath\av.secret) {
        Write-Output "Write ansible secret"
        Copy-WSLFileToTarget -Distribution $WslName -LocalPath $LocalAnsiblePath\av.secret -TargetPath "/home/$WslWorkUser/av.secret" -User root
        Invoke-WSLCommand -Distribution $WslName -Command "sudo chown $($WslWorkUser):$($WslWorkUser) /home/$WslWorkUser/av.secret" -User root
        Invoke-WSLCommand -Distribution $WslName -Command "sudo chmod 600 /home/$WslWorkUser/av.secret" -User root
    } else  { Write-Output "av.secret file not found. Please add it and run the script again or create it in ""/home/$WslWorkUser/av.secret""" }
    
    Write-Output "Check if ""Keys-Path"" exists in $KeySourcePath"
    if(Test-Path $KeySourcePath) {
        Write-Output "Copy secret files"
        Invoke-WSLCommand -Distribution $WslName -Command "mkdir /home/$WslWorkUser/.ssh" -User root
        Invoke-WSLCommand -Distribution $WslName -Command "chown ${WslWorkUser}:${WslWorkUser} /home/$WslWorkUser/.ssh" -User root
        Invoke-WSLCommand -Distribution $WslName -Command "chmod 700 /home/$WslWorkUser/.ssh" -User root
        Copy-WSLFolderToTarget -Distribution $WslName -LocalPath "$KeySourcePath" -TargetPath "/home/$WslWorkUser/.ssh/" -User root -Recurse
        Invoke-WSLCommand -Distribution $WslName -Command "sudo chown $($WslWorkUser):$($WslWorkUser) /home/$WslWorkUser/.ssh/*" -User root
        Invoke-WSLCommand -Distribution $WslName -Command "sudo chmod 600 /home/$WslWorkUser/.ssh/*" -User root
    } else  { Write-Output "Key source path not found" }
    

    Write-Output "Write ansible configuration file"
    $_ansibleDir="{0}" -f $(Convert-WSLPath -LocalPath $LocalAnsiblePath)
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""[defaults]"" > /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""inventory = $_ansibleDir/hosts/inventory.yaml"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""roles_path = $_ansibleDir/roles:$_ansibleDir/roles-container"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""library = $_ansibleDir/library"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""log_path = $_ansibleDir/logs/ansible.log"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""host_key_checking = True"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""ansible_python_interpreter = auto_silent"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""timeout = 30"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""vault_password_file=/home/$WslWorkUser/av.secret"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root
    Invoke-WSLCommand -Distribution $WslName -Command "echo ""collections_paths=/usr/local/share/ansible"" >> /home/$WslWorkUser/ansible_wsl.cfg" -User root

    if(Test-Path $LocalAnsiblePath\av.secret) {
        
        if(-Not ([string]::IsNullOrEmpty($InitialPlaybook))) {
            Write-Output "Run Baseline playbook from $_ansibleDir"
        Invoke-WSLCommand -Distribution $WslName -Command "export ANSIBLE_CONFIG=/home/$WslWorkUser/ansible_wsl.cfg;cd $_ansibleDir;ansible-playbook --limit wsl $($_ansibleDir)/$($InitialPlaybook)" -User root
        }
        
        if(-Not ([string]::IsNullOrEmpty($AnsiblePlaybook))) {
            Write-Output "Run Ansible playbook from $_ansibleDir"
        Invoke-WSLCommand -Distribution $WslName -Command "export ANSIBLE_CONFIG=/home/$WslWorkUser/ansible_wsl.cfg;cd $_ansibleDir;ansible-playbook --limit wsl $($_ansibleDir)/$($AnsiblePlaybook)" -User root
        }

    } else {
        Write-Output "Do not start playbook, because no secret file given"
    }

    $_sw.Stop()
    Write-Output "The script took $($_sw.Elapsed.Seconds) seconds to run."
}