# vCenter Server used to deploy virtual edge cluster
$VIServer = "192.168.10.50"
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


Write-Host -ForegroundColor Yellow "---- ${VIServer} ----"

My-Logger "Connecting to Management vCenter Server $VIServer ..."
$viConnection = Connect-VIServer $VIServer -User $VIUsername -Password $VIPassword -WarningAction SilentlyContinue

My-Logger "Disconnecting from $VIServer ..."
Disconnect-VIServer -Server $viConnection -Confirm:$false
