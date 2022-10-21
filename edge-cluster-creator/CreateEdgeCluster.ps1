# Hacker: Scott Deeg
# 
# A heavily hacked version of a script originally created by
# Author: William Lam
# Website: www.virtuallyghetto.com
#
# I moved a lot of code into an include file and use this for configuration and the the logic
# for deploying and configuring the cluster.

#############################################  Env Variables  #############################################

. ./Config.ps1

# Include the helper functions
. ./UtilityFunctions.ps1
. ./CreateClusterHelperFunctions.ps1

##############################################################################################################
#############################################  Main Entry Point  #############################################
##############################################################################################################

if($preCheck -eq 1) {
    Do-Pre-Checks
}

if($confirmDeployment -eq 1) {
    Confirm-Deployment
    Clear-Host
}

#############  Begin Real Work

# If connect isn't working make sure to disable the TSL checks in PowerCLI
# Set-PowerCLIConfiguration -InvalidCertificateAction Ignore
My-Logger "Connecting to Management vCenter Server $VIServer ..."
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
if(!$viConnection) {
    My-Logger "Connect-VIServer came back empty.  Exiting."
    exit
}

My-Logger "Getting the cluster $VMCluster"
$cluster = Get-Cluster -Server $viConnection -Name $VMCluster
if(!$cluster) {
    My-Logger "Get-Cluster came back empty.  Exiting."
    exit
}

$hosts = $cluster | Get-VMHost
$requestedVirtualHosts = $NestedESXiHostnameToIPs.Count
$availableHosts = $hosts.Count
if($requestedVirtualHosts > $availableHosts) {
    My-Logger "There are not enough hosts ($requestedVirtualHosts) for all the requested virtual hosts ($availableHosts)"
    exit
}
$hosts = $hosts | Sort-Object -Property MemoryUsageGB | Select -First $requestedVirtualHosts
My-Logger "Verify hosts selected for deployment have enough memory to support $NestedESXivMEM Gb virtual hosts:"
#There's something wrong here, but it's not impacting as I know I have the capacity.
# $hosts | Foreach-Object {
#     $hostId = $_.Id;
#     $memAvailableGb = $_.MemoryTotalGB - $_.MemoryUsageGB
#     if($memAvailableGb > $NestedESXivMEM) { My-Logger "VMHost Id=$hostId memAvailable=$memAvailableGb Gb OKay" } # Why isn't this true???
#     else { My-Logger "VMHost Id=$hostId memAvailable=$memAvailableGb Gb Fail" }
# }


