# --- CONFIGURATION ---
$EntMgrServer = "://yourdomain.com"
$Username     = "YOURDOMAIN\BackupAdmin"
$Password     = "YourSecurePassword"
# ---------------------

<#
.SYNOPSIS
    Global Enterprise Manager Component Architecture Auditor.
.DESCRIPTION
    Queries the central Enterprise Manager API to discover all connected VBR parent servers, 
    then iterates through each backup server's internal registry to catalog their respective 
    proxies, repositories, and active backend SQL/PostgreSQL databases.
.NOTES
    - How to use: Provide Enterprise Manager connection details in the configuration block.
    - Requirements: Run from any Windows management host with HTTPS network access to Enterprise Manager.
    - Security: Natively handles self-signed SSL certificate validations.
#>

# Bypass self-signed SSL alerts
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type "public class TrustAll : System.Net.ICertificatePolicy { public bool CheckValidationResult(System.Net.ServicePoint s, System.Security.Cryptography.X509Certificates.X509Certificate c, System.Net.WebRequest r, int p) { return true; } }"
[Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll

$BaseUri = "https://$($EntMgrServer):9399/api"
$EncodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$Username:$Password"))

# Authenticate against Enterprise Manager API
$SessionResponse = Invoke-WebRequest -Uri "$BaseUri/sessionMngr" -Method Post -Headers @{"Authorization" = "Basic $EncodedCredentials"; "Accept" = "application/json"} -Body ""
$Headers = @{"X-RestSvcSessionId" = $SessionResponse.Headers["X-RestSvcSessionId"]; "Accept" = "application/json"}

Write-Host "Querying global managed infrastructure architecture..." -ForegroundColor Cyan

# Fetch all primary Backup Servers registered in Enterprise Manager
$BackupServers = Invoke-RestMethod -Uri "$BaseUri/backupServers" -Method Get -Headers $Headers
$FullArchitectureReport = @()

foreach ($VBR in $BackupServers.Refs) {
    $VBRData = Invoke-RestMethod -Uri $VBR.Href -Method Get -Headers $Headers
    $VBRName = $VBRData.Name
    
    # Establish a remote CIM session to query the individual VBR server's system parameters
    try {
        $RegPath = "SOFTWARE\Veeam\Veeam Backup and Replication"
        $CimSession = New-CimSession -ComputerName $VBRName -ErrorAction Stop
        
        # 1. Pull the Backend Database configuration properties
        $SqlHost = (Get-CimInstance -ClassName Win32_Registry -Namespace root\default -MethodName GetStringValue -Arguments @{hDefKey=2147483650; sSubKeyName=$RegPath; sValueName="SqlServerName"} -CimSession $CimSession).sValue
        $SqlInst = (Get-CimInstance -ClassName Win32_Registry -Namespace root\default -MethodName GetStringValue -Arguments @{hDefKey=2147483650; sSubKeyName=$RegPath; sValueName="SqlInstanceName"} -CimSession $CimSession).sValue
        $SqlDb   = (Get-CimInstance -ClassName Win32_Registry -Namespace root\default -MethodName GetStringValue -Arguments @{hDefKey=2147483650; sSubKeyName=$RegPath; sValueName="SqlDatabaseName"} -CimSession $CimSession).sValue
        $FullDBString = "$SqlHost\$SqlInst ($SqlDb)"
        
        Remove-CimSession $CimSession
    } catch {
        $FullDBString = "Unable to query remotely (Check Permissions/WMI)"
    }

    # 2. Extract Proxies bound to this parent backup server via API paths
    $ProxiesUri = "$($VBR.Href)/proxies"
    $ProxiesData = Invoke-RestMethod -Uri $ProxiesUri -Method Get -Headers $Headers -ErrorAction SilentlyContinue
    
    # 3. Extract Repositories bound to this parent backup server via API paths
    $ReposUri = "$($VBR.Href)/repositories"
    $ReposData = Invoke-RestMethod -Uri $ReposUri -Method Get -Headers $Headers -ErrorAction SilentlyContinue

    # Consolidate and cross-reference infrastructure nodes
    $ProxyList = ($ProxiesData.Refs.Name) -join ", "
    if (-not $ProxyList) { $ProxyList = "None Configured" }

    foreach ($Repo in $ReposData.Refs) {
        $FullArchitectureReport += [PSCustomObject]@{
            "Veeam VBR Server"   = $VBRName
            "Backend DB Engine"  = $FullDBString
            "Backup Proxies"     = $ProxyList
            "Backup Repository"  = $Repo.Name
        }
    }
}

# Display your centralized inventory map layout
$FullArchitectureReport | Out-GridView -Title "Global Veeam Infrastructure Topology Map"

# Clean up API Web Session
Invoke-WebRequest -Uri "$BaseUri/sessionMngr" -Method Delete -Headers $Headers -ErrorAction SilentlyContinue
