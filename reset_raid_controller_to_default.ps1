#This script is to be used to reset C-Series standalone rack servers raid disk controller to factory defaults.

#11.8.2023 -jamwelch@cisco.com
#Tested with Powershell 7.3.8

#Check version of powershell
Get-Host | Select-Object Version

# Use Install-Module -Name Cisco.IMC to install latest Cisco IMC package from Powershell Gallery
# www.powershellgallery.com/packages/Cisco.IMC/
Import-Module Cisco.IMC
Set-UcsPowerToolConfiguration -SupportMultipleDefaultUcs $true

# CSV file should have 3 columns with headings of "ip", "hostname", & "serial" in that specific order.
$csv = Import-Csv C:\Path\to\file\cimc.csv

# Prompt for CIMC IP and credentials 
$cred = Get-Credential

# Function to run on each server that will reset the disks to factory default
function reset-disks {
    Connect-imc $cimcip -Credential $cred
    $MRAID = Get-ImcStorageController -Id MRAID
    $MRAID | Set-ImcStorageController -AdminAction "clear-boot-drive" -Force
    $MRAID | Set-ImcStorageController -AdminAction "clear-all-config" -Force
    $MRAID | Set-ImcStorageController -AdminAction "reset-default-config" -Force
}


# Loop through the rows of the csv file and perform the function
$i=0
ForEach ($row in $csv) {
$i=$i+1
$cimcip = $row.ip
$cimcname = $row.hostname
$cimcsn = $row.serial
reset-disks
Write-host "Disks reset to factory default for server:" $cimcip $cimcname $cimcsn
Disconnect-Imc
}

write-host "All servers in the csv have completed."
