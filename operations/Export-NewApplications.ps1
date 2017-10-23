<#
.SYNOPSIS
	Exports all active applications in the site provided by the SiteCode parameter
	to the network share provided in the exportDir parameter.
.NOTES
	You will need to configure credentials for the export directory.  Be sure to 
	configure a .gitignore file to exclude these credential files from version control.
#>
param (
	[parameter(Mandatory=$true)]
		#SiteCode for the SCCM Site:
		[string]$siteCode,
	[paramter(Mandatory=$true)]
		#Path to a file share where the applications will be exported:
		$exportDir
)
$ErrorActionPreference = 'Stop'

$LogFile = Join-Path -Path $PSScriptRoot -ChildPath 'logs\Export-NewApplications.log'

try {
	#Initialize Log file:
	if (Test-Path $LogFile) {Remove-Item $LogFile}
	
	Push-Location $PSScriptRoot
	Import-Module ..\SCCMCustomFunctions.psm1
	#Get creds for an account that can write to the export directory:
	# Generate credential files:
	# ConvertTo-SecureString -String 'password' -AsPlainText -Force | ConvertFrom-SecureString | out-file "creds-pw.hash" -Force
	# 'domain\user' > creds-user.txt
	$pass = Get-Content .\secrets\creds-pw.hash | ConvertTo-SecureString 
	$user = Get-Content .\secrets\creds-user.txt
	$cred = New-Object System.Management.Automation.PSCredential($user, $pass)
	#Map a drive to the export directory.  Drive mapping reduces the chances of a "path too long" error:
	try {
		# Use the "persist" option to make the drive mapping avaialble to regular Windows processes, 
		# not just the current PowerShell process:
		New-PsDrive -Name Z -PSProvider filesystem -Root $exportDir -Credential $cred -Persist
	} catch {
		Out-ConsoleAndLog -Type Error -Message "Failed to map drive to $exportDir" -LogFile $LogFile
	}
	Pop-Location

	#Load the SCCM PowerShell module, then switch to the SCCM "Site" PSDrive (required for SCCM cmdlets to run):
	Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" # Import the ConfigurationManager.psd1 module 
	Push-Location ($siteCode + ":") # Set the current location to be the site code.

	#Enumerate all applications that are not expired:
	$apps = Get-CMApplication | Where-Object {$_.IsExpired -eq $false}
	foreach ($app in $apps) {
		$path = Join-Path -Path 'Z:\apps\' -ChildPath ($app.LocalizedDisplayName + '.zip')
		#Test to see if there is a current archive:
		if (test-path $path) {
			#Test to see if the current archive is older than the "last changed" time on the application:
			$archive = get-item $path
			if ($app.DateLastModified -gt $archive.LastWriteTime) {
				$doIt = $true
			} else {
				$doIt = $false
			}
		} else {
			$doIt = $true
		}
		if ($doIt) {
			#Export the application, overwriting any existing archives:
			Out-ConsoleAndLog -Message ("Exporting " + $app.LocalizedDisplayName + ' to ' + $path) -LogFile $LogFile
			try {
				Export-CMApplication -InputObject $app -Path $path -Force
			} catch {
				$message = "Unable to export: " + $app.LocalizedDisplayName + "With error: `r`n" + $_.Exception.ToString()
				Out-ConsoleAndLog -Type Error -Message $message -LogFile $LogFile
				Exit 200
			}
		}
	}
	#Enumerate all Configuration Items that are not expired:
	#Loop highly redundant code-wise with the above loop.  This probably could be done more efficiently, 
	# but I don't have time for super-efficient right now.
	$cmitems = Get-CMConfigurationItem | Where-Object {$_.IsExpired -eq $false}
	foreach ($item in $cmitems) {
		#(Note: config items are saved as CAB files, not ZIP files as with applications)
		$path = Join-Path -Path 'Z:\configItems\' -ChildPath ($item.LocalizedDisplayName + '.cab')
		#Test to see if there is a current archive:
		if (test-path $path) {
			#Test to see if the current archive is older than the "last changed" time on the config item:
			$archive = get-item $path
			if ($item.DateLastModified -gt $archive.LastWriteTime) {
				$doIt = $true
			} else {
				$doIt = $false
			}
		} else {
			$doIt = $true
		}
		if ($doIt) {
			#Export the Configuration Item, overwriting any existing archives:
			Out-ConsoleAndLog -Message ("Exporting " + $item.LocalizedDisplayName + ' to ' + $path) -LogFile $LogFile
			try {
				Export-CMConfigurationItem -InputObject $item -Path $path -Force
			} catch {
				$message = "Unable to export: " + $item.LocalizedDisplayName + "With error: `r`n" + $_.Exception.ToString()
				Out-ConsoleAndLog -Type Error -Message $message -LogFile $LogFile
				Exit 210
			}
		}
	}
	#Enumerate all compliance baselines that are not expired:
	# Note: don't use the "IsExpired" attribute here, as Baselines do not support revisions, and so will not 
	#  have data in the IsExpired or IsLatest attributes.
	#Another largely code-redundant loop:
	$cmbases = Get-CMBaseline 
	foreach ($base in $cmbases) {
		#(Note: config baselines are saved as CAB files, not ZIP files as with applications)
		$path = Join-Path -Path 'Z:\baselines\' -ChildPath ($base.LocalizedDisplayName + '.cab')
		#Test to see if there is a current archive:
		if (test-path $path) {
			#Test to see if the current archive is older than the "last changed" time on the config baseline:
			$archive = get-item $path
			if ($base.DateLastModified -gt $archive.LastWriteTime) {
				$doIt = $true
			} else {
				$doIt = $false
			}
		} else {
			$doIt = $true
		}
		if ($doIt) {
			#Export the Configuration Baseline, overwriting any existing archives:
			Out-ConsoleAndLog -Message ("Exporting " + $base.LocalizedDisplayName + ' to ' + $path) -LogFile $LogFile
			try {
				Export-CMBaseline -InputObject $base -Path $path -Force
			} catch {
				$message = "Unable to export: " + $base.LocalizedDisplayName + "With error: `r`n" + $_.Exception.ToString()
				Out-ConsoleAndLog -Type Error -Message $message -LogFile $LogFile
				Exit 220
			}
		}
	}
	Pop-Location
	$rc = 0

} catch {
	#Generic error handler:
    'something borked.' >> $LogFile
    $_.InvocationInfo.PositionMessage.ToString() >> $LogFile
    $_.exception.tostring() >> $LogFile
    $rc = 100
} finally {
	#Cleanup the run environment, regardless of error condition:
	if (get-psdrive Z) {remove-psdrive Z -Force}
	if (get-psdrive YT1) {remove-psdrive YT1 -Force}
	remove-module ConfigurationManager
	remove-module SCCMCustomFunctions
	exit $rc
}