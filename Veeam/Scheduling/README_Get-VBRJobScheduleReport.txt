README — Get-VBRJobScheduleReport.ps1
=========================================

PURPOSE
-------
Get-VBRJobScheduleReport_v2.ps1 creates a read-only inventory of Veeam Backup
& Replication (VBR) jobs and their schedule information. It produces:

  * A sortable/filterable HTML report (primary report)
  * A CSV export for Excel filtering, sorting, pivot tables, or archival
  * An errors CSV only when a requested VBR server cannot be queried

The HTML report supports free-text search, Site and Job Type filtering, and
column sorting. Site/Location and Job Type use independent color coding.

IMPORTANT
---------
* Run only from an authorized administrative workstation or VBR server.
* The script is read-only. It queries Veeam job configuration; it does not
  create, edit, start, stop, or delete Veeam jobs.
* Run VBR queries directly against each VBR server because that server's
  configuration database is the current source for its job definitions.
* Test against one representative VBR server before using it at all sites.
* Follow organizational access, handling, records, and release procedures.

PREREQUISITES
-------------
All modes
  1. Run under an account authorized to read Veeam configuration on the VBR
     server being queried.
  2. The Veeam Backup PowerShell module must be installed on each target VBR
     server (normally installed with Veeam Backup & Replication).
  3. The VBR Backup Service and its configuration database must be available.
  4. You need write permission to OutputDirectory.

Remote modes: -VbrServers or -ServerListCsv
  1. Each target must be reachable from the computer running the script.
  2. WinRM/PowerShell remoting must be enabled and authorized for the account.
  3. Optional -Credential is used for the remote PowerShell session.

Local mode: -LocalOnly
  1. Copy the script to the VBR server.
  2. Log on using an account authorized to query the local Veeam installation.
  3. No WinRM permission is required because no remote session is made.

USAGE — RECOMMENDED WHEN WINRM IS DENIED
----------------------------------------
Copy the script to the VBR server, open PowerShell on that server, and run:

  cd C:	emp
  .
Get-VBRJobScheduleReport_v2.ps1 -LocalOnly -OutputDirectory C:
eportsackup

To apply a meaningful site label rather than the local computer name:

  .
Get-VBRJobScheduleReport_v2.ps1 -LocalOnly -LocalSite Site-GRL -OutputDirectory C:
eportsackup

IMPORTANT: The command must remain on one line unless you deliberately use the
PowerShell line-continuation character (backtick) at the end of preceding lines.

USAGE — REMOTE COLLECTION BY SERVER NAME
----------------------------------------
Run from an authorized administration system:

  .
Get-VBRJobScheduleReport_v2.ps1 -VbrServers VBR01,VBR02,VBR03 -OutputDirectory C:
eportsackup

With alternate credentials:

  .
Get-VBRJobScheduleReport_v2.ps1 -VbrServers VBR01,VBR02,VBR03 -OutputDirectory C:
eportsackup -Credential (Get-Credential)

USAGE — REMOTE COLLECTION WITH SITE LABELS
------------------------------------------
Create a CSV, for example C:
eportsackup
eportrange.csv, with exactly these
headers:

  VBRServer,Site
  GRL003400MV217,Site-GRL
  PEN000603MV217,Site-PEN
  VBR03,Site-03

Then run:

  .
Get-VBRJobScheduleReport_v2.ps1 -ServerListCsv C:
eportsackup
eportrange.csv -OutputDirectory C:
eportsackup -Credential (Get-Credential)

OUTPUTS
-------
The script creates timestamped files in OutputDirectory:

  VBR_Job_Schedules_<timestamp>.html
      Open in a modern browser. Search, filter by Site/Job Type, and click a
      column heading to sort.

  VBR_Job_Schedules_<timestamp>.csv
      Open in Excel for filtering, sorting, pivot tables, or further analysis.

  VBR_Job_Schedule_Collection_Errors_<timestamp>.csv
      Created only if one or more VBR servers could not be collected.

TROUBLESHOOTING
---------------
"Access is denied" from Invoke-Command / Enter-PSSession
  This is a remote PowerShell authorization problem. The script has not queried
  Veeam on that target. Either obtain authorized WinRM/PowerShell remoting access
  or copy the script to the VBR server and use -LocalOnly.

"The property 'Site' cannot be found"
  Use this version 2 script. It normalizes every target into a VBRServer, Site,
and CollectionMode object before collection.

Local-only mode reports a Veeam module/cmdlet error
  Confirm you are actually on a VBR server and that the Veeam Backup PowerShell
  module is installed. Also check that the Veeam Backup Service and its SQL
  configuration database are healthy.

Report is empty or incomplete
  Review the errors CSV. For a local run, confirm Veeam PowerShell cmdlets work
  under the account executing the script. For remote runs, first test the exact
  remote session with:

  Enter-PSSession -ComputerName VBR01 -Credential (Get-Credential)

Some job types are not present
  Job cmdlets vary by VBR release and installed components. Compare results with
the local VBR console and review whether the applicable job family is installed.

SCHEDULE NOTES
--------------
The Veeam PowerShell API can expose schedule properties differently across job
families and VBR versions. The script records the schedule information returned
by the locally installed API and exposes raw schedule detail through the HTML
report and CSV. Confirm critical schedules directly in VBR.

Protection-group discovery/rescan schedules are separate from Veeam Agent backup
policy schedules. Review both when diagnosing endpoint backup timing.

SECURITY NOTES
--------------
* Do not place passwords, tokens, or credentials in the script, command line,
  or server-list CSV.
* Store the generated reports only in approved locations.
* Review output before using it for scheduling, maintenance, or operations.
* Sign the script after final review if organizational policy requires it. Any
  modification after signing invalidates the signature.
