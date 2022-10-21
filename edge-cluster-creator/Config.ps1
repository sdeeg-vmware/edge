# vCenter Server used to deploy virtual edge cluster
$VIServer = "vcenter.planet10.lab"
$VIUsername = "administrator@planet10.lab"
$VIPassword = "K@ngaR00"

# Nested ESXi VMs to deploy
$NestedESXiHostnameToIPs = @{
    "vesx1" = "192.168.4.11"
    # "vesx2" = "192.168.4.12"
    # "vesx3" = "192.168.4.13"
}

$NestedESXiApplianceOVA = "/home/sdeeg/Downloads/Nested_ESXi7.0u3g_Appliance_Template_v1.ova"

# Nested ESXi VM Resources
$NestedESXivCPU = "6"
$NestedESXivMEM = "16" #GB
$NestedESXiCachingvDisk = "8" #GB
$NestedESXiCapacityvDisk = "110" #GB

# General Deployment Configuration
$VMDatacenter = "MiniRack"
$VMCluster = "P10-Cluster"
$VMNetwork = "10Ge-Network"
$VMDatastore = "Yoyodyne"
$VMNetmask = "255.255.255.0"
$VMGateway = "192.168.6.1"
$VMDNS = "192.168.4.20"
$VMNTP = "pool.ntp.org"
$VMPassword = "Tanzu1!"
$VMDomain = "planet10.lab"
#$VMSyslog = "192.168.3.50" #???
$VMFolder = "edge"
# Applicable to Nested ESXi only
$VMSSH = "true"
$VMVMFS = "false"


# Name of new vSphere Datacenter/Cluster when VCSA is deployed
$NewVCDatacenterName = "Edge-Site"
$NewVCVSANClusterName = "Edge-Cluster"
$NewVCVDSName = "Edge-VDS"
$NewVCDVPGName1 = "Management-DPG"
$NewVCDVPGName2 = "Workload-DPG"
$NewVCDVPGName3 = "Frontend-DPG"

# Pacific Configuration ToDo: How much of this do we still need?
$StoragePolicyName = "pacific-gold-storage-policy3c"
$StoragePolicyTagCategory = "pacific-demo-tag-category3c"
$StoragePolicyTagName = "pacific-demo-storage3c"
$DevOpsUsername = "devops"
$DevOpsPassword = "VMware1!"

# Transport Node Profile ToDo: what does this do?
$TransportNodeProfileName = "Pacific-Host-Transport-Node-Profile"

# TEP IP Pool
# ToDo: Probaby a NSX thing, but keep to understand.
$TunnelEndpointName = "TEP-IP-Pool"
$TunnelEndpointDescription = "Tunnel Endpoint for Transport Nodes"
$TunnelEndpointIPRangeStart = "172.30.10.10"
$TunnelEndpointIPRangeEnd = "172.30.10.20"
$TunnelEndpointCIDR = "172.30.10.0/24"
$TunnelEndpointGateway = "172.30.10.1"

# Uplink Profiles TODO: figure this out fo rmy uplinks
$ESXiUplinkProfileName = "ESXi-Host-Uplink-Profile"
$ESXiUplinkProfilePolicy = "FAILOVER_ORDER"
$ESXiUplinkName = "uplink1"

# Edge Profile TODO: These settings need to be changed to match my environment
$EdgeUplinkProfileName = "Edge-Uplink-Profile"
$EdgeUplinkProfilePolicy = "FAILOVER_ORDER"
$EdgeOverlayUplinkName = "uplink1"
$EdgeOverlayUplinkProfileActivepNIC = "fp-eth1"
$EdgeUplinkName = "tep-uplink"
$EdgeUplinkProfileActivepNIC = "fp-eth2"
$EdgeUplinkProfileTransportVLAN = "0"
$EdgeUplinkProfileMTU = "1600"

# Advanced Configurations
# Set to 1 only if you have DNS (forward/reverse) for ESXi hostnames
$addHostByDnsName = 1

#### DO NOT EDIT BEYOND HERE ####

$debug = $true
$verboseLogFile = "edge-cluster-creation.log"
$random_string = -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
$VAppName = "edge-cluster-$random_string"

$preCheck = 1
$confirmDeployment = 0
$preWorkCheks = 0
$deployNestedESXiVMs = 1 ####
$setupVC = 0
$addESXiHostsToVC = 0
$configureVSANDiskGroup = 0
$configureVDS = 0
$clearVSANHealthCheckAlarm = 0
$setupPacificStoragePolicy = 0
$deployNSXManager = 0
$deployNSXEdge = 0
$postDeployNSXConfig = 0
$setupPacific = 0
$moveVMsIntovApp = 0
$deployTKGI = 0
$deployAVI = 0 #####

$esxiTotalCPU = 0
$esxiTotalMemory = 0
$esxiTotalStorage = 0

$StartTime = Get-Date
