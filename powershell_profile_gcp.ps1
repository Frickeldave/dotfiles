################################################################################################
#
# Author:           David Koenig
# Date:             2022-10-07
# Description:      Create a hopping system in GCP and open a tunnel via IAP
#
# Prerequisites:    Create the following fw requests to get access from gcp to internal systems:
#                       - Source: <gcp proxy ip address>/32; Target: <target rdp server>/32; Ports: TCP 3389
#                       - Source: <gcp proxy ip address>/32; Target: <target ssh server>/32; Ports: TCP 22/<custom ssh port>
#
################################################################################################

<#
.EXAMPLE
    VSCode SSH configuration file

    Host <a name of your choice>
    HostName=<Target server hostname or IP>
    User=<Target server linux user name>
    Port=22
    IdentityFile=<Target server ssh key file>
    ProxyCommand=C:\Windows\System32\OpenSSH\ssh.exe -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p username_company_com@localhost -p 5000 -i "C:/Users/<username>/.ssh/google_compute_engine

.EXAMPLE
    Build up a new SSH connection from commandline
    C:\Windows\System32\OpenSSH\ssh.exe -o ProxyCommand='C:\Windows\System32\OpenSSH\ssh.exe -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p username_company_com@localhost -p 5000 -i "C:/Users/<username>/.ssh/google_compute_engine"' <linux user>@<Target sever address> -p 22 -i "C:\Users\<username>\.ssh\id_rsa"
#>

$script:_scriptDir=$PSScriptRoot
$script:_connectionJob = $null; 
$script:_localPort = $null;

function New-IAPConnectionJob() {

    [CmdletBinding()]
    param(
        [Parameter(Position=0,mandatory=$true)]
        $InstanceName,
        [Parameter(Position=1,mandatory=$true)]
        $InstanceZone
    )

    $_count=20
    $_i = 0;

    $_job = {
        param(
            $InstanceName,
            $InstanceZone
        )
        if ($LASTEXITCODE -ne 0) {
            Write-Output "Connect to $InstanceName in zone $InstanceZone"
            gcloud compute start-iap-tunnel $InstanceName 22 --local-host-port=localhost:5000 --zone $InstanceZone # --quiet --verbosity none 
        }
    }

    Do {
        $_i++
        Write-Output "Test gcloud connection"

        $_randomName = -join ((65..90) + (97..122) | Get-Random -Count 5 | Foreach-Object {[char]$_})
        $_jobName = "GCPIAP_{0}" -f $_randomName
        Start-Job -Name $_jobName -ArgumentList @($InstanceName, $InstanceZone) -ScriptBlock $_job | Out-Null
        Start-Sleep -Seconds 20
        $_connectionJob = Get-Job -Name $_jobName
        if ($_connectionJob.State -eq 'Running') {
            Write-Output "Connection successful. Job ID: $($_connectionJob.Id)"
            break
        } else {
            Write-Output "Failed to access maschine (Try $_i/$_count)"
            if($_i -eq $_count) {
                Write-Error "Failed to connect to gcp compute engine"
            }
            Stop-Job -Name $_jobName 
            Remove-Job -Name $_jobName
        }

    } While($_i -lt $_count)
}

