#############################################  Functions  #############################################

Function Do-Pre-Checks {
    My-Logger "Starting pre checks..."

    if($PSVersionTable.PSEdition -ne "Core") {
        My-Logger "`tYPowerShell Core was not detected, please install before continuing ... `nexiting"
        exit 0
    }
    My-Logger "`tPowerShell detected"

    if($vCluster.Keys.Count -eq 0) {
        My-Logger "`tUnable to find the list of vHosts, please set the variable vCluster ...`nexiting"
        exit 0
    }
    My-Logger "`tvHost list found"

    #TODO: Can we change this to look for the VM Template in inventory
    if(!$NestedESXiApplianceOVA) {
        My-Logger "`NestedESXiApplianceOVA is default or unset.  Set to path to ESXi OVA`nexiting"
        exit 0
    }
    if(!(Test-Path $NestedESXiApplianceOVA)) {
        My-Logger "`tUnable to find the file $NestedESXiApplianceOVA ...`nexiting"
        exit 0
    }
    My-Logger "`tNested ESXi Appliance found"

    My-Logger "Finished pre checks"
}

Function VCenter-Connect {
    # If connect isn't working make sure to disable the TSL checks in PowerCLI
    # Set-PowerCLIConfiguration -InvalidCertificateAction Ignore
    My-Logger "Connecting to vCenter Server $vSphereSpec.vCenterServer ... " Blue $true
    $viConnection = Connect-VIServer $vSphereSpec.vCenterServer -User $vSphereSpec.UserName -Password $vSphereSpec.Password -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if(!$viConnection) {
        if($debug) {
            My-Logger "Connect-VIServer came back empty.  debug=true so continuing." DarkMagenta
        } else {
            My-Logger "Connect-VIServer came back empty.  Exiting." Red
            exit
        }
    }
    My-Logger "connected" Green

    # Todo: Add validation of vCenter details here
}


Function VCenter-Disconnect {
    if( $viConnection ) {
        My-Logger "Disconnecting from $vSphereSpec.vCenterServer ..."
        # Disconnect-VIServer -Server $viConnection -Confirm:$false
        Disconnect-VIServer * -Confirm:$false | Out-Null
    }
    $viConnection = $null
}

Function Refresh-Cluster-Details {

}

