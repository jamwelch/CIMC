# This is an example of ascript that could be used to create a report on cert expiration dats for C-Series standalone rack servers.
# A file named 'cimc_cert_report.csv' will be created in the same location as the script

#4.1.2024 -jamwelch@cisco.com
#Tested with Powershell 7.4.1

#Check version of powershell
Get-Host | Select-Object Version

# Use Install-Module -Name Cisco.IMC to install latest Cisco IMC package from Powershell Gallery
# www.powershellgallery.com/packages/Cisco.IMC/
Import-Module Cisco.IMC
Set-UcsPowerToolConfiguration -SupportMultipleDefaultUcs $true

# CSV file should have 1 column with IP address of the cimc for each server and a heading of "IP"
#Ask user for the name of the device file
$csvfile = read-host -Prompt "Enter the name of the csv file with the list of devices to be checked."
$csv = Import-Csv $csvfile
$report = New-Item -Path ".\cimc_cert_report.csv" -ItemType File

# Create the credential
$cred = Get-Credential -Message "Cisco IMC"

function export_certdates {
    $certdata = @{}
    $dates = Get-ImcCertificateManagement -Imc $handle | Get-ImcChild | Select-Object ValidTo, ValidFrom -First 1
    foreach( $property in $dates.psobject.properties.name ){
        $certdata[$property] = $dates.$property
    }
    $certdata.CIMC = $cimcip
    $certdata | ForEach-Object{ [pscustomobject]$_ } | Select-Object "CIMC", "ValidFrom", "ValidTo" | Export-CSV -Path $report -Append
}

ForEach ($row in $csv) {
    $cimcip = $row.IP
    $handle = $null

    try {
        $handle = Connect-Imc -Name $cimcip -Credential $cred -ErrorAction Stop
    } catch {
        Write-Host "Error connecting to CIMC at IP $cimcip"
    }

    if ($handle) {
        # Perform function on each server
        try {
            export_certdates
        } catch {
            Write-Host "Error retrieving certificate dates for $cimcip"
        }
    } else {
        Write-Host "Could not establish a connection to CIMC at IP $cimcip)."
    }
}

Write-Host "All servers in the csv have been examined."