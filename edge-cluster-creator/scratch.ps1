#!/snap/bin/powershell -Command
. ./UtilityFunctions.ps1

$NestedESXiHostnameToIPs = @{
    "vesx1" = "192.168.11.11"
    "vesx2" = "192.168.11.12"
    "vesx3" = "192.168.11.13"
}

# $hostEnum = $NestedESXiHostnameToIPs.GetEnumerator()
# $hostEnum.MoveNext()
# $hostEnum.Current | Write-Output

$vSphereSpec = @{
    "vCenterServer" = "vcenter.planet10.lab"
    "Username" = "administrator@planet10.lab"
    "Password" = "K@ngaR00"
    "Datacenter" = "MiniRack"
    "Cluster" = "P10-Cluster"
    "Folder" = "edge"
}

Write-Host "The vCenter is at: $($vSphereSpec.vCenterServer)"
