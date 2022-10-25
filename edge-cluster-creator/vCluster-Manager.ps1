# Hacker: Scott Deeg
# 
# A heavily hacked version of a script originally created by William Lam (www.virtuallyghetto.com)
#
# Create a virtual cluster on vSphere for use in demonstrating Edge Computing environments
#
# I moved a lot of code into include files and use this for the logic and display of data
# in the REPL as well as the env specific variables

#############################################  Env Variables  #############################################

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
    # vesx3 = @{
    #     vmname = "vesx3"
    #     ip = "192.168.4.13"
    # }
}

$NestedESXiApplianceOVA = "/home/sdeeg/Downloads/Nested_ESXi7.0u3g_Appliance_Template_v1.ova"

# Optional: Create/override any variables here
$verboseLogFile = "edge-manager.log"
if((Test-Path $verboseLogFile)) {
    Write-Host "Logfile $verboseLogFile exists at startup and will be deleted"
    Remove-Item $verboseLogFile
}

#############################################  Functions      #############################################

# General functions
. ./UtilityFunctions.ps1

# Functions that interact with vSphere
. ./CreateClusterHelperFunctions.ps1

#############################################  Local Functions  #############################################

Function Begin-New-Output {
    # Clear-Host
    My-Writer "--- Edge Cluster Manager ---" Yellow
    My-Writer ""
}

Function Write-vCluster-Overview {
    My-Logger "Virtual Cluster Status:"
    $vCluster.GetEnumerator() | Sort-Object -Property Key | Foreach-Object {
        $vHostId = $_.Key
        $vHostValues = $_.Value
        $vm = Get-VM -Name $vHostValues.vmname -Location $vSphereSpec.Cluster -ErrorAction SilentlyContinue
        if($vm) {
            $vHostStatus = "VM exists, PowerState=$($vm.PowerState)"
        }
        else { $vHostStatus = "VM not created" }
        My-Logger "    vHost=$($vHostValues.vmname) Status=$vHostStatus"
    }
}

Function Show-Cluster-Details {
    My-Logger "Virtual Cluster Spec:"
    My-Logger "`tvSphere:"
    My-Logger "`t`tvCenterServer=$($vSphereSpec.vCenterServer)"
    My-Logger "`t`tUsername=$($vSphereSpec.Username)"
    My-Logger "`t`tDatacenter=$($vSphereSpec.Datacenter)"
    My-Logger "`t`tCluster=$($vSphereSpec.Cluster)"
    My-Logger "`t`tFolder=$($vSphereSpec.Folder)"
    My-Logger "`tvHost Spec:"
    My-Logger "`t`tvCpu=$($vHostSpec.vCpu)"

    My-Logger "`tvHosts:"
    $vCluster.GetEnumerator() | Sort-Object -Property Key | Foreach-Object {
        $vHostId = $_.Key
        $vHostValues = $_.Value
        $vm = Get-VM -Name $vHostValues.vmname -Location $vSphereSpec.Cluster -ErrorAction SilentlyContinue
        if($vm) {
            My-Logger "`t$($vm.Name)"
            My-Logger "`t`tPowerState=$($vm.PowerState)"
            My-Logger "`t`tHost=$($vm.VMHost.Name)"
            My-Logger "`t`tCreateDate=$($vm.CreateDate)"
        }
        else {
            My-Logger "`t$($vHostValues.vmname) (Not created)"
        }
    }
}


##############################################################################################################
#############################################  Main Entry Point  #############################################
##############################################################################################################

Do-Pre-Checks
VCenter-Connect


#############################################     Begin REPL     #############################################

$keepLooping=$true
while($keepLooping) {

    Refresh-Cluster-Details
    Begin-New-Output
    Write-vCluster-Overview

    $no = New-Object System.Management.Automation.Host.ChoiceDescription 'E&xit', 'Exit'
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($no)
    if($foundVMs.Count -eq 0) {
        $options += New-Object System.Management.Automation.Host.ChoiceDescription '&Create cluster', 'Create the edge cluster'
    } else {
        $options += New-Object System.Management.Automation.Host.ChoiceDescription '&Delete cluster', 'Delete the edge cluster'
    }
    $options += New-Object System.Management.Automation.Host.ChoiceDescription '&Show details', 'Show details of the edge cluster'
    $result = $host.ui.PromptForChoice('Edge Manager', 'Do something?', $options, 0)

    switch ($result) {
        0 {
            My-Logger "You said No"
            $keepLooping=$false
        }
        1 {
            if($foundVMs.Count -gt 0) {
                Begin-New-Output
                Delete-Edge-Cluster
            } else {
                Begin-New-Output
                Create-Edge-Cluster
            }    
        }
        2 {
            Clear-Host
            Show-Cluster-Details
            Write-Host ""
            Read-Host -Prompt 'Press Enter when done'
        }
    }
}


#############################################      Clean Up      #############################################

VCenter-Disconnect

My-Logger "end of line"
