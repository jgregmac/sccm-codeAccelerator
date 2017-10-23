Function Out-ConsoleAndLog {
    <#
    .SYNOPSIS
        Writes the specifiec message to the specified log file, and to the output stream specified by -Type.
    .DESCRIPTION
        Logs to the file specified in in the -LogFile parameter, and to the output stream selected by the 
        -Type parameter.  
        Log entries will be pre-pended with a time stamp.
        If -Type is not specified, the message is only logged.
        If the -Verbose switch is provided (or if the $VerbosePreference is set to 'Continue') the function 
        also writes the message to verbose output.
        If the global variable 'gLog' is defined, the path contained in that variable will be used as the 
        target for the message.
    .PARAMETER Message
        Mandatory parameter, accepts pipeline input.  
        Text string to send to log file and verbose output.
    .PARAMETER LogFile
        Optional parameter.  
        Full path to the log file to which to write output. If the LogFile is not specified, the path 
        specified in the global variable 'globalLog' will be used instead.  If 'globalLog' is not set,
        then the message will not be logged. 
    .PARAMETER Type
        Optional parameter. Specifies the type of console output to which to send the message.  
        Valid choices are "Verbose", "Host", "StdOut", "Warning", and "Error".
          - Verbose: Writes to the PowerShell Verbose output stream.  
            Use the -Verbose parameter or set the $VerbosePreference variable to display the Verbose stream.
          - StdOut (or 'Pipeline'): Writes to Standard Output.  'Pipeline' is maintained as an alias for
            backward compatibility
          - Host: Writes to the PowerShell host stream.  
            NOTE: This is not the same as standard out.  'Host' output cannot be used in a pipeline.
          - Warning: Writes to the PowerShell Warning output stream
          - Error: Writes to the PowerShell error object.  This option also throws a terminating error,
        If no choice is specified, Verbose will be used (StdOut would be more logical, but we use Verbose
        to reduce the chance of unwanted standard output causing SCCM detection failures).
    .PARAMETER Color
        Specifies the text foreground color to be used with the output type 'Host'.  If any other output
        type is specified, this parameter will be ignored.
    .EXAMPLE
        PS> "Sending Faxes!" | Out-ConsoleAndLog -LogFile 'LikeABoss.txt' -Verbose
        Writes "Sending Faxes!" to the log file "LikeABoss.txt", and sends the same text to Verbose 
        output.  Demonstrates the use of pipeline input.
    .EXAMPLE
        PS> $ErrorActionPreference = 'Continue'; 
        PS> Out-ConsoleAndLog -Message 'Creating Synergies!' -LogFile 'LikeABoss.txt'
        Writes "Creating Synergies" to the log file "LikeABoss.txt", and sends the same text to Verbose 
        output.  Demonstrates use of the variable $ErrorActionPreference to control verbose output.
    .EXAMPLE
        PS> Out-ConsoleAndLog -Type Warning -Message "No promotion!" -LogFile "LikeABoss.txt"
        Writes "No promotion!" to the warning output stream, a logs to "LikeABoss.txt"
    #>
    [cmdletBinding()]
    param(
        [parameter(Position=0,Mandatory=$True,ValueFromPipeline=$True)]
            [string]$Message,
        [parameter()]
            [string]$LogFile = $global:GlobalLog,
        [parameter()][ValidateSet('Verbose','Warning','Error','Pipeline','StdOut','Host')]
            [string]$Type = "Verbose",
        [parameter()][ValidateSet(
            'Black', 'DarkBlue', 'DarkGreen', 'DarkCyan', 'DarkRed', 'DarkMagenta', 'DarkYellow', 
            'Gray', 'DarkGray', 'Blue', 'Green', 'Cyan', 'Red', 'Magenta', 'Yellow', 'White')]
            [string]$Color
    )
    Process {
        $Message = $Type + ': [' + (get-date -Format 'yyyy-MM-dd : HH:mm:ss') + '] : ' + $Message
        switch ($Type) {
            ('Error')                 {Write-Error $Message -ErrorAction Continue}
            ('Warning')               {Write-Warning $Message}
            ('StdOut' -or 'Pipeline') {Write-Output $Message}
            ('Host')                  {if ($color) {Write-Host $message -Foregroundcolor $color} else {Write-Host $Message}}
            ('Verbose')               {Write-Verbose $Message}
        }
        if ($LogFile) {$Message | Out-File -FilePath $LogFile -Append}
    }
}

