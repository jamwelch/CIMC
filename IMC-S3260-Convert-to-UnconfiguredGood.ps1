<#

.SYNOPSIS
	This script converts Top-loaded HDDs and Back-End JBODs from a C3260 or S-Series to Unconfigured Good.  
    It has been adapted from Olli Walsdorf's script here...
    - https://community.cisco.com/t5/cisco-developed-ucs-integrations/ucs-powertool-script-for-ucs-c3000-s-series-convert-all-disks-to/ta-p/3655737

.DESCRIPTION
	In large Red Hat Ceph Storage environments, it can be helpful to convert automatically all Back-End Boot-SSDs and Top-loaded HDDs from JBOD to Unconfigured Good before configuring any RAID. Instead of touching each server, you can simply run the script.

.EXAMPLE
	IMC-S3260-Convert-to-UnconfiguredGood.ps1
	This script can be run without any command line parameters.  User will be prompted for all parameters and options required

.NOTES
	Author: James Welch
	Email: jamwelch@cisco.com
	Company: Cisco Systems, Inc.
	Version: v0.1.
	Date: 11/18/2021
	Disclaimer: Code provided as-is.  No warranty implied or included.  This code is for example use only and not for production

.INPUTS
	***Provide any additional inputs here
	CIMC IP Address(s) or Hostname(s)
	CIMC Credentials Filename
	CIMC Username and Password

.OUTPUTS
	None
	
.LINK

#>

#Command Line Parameters
param(
	[string]$CIMC,				# IP Address(s) or Hostname(s).  If multiple entries, separate by commas
	[switch]$CREDENTIALS,		# CIMC Credentials (Username and Password).  Requires all servers to use the same credentials
	[string]$SAVEDCRED,			# Saved CIMC Credentials.  To create do: $credential = Get-Credential ; $credential | select username,@{Name="EncryptedPassword";Expression={ConvertFrom-SecureString $_.password}} | Export-CSV -NoTypeInformation .\myimccred.csv
	[switch]$SKIPERROR			# Skip any prompts for errors and continues with 'y'
)

#Clear the screen
clear-host

#Script kicking off
Write-Output "Script Running..."
Write-Output ""

#Tell the user what the script does
Write-Output "This script will convert all JBOD Backend-SSDs and Top-loaded HDDs from S-Series to Unconfigured Good"
Write-Output ""

if ($CREDENTIALS)
	{
		Write-Output "Enter CIMC Credentials"
		Write-Output ""
		$cred = Get-Credential -Message "Enter CIMC Credentials"
	}

#Change directory to the script root
cd $PSScriptRoot

#Check to see if credential files exists
if ($SAVEDCRED)
	{
		if ((Test-Path $SAVEDCRED) -eq $false)
			{
				Write-Output ""
				Write-Output "Your credentials file $SAVEDCRED does not exist in the script directory"
				Write-Output "	Exiting..."
				Disconnect-Imc
				exit
			}
	}

#Do not show errors in script
$ErrorActionPreference = "SilentlyContinue"
#$ErrorActionPreference = "Stop"
#$ErrorActionPreference = "Continue"
#$ErrorActionPreference = "Inquire"

#Verify PowerShell Version for script support
Write-Output "Checking for proper PowerShell version"
$PSVersion = $psversiontable.psversion
$PSMinimum = $PSVersion.Major
if ($PSMinimum -ge "5")
	{
		Write-Output "	Your version of PowerShell is valid for this script."
		Write-Output "		You are running version $PSVersion"
		Write-Output ""
	}
else
	{
		Write-Output "	This script requires PowerShell version 5.1 or above"
		Write-Output "		You are running version $PSVersion"
		Write-Output "	Please update your system and try again."
		Write-Output "	You can download PowerShell updates here:"
		Write-Output "	https://gallery.technet.microsoft.com/scriptcenter/2d191bcd-3308-4edd-9de2-88dff796b0bc"
		Write-Output "	If you are running a version of Windows before 7 or Server 2008R2 you need to update to be supported"
		Write-Output "			Exiting..."
		Disconnect-Imc
		exit
	}

#Load the Cisco IMC PowerTool
Write-Output "Checking Cisco PowerTool"
$PowerToolLoaded = $null
$Modules = Get-Module
$PowerToolLoaded = $modules.name
if ( -not ($Modules -like "Cisco.IMC"))
	{
		Write-Output "	Loading Module: Cisco IMC PowerTool Module"
		Import-Module Cisco.IMC
		$Modules = Get-Module
		if ( -not ($Modules -like "Cisco.IMC"))
			{
				Write-Output ""
				Write-Output "	Cisco IMC PowerTool Module did not load.  Please correct his issue and try again"
				Write-Output "		Exiting..."
				exit
			}
		else
			{
				$PTVersion = (Get-Module Cisco.IMC).Version
				Write-Output "		PowerTool version $PTVersion is now Loaded"
			}
	}
else
	{
		$PTVersion = (Get-Module Cisco.IMC).Version
		Write-Output "	PowerTool version $PTVersion is already Loaded"
	}

