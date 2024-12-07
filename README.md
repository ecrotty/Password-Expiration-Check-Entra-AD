# Azure VM Backup Checker

A PowerShell script that identifies Azure Virtual Machines without backup protection across subscriptions. This tool helps ensure your Azure infrastructure maintains proper backup coverage by scanning all VMs and reporting those that lack backup configuration.

## Features

- Scans Azure VMs across single or multiple subscriptions
- Identifies VMs without backup protection
- Supports both local execution and Azure Automation runbook deployment
- Optional email reporting capability using Microsoft Graph
- Calculates and displays backup coverage statistics
- Handles authentication via interactive login or managed identity

## Prerequisites

- PowerShell 5.1 or higher
- Required PowerShell Modules (automatically installed if missing):
  - Az.Accounts (v4.0.0 or higher)
  - Az.Compute
  - Az.RecoveryServices
  - Microsoft.Graph (only if email functionality is enabled)
- Azure subscription with appropriate permissions
- For email functionality: Microsoft 365 account with appropriate Graph API permissions

## Installation

1. Clone this repository:
```powershell
git clone https://github.com/Ed-Crotty/Azure-VM-No-Backup.git
cd Azure-VM-No-Backup
```

2. Ensure you have PowerShell 5.1 or higher installed:
```powershell
$PSVersionTable.PSVersion
```

## Usage

### Local Execution

1. Configure the script parameters in the script header:
```powershell
$runMode = "Local"  # For interactive login
$enableEmail = $false  # Set to $true if you want email notifications
$checkAllSubscriptions = $false  # Set to $true to check all accessible subscriptions
```

2. Run the script:
```powershell
.\Azure-VM-No-Backup.ps1
```

### Azure Automation Execution

1. Import the script as a runbook in Azure Automation
2. Set the following variables:
```powershell
$runMode = "Automation"
```

3. Configure the managed identity for your Automation account
4. Schedule or run the runbook as needed

## Configuration

The script supports the following configuration variables:

| Variable | Description | Default |
|----------|-------------|---------|
| $runMode | Execution mode ("Local" or "Automation") | "Local" |
| $enableEmail | Enable/disable email notifications | $false |
| $checkAllSubscriptions | Check all accessible subscriptions | $false |
| $emailFrom | Sender email address | "changeme" |
| $emailTo | Recipient email address | "changeme" |
| $emailSubject | Email subject line | "Azure VMs Without Backup Protection Report" |

## Output

The script provides:
- Summary of total VMs checked
- Backup coverage percentage
- List of VMs without backup protection
- Complete VM backup status table
- Optional email report with detailed findings

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) for details on how to submit pull requests, report issues, and contribute to the project.

## License

This project is licensed under the BSD-3-Clause License - see the [LICENSE](LICENSE) file for details.

## Author

Ed Crotty (ecrotty@edcrotty.com)

## Acknowledgments

- Azure PowerShell team for maintaining the Az modules
- Microsoft Graph team for the email integration capabilities
