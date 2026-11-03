# Veeam v13 Windows infrastructure auditor

## Prerequisites
- Windows PowerShell 5.1 on a Windows management host with the Veeam Backup & Replication v13 console/PowerShell module installed.
- Access to each VBR server (typically HTTPS 443 for Veeam PowerShell connection), and permissions to read infrastructure.
- Optional Enterprise Manager REST API over HTTPS 9398 with trusted certificate and an account permitted to use the REST API.
- Optional PowerShell remoting / WinRM to each VBR server for *non-authoritative* database registry hints.

## Usage
```powershell
.\Invoke-VeeamInfrastructureAudit.ps1 -EnterpriseManager em.example.com
.\Invoke-VeeamInfrastructureAudit.ps1 -ServerCsv .\vbr-servers-example.csv -OutputDirectory C:\Reports\Veeam
.\Invoke-VeeamInfrastructureAudit.ps1 -ServerCsv .\vbr-servers-example.csv -InspectDatabaseViaPSRemoting
```

The script prompts for credentials. Never put passwords in source code. Certificates are validated normally. The tool only queries data and disconnects sessions.

## Reports
Timestamped folder containing `summary.csv`, `components.csv`, `issues.csv`, `report.html`.

## Caveats
- The optional registry database probe is a *hint*, not an authoritative SQL/PostgreSQL discovery method. `Not inspected` is the default.
- Some VBR cmdlets may differ by installed build/license. Individual failures are captured in `issues.csv` and result in `Partial` status.
- Inventory completeness status does not mean backup health. No backup jobs or repository scans are started.
- Test with one VBR first. The script has not been executed against a live Veeam v13 environment here.
