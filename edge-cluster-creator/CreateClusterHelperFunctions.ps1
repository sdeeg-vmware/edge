#############################################  Functions  #############################################

Function Get-SSLThumbprint256 {
    param(
    [Parameter(
        Position=0,
        Mandatory=$true,
        ValueFromPipeline=$true,
        ValueFromPipelineByPropertyName=$true)
    ]
    [Alias('FullName')]
    [String]$URL
    )

    $Code = @'
using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

namespace CertificateCapture
{
    public class Utility
    {
        public static Func<HttpRequestMessage,X509Certificate2,X509Chain,SslPolicyErrors,Boolean> ValidationCallback =
            (message, cert, chain, errors) => {
                var newCert = new X509Certificate2(cert);
                var newChain = new X509Chain();
                newChain.Build(newCert);
                CapturedCertificates.Add(new CapturedCertificate(){
                    Certificate =  newCert,
                    CertificateChain = newChain,
                    PolicyErrors = errors,
                    URI = message.RequestUri
                });
                return true;
            };
        public static List<CapturedCertificate> CapturedCertificates = new List<CapturedCertificate>();
    }

    public class CapturedCertificate
    {
        public X509Certificate2 Certificate { get; set; }
        public X509Chain CertificateChain { get; set; }
        public SslPolicyErrors PolicyErrors { get; set; }
        public Uri URI { get; set; }
    }
}
'@
    if ($PSEdition -ne 'Core'){
        Add-Type -AssemblyName System.Net.Http
        if (-not ("CertificateCapture" -as [type])) {
            Add-Type $Code -ReferencedAssemblies System.Net.Http
        }
    } else {
        if (-not ("CertificateCapture" -as [type])) {
            Add-Type $Code
        }
    }

    $Certs = [CertificateCapture.Utility]::CapturedCertificates

    $Handler = [System.Net.Http.HttpClientHandler]::new()
    $Handler.ServerCertificateCustomValidationCallback = [CertificateCapture.Utility]::ValidationCallback
    $Client = [System.Net.Http.HttpClient]::new($Handler)
    $Result = $Client.GetAsync($Url).Result

    $sha256 = [Security.Cryptography.SHA256]::Create()
    $certBytes = $Certs[-1].Certificate.GetRawCertData()
    $hash = $sha256.ComputeHash($certBytes)
    $thumbprint = [BitConverter]::ToString($hash).Replace('-',':')
    return $thumbprint
}

