#Check version of powershell
Get-Host | Select-Object Version
#Check version of Modules




#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#CIMC Input

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#CIMC Connect
# Run Install-Module -Name Cisco.IMC from Powershell prompt to install latest version
Import-Module Cisco.IMC

#Login to CIMC, saves login to  file in the location specified
$DirPathIMC = read-host -Prompt "Enter the path (i.e. c:\path) where you want the CIMC credential file created"
New-Item -ItemType Directory cimc-sessions -Force

#Modify this to read CSV file
$CIMC_IP1 = read-host -Prompt "Enter the IP address of CIMC"
Connect-Imc $UCSM_IP1
$CredPathIMC = $DirPathIMC + '\cimc-sessions\imccreds.xml'
Export-UcsPSSession -Path $CredPathIMC
Disconnect-Imc
$handleIMC = Connect-Imc -Path $CredPathIMC


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#CIMC Test


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#CIMC Modify


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
#CIMC Output

#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++#