Function Create-Edge-Cluster {
    My-Logger "Deploying the Edge Cluster"

    My-Logger "Looking for hosts to deploy the vHosts to"
    if(!$cluster) { $cluster = Get-Cluster -Name $vSphereSpec.Cluster }
    $hosts = $cluster | Get-VMHost
    if($vCluster.Count -gt $hosts.Count) { 
        My-Logger "Not enough hosts ($($hosts.Count)) to deploy the number of requested vHosts ($($vCluster.Count)) ... Aborting" Red
    }
    else {
        My-Logger "`tEnough hosts exist ($($hosts.Count)) to deploy the number of requested vHosts ($($vCluster.Count))" Green
    
        $hosts = $hosts | Sort-Object -Property MemoryUsageGB | Select-Object -First $vCluster.Count
        My-Logger "Verify hosts selected for deployment have enough memory to support $($vSphereSpec.vMem) Gb virtual hosts:"
        $hostsHaveMemory = $true;
        $hosts | Foreach-Object {
            $hostName = $_.Name;
            $memAvailableGb = [Math]::Floor($_.MemoryTotalGB - $_.MemoryUsageGB)
            if($memAvailableGb -gt $vSphereSpec.vMem) { My-Logger "`tVMHost Name=$hostName memAvailable=$memAvailableGb Gb OKay" Green } # Why isn't this true???
            else { My-Logger "`tVMHost Name=$hostName memAvailable=$memAvailableGb Gb Fail" Red; $hostsHaveMemory = $false }
        }    
    }

    if($hostsHaveMemory) {
        #Need to re-hash this to attach VM to specific datastores on the Hosts
        $datastore = Get-Datastore -Server $viConnection -Name $vHostSpec.Storage.Main | Select-Object -First 1    
        #$datacenter = $cluster | Get-Datacenter
        $cl = Get-ContentLibrary -Name $vSphereSpec.ContentLibrary
        $cli = Get-ContentLibraryItem -Name $vSphereSpec.ContentLibraryItem -ContentLibrary $cl
        $hostCounter=0
        $vCluster.GetEnumerator() | Sort-Object -Property Key | Foreach-Object {
            # $vHostId = $_.Key
            $vHostConfig = $_.Value
            $hostObject = $hosts[$hostCounter]
    
            $vm = $cluster | Get-VM -Name $vHostConfig.vmname -ErrorAction SilentlyContinue
            if($vm) {
                My-Logger "Found vm $($vm.Name) already exists on host $($vm.VMHost.Name)"
            }
            else {
                My-Logger "Creating VM $($vHostConfig.vmname) on host $($hostObject.Name).  Skipping create."
    
                # $ovfconfig = Get-OvfConfiguration $NestedESXiApplianceOVA
                $ovfconfig = Get-OvfConfiguration -ContentLibraryItem $cli -Target $hostObject
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
        
                My-Logger "Deploying vHost $($vHostConfig.vmname) ..."
    
                # $vm = Import-VApp -Source $NestedESXiApplianceOVA -OvfConfiguration $ovfconfig -Name $vHostConfig.vmname -Location $cluster -VMHost $hostObject -Datastore $datastore -DiskStorageFormat thin
                $vm = New-VM -ContentLibraryItem $cli -OvfConfiguration $ovfconfig -Name $vHostConfig.vmname -Location $vHostSpec.Folder -VMHost $hostObject -Datastore $datastore -DiskStorageFormat thin
        
                if($vm) {
                    My-Logger "the VM was created"
                }
                else { My-Logger "Something happened (and it wasn't good)" }
            }
    
            $hostCounter++
        }
    }

    Read-Host -Prompt 'Press Enter when done'
}

Function Delete-Edge-Cluster {
    My-Logger "Deleting the edge cluster"
    $vCluster.GetEnumerator() | Sort-Object -Property Key | Foreach-Object {
        # $vHostId = $_.Key
        $vHostConfig = $_.Value
        # $hostObject = $hosts[$hostCounter]

        $vm = $cluster | Get-VM -Name $vHostConfig.vmname -ErrorAction SilentlyContinue
        if($vm) {
            My-Logger "Found vm $($vm.Name) already exists on host $($vm.VMHost.Name)"
        }
    }
    foreach ($vm in $foundVMs) {
        if($vm.PowerState -eq "PoweredOn") { My-Logger "VM $($vm.Name) powered on.  Stopping ... " Blue $true; Stop-VM $vm -Confirm=$true; My-Logger "done"; }
        else  { My-Logger "VM $($vm.Name) powered off" }
    }

    My-Logger "Deleting vHost VMs ... " Blue $true
    Remove-VM $foundVMs -DeletePermanently
    My-Logger "done"
}

###################################  Function dump from main script and random code


