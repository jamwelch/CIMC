#This script is to be used to reset C-Series standalone rack servers raid disk controller to factory defaults.

#10.30.2023 -jamwelch@cisco.com
#Tested with Powershell 7.3.6

#Check version of powershell
Get-Host | Select-Object Version

# Run Install-Module -Name Cisco.UCSManager from Powershell prompt to install latest version
# Use Install-Module -Name Cisco.IMC to install latest Cisco IMC package from Powershell Gallery
# www.powershellgallery.com/packages/Cisco.IMC/
Import-Module Cisco.IMC
Set-UcsPowerToolConfiguration -SupportMultipleDefaultUcs $true
# Login to the first server in order to save your credentials
# Use the same Credentials for each server in this script.  If you need separate creds for some servers then put them into a separate CSV file and run the script again for those servers.
# There should be a 1 to 1 relationship between the CSV file and the credentials required to authenticate
New-Item -ItemType Directory imc-sessions -Force
$CIMC_IP1 = read-host -Prompt "Enter the IP address of the first server"
$CredPathCIMC = $DirPathCIMC + '\imc-sessions\cimccreds.xml'
$KeyPathCIMC = $DirPathCIMC + '\imc-sessions\cimccreds.key'
Connect-Imc $CIMC_IP1
Export-ImcPSSession -LiteralPath $CredPathCIMC
Disconnect-Imc
$credkey = read-host -Prompt "Enter key value used to store it securely." -MaskInput
ConvertTo-SecureString -String $credkey -AsPlainText -Force | ConvertFrom-SecureString | Out-File $KeyPathCIMC
$key = ConvertTo-SecureString (Get-Content $KeyPathCIMC)


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
# Get List of Servers to modify from a CSV file. File should contain the CIMC Management IP addresses for the server's to be modified.
# The CSV file should contain 1 row with a header titled "IPAddress"
# Ask user if they have prepared the CSV file for import.  If Y, the script will continue.  If N, the script will end.
$title    = 'CSV Ready?'
$question = 'Have you prepared the CSV File with server data and saved it as a "servers.csv" in the folder where the script files are stored? If not, then answer No to exit and do that first.'
$choices  = '&Yes', '&No'
# Create a folder to hold credential keys and files in the current location
New-Item -ItemType Directory imc-sessions -Force
$decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)
if ($decision -eq 0) {
    #Login to UCS, saves login to  file in the location specified
    #$DirPathIMC = "F:\PowerShell\UCS\IMC" #read-host -Prompt "Enter the path (i.e. c:\path) where the script files are stored."
    #change the name of the input file if needed.
    #$csvinput = $DirPathIMC + "\servers.csv"
    #$csvdata = import-csv $csvinput
    $csvdata = import-csv F:\PowerShell\UCS\IMC\servers.csv
} else {
    exit
}
Start-Sleep -Seconds 1.5
# Verify the CSV Data
$csvrecords = $csvdata.Length
if ($csvrecords -gt 1){
    write-output $csvdata
} else {
    Write-Host "!!!!!!!!!!!!!!!!!!!"
    Write-Host "Cannot read data"
    Write-Host "!!!!!!!!!!!!!!!!!!!"
    exit
}

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
# Create a separate handle used for connecting to each server
$HandleMap = @{}
foreach ($Server in $csvdata){
    $IP = $Server.IPAddress
    Connect-Imc $IP -Key $key -LiteralPath $CredPathCIMC
    

}
Write-Host $HandleMap
