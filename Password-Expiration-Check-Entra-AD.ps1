#
# Password Expiration Check for Entra ID and Active Directory
# Copyright (c) 2024, Ed Crotty (ecrotty@edcrotty.com)
# Repository: https://github.com/ecrotty/Password-Expiration-Check-Entra-AD
#
# Licensed under the BSD 3-Clause License.
# For full license text, see the LICENSE file in the repository root
# or https://github.com/ecrotty/Password-Expiration-Check-Entra-AD/blob/main/LICENSE
#

<#
.SYNOPSIS
Checks password expiration for admin accounts and specified email addresses in Entra ID and/or Active Directory.

.DESCRIPTION
This script checks password expiration dates for admin accounts and/or specified email addresses in Entra ID and/or Active Directory.
It can send notification emails to users whose passwords are approaching expiration.

.PARAMETER AdditionalEmails
An array of email addresses to check in addition to (or instead of) admin accounts.
Example: -AdditionalEmails "user1@company.com","user2@company.com"

.PARAMETER CheckType
Specify the type of password check to perform. Options are 'AD', 'Entra', or 'Both'.
Default is 'Both'.
Example: -CheckType 'Entra'

.PARAMETER DisableNotifications
Switch to disable sending email notifications. When specified, the script will only log what notifications would have been sent.
Example: -DisableNotifications

.PARAMETER Overview
Switch to display a password expiration overview instead of sending individual notifications.
Example: -Overview

.PARAMETER help
Displays detailed help for the script.
Example: -help

.EXAMPLE
.\pw-exp-entra.ps1
Checks all admin accounts in Entra ID and Active Directory and sends notifications if enabled.

.EXAMPLE
.\pw-exp-entra.ps1 -AdditionalEmails "something@email.com","somethingelse@email.com"
Checks admin accounts plus the specified additional accounts in Entra ID and Active Directory.

.EXAMPLE
.\pw-exp-entra.ps1 -CheckType 'Entra'
Checks only Entra ID passwords for admin accounts and any additional specified accounts.

.EXAMPLE
.\pw-exp-entra.ps1 -DisableNotifications
Checks admin accounts in Entra ID and Active Directory but only logs what notifications would have been sent.

.EXAMPLE
.\pw-exp-entra.ps1 -Overview
Displays a password expiration overview for admin accounts in Entra ID and Active Directory.

.EXAMPLE
.\pw-exp-entra.ps1 -help
Displays detailed help for the script.
#>

# Get command line parameters
param(
    [Parameter(Mandatory = $false)]
    [string[]]$AdditionalEmails,

    [Parameter(Mandatory = $false)]
    [ValidateSet('AD', 'Entra', 'Both')]
    [string]$CheckType = 'Both',

    [Parameter(Mandatory = $false)]
    [switch]$DisableNotifications,

    [Parameter(Mandatory = $false)]
    [switch]$Overview,

    [Parameter(Mandatory = $false)]
    [Alias('h')]
    [switch]$help
)

# Show help if -h or -help is specified
if ($help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
    exit
}

# Script configuration
$config = @{
    FromAddress = "changeme"
    ErrorNotificationEmail = "changeme"  # Email to notify if script fails
    DefaultPasswordExpiryDays = 90  # Default if policy can't be retrieved
}

# Enhanced logging function for Azure Automation
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    # Create timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$Level] - $Message"
    
    # Write to Azure Automation job log
    switch ($Level) {
        "ERROR" { Write-Error $logMessage }
        "WARN"  { Write-Warning $logMessage }
        default { Write-Output $logMessage }
    }
}