function Invoke-CommandForSCCM {
    <#
    .SYNOPSIS
        Runs a Command with SCCM-friendly error handing
    .DESCRIPTION
        Runs commands for SCCM Application deployment scripts.  Standard output from commands is suppressed.
        Approximations of command results are logged to file.  Errors will be logged, and then will force the 
        script to exit with an error code provieded by -ExitCode.  The intention is to reduce repetitive code
        use 
    .EXAMPLE
        An example
    .NOTES
        Work-in-progress function. Not-yet exported when loading this module.
    #>
    param(
        [parameter(Mandatory=$true)]
            [string]$Command,
        [parameter()]
            [hashtable]$Parameters,
        [parameter()]
            [int32]$ExitCode,
        [parameter()]
            [string]$LogFile = $global:GlobalLog
    )
    try {
        $ErrorActionPreference = 'Stop'
        & $Command @Parameters
    } catch {
        Out-ConsoleAndLog -Message ("Failure running command: $Command") -Type Error -LogFile $LogFile
        #exit $ExitCode
    }
    #Success report
}
Function Invoke-MSIExec {
    <#
    .SYNOPSIS
        Invokes MSIEXEC.EXE with the arguments provided in the MsiArgs parameter.  
    .DESCRIPTION
        This function will wait for MSIEXEC to complete and will capture the return code of the process.  The function
        is capable of rudimentary error handling.  It will treat MSIEXEC return codes 0,1614,1541,1707, and 3010 as success.
        All other return codes will be considered failures.  By default the function will cause script execution to terminate 
        on non-success return codes.
    .PARAMETER MsiArgs
        Mandatory parameter. Contains all of the arguments to pass to MSIEXEC.exe, formatted in a array of string values. 
    .PARAMETER NoExit
        Optional switch parameter. If specified, the function will allow script execution to continue in the event of an 
        MSIEXEC error.  Otherwise, the default behavior is to terminate script execution and send back a return code to the 
        calling process that matches the return code of MSIEXEC. 
    .PARAMETER LogFile
        Sort-of Required parameter.  Specifies the path to a log file to which to report results.  There actually is a logic error
        here at present, since "$LogFile" is called as a global variable in the script, so this param actually will be ignored.
    .EXAMPLE
        Invoke-MSIExec -MsiArgs @('/i LikeABoss.msi','/q','/norestart') -NoExit
        Installs "LikeABoss.msi" silently and suppresses restart.  If MSIExec fails, script execution continues.
        Activity will be logged to the globally-declared $LogFile path.
    #>
    [CmdletBinding()]
    param(
        [string[]]$MsiArgs,
        [switch]$NoExit = $False,
        [string]$LogFile
    )
    #Array of "successful" msiexec return codes:
    [int[]]$successCodes = @(0,1614,1641,1707,3010)

    #Launch MSIExec and wait for the process to complete:
    Out-ConsoleAndLog -Message ("About to run MSIEXEC with arguments: " + $MsiArgs) -LogFile $Global:LogFile
    $msiProc = Start-Process -FilePath msiexec.exe -ArgumentList $MsiArgs -Wait -PassThru

    #Analyze the return code from MSIExec to determine success or failure:
    if ($successCodes -contains $msiProc.ExitCode) {
        Out-ConsoleAndLog -Message 'Successful MSIEXEC action.' -LogFile $Global:LogFile
    } else {
        $details = & net helpmsg $msiProc.ExitCode
        Out-ConsoleAndLog -Type Warning -Message "MSIEXEC with arguments: $MsiArgs returned an error." -LogFile $Global:LogFile
        Out-ConsoleAndLog -Type Warning `
            -Message ('MSIEXEC failed with exit code: ' + $msiProc.ExitCode + ' and text: "' + $details[1] + '"') `
            -LogFile $Global:LogFile 
        
        #Unless "NoExit" has been specified, we want to terminate on error: (SCCM-specific choice.  We really should be throwing a terminating error.)
        If (-not $NoExit) {
            exit $msiProc.ExitCode
        }
    }
    $msiProc.ExitCode
}

Function Invoke-MSIInstall {
    <#
    .SYNOPSIS
        Invokes MSIExec to perform a silent install the MSI file specified in the -msiFile parameter, and suppress reboot.
    .DESCRIPTION
        This is a wrapper function for the Invoke-MSIExec function that simplifies the syntax for invoking an installer.
    .PARAMETER msiFile
        Specifies the path to the .msi file to be installed.
    .EXAMPLE 
        Invoke-MSIInstall -msiFile LikeABoss.msi
        Installs "LikeABoss.msi" silently and suppresses reboot.  If msiexec returns a non-success return code, script execution
        will terminate.  Activity will be logged to the globally-declared $LogFile path.
    #>
    [cmdletBinding()]
    Param(
        [parameter(Mandatory=$True)]
            [ValidateScript({Test-Path $_})]
            [string]$msiFile,
        [parameter(Mandatory=$false)]
            [string[]]$MSIArgs = @()
    )
    $BaseArgs = @("/i $msiFile",'/q','/norestart')
    $AllArgs = $BaseArgs + $MSIArgs
    Invoke-MSIExec -MsiArgs $AllArgs
}

