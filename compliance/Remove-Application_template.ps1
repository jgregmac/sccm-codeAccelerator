<#
.SYNOPSIS
    Locates a Add/Remove programs uninstall key for $appRegEx, then attempts to uninstall the software if present.
    (To be used in an SCCM remediation script.)
.NOTES
    If it is necessary to terminate the application before uninstall, you can specify the application's process
    name in the variable $procName. (This script will treat the variable as a wildcard match, and will attempt to 
    terminate any matching process.)

    To run interactively, spawn an embedded powershell session, then set "$verbosePreference = 'Continue'",
    then run the script.  The embedded powershell session will exit.  You then can look at "$LASTEXITCODE"
    to see what RC the script would have sent back to SCCM.

    NOTE: Compliance remediation scripts will consider any non-zero return code to be a failure, and a zero return 
    code to be a success.
#>

[string]$appRegEx = "RegEx to search for the application to uninstall."
[string]$procName = "Process name of the appication to terminate, or wildcard approximation of process name."

#Initialize the return code... assume success:
$rc = 0

function Stop-MatchingProcesses {
    param (
        [parameter(Mandatory=$true)]
            [string]$processName
    )
    #Gets all processes matching the input parameter $processName, then attempts to terminate the processes.
    # Uses wildcard matching logic to get the processes.

   [array]$processes = Get-Process $processName -ErrorAction SilentlyContinue
    if ($processes.count -gt 0) {
        foreach ($process in $processes) {
            # Terminate the process if it is running, exit if process termination fails.            
            try {
                Stop-Process -InputObject $process -Force -Confirm:$false -ErrorAction Stop
            } catch {
                Write-Verbose "Could not terminate $process"
                exit -2
            }
        }
    }
}

# Registry locations to look for uninstall information... many applications could be in either 32 or 64-bit
# Uninstall registry trees:
$searchBases = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

[string[]]$uninsts = @() #Contains uninstall information for all matching application installs on a system.
:bases foreach ($searchBase in $searchBases) {
    # $keys contains all uninstall registry keys
    try {
        $keys = Get-ChildItem $searchBase -ErrorAction Stop
    } catch {
        continue :bases
    }
    ForEach ($key in $keys) {
        $displayName = Get-ItemProperty -path $key.PSPath -Name DisplayName -ErrorAction SilentlyContinue | 
            Select-Object -ExpandProperty DisplayName
        if ($displayName -match $appRegEx) {
            #Get the uninstall code.
            try {
                $uninsts += Get-ItemProperty -Path $key.PSPath -name UninstallString -ErrorAction Stop | 
                    Select-Object -ExpandProperty UninstallString
            } catch {
                Write-Verbose "Could not read UninstallString registry value for $appRegEx."
                exit -4
            }
        }
    }
}

if ($uninsts.count -gt 0) {
    foreach ($uninst in $uninsts) {
        # Stop all $appRegEx processes (continue on error):
        Stop-MatchingProcesses -processName $procName

        # Build final uninstallation arguments to feed to "msiexec.exe":
        [string]$arguments = $uninst.Substring(($uninst.IndexOf(' ')+1))
        # Some applications have the "/I" argument listed in the uninstall string, but we want to run silently,
        # so substitute out "/X", and add silent uninstall arguments:
        if ($arguments.Contains('/I')) {$arguments = $arguments.Replace('/I{','/X{')}
        $arguments += ' /qn /norestart'

        # Start MsiExec and wait for the process to complete:
        Write-Verbose ("Attempting to run msiexec.exe with arguments: " + $arguments) 
        $msiProc = Start-Process -FilePath msiexec.exe -ArgumentList $arguments -Wait -PassThru -ErrorAction SilentlyContinue

        #Return the Exit Code of the MSI installer process:
        [int[]]$success = @(0,1605,1614,1641,3010)
        if ($success -contains $msiProc.ExitCode) {
            Write-Verbose 'Uninstall successful'
        } else {
            Write-Verbose ('MSI Installer failed with exit code: ' + $msiProc.ExitCode)
            #Set return code to -1, but continue processing in case there are more detected instances of ID finder in the registry:
            $rc = -1
        }
    }
} else {
    # No uninstall registry entries were located, so system is compliant:
    Write-Verbose "$appRegEx uninstall registry not found."
    exit 0
}
# If we are here, the application was located, and uninstall completed without error:
exit $rc