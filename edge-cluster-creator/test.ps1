#!/snap/bin/powershell -Command

# vCenter Server used to deploy virtual edge cluster
$VIServer = "vcenter.planet10.lab"
$VIUsername = "administrator@planet10.lab"
$VIPassword = "K@ngaR00"

$NestedESXiVMToHostNameToIPs = @{
    "vesx1" = "192.168.11.11"
    "vesx2" = "192.168.11.12"
    "vesx3" = "192.168.11.13"
}

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

function Display-Object ($TheObject, $Parent = '$')
{
	$MemberType = 'Property' #assume this for the time being
	$ObjType = $TheObject.GetType().Name;
	if ($ObjType -in 'Hashtable', 'OrderedDictionary')
	{
		$TheObject = [pscustomObject]$TheObject;
		$ObjType = 'PSCustomObject';
	}
	if ($ObjType -eq 'PSCustomObject')
	{
		$MemberType = 'NoteProperty'
	}
	
	$members = gm -MemberType $MemberType -InputObject $TheObject
	$members | Foreach {
		Try { $child = $TheObject.($_.Name); }
		Catch { $Child = $null } # avoid crashing on write-only objects
		if ($child -eq $null -or #is the current child a value or a null?
			$child.GetType().BaseType.Name -eq 'ValueType' -or
			$child.GetType().Name -in @('String', 'Object[]'))
		{#output the value of this as a ps object
			[pscustomobject]@{ 'Path' = "$Parent.$($_.Name)"; 'Value' = $Child; }
		}
		else #not a value but an object of some sort
		{
			Display-Object -TheObject $child -Parent "$Parent.$($_.Name)"
		}
	}
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

        $vESXiTemplate = Get-Template "vesxi-0"
        if ($vESXiTemplate) {
            My-Logger "Got the template $vESXiTemplate"
            My-Logger ($vESXiTemplate | Format-List -Force | Out-String)
            Display-Object $vESXiTemplate
            # New-VM -Name 'vesxi-1' -Template $vESXiTemplate -VMHost 'esx4.planet10.lab'
        }

        # #https://developer.vmware.com/docs/15315/powercli-user-s-guide/GUID-042718D9-0536-4AAB-9397-2A2103BEE8A3.html?h=vmgroup
        # #Get the virtual machines for the VM DRS cluster group.
        # $vms = Get-VM "vesxi-0"
        # #Get the hosts for the VMHost DRS cluster group.
        # $vmHosts = Get-VMHost "esx2.planet10.lab"
        # #Get the cluster where you want to create the rule.
        # $cluster = Get-Cluster "P10-Cluster"
        # #Create a VM DRS cluster group.
        # $vmGroup = New-DrsClusterGroup -Name "vesx0-VmsDrsClusterGroup" -VM $vms -Cluster $cluster
        # #Create a VMHost DRS cluster group.
        # $vmHostGroup = New-DrsClusterGroup -Name "esx2-HostsDrsClusterGroup" -VMHost $vmHosts -Cluster $cluster
        # #Create the VM-VMHost DRS rule by using the newly created VM DRS cluster group and VMHost DRS cluster group.
        # New-DrsVMHostRule -Name "vesxi0-esx2" -Cluster $cluster -VMGroup $vmGroup -VMHostGroup $vmHostGroup -Type "MustRunOn"
    }
    else {
        My-Logger "Failed to get the connection ... Exiting."
    }
}
catch {
    My-Logger "Exception caught: $_.Exception.InnerException"
}

# if($viConnection) {
#     My-Logger "Disconnecting from $VIServer ..."
#     Disconnect-VIServer -Server $viConnection -Confirm:$false
# }
