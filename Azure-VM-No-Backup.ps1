<#
.SYNOPSIS
    Identifies Azure Virtual Machines without backup protection across subscriptions.

.DESCRIPTION
    This script scans Azure subscriptions to identify Virtual Machines that are not configured
    with backup protection. It supports both local execution and Azure Automation runbook deployment,
    with optional email reporting capabilities.

.NOTES
    Version:        1.0.0
    Author:         Ed Crotty (ecrotty@edcrotty.com)
    Creation Date:  2024
    License:        BSD 3-Clause
    Repository:     https://github.com/ecrotty/Azure-VM-No-Backup

.LINK
    https://github.com/ecrotty/Azure-VM-No-Backup

.EXAMPLE
    # Run locally for a specific subscription
    .\Azure-VM-No-Backup.ps1

.EXAMPLE
    # Run locally for all accessible subscriptions with email notification
    $runMode = "Local"
    $enableEmail = $true
    $checkAllSubscriptions = $true
    .\Azure-VM-No-Backup.ps1
#>

# Required PowerShell Modules (will be automatically installed if missing):
# - Az.Accounts (v4.0.0 or higher)
# - Az.Compute
# - Az.RecoveryServices
# - Microsoft.Graph (only if email is enabled)

# Configuration variables
[string]$runMode = "Local"  # Set to "Local" for interactive login, "Automation" for running in Azure Automation
[bool]$enableEmail = $false  # Set to $true to enable email sending
[bool]$checkAllSubscriptions = $false  # Set to $true to check all accessible subscriptions, $false to select a specific subscription
[string]$emailFrom = "changeme"
[string]$emailTo = "changeme"
[string]$emailSubject = "Azure VMs Without Backup Protection Report"

# Validate configuration
if ($enableEmail) {
    if ($emailFrom -eq "changeme" -or $emailTo -eq "changeme") {
        throw "Email configuration is enabled but email addresses are not configured. Please set valid email addresses."
    }
    if (-not ($emailFrom -as [System.Net.Mail.MailAddress])) {
        throw "Invalid sender email address format: $emailFrom"
    }
    if (-not ($emailTo -as [System.Net.Mail.MailAddress])) {
        throw "Invalid recipient email address format: $emailTo"
    }
}

if ($runMode -notin @("Local", "Automation")) {
    throw "Invalid runMode. Must be either 'Local' or 'Automation'."
}

# Function to ensure modules are installed with correct versions
function Ensure-ModuleInstalled {
    param (
        [string]$ModuleName,
        [string]$MinimumVersion = $null
    )
    
    $moduleParams = @{
        Name = $ModuleName
        Scope = 'CurrentUser'
        Force = $true
        AllowClobber = $true
    }

    if ($MinimumVersion) {
        $moduleParams['MinimumVersion'] = $MinimumVersion
    }

    if (-not (Get-Module -ListAvailable -Name $ModuleName | Where-Object { !$MinimumVersion -or $_.Version -ge [Version]$MinimumVersion })) {
        Write-Output "Module '$ModuleName' with required version is not installed. Attempting to install..."
        try {
            Install-Module @moduleParams
            Write-Output "Successfully installed module '$ModuleName'"
        }
        catch {
            Write-Error "Failed to install module '$ModuleName': $_"
            return $false
        }
    }
    return $true
}

# Check if we're running in a PowerShell session with incompatible module versions
$azAccountsModule = Get-Module Az.Accounts -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if ($azAccountsModule -and $azAccountsModule.Version -lt [Version]"4.0.0") {
    Write-Error "Detected incompatible Az.Accounts version. Please close all PowerShell windows and run this script in a new PowerShell session."
    exit 1
}

# Remove any existing Azure PowerShell modules from the current session
Get-Module Az.* | Remove-Module -Force