function Open-IAPConnection {

    param(
        [Parameter(Position=0,mandatory=$true)]
        [string]$InstanceZone,
        [Parameter(Position=1,mandatory=$true)]
        [string]$InstanceProject,
        [Parameter(Position=2,mandatory=$true)]
        [string]$InstanceName,
        [Parameter(Position=3,mandatory=$false)]
        [string]$InstanceMachineType="e2-medium",
        [Parameter(Position=4,mandatory=$true)]
        [string]$InstanceNetworkIP,
        [Parameter(Position=5,mandatory=$true)]
        [string]$InstanceSubnetworkInterface,
        [Parameter(Position=6,mandatory=$true)]
        [string]$InstanceTags,
        [Parameter(Position=7,mandatory=$false)]
        [string]$InstanceDiskSpecs="image-family=ubuntu-minimal-2004-lts,image-project=ubuntu-os-cloud",
        [Parameter(Position=8,mandatory=$false)]
        [string]$InstanceDiskSize="10",
        [Parameter(Position=9,mandatory=$true)]
        [string]$InstanceDiskType,
        [Parameter(Position=10,mandatory=$false)]
        [string]$InstanceLabels
    )

    if (-Not (Get-Command gcloud -ErrorAction SilentlyContinue)) { throw "Gcloud utility must be installed" }

    Write-Output "Set project to ""$InstanceProject"""
    gcloud config set project $InstanceProject --quiet --verbosity none

    if((gcloud compute instances list --format="table(name)").contains($InstanceName)) { 
        Write-Output "Delete existing instance ""$InstanceName"""
        gcloud compute instances delete $InstanceName --zone=$InstanceZone --delete-disks=all --quiet --verbosity none
        $_return=$?
        if (! $_return) {
            Write-Error "  Failed to delete instance (Returncode: $_return)"
        } else {
            Write-Output -Message "  Sucessful deleted instance"
        }
    } else {
        Write-Output -Message "Instance ""$InstanceName"" not found"
    }

    # Create the bash file which configures ssh
    $_randomName = -join ((65..90) + (97..122) | Get-Random -Count 5 | Foreach-Object {[char]$_})
    $_fileName = "{0}\GCPIAP_{1}" -f $env:TMP, $_randomName
    'echo "AuthorizedKeysCommand /usr/bin/google_authorized_keys" > /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Encoding ascii
    'echo "AuthorizedKeysCommandUser root" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "PasswordAuthentication no" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "UsePAM yes" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "X11Forwarding yes" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "PrintMotd no" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "AcceptEnv LANG LC_*" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "Subsystem       sftp    /usr/lib/openssh/sftp-server" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'echo "GatewayPorts yes" >> /etc/ssh/sshd_config' | Out-File -FilePath $_fileName -Append
    'sudo systemctl restart sshd' | Out-File -FilePath $_fileName -Append
    
    Write-Output "Try to create the instance ""$InstanceName"""
    gcloud compute instances create $InstanceName `
    --project="$($InstanceProject)" `
    --zone="$($InstanceZone)" `
    --machine-type="$($InstanceMachineType)" `
    --network-interface="private-network-ip=$($InstanceNetworkIP),subnet=$($InstanceSubnetworkInterface),no-address" `
    --metadata="enable-oslogin=true" `
    --maintenance-"policy=MIGRATE" `
    --provisioning-model="STANDARD" `
    --no-service-account `
    --no-scopes `
    --tags="$($InstanceTags)" `
    --create-disk="auto-delete=yes,boot=yes,device-name=$($InstanceName)-disk0,$($InstanceDiskSpecs),mode=rw,size=$($InstanceDiskSize),type=$($InstanceDiskType)" `
    --resource-policies="cost-saving-pkg" `
    --no-shielded-secure-boot `
    --shielded-vtpm `
    --shielded-integrity-monitoring `
    --labels="$($InstanceLabels)" `
    --reservation-affinity="any" `
    --metadata-from-file="startup-script=$($_fileName)" `
    --quiet `
    --verbosity none

    Remove-Item -Path $_fileName -Force

    $_return=$?
    if (! $_return) {
        Write-Error "  Failed to create instance ""$InstanceName"" (Returncode: $_return)"
    } else {
        Write-Output "  Successful created instance" 
    }

    $_GCPIAPJobs = Get-Job -Name "GCPIAP*"
    $_GCPIAPJobs | ForEach-Object { Stop-Job $_ }
    $_GCPIAPJobs | ForEach-Object { Remove-Job $_ }

    if ($null -eq (Get-Job -Name "GCPIAP*")) {
        Write-Output "Create IAP connection to computer ""$InstanceName"" in zone ""$InstanceZone"" on local port ""5000"""
        New-IAPConnectionJob -InstanceName $InstanceName -InstanceZone $InstanceZone
    } else {
        Write-Output "Please cleanup your IAP connection Job. There is some shit in the background (execute PS Command Get-Jobs ad remove GCPIAP* Jobs)"
        exit 1
    }
}