# Function to ensure required modules are installed and imported
function Initialize-RequiredModules {
    $requiredModules = @(
        @{
            Name = 'Microsoft.Graph.Authentication'
            MinimumVersion = '2.0.0'
        },
        @{
            Name = 'Microsoft.Graph.Users'
            MinimumVersion = '2.0.0'
        },
        @{
            Name = 'Microsoft.Graph.Identity.DirectoryManagement'
            MinimumVersion = '2.0.0'
        }
    )

    # Only add ActiveDirectory module if we're checking AD
    if ($CheckType -in ('AD', 'Both')) {
        $requiredModules += @{
            Name = 'ActiveDirectory'
            MinimumVersion = '1.0.0'
        }
    }

    foreach ($module in $requiredModules) {
        try {
            Write-Log -Message "Checking for module: $($module.Name)"
            
            # Check if module is installed
            $installedModule = Get-Module -ListAvailable -Name $module.Name |
                Where-Object { $_.Version -ge $module.MinimumVersion } |
                Sort-Object Version -Descending |
                Select-Object -First 1

            if (-not $installedModule) {
                Write-Log -Message "Installing module: $($module.Name)" -Level "WARN"
                Install-Module -Name $module.Name -MinimumVersion $module.MinimumVersion -Force -AllowClobber -Scope CurrentUser
                Write-Log -Message "Module installed: $($module.Name)"
            }

            # Import the module
            Import-Module -Name $module.Name -MinimumVersion $module.MinimumVersion -Force -ErrorAction Stop
            Write-Log -Message "Module imported: $($module.Name)"
        }
        catch {
            Write-Log -Message "Error with module $($module.Name): $($_.Exception.Message)" -Level "ERROR"
            throw
        }
    }
}

# Function to simulate or send notification
function Send-GraphNotification {
    param (
        $ToAddress,
        $Subject,
        $Body
    )

    if (-not $DisableNotifications) {
        try {
            # Create the message
            $params = @{
                Message = @{
                    Subject = $Subject
                    Body = @{
                        ContentType = "Text"
                        Content = $Body
                    }
                    ToRecipients = @(
                        @{
                            EmailAddress = @{
                                Address = $ToAddress
                            }
                        }
                    )
                }
            }

            # Send using Graph API directly
            $apiVersion = "v1.0"
            $userId = $config.FromAddress
            $uri = "https://graph.microsoft.com/$apiVersion/users/$userId/sendMail"
            
            Invoke-MgGraphRequest -Method POST -Uri $uri -Body $params
            Write-Log -Message "Email sent to $ToAddress" -Level "INFO"
        }
        catch {
            Write-Log -Message ("Error sending email to " + $ToAddress + ": " + $_.Exception.Message) -Level "ERROR"
        }
    }
    else {
        Write-Log -Message "SIMULATION - Would send email:" -Level "INFO"
        Write-Log -Message "  To: $ToAddress" -Level "INFO"
        Write-Log -Message "  Subject: $Subject" -Level "INFO"
        Write-Log -Message "  Body:" -Level "INFO"
        $Body -split "`n" | ForEach-Object { Write-Log -Message "    $_" -Level "INFO" }
    }
}

# Function to handle password expiry notification
function Send-PasswordExpiryEmail {
    param (
        $UserEmail,
        $DaysRemaining,
        $UserName
    )

    $subject = "Password Expiration Notice - Action Required"
    $body = @"
Dear $UserName,

Your password will expire in $DaysRemaining days.

Please change your password before it expires to maintain access to your account.

If you need assistance, please contact the IT Help Desk.

Best regards,
IT Department
"@

    Send-GraphNotification -ToAddress $UserEmail -Subject $subject -Body $body
}

# Function to handle error notification
function Send-ErrorNotification {
    param (
        [string]$ErrorMessage
    )

    $subject = "Password Expiry Check Script Error"
    $body = @"
The password expiry check script encountered an error:

$ErrorMessage

Please check the Azure Automation job logs for more details.

Runbook: $($PSPrivateMetadata.JobId)
Timestamp: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

    Send-GraphNotification -ToAddress $config.ErrorNotificationEmail -Subject $subject -Body $body
}

# Function to check AD password expiration
function Get-ADPasswordExpiration {
    param(
        [string]$UserEmail
    )
    
    try {
        $user = Get-ADUser -Filter "EmailAddress -eq '$UserEmail'" -Properties PasswordLastSet, PasswordNeverExpires
        
        if ($user) {
            if ($user.PasswordNeverExpires) {
                return @{
                    DaysRemaining = -1  # Special value for never expires
                    LastSet = $user.PasswordLastSet
                    NeverExpires = $true
                }
            }
            
            $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge
            $expiryDate = $user.PasswordLastSet + $maxPasswordAge
            $daysRemaining = ($expiryDate - (Get-Date)).Days
            
            return @{
                DaysRemaining = $daysRemaining
                LastSet = $user.PasswordLastSet
                NeverExpires = $false
            }
        }
        return $null
    }
    catch {
        Write-Log -Message "Error checking AD password for $UserEmail : $($_.Exception.Message)" -Level "ERROR"
        return $null
    }
}

