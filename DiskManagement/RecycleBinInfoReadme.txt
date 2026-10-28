
How to Use the Script:

1. Run the EventViewerSumBypassEP.bat file to initiate the script.
2. Provide the Input:
	• The script will pause and prompt: Enter the number of hours to pull event logs for [Default: 24].
	• Custom Duration: Type a whole number between 1 and 720 (up to 30 days) and press Enter.
	• Quick Launch: Press Enter on a blank line to accept the default of 24 hours.


Technical Breakdown:

1. Initialization and Input Validation

Upon startup, the script presents an interactive command line interface using Read-Host. It checks your entered value using an evaluation routine:
• If blank, it defaults to 24 hours.
• If a number is provided, it verifies it falls inside a safe system threshold (1 to 720 hours).
• Invalid syntax (text strings or out-of-bounds numbers) throws a warning banner and automatically falls back to 24 hours.

2. Workspace and Directory Management

To ensure the script never fails due to missing directory path references, it uses a flexible tracking structure:
• Repository Check: It looks for a project workspace path at ..\..\Reports\CSV relative to the script location.
• User Profile Fallback: If the repository workspace folder structures are not found (or if running from an unsaved memory buffer), it automatically generates an absolute safe-haven export folder in your personal user directory at C:\Users\<username>\Reports\CSV.

3. Optimized Event Log Extraction

Using an optimized query mapping model via Get-WinEvent, the engine connects directly to the local Windows event loop engine. It passes an inline filter hashtable that targets the System and Application logs, filtering for serious severity tiers:
• Level 1: Critical
• Level 2: Error
• Level 3: Warning
• It extracts vital properties: TimeCreated, ThreadId, EventId, ProviderName, and Channel.

4. Deduplication, Chronological Sorting, and Display

• Grouping: The array is passed to Group-Object to cluster identical log footprints together, assigning an operational impact Count to repetitive items.
• Sorting: The grouped entries are evaluated by their raw timestamps and sorted descending so that the absolute newest warnings and errors sit at the very top of your terminal screen.
• Visual Formatting: Enforces clear character layout spacing (35 spaces for the provider, 18 spaces for the log channel) to prevent long system paths from truncating.
• File Export: At completion, it saves two timestamped CSV database reports (EventLogDetails-*.csv and EventLogSummary-*.csv) to your output folder and prints a high-visibility execution banner.