Function Invoke-MSIPatch {
    <#
    .SYNOPSIS
        Invokes MSIExec to perform a silent install of the MSP file specified in the -mspFile parameter.  Reboot is suppressed.
    .DESCRIPTION
        This is a wrapper function for the Invoke-MSIExec function that simplifies the syntax for invoking an patch.
    .PARAMETER mspFile
        Specifies the path to the .MSP file to be installed.
    .EXAMPLE
        Invoke-MSIPatch -mspFile remembrinBirthdays.msp
        Installs the MSI patch file "remembrinBirthdays.msp" silently and suppresses any required reboots.
    .NOTES
        "MSIExec /Update" actually can support multiple MSP files simultaneously.  This function should be updated to include
        the ability to parse and install from an array of supplied MSP file.
    #>
    [cmdletBinding()]
    Param(
        [parameter(Mandatory=$True)]
            [ValidateScript({Test-Path $_})]
            [string]$mspFile,
        [parameter(Mandatory=$false)]
            [string[]]$MSIArgs = @()
    )
    $BaseArgs = @("/update $mspFile",'/q','/norestart')
    $AllArgs = $BaseArgs + $MSIArgs
    $rc = Invoke-MSIExec -MsiArgs $AllArgs
    if (@(0,1614) -contains $rc) {
        Out-ConsoleAndLog -Message "Uninstall succeeded with return code: $rc" -Type Verbose
    } else {
        Out-ConsoleAndLog -Message "Uninstall appears to have failed with return code: $rc" -Type Warning
    }
}

Function Invoke-MSIUninstall {
    <#
    .SYNOPSIS
        Scans the MSI registry for applications that match the pattern specified in the -pattern parameter and attempts to 
        uninstall them.  
    .DESCRIPTION
        Searches both 32-and 64-bit MSI "Uninstall" registry keys for "DisplayName" values that match the regular expression
        specified in the -Pattern parameter.  The function will attempt to uninstall any matching applications by using 
        the MSI GUID value of the parent regustry entry.  Since older MSI-based installers frequently fail to uninstall cleanly,
        (either because of database corruption, missing MSI source data, or just bad programming), the function assumes that
        script execution should continue on error.
    .PARAMETER Pattern
        A RegEx value that specifies software that should be installed.
    .EXAMPLE
        Invoke-MSIUninstall -Pattern '.+Boss$'
        Attempts to uninstall any software with any text ending with "Boss" in the display name.
        Thus, the software titles "Like A Boss" will be uninstalled, but "Like a Boss 2.0" will not.
    .TODO
        Add "-NoExit" switch parameter to allow options to continue on error. (at present, we assume -NoExit)
    #>
    [cmdletBinding()]
    Param(
        [Parameter(Mandatory=$True)][string]$Pattern
    )
    #Registry paths to search for MSI uninstall keys:
    $Paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($path in $paths) {
        #Now, we search each each uninstall registry entry by looping though all keys in the path: 
        $keys = Get-ChildItem -Path $path
        foreach ($key in $keys) {
            
            #Check the keys for a DisplayName matching $Pattern
            $displayNameProp = Get-ItemProperty -path $key.PSPath -Name DisplayName -ErrorAction SilentlyContinue
            if ($displayNameProp.DisplayName -match $Pattern) {

                #Get the MSI product GUID when a pattern match is found:
                $guid = $key.PSChildName 
                if ($guid -notmatch '^{[0-9A-Fa-f-]+}$') {
                    #The uninstall string was not valid... skip and hope for the best.
                    continue
                }            

                #Execute the MSI installer (msiexec.exe needs to be called by "Start-Process" to allow capturing of the return code of the installer)
                # Use -NoExit because we are assuming that we would like to continue on error.
                $MsiArgs = @("/X$guid","/q","/norestart") 
                Invoke-MSIExec -MsiArgs $MsiArgs -NoExit 
            }
        }
    }
}

Export-ModuleMember -Function `
    Out-ConsoleAndLog,
    Invoke-MSIExec,
    Invoke-MSIInstall,
    Invoke-MSIPatch,
    Invoke-MSIUninstall