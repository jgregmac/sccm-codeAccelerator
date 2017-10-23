# sccm-codeAccelerator
A collection of scripts and guidance for scripting actions in System Center Configuration Manager

General Purpose Scripts:
SCCMCustomFunctions.psm1 - A script module with a common logging function and MSI installer handling functions.

Application management scripts:
Install-Application_template.ps1 - A script template for use in installing MSI-based applications within the SCCM "Applications" node.

Compliance node scripts:
Detect-Application_template.ps1 - To be used in a compliance rule to detect the presence of undesirable (or desirable) applications.
Remove-Application_template.ps1 - To be used in a compliance rule to remove undesirable software as a remediation action.

Operational Scripts:
Export-NewApplications.ps1 - Exports new or changed appications from a site to an external file share. Useful for backup or shipping from test to production.
Set-CUMaxExecutionTime.ps1 - Changes the maximum execution time for cumulative security updates if they are not already greater than 30 minutes.  Useful for Server 2016 CUs.
