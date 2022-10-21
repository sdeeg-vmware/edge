# Function My-Logger {
#     param(
#     [Parameter(Mandatory=$true)]
#     [String]$message
#     )

Function My-Logger([String]$message, [System.ConsoleColor]$FColor="White", [bool]$noNewLine=$false) {

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    # Write to the console
    if($noNewLine) { Write-Host -NoNewline -ForegroundColor $FColor $message }
    else           { Write-Host -ForegroundColor $FColor $message }

    # Write to the log file
    $logMessage = "[$timeStamp] $message"
    $logMessage | Out-File -Append -LiteralPath $verboseLogFile
}
