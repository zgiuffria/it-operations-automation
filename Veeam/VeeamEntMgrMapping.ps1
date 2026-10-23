# --- CONFIGURATION ---
$EntMgrServer = "://yourdomain.com"
$Username     = "YOURDOMAIN\BackupAdmin"
$Password     = "YourSecurePassword"
# ---------------------

<#
.SYNOPSIS
    Global Veeam Enterprise Manager Infrastructure Inventory Map.
.DESCRIPTION
    Queries the Veeam Enterprise Manager REST API to generate a consolidated, 
    global host mapping inventory across all connected VBR backup servers.
.NOTES
    - How to use: Fill in your server FQDN/IP, API user, and password in the configuration block.
    - Requirements: Run from any Windows PowerShell host with HTTPS network access to Enterprise Manager.
    - Security: Bypasses self-signed SSL alerts natively and cleanly terminates the API session.
#>

# Bypass self-signed SSL alerts
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type "public class TrustAll : System.Net.ICertificatePolicy { public bool CheckValidationResult(System.Net.ServicePoint s, System.Security.Cryptography.X509Certificates.X509Certificate c, System.Net.WebRequest r, int p) { return true; } }"
[Net.ServicePointManager]::CertificatePolicy = New-Object TrustAll

$BaseUri = "https://$($EntMgrServer):9399/api"
$EncodedCredentials = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$Username:$Password"))

# Authenticate
$SessionResponse = Invoke-WebRequest -Uri "$BaseUri/sessionMngr" -Method Post -Headers @{"Authorization" = "Basic $EncodedCredentials"; "Accept" = "application/json"} -Body ""
$Headers = @{"X-RestSvcSessionId" = $SessionResponse.Headers["X-RestSvcSessionId"]; "Accept" = "application/json"}

Write-Host "Querying all managed infrastructure hosts..." -ForegroundColor Cyan

# Fetch all infrastructure components tracked across ALL connected backup servers
$ManagedServers = Invoke-RestMethod -Uri "$BaseUri/managedServers" -Method Get -Headers $Headers

$GlobalMap = @()
foreach ($Server in $ManagedServers.Refs) {
    $ServerData = Invoke-RestMethod -Uri $Server.Href -Method Get -Headers $Headers
    $GlobalMap += [PSCustomObject]@{
        "VBR Parent Instance" = $ServerData.BackupServerName
        "Component Hostname"  = $ServerData.Name
        "OS / Platform Type"  = $ServerData.Type
        "Description"         = $ServerData.Description
    }
}

# Display your centralized inventory map
$GlobalMap | Out-GridView -Title "Global Enterprise Manager Infrastructure Map"

# Cleanup Session
Invoke-WebRequest -Uri "$BaseUri/sessionMngr" -Method Delete -Headers $Headers -ErrorAction SilentlyContinue