# WL's function to print out and confirm the settings.  Use for inspiration before deleting.
Function Confirm-Deployment {
    # Write-Host -ForegroundColor Magenta "`nPlease confirm the following configuration will be deployed:`n"

    # Write-Host -ForegroundColor Yellow "---- Virtual ESXi cluster Image ---- "
    # Write-Host -NoNewline -ForegroundColor Green "Nested ESXi Image Path: "
    # Write-Host -ForegroundColor White $NestedESXiApplianceOVA

    # Write-Host -ForegroundColor Yellow "`n---- vCenter Server Deployment Target Configuration ----"
    # Write-Host -NoNewline -ForegroundColor Green "vCenter Server Address: "
    # Write-Host -ForegroundColor White $vSphereSpec.vCenterServer
    # Write-Host -NoNewline -ForegroundColor Green "VM Network: "
    # Write-Host -ForegroundColor White $VMNetwork

    # Write-Host -NoNewline -ForegroundColor Green "VM Storage: "
    # Write-Host -ForegroundColor White $VMDatastore
    # Write-Host -NoNewline -ForegroundColor Green "VM Cluster: "
    # Write-Host -ForegroundColor White $VMCluster
    # Write-Host -NoNewline -ForegroundColor Green "VM vApp: "
    # Write-Host -ForegroundColor White $VAppName

    # Write-Host -ForegroundColor Yellow "`n---- vESXi Configuration ----"
    # Write-Host -NoNewline -ForegroundColor Green "# of Nested ESXi VMs: "
    # Write-Host -ForegroundColor White $NestedESXiHostnameToIPs.count
    # Write-Host -NoNewline -ForegroundColor Green "vCPU: "
    # Write-Host -ForegroundColor White $vSphereSpec.vCPU
    # Write-Host -NoNewline -ForegroundColor Green "vMEM: "
    # Write-Host -ForegroundColor White "$vSphereSpec.vMem GB"
    # Write-Host -NoNewline -ForegroundColor Green "Caching VMDK: "
    # Write-Host -ForegroundColor White "$vSphereSpec.Storage.Caching GB"
    # Write-Host -NoNewline -ForegroundColor Green "Capacity VMDK: "
    # Write-Host -ForegroundColor White "$vSphereSpec.Storage.Capacity GB"
    # Write-Host -NoNewline -ForegroundColor Green "IP Address(s): "
    # Write-Host -ForegroundColor White $NestedESXiHostnameToIPs.Values
    # Write-Host -NoNewline -ForegroundColor Green "Netmask "
    # Write-Host -ForegroundColor White $VMNetmask
    # Write-Host -NoNewline -ForegroundColor Green "Gateway: "
    # Write-Host -ForegroundColor White $VMGateway
    # Write-Host -NoNewline -ForegroundColor Green "DNS: "
    # Write-Host -ForegroundColor White $VMDNS
    # Write-Host -NoNewline -ForegroundColor Green "NTP: "
    # Write-Host -ForegroundColor White $VMNTP
    # Write-Host -NoNewline -ForegroundColor Green "Syslog: "
    # Write-Host -ForegroundColor White $VMSyslog
    # Write-Host -NoNewline -ForegroundColor Green "Enable SSH: "
    # Write-Host -ForegroundColor White $VMSSH
    # Write-Host -NoNewline -ForegroundColor Green "Create VMFS Volume: "
    # Write-Host -ForegroundColor White $VMVMFS

    # $esxiTotalCPU = $NestedESXiHostnameToIPs.count * [int]$vSphereSpec.vCPU
    # $esxiTotalMemory = $NestedESXiHostnameToIPs.count * [int]$vSphereSpec.vMem
    # $esxiTotalStorage = ($NestedESXiHostnameToIPs.count * [int]$vSphereSpec.Storage.Caching) + ($NestedESXiHostnameToIPs.count * [int]$vSphereSpec.Storage.Capacity)

    # Write-Host -ForegroundColor Yellow "`n---- Resource Requirements ----"
    # Write-Host -NoNewline -ForegroundColor Green "ESXi     VM CPU: "
    # Write-Host -NoNewline -ForegroundColor White $esxiTotalCPU
    # Write-Host -NoNewline -ForegroundColor Green " ESXi     VM Memory: "
    # Write-Host -NoNewline -ForegroundColor White $esxiTotalMemory "GB "
    # Write-Host -NoNewline -ForegroundColor Green "ESXi     VM Storage: "
    # Write-Host -ForegroundColor White $esxiTotalStorage "GB"
    # Write-Host -NoNewline -ForegroundColor Green "VCSA     VM CPU: "
    # Write-Host -NoNewline -ForegroundColor White $vcsaTotalCPU
    # Write-Host -NoNewline -ForegroundColor Green " VCSA     VM Memory: "
    # Write-Host -NoNewline -ForegroundColor White $vcsaTotalMemory "GB "
    # Write-Host -NoNewline -ForegroundColor Green "VCSA     VM Storage: "
    # Write-Host -ForegroundColor White $vcsaTotalStorage "GB"

    # Write-Host -ForegroundColor White "---------------------------------------------"
    # Write-Host -NoNewline -ForegroundColor Green "Total CPU: "
    # Write-Host -ForegroundColor White ($esxiTotalCPU + $vcsaTotalCPU + $nsxManagerTotalCPU + $nsxEdgeTotalCPU)
    # Write-Host -NoNewline -ForegroundColor Green "Total Memory: "
    # Write-Host -ForegroundColor White ($esxiTotalMemory + $vcsaTotalMemory + $nsxManagerTotalMemory + $nsxEdgeTotalMemory) "GB"
    # Write-Host -NoNewline -ForegroundColor Green "Total Storage: "
    # Write-Host -ForegroundColor White ($esxiTotalStorage + $vcsaTotalStorage + $nsxManagerTotalStorage + $nsxEdgeTotalStorage) "GB"

    # Write-Host -ForegroundColor Magenta "`nWould you like to proceed with this deployment?`n"
    # $answer = Read-Host -Prompt "Do you accept (Y or N)"
    # if($answer -ne "Y" -or $answer -ne "y") {
    #     exit
    # }
}

