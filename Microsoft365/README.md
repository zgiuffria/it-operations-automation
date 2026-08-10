# Microsoft 365 Read-Only Reporting

These scripts use Microsoft Graph PowerShell and request delegated **read-only** scopes. They do not create, update, disable, delete, assign, or revoke tenant objects.

## Setup

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

Run a script and sign in when prompted. The first run may require administrator consent depending on tenant policy and the requested scope.

## Included reports

| Area | Script | Typical scope |
|---|---|---|
| Identity | `Get-M365UserOverview.ps1` | `User.Read.All` |
| Identity | `Get-M365InactiveUsers.ps1` | `User.Read.All`, `AuditLog.Read.All` |
| Licensing | `Get-M365LicenseUtilization.ps1` | `Organization.Read.All`, `Directory.Read.All` |
| Security | `Get-M365MfaRegistrationReport.ps1` | `AuditLog.Read.All` |
| Groups | `Get-M365GroupInventory.ps1` | `Group.Read.All` |
| Security | `Get-M365GuestUserReview.ps1` | `User.Read.All`, `AuditLog.Read.All` |
| Security | `Get-M365DirectoryRoleAssignments.ps1` | `RoleManagement.Read.Directory`, `Directory.Read.All` |
| Exchange | `Get-M365MailboxUsageReport.ps1` | `Reports.Read.All` |
| OneDrive | `Get-M365OneDriveUsageReport.ps1` | `Reports.Read.All` |
| Teams | `Get-M365TeamsUserActivityReport.ps1` | `Reports.Read.All` |

Reports may conceal user or site names depending on Microsoft 365 report privacy settings. Sign-in activity and some advanced reports can require appropriate licensing.
