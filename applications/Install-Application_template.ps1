<#
.SYNOPSIS
    Brief description of the purpose of this script here.
.DESCRIPTION
    Describe the purpose of the script and actions that it takes in detail.  Document any 
    expected return codes of your script here.
#>

#region initialize environment
Set-PSDebug -Strict
$ErrorActionPreference = 'Stop'

# Load the SCCMCustomFunctions.psm1 script module for logging and MSI support: 
# (Copy the latest version from [RepositoryRoot]\SCCMCustomFunctions.psm1)
Import-Module .\SCCMCustomFunctions.psm1

# Set Script Variables here

# Initialize logging.  
# Set $logFile as a global variable so that it can be referenced consistently in any calling functions:
# (Rename this file to match the name of the calling script.)
$Global:LogFile = '.\Script-Template.log'
if (Test-Path $LogFile) { Remove-Item $LogFile | Out-Null }

# Array of MSIExec return codes that will allow script continuation:
$msiSuccess = @(0,1614,3010)
<#
Mini return code reference:
(Full reference here:
https://msdn.microsoft.com/en-us/library/windows/desktop/aa376931(v=vs.85).aspx)
    0       = Success
    1707    = Success (Note: This is not an MSIEXEC return code, but it is value that considered a success by SCCM.)
    1618    = Another MSIEXEC process is running.  Signals "fast retry" to the SCCM Agent.
    1614    = Product uninstalled.
    1641    = MSIEXEC was successful, and a reboot has been initiated.
    3010    = MSIEXEC was successful, but a reboot is required to complete installation.
    100-199 = Reserve for script pre-installation errors.
    200-299 = Reserve for scripted installer errors.
    300-399 = Reserve for script post-installation errors.
#>
#endregion

#region function library
# Add any functions called in your script here, ahead of the main logic body.
#endregion

#region pre-install
# Perform configuration item or environment prep actions here:
try {
    #Pre-installation logic here.
} catch {
    exit 100
}
# Uninstall actions here:
$uninstallRC = Invoke-MSIUninstall -Pattern 'productName' | Out-Null
switch ($uninstallRC) {
    {$_ -eq $null} {
        Out-ConsoleAndLog -Message "A prior install was not found on the system." -Type Verbose
        break
    }
    {$msiSuccess -notcontains $_} {
        Out-ConsoleAndLog -Message "Attempt to uninstall prior software failed with RC: $uninstallRC" -Type Error
        exit $uninstallRC
    }
}
#endregion

#region install
# Primary installation operations here:
try {
    # Non-MSI-based Installation logic here
} catch {
    exit 200
}
# Or for MSI installers:
#Find the MSI installer package in the current directory:
[string]$msiFile = (Get-ChildItem -Filter *.msi).FullName
Out-ConsoleAndLog -Message "Attempting to install from file: $msiFile" -Type Host 
$msiRC = Invoke-MSIInstall -MSIFile $msiFile -MSIArgs @(<#Additional Arguments for MSIEXEC#>)

# Sample error handling:
if ($successCodes -notcontains $msiRC) {
    Out-ConsoleAndLog -Message "Installer failed with RC: $msiRC" -Type Error
    exit $msiRC
} else {
    Out-ConsoleAndLog -Message "Installer succeeded with RC: $msiRC" -Type Host
    #If no post-installation logic is needed, "exit" here.
}

# Or if installing an additional MSP, sample .MSP patch installation logic:
if ($successCodes -contains $msiRC) {
    [string]$mspFile = (Get-ChildItem -Filter *.msp).FullName
    Out-ConsoleAndLog -Message "Software installed successfully.  Now attempting to install patch package: $mspFile" -Type Host
    $mspRC = Invoke-MSIPatch -MSPFile $mspFile
    Out-ConsoleAndLog -Message "Patch installation return code: $mspRC" -Type Host
    exit $mspRC
} else {
    Out-ConsoleAndLog -Message "Software installation failed with return code: $msiRC" -Type Error
    #return the MSIEXEC exit code to the SCCM agent:
    exit $msiRC
}
#endregion

#region post-install
try {
    #Post-installation logic here
} catch {
    exit 300
}
#endregion

exit 0