#Select CIMC(s) for login
if ($CIMC -ne "")
	{
		$myimc = $CIMC
	}
else
	{
		$myimc = Read-Host "Enter CIMC IP or a list of CIMC IP's separated by commas"
	}
[array]$myimc = ($myimc.split(",")).trim()
if ($myimc.count -eq 0)
	{
		Write-Output ""
		Write-Output "You did not enter anything"
		Write-Output "	Exiting..."
		Disconnect-Imc
		exit
	}

#Make sure we are disconnected from all CIMC's
Disconnect-Imc

#Test that CIMC(s) are IP Reachable via Ping
Write-Output ""
Write-Output "Testing PING access to CIMC"
foreach ($imc in $myimc)
	{
		$ping = new-object system.net.networkinformation.ping
		$results = $ping.send($imc)
		if ($results.Status -ne "Success")
			{
				Write-Output "	Can not access CIMC $imc by Ping"
				Write-Output "		It is possible that a firewall is blocking ICMP (PING) Access.  Would you like to try to log in anyway?"
				if ($SKIPERROR)
					{
						$Try = "y"
					}
				else
					{
						$Try = Read-Host "Would you like to try to log in anyway? (Y/N)"
					}				if ($Try -ieq "y")
					{
						Write-Output "				Will try to log in anyway!"
					}
				elseif ($Try -ieq "n")
					{
						Write-Output ""
						Write-Output "You have chosen to exit"
						Write-Output "	Exiting..."
						Disconnect-Imc
						exit
					}
				else
					{
						Write-Output ""
						Write-Output "You have provided invalid input"
						Write-Output "	Exiting..."
						Write-Output ""
						Disconnect-Imc
						exit
					}			
			}
		else
			{
				Write-Output "	Successful access to $imc by Ping"
			}
	}


#Log into the CIMC(s)
$multilogin = 
$multilogin = Set-UcsPowerToolConfiguration -SupportMultipleDefaultUcs $true
Write-Output ""
Write-Output "Logging into IMC"
#Verify PowerShell Version to pick prompt type
$PSVersion = $psversiontable.psversion
$PSMinimum = $PSVersion.Major
if (!$CREDENTIALS)
	{
		if (!$SAVEDCRED)
			{
				if ($PSMinimum -ge "3")
					{
						Write-Output "	Enter your CIMC credentials"
						$cred = Get-Credential -Message "CIMC(s) Login Credentials" -UserName "admin"
					}
				else
					{
						Write-Output "	Enter your CIMC credentials"
						$cred = Get-Credential
					}
			}
		else
			{
				$CredFile = import-csv $SAVEDCRED
				$Username = $credfile.UserName
				$Password = $credfile.EncryptedPassword
				$cred = New-Object System.Management.Automation.PsCredential $Username,(ConvertTo-SecureString $Password)			
			}

	}
foreach ($myimclist in $myimc)
	{
		Write-Output "		Logging into: $myimclist"
		$myCon = $null
		$myCon = Connect-Imc $myimclist -Credential $cred
		if (($mycon).Name -ne ($myimclist)) 
			{
				#Exit Script
				Write-Output "			Error Logging into this CIMC"
				if ($myimc.count -le 1)
					{
						$continue = "n"
					}
				else
					{
						$continue = Read-Host "Continue without this CIMC (Y/N)"
					}
				if ($continue -ieq "n")
					{
						Write-Output "				You have chosen to exit..."
						Write-Output ""
						Write-Output "Exiting Script..."
						Disconnect-Imc
						exit
					}
				else
					{
						Write-Output "				Continuing..."
					}
			}
		else
			{
				Write-Output "			Login Successful"
			}
		sleep 1
	}
$myCon = (Get-UcsPSSession | measure).Count
if ($myCon -eq 0)
	{
		Write-Output ""
		Write-Output "You are not logged into any CIMC's"
		Write-Output "	Exiting..."
		Disconnect-Imc
		exit
	}

Write-Output ""
#$Jbod = Get-ImcStorageLocalDisk -DiskState jbod | where {$_.VariantType -like "*BOOT*" -OR $_.DeviceType -like "*HDD*"}
$Jbod = Get-ImcStorageLocalDisk -DiskState jbod
echo $Jbod | select DeviceType,DiskState,Dn,Rn
Write-Output ""
		if (!$Jbod)
			{
				Write-Output "No JBODs found"
				Write-Output "Exiting..."
				exit
			}
		else
			{
				Write-Output "Converting Disks to Unconfigured Good"
				Write-Output ""
				$continueJbod = Read-Host "Continue (Y/N)"
				if ($continueJbod -ieq "n")
					{
						Write-Output "				You have chosen to exit..."
						Write-Output ""
						Write-Output "Exiting Script..."
						Disconnect-Imc
						exit
					}
					foreach ($Item in $Jbod)
						{
							$Item | Set-ImcStorageLocalDisk -AdminAction make-unconfigured-good -Force
						}
				Write-Output ""
				Write-Output "Done converting JBODs"
			}

#Disconnect from UCSM(s)
Disconnect-Imc

#Exit the Script
Write-Output ""
Write-Output "Script Complete "
exit