# Main script execution
try {
    # Initialize modules and connect to services
    Initialize-RequiredModules
    Connect-MgGraph -Scopes "User.Read.All", "Directory.Read.All" -NoWelcome
    
    # Initialize array to store password status for overview
    $passwordStatus = @()

    # Process based on CheckType
    $usersToCheck = @()
    
    if ($CheckType -in ('Entra', 'Both')) {
        Write-Log -Message "Starting Entra ID password check..."
        
        # Get admin users if checking Entra
        if (-not $AdditionalEmails) {
            try {
                Write-Log -Message "Retrieving admin roles from Entra ID..."
                $adminRoles = Get-MgDirectoryRole -ErrorAction Stop | 
                    Where-Object { $_.DisplayName -like "*admin*" }
                
                foreach ($role in $adminRoles) {
                    Write-Log -Message "Processing role: $($role.DisplayName)"
                    try {
                        $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -ErrorAction Stop
                        
                        # Get all users in one batch to improve performance
                        $userIds = $members | Where-Object { $_.Id } | Select-Object -ExpandProperty Id
                        foreach ($userId in $userIds) {
                            try {
                                $user = Get-MgUser -UserId $userId -Property UserPrincipalName, Mail -ErrorAction Stop
                                if ($user -and $user.UserPrincipalName) {
                                    if ($user.UserPrincipalName -notin $usersToCheck) {
                                        $usersToCheck += $user.UserPrincipalName
                                        Write-Log -Message "Added admin user: $($user.UserPrincipalName)"
                                    }
                                }
                            }
                            catch {
                                Write-Log -Message "Skipping invalid user ID: $userId" -Level "WARN"
                                continue
                            }
                        }
                    }
                    catch {
                        Write-Log -Message "Could not retrieve members for role $($role.DisplayName)" -Level "WARN"
                        continue
                    }
                }
            }
            catch {
                Write-Log -Message "Error retrieving admin roles: $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        # Add additional emails if specified
        if ($AdditionalEmails) {
            foreach ($email in $AdditionalEmails) {
                if (-not [string]::IsNullOrWhiteSpace($email)) {
                    try {
                        # Verify the user exists before adding to check list
                        $user = Get-MgUser -UserId $email -ErrorAction Stop
                        if ($user -and $user.UserPrincipalName -notin $usersToCheck) {
                            $usersToCheck += $user.UserPrincipalName
                            Write-Log -Message "Added additional user: $($user.UserPrincipalName)"
                        }
                    }
                    catch {
                        Write-Log -Message "Could not find additional user: $email" -Level "WARN"
                        continue
                    }
                }
            }
        }
        
        # Process users
        if ($usersToCheck.Count -eq 0) {
            Write-Log -Message "No valid users found to check in Entra ID" -Level "WARN"
        }
        else {
            Write-Log -Message "Found $($usersToCheck.Count) users to check in Entra ID"
            
            foreach ($userEmail in $usersToCheck) {
                if ([string]::IsNullOrWhiteSpace($userEmail)) { continue }
                
                try {
                    Write-Log -Message "Checking password for: $userEmail"
                    $user = Get-MgUser -UserId $userEmail `
                        -Property UserPrincipalName, DisplayName, PasswordPolicies, LastPasswordChangeDateTime `
                        -ErrorAction Stop
                    
                    if (-not $user) {
                        Write-Log -Message "User not found: $userEmail" -Level "WARN"
                        continue
                    }
                    
                    # Check if password never expires
                    if ($user.PasswordPolicies -contains "DisablePasswordExpiration") {
                        Write-Log -Message "Password never expires for: $userEmail"
                        
                        # Add to password status array for overview
                        $status = [PSCustomObject]@{
                            UserEmail = $userEmail
                            DisplayName = $user.DisplayName
                            LastPasswordChange = $null
                            DaysRemaining = -1
                            Status = "NEVER EXPIRES"
                            Source = "Entra ID"
                            NeverExpires = $true
                        }
                        $passwordStatus += $status
                        continue
                    }
                    
                    if ($user.LastPasswordChangeDateTime) {
                        $lastChange = [DateTime]::Parse($user.LastPasswordChangeDateTime)
                        $daysRemaining = $config.DefaultPasswordExpiryDays - ((Get-Date) - $lastChange).Days
                        Write-Log -Message "$userEmail password expires in $daysRemaining days"
                        
                        # Add to password status array for overview
                        $status = [PSCustomObject]@{
                            UserEmail = $userEmail
                            DisplayName = $user.DisplayName
                            LastPasswordChange = $lastChange
                            DaysRemaining = $daysRemaining
                            Status = if ($daysRemaining -le 0) { "EXPIRED" } 
                                   elseif ($daysRemaining -le 14) { "WARNING" }
                                   else { "OK" }
                            Source = "Entra ID"
                            NeverExpires = $false
                        }
                        $passwordStatus += $status

                        if ($daysRemaining -le 14 -and -not $Overview) {
                            Send-PasswordExpiryEmail -UserEmail $userEmail -DaysRemaining $daysRemaining -UserName $user.DisplayName
                        }
                    }
                    else {
                        Write-Log -Message "No password change date found for: $userEmail" -Level "WARN"
                    }
                }
                catch {
                    Write-Log -Message "Error processing user $userEmail : $($_.Exception.Message)" -Level "WARN"
                    continue
                }
            }
        }
    }
    
    if ($CheckType -in ('AD', 'Both')) {
        Write-Log -Message "Checking AD passwords"
        foreach ($userEmail in $usersToCheck) {
            $adStatus = Get-ADPasswordExpiration -UserEmail $userEmail
            if ($adStatus) {
                $user = Get-ADUser -Filter "EmailAddress -eq '$userEmail'" -Properties DisplayName
                
                # Add to password status array for overview
                $status = [PSCustomObject]@{
                    UserEmail = $userEmail
                    DisplayName = $user.DisplayName
                    LastPasswordChange = $adStatus.LastSet
                    DaysRemaining = $adStatus.DaysRemaining
                    Status = if ($adStatus.NeverExpires) { "NEVER EXPIRES" }
                            elseif ($adStatus.DaysRemaining -le 0) { "EXPIRED" }
                            elseif ($adStatus.DaysRemaining -le 14) { "WARNING" }
                            else { "OK" }
                    Source = "Active Directory"
                    NeverExpires = $adStatus.NeverExpires
                }
                $passwordStatus += $status

                if (-not $adStatus.NeverExpires -and $adStatus.DaysRemaining -le 14 -and -not $Overview) {
                    Send-PasswordExpiryEmail -UserEmail $userEmail -DaysRemaining $adStatus.DaysRemaining -UserName $user.DisplayName
                }
            }
        }
    }

    # Display overview if requested
    if ($Overview) {
        Write-Log -Message "`nPassword Expiration Overview:"
        Write-Log -Message "================================"
        
        # Sort by days remaining (putting "NEVER EXPIRES" at the end)
        $sortedStatus = $passwordStatus | Sort-Object { 
            if ($_.NeverExpires) { [int]::MaxValue } 
            else { $_.DaysRemaining }
        }
        
        foreach ($status in $sortedStatus) {
            $statusMessage = if ($status.NeverExpires) {
                "Password never expires"
            }
            else {
                $expiryDate = (Get-Date).AddDays($status.DaysRemaining).ToString("yyyy-MM-dd")
                if ($status.DaysRemaining -le 0) {
                    "Password EXPIRED on $expiryDate"
                }
                else {
                    "Expires in $($status.DaysRemaining) days ($expiryDate)"
                }
            }
            
            Write-Log -Message ("`nUser: " + $status.DisplayName + " (" + $status.UserEmail + ")")
            Write-Log -Message ("Source: " + $status.Source)
            Write-Log -Message ("Status: " + $statusMessage)
            if ($status.LastPasswordChange) {
                Write-Log -Message ("Last Changed: " + $status.LastPasswordChange.ToString("yyyy-MM-dd"))
            }
        }
        Write-Log -Message "`n================================"
    }

    Write-Log -Message "Password expiry check completed successfully"
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Log -Message ("Error in script execution: " + $errorMessage) -Level "ERROR"
    Send-ErrorNotification -ErrorMessage $errorMessage
    throw $_.Exception
}
finally {
    Disconnect-MgGraph
}
