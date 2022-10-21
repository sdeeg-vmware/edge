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

My-Logger "Getting the cluster" Blue