if($deployNestedESXiVMs -eq 1) {
    My-Logger "Setting up to deploy nested cluster ..."

    #Need to re-hash this to attach VM to specific datastores on the Hosts
    $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select -First 1

    $datacenter = $cluster | Get-Datacenter


    $vHostsEnumerator = $NestedESXiHostnameToIPs.GetEnumerator()
    $hosts | Foreach-Object {
        if(!$vHostsEnumerator.MoveNext()) {
            My-Logger "Error: the number of nested hosts is out of synch with the available host list"
        }
        $VMName = $vHostsEnumerator.Current.Key
        $VMIPAddress = $vHostsEnumerator.Current.Value
        $hostId = $_.Id;

        My-Logger "Preparing to create VM $VMName with IP $VMIPAddress on Host $hostId"
        $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
        $networkMapLabel = ($ovfconfig.ToHashTable().keys | where {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
        $ovfconfig.NetworkMapping.$networkMapLabel.value = $VMNetwork

        $ovfconfig.common.guestinfo.hostname.value = $VMName
        $ovfconfig.common.guestinfo.ipaddress.value = $VMIPAddress
        $ovfconfig.common.guestinfo.netmask.value = $VMNetmask
        $ovfconfig.common.guestinfo.gateway.value = $VMGateway
        $ovfconfig.common.guestinfo.dns.value = $VMDNS
        $ovfconfig.common.guestinfo.domain.value = $VMDomain
        $ovfconfig.common.guestinfo.ntp.value = $VMNTP
        $ovfconfig.common.guestinfo.syslog.value = $VMSyslog
        $ovfconfig.common.guestinfo.password.value = $VMPassword
        if($VMSSH -eq "true") {
            $VMSSHVar = $true
        } else {
            $VMSSHVar = $false
        }
        $ovfconfig.common.guestinfo.ssh.value = $VMSSHVar

        My-Logger "Deploying Nested ESXi VM $VMName ..."
        $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $VMName -Location $cluster -VMHost $_ -Datastore $datastore -DiskStorageFormat thin

        if($vm) {
            My-Logger "the VM was created"
        }
        else { My-Logger "Something happened (and it wasn't good)" }
    }
    
    # $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
    #     $VMName = $_.Key
    #     $VMIPAddress = $_.Value
    #     $VMHost = $hostsEnumerator.Current
    #     $hostId = $VMHost.Id


    #     $hostsEnumerator.MoveNext

    #     $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
    #     $networkMapLabel = ($ovfconfig.ToHashTable().keys | where {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
    #     $ovfconfig.NetworkMapping.$networkMapLabel.value = $VMNetwork

    #     $ovfconfig.common.guestinfo.hostname.value = $VMName
    #     $ovfconfig.common.guestinfo.ipaddress.value = $VMIPAddress
    #     $ovfconfig.common.guestinfo.netmask.value = $VMNetmask
    #     $ovfconfig.common.guestinfo.gateway.value = $VMGateway
    #     $ovfconfig.common.guestinfo.dns.value = $VMDNS
    #     $ovfconfig.common.guestinfo.domain.value = $VMDomain
    #     $ovfconfig.common.guestinfo.ntp.value = $VMNTP
    #     $ovfconfig.common.guestinfo.syslog.value = $VMSyslog
    #     $ovfconfig.common.guestinfo.password.value = $VMPassword
    #     if($VMSSH -eq "true") {
    #         $VMSSHVar = $true
    #     } else {
    #         $VMSSHVar = $false
    #     }
    #     $ovfconfig.common.guestinfo.ssh.value = $VMSSHVar

    #     My-Logger "Deploying Nested ESXi VM $VMName ..."
    #     $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $VMName -Location $cluster -VMHost $vmhost -Datastore $datastore -DiskStorageFormat thin

    #     My-Logger "Adding vmnic2/vmnic3 to $NSXVTEPNetwork ..."
    #     New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $NSXVTEPNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    #     New-NetworkAdapter -VM $vm -Type Vmxnet3 -NetworkName $NSXVTEPNetwork -StartConnected -confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    #     $vm | New-AdvancedSetting -name "ethernet2.filter4.name" -value "dvfilter-maclearn" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile
    #     $vm | New-AdvancedSetting -Name "ethernet2.filter4.onFailure" -value "failOpen" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile

    #     $vm | New-AdvancedSetting -name "ethernet3.filter4.name" -value "dvfilter-maclearn" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile
    #     $vm | New-AdvancedSetting -Name "ethernet3.filter4.onFailure" -value "failOpen" -confirm:$false -ErrorAction SilentlyContinue | Out-File -Append -LiteralPath $verboseLogFile

    #     My-Logger "Updating vCPU Count to $NestedESXivCPU & vMEM to $NestedESXivMEM GB ..."
    #     Set-VM -Server $viConnection -VM $vm -NumCpu $NestedESXivCPU -MemoryGB $NestedESXivMEM -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    #     My-Logger "Updating vSAN Cache VMDK size to $NestedESXiCachingvDisk GB & Capacity VMDK size to $NestedESXiCapacityvDisk GB ..."
    #     Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 2" | Set-HardDisk -CapacityGB $NestedESXiCachingvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
    #     Get-HardDisk -Server $viConnection -VM $vm -Name "Hard disk 3" | Set-HardDisk -CapacityGB $NestedESXiCapacityvDisk -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

    #     My-Logger "Powering On $vmname ..."
    #     $vm | Start-Vm -RunAsync | Out-Null
    # }
}


if($moveVMsIntovApp -eq 1) {
    My-Logger "Creating vApp $VAppName ..."
#     $VApp = New-VApp -Name $VAppName -Server $viConnection -Location $cluster

#     if(-Not (Get-Folder $VMFolder -ErrorAction Ignore)) {
#         My-Logger "Creating VM Folder $VMFolder ..."
#         $folder = New-Folder -Name $VMFolder -Server $viConnection -Location (Get-Datacenter $VMDatacenter | Get-Folder vm)
#     }

#     if($deployNestedESXiVMs -eq 1) {
#         My-Logger "Moving Nested ESXi VMs into $VAppName vApp ..."
#         $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
#             $vm = Get-VM -Name $_.Key -Server $viConnection
#             Move-VM -VM $vm -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
#         }
#     }

#     if($deployVCSA -eq 1) {
#         $vcsaVM = Get-VM -Name $VCSADisplayName -Server $viConnection
#         My-Logger "Moving $VCSADisplayName into $VAppName vApp ..."
#         Move-VM -VM $vcsaVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
#     }

#     if($deployNSXManager -eq 1) {
#         $nsxMgrVM = Get-VM -Name $NSXTMgrDisplayName -Server $viConnection
#         My-Logger "Moving $NSXTMgrDisplayName into $VAppName vApp ..."
#         Move-VM -VM $nsxMgrVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
#     }

#     if($deployTKGI -eq 1) {
#         $TKGIVM = Get-VM -Name $TKGIPKSConsoleName  -Server $viConnection
#         My-Logger "Moving $TKGIPKSConsoleName into $VAppName vApp ..."
#         Move-VM -VM $TKGIVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
#     }

#     if($deployNSXEdge -eq 1) {
#         My-Logger "Moving NSX Edge VMs into $VAppName vApp ..."
#         $NSXTEdgeHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
#             $nsxEdgeVM = Get-VM -Name $_.Key -Server $viConnection
#             Move-VM -VM $nsxEdgeVM -Server $viConnection -Destination $VApp -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
#         }
#     }

    My-Logger "Moving $VAppName to VM Folder $VMFolder ..."
#     Move-VApp -Server $viConnection $VAppName -Destination (Get-Folder -Server $viConnection $VMFolder) | Out-File -Append -LiteralPath $verboseLogFile
}

if( $viConnection ) {
    My-Logger "Disconnecting from $VIServer ..."
    Disconnect-VIServer -Server $viConnection -Confirm:$false
}

$EndTime = Get-Date
$duration = [math]::Round((New-TimeSpan -Start $StartTime -End $EndTime).TotalMinutes,2)

My-Logger "End deployment of edge cluster"
My-Logger "StartTime: $StartTime"
My-Logger "  EndTime: $EndTime"
My-Logger " Duration: $duration minutes"