# Check and install required modules with specific versions
$modulesOk = $true
$modulesOk = $modulesOk -and (Ensure-ModuleInstalled -ModuleName 'Az.Accounts' -MinimumVersion '4.0.0')
$modulesOk = $modulesOk -and (Ensure-ModuleInstalled -ModuleName 'Az.Compute')
$modulesOk = $modulesOk -and (Ensure-ModuleInstalled -ModuleName 'Az.RecoveryServices')

# Only check for Microsoft.Graph if email is enabled
if ($enableEmail) {
    $modulesOk = $modulesOk -and (Ensure-ModuleInstalled -ModuleName 'Microsoft.Graph')
}

if (-not $modulesOk) {
    Write-Error "Failed to install one or more required modules. Please run PowerShell as Administrator and try again."
    exit 1
}

# Import required modules in correct order
Import-Module Az.Accounts
Import-Module Az.Compute
Import-Module Az.RecoveryServices

# Connect to Azure and Microsoft Graph based on run mode
try {
    if ($runMode -eq "Local") {
        # Interactive login for local execution
        Write-Output "Connecting to Azure (interactive login)..."
        Connect-AzAccount
        if ($enableEmail) {
            Write-Output "Connecting to Microsoft Graph (interactive login)..."
            Import-Module Microsoft.Graph
            Connect-MgGraph -Scopes "Mail.Send"
        }
    } else {
        # Managed identity login for Azure Automation
        Write-Output "Connecting using managed identity..."
        Connect-AzAccount -Identity
        if ($enableEmail) {
            Import-Module Microsoft.Graph
            Connect-MgGraph -Identity
        }
    }
} catch {
    Write-Error "Failed to connect to Azure or Microsoft Graph. Error: $_"
    Write-Error "Please ensure you have the necessary permissions and credentials."
    exit 1
}

# Initialize arrays to store results
$allVMs = @()
$vmsWithoutBackup = @()
$totalVMCount = 0

# Get subscriptions based on configuration
if ($checkAllSubscriptions) {
    Write-Output "Getting all accessible Azure subscriptions..."
    $subscriptions = Get-AzSubscription
    
    if (-not $subscriptions) {
        Write-Error "No accessible subscriptions found. Please verify your permissions."
        exit 1
    }
} else {
    # Get all available subscriptions
    $availableSubscriptions = Get-AzSubscription

    if (-not $availableSubscriptions) {
        Write-Error "No accessible subscriptions found. Please verify your permissions."
        exit 1
    }

    # Display available subscriptions
    Write-Output "`nAvailable Subscriptions:"
    $availableSubscriptions | Format-Table -Property Name, Id, State -AutoSize

    # Prompt user to select a subscription
    $selectedSubscriptionId = Read-Host "`nEnter the Subscription ID to check"
    $subscriptions = $availableSubscriptions | Where-Object { $_.Id -eq $selectedSubscriptionId }

    if (-not $subscriptions) {
        Write-Error "Invalid Subscription ID. Please run the script again with a valid Subscription ID."
        exit 1
    }
}

# Loop through selected subscription(s)
foreach ($sub in $subscriptions) {
    # Set context to current subscription
    Set-AzContext -Subscription $sub.Id | Out-Null
    Write-Output "Processing subscription: $($sub.Name)"

    # Get all VMs in the subscription
    $vms = Get-AzVM
    $totalVMCount += $vms.Count

    # Get all recovery services vaults in the subscription
    $allVaults = Get-AzRecoveryServicesVault

    # Check each VM for backup protection
    foreach ($vm in $vms) {
        Write-Output "Checking backup status for VM: $($vm.Name)"
        
        try {
            $isProtected = $false

            # Check each vault in the subscription for backup protection of the VM
            foreach ($vault in $allVaults) {
                try {
                    $backupItems = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureVM -WorkloadType AzureVM -VaultId $vault.ID
                    if ($backupItems | Where-Object { $_.SourceResourceId -eq $vm.Id }) {
                        $isProtected = $true
                        break
                    }
                } catch {
                    Write-Warning "Error checking vault $($vault.Name) for VM $($vm.Name): $_"
                    continue
                }
            }

            # Create VM info object
            $vmInfo = [PSCustomObject]@{
                VMName = $vm.Name
                ResourceGroup = $vm.ResourceGroupName
                SubscriptionName = $sub.Name
                Location = $vm.Location
                BackupEnabled = $isProtected
                Note = if ($isProtected) { "Protected" } else { "No backup configured" }
            }
            $allVMs += $vmInfo

            # If VM is not protected, add to the unprotected list
            if (-not $isProtected) {
                $vmsWithoutBackup += $vmInfo
            }
        } catch {
            Write-Warning "Error checking backup status for VM $($vm.Name): $_"
            # Add VM to both lists with error status
            $vmInfo = [PSCustomObject]@{
                VMName = $vm.Name
                ResourceGroup = $vm.ResourceGroupName
                SubscriptionName = $sub.Name
                Location = $vm.Location
                BackupEnabled = $false
                Note = "Error checking backup status: $_"
            }
            $allVMs += $vmInfo
            $vmsWithoutBackup += $vmInfo
        }
    }
}

