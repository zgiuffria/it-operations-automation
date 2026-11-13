# Veeam v13 Database Configuration Inspector
# Read-only registry inspection

$Path = 'HKLM:\SOFTWARE\Veeam\Veeam Backup and Replication'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "Veeam registry path not found: $Path"
    return
}

try {
    $Registry = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop

    $Properties = @(
        'SqlServerName'
        'SqlInstanceName'
        'SqlDatabaseName'
        'PostgreSqlHost'
        'PostgreSqlPort'
        'PostgreSqlDatabase'
    )

    $Results = foreach ($Property in $Properties) {
        $Value = $Registry.PSObject.Properties[$Property]

        if ($null -ne $Value -and
            $null -ne $Value.Value -and
            "$($Value.Value)".Trim()) {

            [PSCustomObject]@{
                ComputerName = $env:COMPUTERNAME
                RegistryPath = $Path
                PropertyName = $Property
                Value        = $Value.Value
            }
        }
    }

    if ($Results) {
        $Results | Format-Table -AutoSize
    }
    else {
        Write-Warning 'No recognized database configuration values were found.'
    }
}
catch {
    Write-Error "Registry inspection failed: $($_.Exception.Message)"
}
