#!/snap/bin/powershell -Command

# vCenter Server used to deploy virtual edge cluster
$VIServer = "192.168.4.50"
$VIUsername = "administrator@planet10.lab"
$VIPassword = "K@ngaR00"

Function My-Logger {
    param(
    [Parameter(Mandatory=$true)]
    [String]$message
    )

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White "[$timestamp]"
    Write-Host -ForegroundColor Green " $message"
    # $logMessage = "[$timeStamp] $message"
    # $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}

###################################################################################################
#####################################  Main  ######################################################
###################################################################################################

Write-Host -ForegroundColor Yellow "---- ${VIServer} ----"

My-Logger "Connecting to Management vCenter Server $VIServer ..."
try {
    $viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword
    if($viConnection) {
        My-Logger "Got the connection and doing some work."

        #https://developer.vmware.com/docs/15315/powercli-user-s-guide/GUID-042718D9-0536-4AAB-9397-2A2103BEE8A3.html?h=vmgroup
        #Get the virtual machines for the VM DRS cluster group.
        $vms = Get-VM "vesxi-0"
        #Get the hosts for the VMHost DRS cluster group.
        $vmHosts = Get-VMHost "esx2.planet10.lab"
        #Get the cluster where you want to create the rule.
        $cluster = Get-Cluster "P10-Cluster"
        #Create a VM DRS cluster group.
        $vmGroup = New-DrsClusterGroup -Name "vesx0-VmsDrsClusterGroup" -VM $vms -Cluster $cluster
        #Create a VMHost DRS cluster group.
        $vmHostGroup = New-DrsClusterGroup -Name "esx2-HostsDrsClusterGroup" -VMHost $vmHosts -Cluster $cluster
        #Create the VM-VMHost DRS rule by using the newly created VM DRS cluster group and VMHost DRS cluster group.
        New-DrsVMHostRule -Name "vesxi0-esx2" -Cluster $cluster -VMGroup $vmGroup -VMHostGroup $vmHostGroup -Type "MustRunOn"
    }
    else {
        My-Logger "Failed to get the connection ... Exiting."
    }
}
catch {
    My-Logger "Exception caught"
    My-Logger $_.Exception.InnerException
}

if($viConnection) {
    My-Logger "Disconnecting from $VIServer ..."
    Disconnect-VIServer -Server $viConnection -Confirm:$false
}