# Create summary message
$summary = @"
Azure VM Backup Status Summary:
-----------------------------
Total VMs checked: $totalVMCount
VMs without backup: $($vmsWithoutBackup.Count)
VMs with backup: $($totalVMCount - $vmsWithoutBackup.Count)
Backup coverage: $([math]::Round(($totalVMCount - $vmsWithoutBackup.Count) / $totalVMCount * 100, 2))%

"@

# If there are VMs without backup and email is enabled, send email
if ($vmsWithoutBackup.Count -gt 0 -and $enableEmail) {
    # Create email body
    $emailBody = $summary
    $emailBody += "VMs Requiring Backup Configuration:`n`n"
    foreach ($vm in $vmsWithoutBackup) {
        $emailBody += "VM Name: $($vm.VMName)`n"
        $emailBody += "Resource Group: $($vm.ResourceGroup)`n"
        $emailBody += "Subscription: $($vm.SubscriptionName)`n"
        $emailBody += "Location: $($vm.Location)`n"
        $emailBody += "Status: $($vm.Note)`n"
        $emailBody += "Required Action: Configure backup protection for this VM`n"
        $emailBody += "-----------------`n"
    }

    # Create email message using Microsoft Graph
    $mailMessage = @{
        Message = @{
            Subject = $emailSubject
            Body = @{
                ContentType = "Text"
                Content = $emailBody
            }
            ToRecipients = @(
                @{
                    EmailAddress = @{
                        Address = $emailTo
                    }
                }
            )
        }
        SaveToSentItems = $true
    }

    # Send email using Microsoft Graph
    try {
        Send-MgUserMail -UserId $emailFrom -BodyParameter $mailMessage
        Write-Output "Email sent successfully with list of VMs without backup."
    } catch {
        Write-Error "Failed to send email: $_"
        Write-Error "Please verify your email configuration and permissions."
    }
} else {
    if ($vmsWithoutBackup.Count -gt 0) {
        Write-Output "`n$summary"
        Write-Output "VMs without backup protection (email sending is disabled):"
        $vmsWithoutBackup | Format-Table -Property VMName, ResourceGroup, SubscriptionName, Location, BackupEnabled, Note -AutoSize
    } else {
        Write-Output "`n$summary"
        Write-Output "All VMs are protected with backup."
    }
}

# Display all VMs status
Write-Output "`nComplete VM Backup Status:"
$allVMs | Format-Table -Property VMName, ResourceGroup, SubscriptionName, Location, BackupEnabled, Note -AutoSize

# Cleanup based on run mode
if ($runMode -eq "Local") {
    Write-Output "Disconnecting from Microsoft Graph and Azure..."
    if ($enableEmail) {
        Disconnect-MgGraph
    }
    Disconnect-AzAccount
} else {
    if ($enableEmail) {
        Write-Output "Disconnecting from Microsoft Graph..."
        Disconnect-MgGraph
    }
}

Write-Output "Script execution completed."
