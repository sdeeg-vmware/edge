# Include the standard config
. ./Config.ps1

# These variables must be set

$vCluster = @{
    vesx1 = @{
        vmname = "vesx1"
        ip = "192.168.4.11"
    }
    vesx2 = @{
        vmname = "vesx2"
        ip = "192.168.4.12"
    }
    vesx3 = @{
        vmname = "vesx3"
        ip = "192.168.4.13"
    }
}

$NestedESXiApplianceOVA = "/home/sdeeg/Downloads/Nested_ESXi7.0u3g_Appliance_Template_v1.ova"

# Optional: Create/override any variables here
$verboseLogFile = "scratch.log"
if((Test-Path $verboseLogFile)) {
    Write-Host "Logfile $verboseLogFile exists at startup and will be deleted"
    Remove-Item $verboseLogFile
}

#############################################  Functions      #############################################

# General functions
. ./UtilityFunctions.ps1

# Functions that interact with vSphere
. ./CreateClusterHelperFunctions.ps1

#$MY_WRITE_TYPE="output"

# VCenter-Connect

# $cl = Get-ContentLibrary -Name "nested-esxi"
# $cli = Get-ContentLibraryItem -Name "Nested_ESXi7.0u3g_Appliance_Template_v1" -ContentLibrary $cl
# My-Logger $cli

# VCenter-Disconnect

$ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
$networkMapLabel = ($ovfconfig.ToHashTable().keys | Where-Object {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
$ovfconfig.NetworkMapping.$networkMapLabel.value = $VMNetwork

$ovfconfig.common.guestinfo.hostname.value = $vHostSpec.Network.Name
$ovfconfig.common.guestinfo.ipaddress.value = $vHostConfig.ip
$ovfconfig.common.guestinfo.netmask.value = $vHostSpec.Network.Netmask
$ovfconfig.common.guestinfo.gateway.value = $vHostSpec.Network.Gateway
$ovfconfig.common.guestinfo.dns.value = $vHostSpec.Network.DNS
$ovfconfig.common.guestinfo.domain.value = $vHostSpec.Domain
$ovfconfig.common.guestinfo.ntp.value = $vHostSpec.NTP
$ovfconfig.common.guestinfo.syslog.value = $vHostSpec.Syslog
$ovfconfig.common.guestinfo.password.value = $vHostSpec.Password
$ovfconfig.common.guestinfo.ssh.value = $vHostSpec.VMSSH

My-Logger $ovfconfig.common.guestinfo

My-Logger "end of line"