Function setupNewVC {
    My-Logger "setupNewVC is not implemented"
#     My-Logger "Connecting to the new VCSA ..."
#     $vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue

#     $d = Get-Datacenter -Server $vc $NewVCDatacenterName -ErrorAction Ignore
#     if( -Not $d) {
#         My-Logger "Creating Datacenter $NewVCDatacenterName ..."
#         New-Datacenter -Server $vc -Name $NewVCDatacenterName -Location (Get-Folder -Type Datacenter -Server $vc) | Out-File -Append -LiteralPath $verboseLogFile
#     }

#     $c = Get-Cluster -Server $vc $NewVCVSANClusterName -ErrorAction Ignore
#     if( -Not $c) {
#         My-Logger "Creating VSAN Cluster $NewVCVSANClusterName ..."
#         New-Cluster -Server $vc -Name $NewVCVSANClusterName -Location (Get-Datacenter -Name $NewVCDatacenterName -Server $vc) -DrsEnabled -HAEnabled -VsanEnabled | Out-File -Append -LiteralPath $verboseLogFile
#         (Get-Cluster $NewVCVSANClusterName) | New-AdvancedSetting -Name "das.ignoreRedundantNetWarning" -Type ClusterHA -Value $true -Confirm:$false -Force | Out-File -Append -LiteralPath $verboseLogFile
#     }

#     if($addESXiHostsToVC -eq 1) {
#         $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
#             $VMName = $_.Key
#             $VMIPAddress = $_.Value

#             $targetVMHost = $VMIPAddress
#             if($addHostByDnsName -eq 1) {
#                 $targetVMHost = $VMName
#             }
# 			$orf1 = (Get-Cluster -Name $NewVCVSANClusterName).Name | Select-Object -first 1
#             My-Logger "Adding ESXi host $targetVMHost to Cluster ...$orf1"
#             Add-VMHost -Server $vc -Location $orf1 -User "root" -Password $VMPassword -Name $targetVMHost -Force | Out-File -Append -LiteralPath $verboseLogFile
#             #Add-VMHost -Server $vc -Location (Get-Cluster -Name $NewVCVSANClusterName) -User "root" -Password $VMPassword -Name $targetVMHost -Force | Out-File -Append -LiteralPath $verboseLogFile
#         }
#     }

#     if($configureVSANDiskGroup -eq 1) {
#         My-Logger "Enabling VSAN & disabling VSAN Health Check ..."
#         Get-VsanClusterConfiguration -Server $vc -Cluster $NewVCVSANClusterName | Set-VsanClusterConfiguration -HealthCheckIntervalMinutes 0 | Out-File -Append -LiteralPath $verboseLogFile

#         foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
#             $luns = $vmhost | Get-ScsiLun | select CanonicalName, CapacityGB

#             My-Logger "Querying ESXi host disks to create VSAN Diskgroups ..."
#             foreach ($lun in $luns) {
#                 if(([int]($lun.CapacityGB)).toString() -eq "$vSphereSpec.Storage.Caching") {
#                     $vsanCacheDisk = $lun.CanonicalName
#                 }
#                 if(([int]($lun.CapacityGB)).toString() -eq "$vSphereSpec.Storage.Capacity") {
#                     $vsanCapacityDisk = $lun.CanonicalName
#                 }
#             }
#             My-Logger "Creating VSAN DiskGroup for $vmhost ..."
#             New-VsanDiskGroup -Server $vc -VMHost $vmhost -SsdCanonicalName $vsanCacheDisk -DataDiskCanonicalName $vsanCapacityDisk | Out-File -Append -LiteralPath $verboseLogFile
#         }
#     }

#     if($configureVDS -eq 1) {
#         $vds = New-VDSwitch -Server $vc  -Name $NewVCVDSName -Location (Get-Datacenter -Name $NewVCDatacenterName) -Mtu 1600

#         New-VDPortgroup -Server $vc -Name $NewVCDVPGName1 -Vds $vds | Out-File -Append -LiteralPath $verboseLogFile

#         foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
#             My-Logger "Adding $vmhost to $NewVCVDSName"
#             $vds | Add-VDSwitchVMHost -VMHost $vmhost | Out-Null

#             $vmhostNetworkAdapter = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic1
#             $vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
#         }

#         New-VDPortgroup -Server $vc -Name $NewVCDVPGName2 -Vds $vds | Out-File -Append -LiteralPath $verboseLogFile

#         foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
#             My-Logger "Adding $vmhost to $NewVCVDSName"
#             $vds | Add-VDSwitchVMHost -VMHost $vmhost | Out-Null

#             $vmhostNetworkAdapter = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic1
#             $vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
#         }
# 		New-VDPortgroup -Server $vc -Name $NewVCDVPGName3 -Vds $vds | Out-File -Append -LiteralPath $verboseLogFile

#         foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
#             My-Logger "Adding $vmhost to $NewVCVDSName"
#             $vds | Add-VDSwitchVMHost -VMHost $vmhost | Out-Null

#             $vmhostNetworkAdapter = Get-VMHost $vmhost | Get-VMHostNetworkAdapter -Physical -Name vmnic1
#             $vds | Add-VDSwitchPhysicalNetworkAdapter -VMHostNetworkAdapter $vmhostNetworkAdapter -Confirm:$false
#         }
#     }

#     if($clearVSANHealthCheckAlarm -eq 1) {
#         My-Logger "Clearing default VSAN Health Check Alarms, not applicable in Nested ESXi env ..."
#         $alarmMgr = Get-View AlarmManager -Server $vc
#         Get-Cluster -Server $vc | where {$_.ExtensionData.TriggeredAlarmState} | %{
#             $cluster = $_
#             $Cluster.ExtensionData.TriggeredAlarmState | %{
#                 $alarmMgr.AcknowledgeAlarm($_.Alarm,$cluster.ExtensionData.MoRef)
#             }
#         }
#         $alarmSpec = New-Object VMware.Vim.AlarmFilterSpec
#         $alarmMgr.ClearTriggeredAlarms($alarmSpec)
#     }

#     # Final configure and then exit maintanence mode in case patching was done earlier
#     foreach ($vmhost in Get-Cluster -Server $vc | Get-VMHost) {
#         # Disable Core Dump Warning
#         Get-AdvancedSetting -Entity $vmhost -Name UserVars.SuppressCoredumpWarning | Set-AdvancedSetting -Value 1 -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

#         # Enable vMotion traffic
#         $vmhost | Get-VMHostNetworkAdapter -VMKernel | Set-VMHostNetworkAdapter -VMotionEnabled $true -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile

#         if($vmhost.ConnectionState -eq "Maintenance") {
#             Set-VMHost -VMhost $vmhost -State Connected -RunAsync -Confirm:$false | Out-File -Append -LiteralPath $verboseLogFile
#         }
#     }

#     if($setupPacificStoragePolicy) {
#         My-Logger "Creating Project Pacific Storage Policies and attaching to vsanDatastore ..."

# My-Logger "Wating for vsan...., sleeping 80 seconds ..." 
# Start-Sleep 80
# My-Logger "Disconnect again from $viConnection" 
# Disconnect-VIServer -Server $viConnection -Confirm:$false

# My-Logger "Connecting to the new VCSA again ..."
# $vc = Connect-VIServer $VCSAIPAddress -User "administrator@$VCSASSODomainName" -Password $VCSASSOPassword -WarningAction SilentlyContinue
# My-Logger "$vc = vc variable.... ..." 
# My-Logger "$VCSAIPAddress = vc variable.... ..."


#         New-TagCategory -Server $vc -Name $StoragePolicyTagCategory -Cardinality single -EntityType Datastore | Out-File -Append -LiteralPath $verboseLogFile
#         New-Tag -Server $vc -Name $StoragePolicyTagName -Category $StoragePolicyTagCategory | Out-File -Append -LiteralPath $verboseLogFile
# $orf1 = Get-Datastore -Server $vc -Name "vsanDatastore"
# My-Logger "$orf1 ........"
# $orf2 = Get-Datastore -Server $vc -Name "vsanDatastore" | New-TagAssignment -Tag $StoragePolicyTagName
# My-Logger "$orf2 ...LaLa.....$StoragePolicyTagName"

#         Get-Datastore -Server $vc -Name "vsanDatastore" | New-TagAssignment -Tag $StoragePolicyTagName | Out-File -Append -LiteralPath $verboseLogFile
#         New-SpbmStoragePolicy -Name $StoragePolicyName -AnyOfRuleSets (New-SpbmRuleSet -Name "pacific-ruleset" -AllOfRules (New-SpbmRule -AnyOfTags (Get-Tag $StoragePolicyTagName))) | Out-File -Append -LiteralPath $verboseLogFile
#     }

#     My-Logger "Disconnecting from new VCSA ..."
#     Disconnect-VIServer $vc -Confirm:$false
}