Function Set-VMKeystrokes {
    <#
        Please see http://www.virtuallyghetto.com/2017/09/automating-vm-keystrokes-using-the-vsphere-api-powercli.html for more details
    #>
        param(
            [Parameter(Mandatory=$true)][String]$VMName,
            [Parameter(Mandatory=$true)][String]$StringInput,
            [Parameter(Mandatory=$false)][Boolean]$ReturnCarriage,
            [Parameter(Mandatory=$false)][Boolean]$DebugOn
        )

        # Map subset of USB HID keyboard scancodes
        # https://gist.github.com/MightyPork/6da26e382a7ad91b5496ee55fdc73db2
        $hidCharacterMap = @{
            "a"="0x04";
            "b"="0x05";
            "c"="0x06";
            "d"="0x07";
            "e"="0x08";
            "f"="0x09";
            "g"="0x0a";
            "h"="0x0b";
            "i"="0x0c";
            "j"="0x0d";
            "k"="0x0e";
            "l"="0x0f";
            "m"="0x10";
            "n"="0x11";
            "o"="0x12";
            "p"="0x13";
            "q"="0x14";
            "r"="0x15";
            "s"="0x16";
            "t"="0x17";
            "u"="0x18";
            "v"="0x19";
            "w"="0x1a";
            "x"="0x1b";
            "y"="0x1c";
            "z"="0x1d";
            "1"="0x1e";
            "2"="0x1f";
            "3"="0x20";
            "4"="0x21";
            "5"="0x22";
            "6"="0x23";
            "7"="0x24";
            "8"="0x25";
            "9"="0x26";
            "0"="0x27";
            "!"="0x1e";
            "@"="0x1f";
            "#"="0x20";
            "$"="0x21";
            "%"="0x22";
            "^"="0x23";
            "&"="0x24";
            "*"="0x25";
            "("="0x26";
            ")"="0x27";
            "_"="0x2d";
            "+"="0x2e";
            "{"="0x2f";
            "}"="0x30";
            "|"="0x31";
            ":"="0x33";
            "`""="0x34";
            "~"="0x35";
            "<"="0x36";
            ">"="0x37";
            "?"="0x38";
            "-"="0x2d";
            "="="0x2e";
            "["="0x2f";
            "]"="0x30";
            "\"="0x31";
            "`;"="0x33";
            "`'"="0x34";
            ","="0x36";
            "."="0x37";
            "/"="0x38";
            " "="0x2c";
        }

        $vm = Get-View -ViewType VirtualMachine -Filter @{"Name"=$VMName}

        # Verify we have a VM or fail
        if(!$vm) {
            Write-host "Unable to find VM $VMName"
            return
        }

        $hidCodesEvents = @()
        foreach($character in $StringInput.ToCharArray()) {
            # Check to see if we've mapped the character to HID code
            if($hidCharacterMap.ContainsKey([string]$character)) {
                $hidCode = $hidCharacterMap[[string]$character]

                $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent

                # Add leftShift modifer for capital letters and/or special characters
                if( ($character -cmatch "[A-Z]") -or ($character -match "[!|@|#|$|%|^|&|(|)|_|+|{|}|||:|~|<|>|?]") ) {
                    $modifer = New-Object Vmware.Vim.UsbScanCodeSpecModifierType
                    $modifer.LeftShift = $true
                    $tmp.Modifiers = $modifer
                }

                # Convert to expected HID code format
                $hidCodeHexToInt = [Convert]::ToInt64($hidCode,"16")
                $hidCodeValue = ($hidCodeHexToInt -shl 16) -bor 0007

                $tmp.UsbHidCode = $hidCodeValue
                $hidCodesEvents+=$tmp
            } else {
                My-Logger Write-Host "The following character `"$character`" has not been mapped, you will need to manually process this character"
                break
            }
        }

        # Add return carriage to the end of the string input (useful for logins or executing commands)
        if($ReturnCarriage) {
            # Convert return carriage to HID code format
            $hidCodeHexToInt = [Convert]::ToInt64("0x28","16")
            $hidCodeValue = ($hidCodeHexToInt -shl 16) + 7

            $tmp = New-Object VMware.Vim.UsbScanCodeSpecKeyEvent
            $tmp.UsbHidCode = $hidCodeValue
            $hidCodesEvents+=$tmp
        }

        # Call API to send keystrokes to VM
        $spec = New-Object Vmware.Vim.UsbScanCodeSpec
        $spec.KeyEvents = $hidCodesEvents
        $results = $vm.PutUsbScanCodes($spec)
}

# Function My-Logger {
#     param(
#     [Parameter(Mandatory=$true)]
#     [String]$message
#     )

#     $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

#     Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
#     Write-Host -ForegroundColor Green " $message"
#     $logMessage = "[$timeStamp] $message"
#     $logMessage | Out-File -Append -LiteralPath $verboseLogFile
# }

Function URL-Check([string] $url) {
    $isWorking = $true

    try {
        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "HEAD"
        $request.UseDefaultCredentials = $true

        $response = $request.GetResponse()
        $httpStatus = $response.StatusCode

        $isWorking = ($httpStatus -eq "OK")
    }
    catch {
        $isWorking = $false
    }
    return $isWorking
}

Function Confirm-Deployment {
    Write-Host -ForegroundColor Magenta "`nPlease confirm the following configuration will be deployed:`n"

    Write-Host -ForegroundColor Yellow "---- Virtual ESXi cluster Image ---- "
    Write-Host -NoNewline -ForegroundColor Green "Nested ESXi Image Path: "
    Write-Host -ForegroundColor White $NestedESXiApplianceOVA

    Write-Host -ForegroundColor Yellow "`n---- vCenter Server Deployment Target Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "vCenter Server Address: "
    Write-Host -ForegroundColor White $VIServer
    Write-Host -NoNewline -ForegroundColor Green "VM Network: "
    Write-Host -ForegroundColor White $VMNetwork

    Write-Host -NoNewline -ForegroundColor Green "VM Storage: "
    Write-Host -ForegroundColor White $VMDatastore
    Write-Host -NoNewline -ForegroundColor Green "VM Cluster: "
    Write-Host -ForegroundColor White $VMCluster
    Write-Host -NoNewline -ForegroundColor Green "VM vApp: "
    Write-Host -ForegroundColor White $VAppName

    Write-Host -ForegroundColor Yellow "`n---- vESXi Configuration ----"
    Write-Host -NoNewline -ForegroundColor Green "# of Nested ESXi VMs: "
    Write-Host -ForegroundColor White $NestedESXiHostnameToIPs.count
    Write-Host -NoNewline -ForegroundColor Green "vCPU: "
    Write-Host -ForegroundColor White $NestedESXivCPU
    Write-Host -NoNewline -ForegroundColor Green "vMEM: "
    Write-Host -ForegroundColor White "$NestedESXivMEM GB"
    Write-Host -NoNewline -ForegroundColor Green "Caching VMDK: "
    Write-Host -ForegroundColor White "$NestedESXiCachingvDisk GB"
    Write-Host -NoNewline -ForegroundColor Green "Capacity VMDK: "
    Write-Host -ForegroundColor White "$NestedESXiCapacityvDisk GB"
    Write-Host -NoNewline -ForegroundColor Green "IP Address(s): "
    Write-Host -ForegroundColor White $NestedESXiHostnameToIPs.Values
    Write-Host -NoNewline -ForegroundColor Green "Netmask "
    Write-Host -ForegroundColor White $VMNetmask
    Write-Host -NoNewline -ForegroundColor Green "Gateway: "
    Write-Host -ForegroundColor White $VMGateway
    Write-Host -NoNewline -ForegroundColor Green "DNS: "
    Write-Host -ForegroundColor White $VMDNS
    Write-Host -NoNewline -ForegroundColor Green "NTP: "
    Write-Host -ForegroundColor White $VMNTP
    Write-Host -NoNewline -ForegroundColor Green "Syslog: "
    Write-Host -ForegroundColor White $VMSyslog
    Write-Host -NoNewline -ForegroundColor Green "Enable SSH: "
    Write-Host -ForegroundColor White $VMSSH
    Write-Host -NoNewline -ForegroundColor Green "Create VMFS Volume: "
    Write-Host -ForegroundColor White $VMVMFS

    $esxiTotalCPU = $NestedESXiHostnameToIPs.count * [int]$NestedESXivCPU
    $esxiTotalMemory = $NestedESXiHostnameToIPs.count * [int]$NestedESXivMEM
    $esxiTotalStorage = ($NestedESXiHostnameToIPs.count * [int]$NestedESXiCachingvDisk) + ($NestedESXiHostnameToIPs.count * [int]$NestedESXiCapacityvDisk)

    Write-Host -ForegroundColor Yellow "`n---- Resource Requirements ----"
    Write-Host -NoNewline -ForegroundColor Green "ESXi     VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $esxiTotalCPU
    Write-Host -NoNewline -ForegroundColor Green " ESXi     VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $esxiTotalMemory "GB "
    Write-Host -NoNewline -ForegroundColor Green "ESXi     VM Storage: "
    Write-Host -ForegroundColor White $esxiTotalStorage "GB"
    Write-Host -NoNewline -ForegroundColor Green "VCSA     VM CPU: "
    Write-Host -NoNewline -ForegroundColor White $vcsaTotalCPU
    Write-Host -NoNewline -ForegroundColor Green " VCSA     VM Memory: "
    Write-Host -NoNewline -ForegroundColor White $vcsaTotalMemory "GB "
    Write-Host -NoNewline -ForegroundColor Green "VCSA     VM Storage: "
    Write-Host -ForegroundColor White $vcsaTotalStorage "GB"

    Write-Host -ForegroundColor White "---------------------------------------------"
    Write-Host -NoNewline -ForegroundColor Green "Total CPU: "
    Write-Host -ForegroundColor White ($esxiTotalCPU + $vcsaTotalCPU + $nsxManagerTotalCPU + $nsxEdgeTotalCPU)
    Write-Host -NoNewline -ForegroundColor Green "Total Memory: "
    Write-Host -ForegroundColor White ($esxiTotalMemory + $vcsaTotalMemory + $nsxManagerTotalMemory + $nsxEdgeTotalMemory) "GB"
    Write-Host -NoNewline -ForegroundColor Green "Total Storage: "
    Write-Host -ForegroundColor White ($esxiTotalStorage + $vcsaTotalStorage + $nsxManagerTotalStorage + $nsxEdgeTotalStorage) "GB"

    Write-Host -ForegroundColor Magenta "`nWould you like to proceed with this deployment?`n"
    $answer = Read-Host -Prompt "Do you accept (Y or N)"
    if($answer -ne "Y" -or $answer -ne "y") {
        exit
    }
}

Function Do-Pre-Checks {
    My-Logger "Doing the pre checks..."

    if($PSVersionTable.PSEdition -ne "Core") {
        My-Logger "`tYPowerShell Core was not detected, please install that before continuing ... `nexiting"
        exit 0
    }
    My-Logger "PowerShell detected"

    #TODO: Can we change this to look for the VM Template in inventory
    if(!(Test-Path $NestedESXiApplianceOVA)) {
        My-Logger "`nUnable to find $NestedESXiApplianceOVA ...`nexiting"
        exit 0
    }
    My-Logger "Nested ESXi Appliance found"
}



Function Create-Edge-Cluster {
    My-Logger "Setting up to deploy nested cluster ..."

    $hosts = $cluster | Get-VMHost
    $requestedVirtualHosts = $NestedESXiHostnameToIPs.Count
    $availableHosts = $hosts.Count
    if($requestedVirtualHosts -gt $availableHosts) {
        My-Logger "There are not enough hosts ($requestedVirtualHosts) for all the requested virtual hosts ($availableHosts)"
        exit
    }
    $hosts = $hosts | Sort-Object -Property MemoryUsageGB | Select-Object -First $requestedVirtualHosts
    My-Logger "Verify hosts selected for deployment have enough memory to support $NestedESXivMEM Gb virtual hosts:"
    #There's something wrong here, but it's not impacting as I know I have the capacity.
    # $hosts | Foreach-Object {
    #     $hostId = $_.Id;
    #     $memAvailableGb = $_.MemoryTotalGB - $_.MemoryUsageGB
    #     if($memAvailableGb > $NestedESXivMEM) { My-Logger "VMHost Id=$hostId memAvailable=$memAvailableGb Gb OKay" } # Why isn't this true???
    #     else { My-Logger "VMHost Id=$hostId memAvailable=$memAvailableGb Gb Fail" }
    # }

    #Need to re-hash this to attach VM to specific datastores on the Hosts
    $datastore = Get-Datastore -Server $viConnection -Name $VMDatastore | Select-Object -First 1

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
        $networkMapLabel = ($ovfconfig.ToHashTable().keys | Where-Object {$_ -Match "NetworkMapping"}).replace("NetworkMapping.","").replace("-","_").replace(" ","_")
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
}

Function Delete-Edge-Cluster {
    My-Logger "Powering off any VMs that are powered on"
    foreach ($vm in $foundVMs) {
        $ps = $vm.PowerState
        $VMName = $vm.Name
        if($ps -eq "PoweredOn") { My-Logger "VM $VMName powered on.  Stopping ... " Blue $true; Stop-VM $vm -Confirm=$true; My-Logger "done"; }
        else  { My-Logger "VM $VMName powered off"}
    }

    My-Logger "Deleting vHost VMs ... " Blue $true
    Remove-VM $foundVMs -DeletePermanently
    My-Logger "done"
}

###################################  Function dump from main script

if($setupNewVC -eq 1) {
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
#                 if(([int]($lun.CapacityGB)).toString() -eq "$NestedESXiCachingvDisk") {
#                     $vsanCacheDisk = $lun.CanonicalName
#                 }
#                 if(([int]($lun.CapacityGB)).toString() -eq "$NestedESXiCapacityvDisk") {
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

if($setupPacific -eq 1) {
    Write-Host -ForegroundColor Red "setupPacific is not implemented"
#     My-Logger "Connecting to Management vCenter Server $VIServer for enabling Pacific ..."
#     Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue | Out-Null

#     My-Logger "Creating Principal Identity in vCenter Server ..."
#     $princpitalIdentityCmd = "echo `'$VCSASSOPassword`' | appliancesh dcli +username `'administrator@$VCSASSODomainName`' +password `'$VCSASSOPassword`' +show-unreleased com vmware vcenter nsxd principalidentity create --username `'$NSXAdminUsername`' --password `'$NSXAdminPassword`'"
#     Invoke-VMScript -ScriptText $princpitalIdentityCmd  -vm (Get-VM $VCSADisplayName) -GuestUser "root" -GuestPassword "$VCSARootPassword" | Out-File -Append -LiteralPath $verboseLogFile

#     My-Logger "Creating local $DevOpsUsername User in vCenter Server ..."
#     $devopsUserCreationCmd = "/usr/lib/vmware-vmafd/bin/dir-cli user create --account $DevOpsUsername --first-name `"Dev`" --last-name `"Ops`" --user-password `'$DevOpsPassword`' --login `'administrator@$VCSASSODomainName`' --password `'$VCSASSOPassword`'"
#     Invoke-VMScript -ScriptText $devopsUserCreationCmd -vm (Get-VM -Name $VCSADisplayName) -GuestUser "root" -GuestPassword "$VCSARootPassword" | Out-File -Append -LiteralPath $verboseLogFile

    My-Logger "Disconnecting from Management vCenter ..."
    # Disconnect-VIServer * -Confirm:$false | Out-Null
}
