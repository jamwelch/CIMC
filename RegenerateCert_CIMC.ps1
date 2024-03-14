# This is an example of a script that could be used to regenerate a new self-signed certification for C-Series standalone rack servers.

#3.14.2024 -jamwelch@cisco.com
#Tested with Powershell 7.4.1

#Check version of powershell
Get-Host | Select-Object Version

# Use Install-Module -Name Cisco.IMC to install latest Cisco IMC package from Powershell Gallery
# www.powershellgallery.com/packages/Cisco.IMC/
Import-Module Cisco.IMC

# This CSV file should have 1 column with IP address of the cimc for each server and a heading of "IP"
# Ask user for the name of the device file located in the same folder as the script.
$csvfile = read-host -Prompt "Enter the name of the csv file with the list of devices to be checked."
$csv = Import-Csv $csvfile

# Create the credential
$cred = Get-Credential -Message "Cisco IMC"

# Function to run on each server that will regenerate a self-signed Cisco cert
function renew_cert {
    $cname = Get-ImcCertificateManagement -Imc $handle | Select-Object -ExpandProperty Imc
    #$country = "United States"
    $city = "San Jose"
    $state = "California"
    $org = "Cisco Self Sign"
    $ou = "Cisco"

    New-ImcCertificateSigningRequest -Imc $handle -CommonName $cname -CountryCode 'United States' -Locality $city -State $state -Organization $org -OrganizationalUnit $ou -SelfSigned Yes
    Write-host "A New Cert has been applied to $cname.  CIMC for this host will automatically restart with the new cert."
    Start-Sleep -Seconds 30
}

# Function to pause the script while CIMC is reloaded and continue once it is rebooted with the new cert.
function WaitForDeviceToComeOnline {
    param (
        [string]$DeviceIP,
        [int]$PingDelayInSeconds = 5,
        [int]$TimeoutInMinutes = 2
    )

    $timeout = (Get-Date).AddMinutes($TimeoutInMinutes)
    $isOnline = $false

    Write-Host "Waiting for device $DeviceIP to come online..."

    while ((Get-Date) -lt $timeout -and -not $isOnline) {
        try {
            Test-Connection -ComputerName $DeviceIP -Count 1 -ErrorAction Stop
            $isOnline = $true
            Write-Host "Device $DeviceIP is back online!"
        } catch {
            Write-Host "Device $DeviceIP is not online yet. Waiting for $PingDelayInSeconds seconds..."
            Start-Sleep -Seconds $PingDelayInSeconds
        }
    }

    if (-not $isOnline) {
        Write-Host "Device $DeviceIP did not come back online within the timeout period. Continuing script..."
    }

    return $isOnline
}

ForEach ($row in $csv) {
    $cimcip = $row.IP
    $handle = Connect-Imc -Name $cimcip -Credential $cred
    # Perform functions on each server
    renew_cert
    $deviceIsOnline = WaitForDeviceToComeOnline -DeviceIP $cimcip -PingDelayInSeconds 5 -TimeoutInMinutes 2
    if ($deviceIsOnline) {
        # The device is online, continue with other operations that require the device to be online
        Write-Host "Test connection for $cimcip was successful"
    } else {
        # The device is not online, handle accordingly or continue with other operations that don't require the device
        Write-host "Could not reach $cimcip within the timeout.  The script will continue."
    }
}
write-host "All servers in the csv should have a new cert."
