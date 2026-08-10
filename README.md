# IT Operations Automation Portfolio

A separate, interview-ready PowerShell repository containing practical systems, network, security, and Microsoft 365 reporting tools. The scripts favor safe read-only collection, structured output, clear error handling, and reusable parameters.

## Repository layout

```text
IT-Operations-Automation/
├── Reporting/
│   ├── Network/
│   ├── Certificates/
│   └── EventLogs/
├── Inventory/Windows/
├── Microsoft365/
│   ├── Identity/
│   ├── Licensing/
│   ├── Security/
│   ├── Groups/
│   ├── Exchange/
│   ├── OneDrive/
│   └── Teams/
├── SampleData/
├── Reports/
├── Docs/
├── Tests/
└── .github/workflows/
```

## Included tools

### Core IT operations

- Network health reporting with DNS, ICMP, and TCP checks
- TLS certificate expiration monitoring
- Windows event-log summaries
- Windows server inventory

### Microsoft 365 read-only reports

- User overview
- Inactive-user review
- License utilization
- MFA registration status
- Group inventory and member counts
- Guest-user review
- Directory-role assignments
- Exchange mailbox usage
- OneDrive usage
- Teams user activity

See [`Microsoft365/README.md`](Microsoft365/README.md) for scopes and setup.

## Quick start

```powershell
Set-ExecutionPolicy -Scope Process Bypass

.\Reporting\Network\Get-NetworkHealthReport.ps1 `
    -InputCsv .\SampleData\network-targets.csv

.\Inventory\Windows\Get-WindowsServerInventory.ps1 `
    -ComputerName $env:COMPUTERNAME

Install-Module Microsoft.Graph -Scope CurrentUser
.\Microsoft365\Licensing\Get-M365LicenseUtilization.ps1 -Verbose
```

## Quality improvements included

- Comment-based `Get-Help` support
- Parameter validation
- Strict mode and terminating error behavior
- Verbose diagnostic output where appropriate
- Per-target error handling in operational collectors
- Structured objects and CSV/HTML output
- Relative paths based on `$PSScriptRoot`
- PSScriptAnalyzer GitHub Actions workflow
- Pester repository smoke tests
- Interview demo guide
- Sample input files and report folders

## Safety

Test against systems and tenants you are authorized to access. Microsoft 365 scripts in this repository are reporting-only, but the data they return may still be sensitive and should be protected accordingly.

## License

MIT
