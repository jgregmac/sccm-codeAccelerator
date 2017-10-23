<#
.SYNOPSIS
    Searches the "Add/Remove programs" uninstall keys for the application string named in the variable $appRegEx
.NOTES
    Returns "True" if a key is found, "False" if no key is found.
    (This specific strings output is required for SCCM compliance rules.)
.EXAMPLE
    Set $appRegEx to "Adobe Reader" to find any version of Adobe Reader, including DX
    Set $appRegEx to "firefox" to any version of Mozilla Firefox.
#>

[string]$appRegEx = "My Exciting App"

$regKeys = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
)

[bool]$found = $false

forEach ($key in $regKeys) {
    if (
        Get-ChildItem $key | 
            ForEach-Object {
                Get-ItemProperty -path $_.PSPath -Name DisplayName -ErrorAction SilentlyContinue | 
                    Where-Object {$_.DisplayName -match $appRegEx}
            }
    ) {
        $found = $true
    }
}

if ($found) {
    Write-Output "True"
} else {
    Write-Output "False"
}