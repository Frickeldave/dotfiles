# https://ohmyposh.dev/docs/themes
$_oh_my_posh_install_dir="$env:LOCALAPPDATA\Programs\oh-my-posh"
$oh_my_posh_nerdfont_version="2.2.2"
$oh_my_posh_nerdfont="meslo"

function install-ohmyposh {

    param(
        [Parameter(Position=0, mandatory=$false)]
        [string]$Theme="avit"
    )

    if([string]::IsNullOrEmpty($Theme)) { $Theme="avit" }

    if(Test-Path "$env:windir\Fonts\Meslo LG M Regular Nerd Font Complete.ttf") {

        if (-not (Test-Path "$_oh_my_posh_install_dir\bin\oh-my-posh.exe")) {
            # create oh-my-posh-dir
            Write-Output "Install oh-my-posh"
            if (-not (Test-Path "$_oh_my_posh_install_dir")) {New-Item -ItemType Directory -Force -Path "$_oh_my_posh_install_dir" | Out-Null};

            $installer = ''
            $arch = (Get-CimInstance -Class Win32_Processor -Property Architecture).Architecture
            switch ($arch) {
                0 { $installer = "install-386.exe" } # x86
                5 { $installer = "install-arm64.exe" } # ARM
                9 {
                    if ([Environment]::Is64BitOperatingSystem) {
                        $installer = "install-amd64.exe"
                    } else {
                        $installer = "install-386.exe"
                    }
                }
                12 { $installer = "install-amd64.exe" } # x64 emulated on Surface Pro X
            }

            if ($installer -eq '') {
                Write-Output "The posh installer for system architecture ($arch) is not available."
            }

            Write-Output "Downloading $installer..."
            $url = "https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/$installer"
            Invoke-WebRequest -OutFile "$_oh_my_posh_install_dir\$installer" -Uri $url
            Write-Output 'Running installer...'
            & "$_oh_my_posh_install_dir\$installer" /VERYSILENT /CURRENTUSER
            Start-Sleep 3
            "$_oh_my_posh_install_dir\$installer" | Remove-Item
            Write-Output "Done!"
        }
        else {
            Write-Output "oh-my-posh is already installed"
        }

        Write-Output "Execute oh-my-posh"
        Push-Location
        Set-Location $_oh_my_posh_install_dir\bin
        try {
            ./oh-my-posh.exe init powershell --config "$_oh_my_posh_install_dir\themes\$Theme.omp.json" | Invoke-Expression
        }
        catch {
            # Do nothing here. 
            # In powershell 5 you can get a PS readline error when executing oh-my-psoh multiple time in the same session. 
            # This is because of an outaded PSReadLine module. You can ignore this message."
        }
        Pop-Location 

        #Install oh-my-posh-git
        Write-Output "Install oh-my-posh-git"
        if (-Not (Get-Module posh-git -ListAvailable)) { Install-Module posh-git -Scope CurrentUser -Force };
        if (-Not (Get-Module posh-git)) { Import-Module posh-git };

        # Install Terminal Icons
        Write-Output "Install Terminal Icons"
        if (-Not (Get-Module Terminal-Icons -ListAvailable)) { Install-Module Terminal-Icons -Scope CurrentUser -Force };
        if (-Not (Get-Module Terminal-Icons)) { Import-Module Terminal-Icons };

    }  else {
        Write-Output "Please make sure that you have Meslo Nerd Fonts installed on your maschine to have an beautified prompt."
        get-ohmyposh-help
    }
}

function get-ohmyposh-help {
    $url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v$($oh_my_posh_nerdfont_version)/$($oh_my_posh_nerdfont).zip"
    Write-Output "  Probably your terminal looks very creepy after running this scripts. Follow this instruction to have it nice looking."
    Write-Output " -------------------------------------------------------------------------------------------------------------------------------------"
    Write-Output "  1) Download the Mesko NerdFont from here: $url"
    Write-Output "  2) Extract the downloaded ZIP file and do a right click in Windows explorer"
    Write-Output "  3) Open Properties/Terminal/integrated in VSCode and configure ""MesloLGM NF"" as font."
    Write-Output "    - Probably you need a restart of VSCode, when the Font was installed just before."
    Write-Output "  4) Open the profile in your Windows Terminal and set the font to Meslo LGM NF."
    Write-Output "    - Probably you need a restart of the Windows Terminal App, when the Font was installed just before."
    
}