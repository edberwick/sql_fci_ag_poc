# SQL Server Availability Group Health Check and Verification
# Run on any node to check overall AG status
# Usage: .\Verify-AGHealth.ps1 -PrimaryServer "vm-sql-uksouth"

param(
    [Parameter(Mandatory=$true)]
    [string]$PrimaryServer,
    
    [string]$InstanceName = "MSSQLSERVER",
    [string]$AGName = "AG_POC",
    [string]$DatabaseName = "TestDB_AG"
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Green
Write-Host "SQL Server AG Health Check & Verification" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Load SQL SMO
try {
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Sdk.Sfc") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
} catch {
    Write-Host "ERROR: Failed to load SQL Server assemblies" -ForegroundColor Red
    exit 1
}

# Connect to primary
Write-Host "[1/5] Checking Primary Server Connection..." -ForegroundColor Cyan
try {
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server("$PrimaryServer\$InstanceName")
    $server.ConnectionContext.LoginSecure = $true
    $version = $server.Version
    Write-Host "✓ Connected to $PrimaryServer" -ForegroundColor Green
    Write-Host "  SQL Server Version: $($server.VersionString)" -ForegroundColor Gray
} catch {
    Write-Host "✗ Failed to connect to $PrimaryServer" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check SQL Server Services
Write-Host "`n[2/5] Checking SQL Server Services..." -ForegroundColor Cyan
try {
    $sqlService = Get-Service -Name MSSQLSERVER -ComputerName $PrimaryServer -ErrorAction SilentlyContinue
    $browserService = Get-Service -Name SQLBrowser -ComputerName $PrimaryServer -ErrorAction SilentlyContinue
    
    if ($sqlService.Status -eq "Running") {
        Write-Host "✓ SQL Server Service: Running" -ForegroundColor Green
    } else {
        Write-Host "✗ SQL Server Service: $($sqlService.Status)" -ForegroundColor Red
    }
    
    if ($browserService.Status -eq "Running") {
        Write-Host "✓ SQL Browser Service: Running" -ForegroundColor Green
    } else {
        Write-Host "✗ SQL Browser Service: $($browserService.Status)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "! Could not check services: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Check Availability Group
Write-Host "`n[3/5] Checking Availability Group Configuration..." -ForegroundColor Cyan
try {
    $ag = $server.AvailabilityGroups[$AGName]
    
    if ($ag) {
        Write-Host "✓ Availability Group Found: $($ag.Name)" -ForegroundColor Green
        Write-Host "  Database Count: $($ag.AvailabilityGroupDatabases.Count)" -ForegroundColor Gray
        Write-Host "  Replica Count: $($ag.AvailabilityGroupReplicas.Count)" -ForegroundColor Gray
        
        # List replicas
        foreach ($replica in $ag.AvailabilityGroupReplicas) {
            Write-Host "  - $($replica.Name) (Role: $($replica.Role))" -ForegroundColor Gray
        }
    } else {
        Write-Host "✗ Availability Group Not Found: $AGName" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ Error checking AG: $($_.Exception.Message)" -ForegroundColor Red
}

# Check Database Status
Write-Host "`n[4/5] Checking Database & Synchronization Status..." -ForegroundColor Cyan

$query = @"
SELECT 
    db.name AS DatabaseName,
    ar.replica_server_name AS ReplicaServer,
    ar.role_desc AS Role,
    drs.synchronization_state_desc AS SyncState,
    drs.is_failover_ready AS FailoverReady,
    drs.database_state_desc AS DBState,
    CAST(DATEDIFF(SECOND, last_commit_time, GETDATE()) AS VARCHAR) + ' sec' AS 'TimeBehindPrimary'
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id
JOIN sys.databases db ON drs.database_id = db.database_id
WHERE ag.name = '$AGName'
ORDER BY ar.replica_server_name
"@

try {
    $result = $server.Databases["master"].ExecuteWithResults($query)
    $table = $result.Tables[0]
    
    if ($table.Rows.Count -gt 0) {
        Write-Host "✓ Database Synchronization Status:" -ForegroundColor Green
        
        foreach ($row in $table.Rows) {
            $replica = $row["ReplicaServer"]
            $role = $row["Role"]
            $syncState = $row["SyncState"]
            $failover = $row["FailoverReady"]
            
            $statusIcon = if ($syncState -eq "SYNCHRONIZED") { "✓" } else { "!" }
            Write-Host "  $statusIcon $replica ($role): $syncState" -ForegroundColor Gray
            Write-Host "      Failover Ready: $failover, State: $($row['DBState'])" -ForegroundColor Gray
        }
    } else {
        Write-Host "! No databases found in AG" -ForegroundColor Yellow
    }
} catch {
    Write-Host "! Error checking database status: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Check for Issues
Write-Host "`n[5/5] Checking for Common Issues..." -ForegroundColor Cyan

$issueQuery = @"
SELECT 
    suspension_reason_desc,
    database_id,
    COUNT(*) AS Instances
FROM sys.dm_hadr_database_replica_states
WHERE suspension_reason_desc IS NOT NULL
GROUP BY suspension_reason_desc, database_id
"@

try {
    $result = $server.Databases["master"].ExecuteWithResults($issueQuery)
    $table = $result.Tables[0]
    
    if ($table.Rows.Count -gt 0) {
        Write-Host "! Issues Detected:" -ForegroundColor Red
        foreach ($row in $table.Rows) {
            Write-Host "  - $($row['suspension_reason_desc'])" -ForegroundColor Red
        }
    } else {
        Write-Host "✓ No suspension issues detected" -ForegroundColor Green
    }
} catch {
    Write-Host "! Could not check for issues: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Health Check Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$summaryQuery = @"
SELECT 
    ag.name AS AGName,
    COUNT(DISTINCT ar.replica_id) AS ReplicaCount,
    SUM(CASE WHEN drs.synchronization_state_desc = 'SYNCHRONIZED' THEN 1 ELSE 0 END) AS SynchronizedCount,
    SUM(CASE WHEN drs.is_failover_ready = 1 THEN 1 ELSE 0 END) AS FailoverReadyCount,
    SUM(CASE WHEN drs.database_state_desc = 'ONLINE' THEN 1 ELSE 0 END) AS OnlineCount
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
LEFT JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id
WHERE ag.name = '$AGName'
GROUP BY ag.name
"@

try {
    $result = $server.Databases["master"].ExecuteWithResults($summaryQuery)
    $table = $result.Tables[0]
    
    if ($table.Rows.Count -gt 0) {
        $row = $table.Rows[0]
        Write-Host "AG Name: $($row['AGName'])" -ForegroundColor Cyan
        Write-Host "Total Replicas: $($row['ReplicaCount'])" -ForegroundColor Cyan
        Write-Host "Synchronized: $($row['SynchronizedCount']) / $($row['ReplicaCount'])" -ForegroundColor Cyan
        Write-Host "Failover Ready: $($row['FailoverReadyCount']) / $($row['ReplicaCount'])" -ForegroundColor Cyan
        Write-Host "Online: $($row['OnlineCount']) / $($row['ReplicaCount'])" -ForegroundColor Cyan
        
        if ($row['SynchronizedCount'] -eq $row['ReplicaCount']) {
            Write-Host "`n✓ All replicas are synchronized and ready!" -ForegroundColor Green
        } else {
            Write-Host "`n! Not all replicas are synchronized yet" -ForegroundColor Yellow
            Write-Host "  This is normal during initial setup. Please wait a few minutes." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "! Could not generate summary: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Recommendations
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Recommendations & Next Steps" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nIf all checks passed:" -ForegroundColor Cyan
Write-Host "1. Test failover: ALTER AVAILABILITY GROUP $AGName FAILOVER" -ForegroundColor Gray
Write-Host "2. Test read-only queries on secondary" -ForegroundColor Gray
Write-Host "3. Monitor performance during steady-state replication" -ForegroundColor Gray

Write-Host "`nIf issues detected:" -ForegroundColor Cyan
Write-Host "1. Check SQL Server error logs" -ForegroundColor Gray
Write-Host "2. Verify network connectivity between servers" -ForegroundColor Gray
Write-Host "3. Review firewall rules (ports 1433, 1434, 5022)" -ForegroundColor Gray
Write-Host "4. Ensure database is in FULL recovery model" -ForegroundColor Gray

Write-Host "`nUseful Monitoring Queries:" -ForegroundColor Yellow
Write-Host "`n-- Real-time sync status:" -ForegroundColor Gray
Write-Host "`$query = @'" -ForegroundColor Gray
Write-Host "SELECT ar.replica_server_name, drs.database_name, drs.synchronization_state_desc," -ForegroundColor Gray
Write-Host "       DATEDIFF(SECOND, drs.last_commit_time, GETDATE()) as LagSeconds" -ForegroundColor Gray
Write-Host "FROM sys.availability_replicas ar" -ForegroundColor Gray
Write-Host "JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id" -ForegroundColor Gray
Write-Host "'@" -ForegroundColor Gray

Write-Host "========================================" -ForegroundColor Green
