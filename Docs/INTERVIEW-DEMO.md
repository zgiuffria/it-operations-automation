# Interview Demo Guide

## Best five-minute demonstration

1. Open `Reporting/Network/Get-NetworkHealthReport.ps1`.
2. Show comment-based help and parameter validation.
3. Run it against `SampleData/network-targets.csv`.
4. Open the resulting CSV or HTML report.
5. Explain how you would schedule it, send alerts only on failures, or publish results to a dashboard.

## Microsoft 365 discussion points

- Uses Microsoft Graph instead of retired AzureAD/MSOnline modules.
- Requests delegated least-privilege, read-only scopes.
- Handles Graph paging and returns structured PowerShell objects.
- Exports CSV for Excel, Power BI, ticket attachments, and audit evidence.
- Keeps authentication interactive and never stores credentials or secrets.
- Separates collection logic from presentation so HTML, JSON, or API output can be added later.

## Honest limitations to mention

- Tenant consent and licensing determine which reports are available.
- Large tenants may need throttling/retry enhancements.
- Production scheduling should use certificate-based app authentication and tightly scoped application permissions.
