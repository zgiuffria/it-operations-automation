README — Get-VBRJobScheduleReport.ps1
======================================

PURPOSE
-------
Get-VBRJobScheduleReport.ps1 collects a read-only inventory of Veeam Backup &
Replication (VBR) jobs and their schedule information from one or more VBR
servers. It creates:

  • A sortable and filterable HTML report (primary report)
  • A CSV export for Excel filtering, sorting, pivot tables, or archival
  • An errors CSV only when one or more VBR servers cannot be queried

The report uses color coding for Site/Location and Job Type. In the HTML report,
you can search, filter by site or job type, and sort by clicking a column header.

IMPORTANT
---------
• Run this only from an authorized administrative workstation or server.
• The script is read-only. It queries Veeam job configuration data; it does not
  create, edit, start, stop, or delete Veeam jobs.
• Querying each VBR server directly is recommended because its configuration
  database is the current authoritative source for its jobs and schedules.
• Test the script against one representative VBR server before running it against
  all sites.
• Follow local access, handling, records, and release procedures for all reports.

PREREQUISITES
-------------
1. The target VBR servers must be reachable from the computer running the script.
2. PowerShell remoting (WinRM) must be enabled and permitted to each target VBR
   server, unless running the script locally on that VBR server.
3. The account used must be authorized to:
   • connect remotely to the VBR servers; and
   • query the installed Veeam Backup PowerShell module and VBR configuration.
4. The Veeam Backup PowerShell module must be installed on each target VBR server.
   It is normally installed with Veeam Backup & Replication.
5. You need write permission to the selected output directory.

FILES
-----
Get-VBRJobScheduleReport.ps1
    The PowerShell collection/reporting script.

Optional server list CSV
    A CSV file with these exact column names:

    VBRServer,Site

    Example:
    PEN000603MV217,Site-PEN
    VBR02,Site-02
    VBR03,Site-03

The Site value is used for location labeling and color coding. If you do not use
a server-list CSV, the script uses each VBR server name as its site label.

QUICK START — SERVER NAMES
--------------------------
Open PowerShell and run:

  .\Get-VBRJobScheduleReport.ps1 `
    -VbrServers VBR01,VBR02,VBR03 `
    -OutputDirectory C:\Reports\Veeam

Replace VBR01, VBR02, and VBR03 with your VBR server names or FQDNs.

RUN WITH ALTERNATE CREDENTIALS
------------------------------
If the logged-on account does not have the required remote/Veeam permissions:

  .\Get-VBRJobScheduleReport.ps1 `
    -VbrServers VBR01,VBR02,VBR03 `
    -OutputDirectory C:\Reports\Veeam `
    -Credential (Get-Credential)

Enter an authorized account when prompted. Do not place passwords in the script,
a command line, or the server-list CSV.

RUN WITH SITE/LOCATION LABELS
-----------------------------
1. Create a CSV file, for example: C:\Reports\VbrServers.csv

2. Add the exact headers and server/site values:

  VBRServer,Site
  PEN000603MV217,Site-PEN
  VBR02,Site-02
  VBR03,Site-03

3. Run:

  .\Get-VBRJobScheduleReport.ps1 `
    -ServerListCsv C:\Reports\VbrServers.csv `
    -OutputDirectory C:\Reports\Veeam `
    -Credential (Get-Credential)

OUTPUTS
-------
The script writes timestamped files into the OutputDirectory:

• VBR-JobScheduleReport_<timestamp>.html
    Open this in a modern browser. Use the search field and Site/Job Type filters.
    Click a column header to sort the report.

• VBR-JobScheduleReport_<timestamp>.csv
    Open in Excel for filtering, sorting, pivot tables, or further analysis.

• VBR-JobScheduleReport_Errors_<timestamp>.csv (only if needed)
    Review this file for servers that could not be reached or queried.

SCHEDULE INFORMATION
--------------------
Veeam job schedule details vary by job family and installed VBR version. The
script captures the schedule information exposed by the installed Veeam
PowerShell API and keeps raw schedule detail available in the report/export for
review. Review job settings directly in VBR when an exact schedule interpretation
is mission-critical.

The script may report job families such as standard backup/replication, backup
copy, SureBackup, tape, Agent policy, and plug-in jobs where their installed
Veeam cmdlets are available.

Protection-group discovery/rescan schedules are separate from Agent backup policy
schedules. Review both when troubleshooting managed-agent backup timing.

TROUBLESHOOTING
---------------
Cannot connect to a VBR server
    • Confirm DNS resolution, network reachability, and WinRM/PowerShell remoting.
    • Confirm the provided account is allowed to remote to the target server.
    • Check the errors CSV for the detailed exception.

Veeam module/cmdlet error
    • Confirm Veeam Backup & Replication and its PowerShell module are installed
      on the target VBR server.
    • Open PowerShell on the target server and verify that Veeam PowerShell
      commands are available under the account used.

Some job types are absent
    • The VBR version may use different cmdlets, or the job family may not be
      installed/configured on that VBR server.
    • Check the CSV and error output, then compare with the VBR console.

HTML report opens but appears incomplete
    • Verify that the CSV has rows for the expected VBR servers.
    • Check the errors CSV for collection failures.
    • Verify you are opening the newest timestamped report.

SECURITY AND OPERATIONS NOTES
-----------------------------
• Do not modify the script to embed passwords, tokens, or other credentials.
• Store reports only in approved locations and apply organizational handling and
  access controls appropriate to the collected environment data.
• Review results for accuracy before using them for scheduling, maintenance, or
  operational decisions.
• The report is an inventory aid; it does not replace VBR-console verification or
  administrator review.
