# Password Expiration Check for Entra ID and Active Directory

A PowerShell script that automates password expiration monitoring and notification for both Microsoft Entra ID (Azure AD) and Active Directory environments, helping organizations maintain security compliance and prevent account lockouts.

## Features

- Checks password expiration for both Entra ID and Active Directory accounts
- Supports checking admin accounts automatically
- Allows checking additional specified email addresses
- Sends customizable email notifications for expiring passwords
- Provides an overview mode for password status reporting
- Handles both never-expiring and standard password policies
- Supports simulation mode for testing notifications
- Comprehensive logging for troubleshooting

## Prerequisites

- PowerShell 5.1 or higher
- Required PowerShell Modules (automatically installed if missing):
  - Microsoft.Graph.Authentication (v2.0.0 or higher)
  - Microsoft.Graph.Users
  - Microsoft.Graph.Identity.DirectoryManagement
  - ActiveDirectory (if checking AD passwords)
- Appropriate permissions in Entra ID and/or Active Directory
- Microsoft Graph API permissions for email notifications:
  - User.Read.All
  - Directory.Read.All

## Installation

1. Clone this repository:
```powershell
git clone https://github.com/ecrotty/Password-Expiration-Check-Entra-AD.git
cd Password-Expiration-Check-Entra-AD
```

2. Ensure you have PowerShell 5.1 or higher installed:
```powershell
$PSVersionTable.PSVersion
```

## Usage

### Basic Usage

```powershell
.\Password-Expiration-Check-Entra-AD.ps1
```
This will check all admin accounts in both Entra ID and Active Directory.

### Check Specific Email Addresses

```powershell
.\Password-Expiration-Check-Entra-AD.ps1 -AdditionalEmails "user1@company.com","user2@company.com"
```

### Check Only Entra ID

```powershell
.\Password-Expiration-Check-Entra-AD.ps1 -CheckType 'Entra'
```

### Disable Notifications (Simulation Mode)

```powershell
.\Password-Expiration-Check-Entra-AD.ps1 -DisableNotifications
```

### Display Password Expiration Overview

```powershell
.\Password-Expiration-Check-Entra-AD.ps1 -Overview
```

### Show Help

```powershell
.\Password-Expiration-Check-Entra-AD.ps1 -help
```

## Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| AdditionalEmails | Array of email addresses to check | No | None |
| CheckType | Type of check: 'AD', 'Entra', or 'Both' | No | 'Both' |
| DisableNotifications | Switch to disable sending emails | No | False |
| Overview | Switch to display expiration overview | No | False |
| help | Display detailed help | No | False |

## Configuration

The script uses a configuration hashtable that can be modified at the top of the script:

```powershell
$config = @{
    FromAddress = "changeme"  # Sender email address
    ErrorNotificationEmail = "changeme"  # Email for script error notifications
    DefaultPasswordExpiryDays = 90  # Default if policy can't be retrieved
}
```

## Output

The script provides:
- Detailed logging of all operations
- Password expiration status for each user
- Email notifications for users with expiring passwords
- Overview report showing all password statuses
- Error notifications for script issues

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) for details on how to submit pull requests, report issues, and contribute to the project.

## License

This project is licensed under the BSD-3-Clause License - see the [LICENSE](LICENSE) file for details.

## Author

Ed Crotty (ecrotty@edcrotty.com)

## Acknowledgments

- Microsoft Graph PowerShell SDK team
- Active Directory PowerShell module team
