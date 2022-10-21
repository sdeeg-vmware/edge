
. ./UtilityFunctions.ps1
. ./CreateClusterHelperFunctions.ps1
. ./Config.ps1

# Create or override any variables here
$verboseLogFile = "edge-manager.log"

Function Write-vCluster-Spec {
    My-Logger "Virtual Cluster Spec:"
    $NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Value | Foreach-Object {
        $VMName = $_.Key
        $VMIPAddress = $_.Value
        My-Logger "    vHost=$VMName Ip=$VMIPAddress"
    }
    $foundVMsCount = $foundVMs.Count
    My-Logger "Found vHosts ( $foundVMsCount ):"
    foreach ($vm in $foundVMs) {
        $VMName = $vm.Name
        $VMps = $vm.PowerState
        My-Logger "    vHost=$VMName State=$VMps"
    }
}

# If connect isn't working make sure to disable the TSL checks in PowerCLI
# Set-PowerCLIConfiguration -InvalidCertificateAction Ignore
My-Logger "Connecting to vCenter Server $VIServer ..." Blue $true
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue
if(!$viConnection) {
    My-Logger "Connect-VIServer came back empty.  Exiting." Red
    exit
}
My-Logger "connected" Green

My-Logger "Looking for objects in vSphere ... " Blue $true
$cluster = Get-Cluster -Server $viConnection -Name $VMCluster
if(!$cluster) {
    My-Logger "Get-Cluster -Name $VMCluster came back empty.  Exiting." Red
    exit
}

$foundVMs=@()
$NestedESXiHostnameToIPs.GetEnumerator() | Sort-Object -Property Key | Foreach-Object {
    $VMName = $_.Key
    $VMIPAddress = $_.Value

    $vm = Get-VM -Name $VMName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ( $vm ) { $foundVMs += $vm; }
}

My-Logger "done with pre-checks"

# Done with pre work.  Start REPL loop

$keepLooping=$true
while($keepLooping) {
    Clear-Host
    My-Logger "--- Edge Cluster Manager ---" Yellow
    Write-Host ""
    Write-vCluster-Spec

    $no = New-Object System.Management.Automation.Host.ChoiceDescription '&No', 'Exit'
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($no)
    if($foundVMs.Count -eq 0) {
        $options += New-Object System.Management.Automation.Host.ChoiceDescription '&Create cluster', 'Create the edge cluster'
    } else {
        $options += New-Object System.Management.Automation.Host.ChoiceDescription '&Delete cluster', 'Delete the edge cluster'
    }
    $result = $host.ui.PromptForChoice('Edge Manager', 'Do something?', $options, 0)

    if($result -eq 0) {
        My-Logger "You said No"
        $keepLooping=$false
    }
    if ($result -eq 1) {
        if($foundVMs.Count -gt 0) {
            Delete-Edge-Cluster
        } else {
            Create-Edge-Cluster
        }
    }
}

if( $viConnection ) {
    My-Logger "Disconnecting from $VIServer ..."
    Disconnect-VIServer -Server $viConnection -Confirm:$false
}

My-Logger "end of line"
