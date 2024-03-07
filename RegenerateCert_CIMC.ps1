# This is an example of ascript that could be used to regenerate a new self-signed certification for C-Series standalone rack servers.

#3.5.2024 -jamwelch@cisco.com
#Tested with Powershell 7.4.1

#Check version of powershell
Get-Host | Select-Object Version

# Use Install-Module -Name Cisco.IMC to install latest Cisco IMC package from Powershell Gallery
# www.powershellgallery.com/packages/Cisco.IMC/
Import-Module Cisco.IMC
Set-UcsPowerToolConfiguration -SupportMultipleDefaultUcs $true

# CSV file should have 1 column with IP address of the cimc for each server and a heading of "IP"
#Ask user for the name of the device file
#$csv = read-host -Prompt "Enter the name of the csv file with the list of devices to be checked."
$csv = Import-Csv F:\PowerShell\CIMC\serverlist.csv

# Create the credential
$cred = Get-Credential -Message "Cisco IMC"

# Function to run on each server that will regenerate a self-signed Cisco cert
function renew_cert {
    # Prompt for CIMC IP and credentials
    $cname = Get-ImcCertificateManagement -Imc $handle | Select-Object -ExpandProperty Imc
    #$country = "United States"
    $city = "San Jose"
    $state = "California"
    $org = "Cisco Self Sign"
    $ou = "Cisco"

    # Pause the script and wait for the user to press Enter
    Read-Host -Prompt "Do you wish to renew a self signed cert for $cname? Press Enter to continue"
    # The script will continue after the user presses Enter

    New-ImcCertificateSigningRequest -Imc $handle -CommonName $cname -CountryCode 'United States' -Locality $city -State $state -Organization $org -OrganizationalUnit $ou -SelfSigned Yes
    Write-host "A New Cert has been applied to $cname.  CIMC for this host will automatically restart with the new cert."
    Start-Sleep -Seconds 30
}

# Function to pause the script while CIMC is reloaded and continue once it is rebooted with the new cert.
function WaitForDeviceToComeOnline {
    param (
        [string]$cimcip,
        [int]$PingDelayInSeconds = 20,
        [int]$TimeoutInMinutes = 5
    )

    $timeout = (Get-Date).AddMinutes($TimeoutInMinutes)
    $isOnline = $false

    Write-Host "Waiting for device $cimcip to come online..."

    while ((Get-Date) -lt $timeout -and -not $isOnline) {
        try {
            Test-Connection -ComputerName $cimcip -Count 1 -ErrorAction Stop
            $isOnline = $true
            Write-Host "Device $cimcip is back online!"
        } catch {
            Write-Host "Device $cimcip is not online yet. Waiting for $PingDelayInSeconds seconds..."
            Start-Sleep -Seconds $PingDelayInSeconds
        }
    }

    if (-not $isOnline) {
        Write-Host "Device $cimcip did not come back online within the timeout period. Continuing script..."
    }

    return $isOnline
}


# Function to read the current cert info in order to validate that the cert has been successfully renewed.
function read_cert {
    # Prompt for CIMC IP and credentials 
    $result = Get-ImcCertificateManagement -Imc $handle
    write-host $result
}

ForEach ($row in $csv) {
    $cimcip = $row.IP
    $handle = Connect-Imc -Name $cimcip -Credential $cred
    # Perform functions on each server
    renew_cert
    $deviceIsOnline = WaitForDeviceToComeOnline -DeviceIP $cimcip -PingDelayInSeconds 20 -TimeoutInMinutes 5
    if ($deviceIsOnline) {
        # The device is online, continue with other operations that require the device to be online
        read_cert
    } else {
        # The device is not online, handle accordingly or continue with other operations that don't require the device
        Write-host "Could not reach $cimcip within the timeout.  The script will continue to the next device."
    }
}


write-host "All servers in the csv should have a new cert."







