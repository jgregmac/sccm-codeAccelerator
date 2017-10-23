<#
.SYNOPSIS
    Sets the meximum execution time to 30 minutes for all Windows Cumulative Updates and Security 
    Quality Rollups.
.DESCRIPTION
    Modern monthly security updates from Microsoft can be quite large, and often will take longer 
    than the default maximum execution time of 10 minutes to complete installation.  If the default
    value is not changed, the installation of cumulative updates will fail on large numbers of 
    Windows Server 2016 hosts, and probably on many Server 2012 / 2008 systems as well.

    This script will find any such updates that have a maximum execution time set to less that 30
    minutes, and increase the execution time to 30 minutes under these conditions.

    Requires the ConfigurationManager.psd1 PowerShell module, which is installed with the System
    Center Configuration Manager Management Console software.
#>
param (
    [parameter(Mandatory=$True)]
        [string]$SiteCode,
    [parameter(Mandatory=$false)]
        [ValidateRange(10,120)]
        [int32]$maxMinutes = 30,
    [parameter(Mandatory=$false)]
        [string[]]$names = @(
        "*cumulative update for windows server*",
        "*security monthly quality rollup*"
    )
)
Set-PSDebug -Strict
$ErrorActionPreference = 'Stop'

#Set the desired maximum execution time for select software updates:
[Int32]$maxSeconds = $maxMinutes * 60

#Set the log file location:
$log = $PWD.Path + '\Set-CUMaxExecutionTime.log'
if (test-path $log) {Remove-Item $log -Force -Confirm:$false}

$SiteDrive = $SiteCode + ':\'

Function Out-ConsoleAndLog {
    <#
    .SYNOPSIS
        Writes the specific message to the specified log file, and to the output stream specified by -Type.
    .DESCRIPTION
        Logs to the file specified in in the -LogFile parameter, and to the output stream selected by the -Type parameter.  
        Log entries will be pre-pended with a time stamp.
        If -Type is not specified, the message is logged only.
        If the -Verbose switch is provided (or if the $VerbosePreference is set to 'Continue') the function also writes the message to verbose output.
    .PARAMETER Message
        Mandatory parameter, accepts pipeline input.  
        Text string to send to log file and verbose output.
    .PARAMETER LogFile
        Optional parameter.  
        Full path to the log file to which to write output.
    .PARAMETER Type
        Optional parameter.
        Specifies the type of console output to which to send the message.  
        Valid choices are "Verbose", "Pipeline", "Warning", and "Error".  
        If no choice is specified, Verbose output will be used, and the message will not be displayed unless -Verbose is specified.
    .EXAMPLE
        "Sending Faxes!" | Out-ConsoleAndLog -LogFile 'LikeABoss.txt' -Verbose
        Writes "Sending Faxes!" to the log file "LikeABoss.txt", and sends the same text to Verbose output.  Demonstrates the use of pipeline input.
    .EXAMPLE
        $ErrorActionPreference = 'Continue'; Out-ConsoleAndLog -Message 'Creating Synergies!' -LogFile 'LikeABoss.txt'
        Writes "Creating Synergies" to the log file "LikeABoss.txt", and sends the same text to Verbose output.  Demonstrates use of the variable $ErrorActionPreference to control verbose output.
    .EXAMPLE
        Out-ConsoleAndLog -Type Warning -Message "No promotion!" -LogFile "LikeABoss.txt"
        Writes "No promotion!" to the warning output stream, a logs to "LikeABoss.txt"
    #>
    [cmdletBinding()]
    param(
        [parameter(Mandatory=$True)]
            [string]$LogFile,
        [parameter(Mandatory=$True,ValueFromPipeline=$True)]
            [string]$Message,
        [parameter()][ValidateSet('Verbose','Warning','Error','Pipeline')]
            [string]$Type = "Verbose"
    )
    Process {
        $Message = $Type + ': [' + (get-date -Format 'yyyy-MM-dd : HH:mm:ss') + '] : ' + $Message
        switch ($Type) {
            ('Error')     {$ErrorActionPreference = 'Continue'; Write-Error $Message}
            ('Warning')   {Write-Warning $Message}
            ('Pipeline')  {Write-Output $Message}
            ('Verbose')   {Write-Verbose $Message}
        }
        
        if ($LogFile) {$Message | Out-File -FilePath $LogFile -Append}
    }
}

try {
    #Load required PowerShell resources:
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" # Import the ConfigurationManager.psd1 module 
    Push-Location $SiteDrive # Set the current location to be the site code.
} catch {
    $out = 'Unable to initialize the Configuration Manager PowerShell environment.'
    Out-ConsoleAndLog -LogFile $log -Type Error -Message $out
}

#Loop through each name pattern and collect matching updates:
$updates = @()
foreach ($name in $names) {
    $updates += Get-CMSoftwareUpdate -name $name -Fast |
        Where-Object {$_.MaxExecutionTime -lt $maxSeconds}
}
#If matching updates are found, modify the MaximumExecutionMinutes:
if ($updates.count -gt 0) {
    Out-ConsoleAndLog -LogFile $log -Type Pipeline -Message "Found the following updates with short maximum execution times..."
    Out-ConsoleAndLog -LogFile $log -Type Pipeline -Message ' '
    ForEach ($update in $updates) {
        Out-ConsoleAndLog -LogFile $log -Type Pipeline -Message ("  Update: " + $update.LocalizedDisplayName)
        Out-ConsoleAndLog -LogFile $log -Type Pipeline -Message ('  MaxExecutionTime: ' + $update.MaxExecutionTime)
        try {
            Set-CMSoftwareUpdate -InputObject $update -MaximumExecutionMinutes $maxMinutes -errorAction Stop
            Out-ConsoleAndLog -LogFile $log -Type Pipeline "    Updated successfully"
        } catch {
            Out-ConsoleAndLog -LogFile $log -Type Error -Message "    Update Failed!"
        } finally {
            Out-ConsoleAndLog -LogFile $log -Type Pipeline -Message ' '
        }
    }
} else {
    Out-ConsoleAndLog -LogFile $log -Type Pipeline 'No matching updates found.'
}

Pop-Location