Function setupPacific {
    Write-Host -ForegroundColor Red "setupPacific is not implemented"
#     My-Logger "Connecting to Management vCenter Server $vSphereSpec.vCenterServer for enabling Pacific ..."
#     Connect-VIServer $vSphereSpec.vCenterServer -User $vSphereSpec.UserName -Password $vSphereSpec.Password -WarningAction SilentlyContinue | Out-Null

#     My-Logger "Creating Principal Identity in vCenter Server ..."
#     $princpitalIdentityCmd = "echo `'$VCSASSOPassword`' | appliancesh dcli +username `'administrator@$VCSASSODomainName`' +password `'$VCSASSOPassword`' +show-unreleased com vmware vcenter nsxd principalidentity create --username `'$NSXAdminUsername`' --password `'$NSXAdminPassword`'"
#     Invoke-VMScript -ScriptText $princpitalIdentityCmd  -vm (Get-VM $VCSADisplayName) -GuestUser "root" -GuestPassword "$VCSARootPassword" | Out-File -Append -LiteralPath $verboseLogFile

#     My-Logger "Creating local $DevOpsUsername User in vCenter Server ..."
#     $devopsUserCreationCmd = "/usr/lib/vmware-vmafd/bin/dir-cli user create --account $DevOpsUsername --first-name `"Dev`" --last-name `"Ops`" --user-password `'$DevOpsPassword`' --login `'administrator@$VCSASSODomainName`' --password `'$VCSASSOPassword`'"
#     Invoke-VMScript -ScriptText $devopsUserCreationCmd -vm (Get-VM -Name $VCSADisplayName) -GuestUser "root" -GuestPassword "$VCSARootPassword" | Out-File -Append -LiteralPath $verboseLogFile
}

Function moveVMsIntovApp {
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
