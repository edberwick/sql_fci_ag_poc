# SQL Server Availability Group Configuration Script
# Run on PRIMARY node - requires cluster and AG prerequisites
# Usage: .\Configure-AG.ps1 -PrimaryServer "vm-sql-uksouth" -SecondaryServers "vm-sql-westeurope", "vm-sql-northeu"

param(
    [Parameter(Mandatory=$true)]
    [string]$PrimaryServer,
    
    [Parameter(Mandatory=$true)]
    [string[]]$SecondaryServers,
    
    [string]$AGName = "AG_POC",
    [string]$DatabaseName = "TestDB_AG",
    [string]$ListenerName = "AG_POC_Listener",
    [int]$ListenerPort = 1433,
    [string]$InstanceName = "MSSQLSERVER",
    [string]$BackupPath = "\\$PrimaryServer\SQLBackup"
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Green
Write-Host "SQL Server Availability Group Setup" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Primary Server: $PrimaryServer" -ForegroundColor Cyan
Write-Host "Secondary Servers: $($SecondaryServers -join ', ')" -ForegroundColor Cyan
Write-Host "AG Name: $AGName" -ForegroundColor Cyan
Write-Host "Database: $DatabaseName" -ForegroundColor Cyan
Write-Host ""

# Load SQL SMO
Write-Host "[1/7] Loading SQL Server Management Objects..." -ForegroundColor Cyan
try {
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Sdk.Sfc") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null
    Write-Host "SQL Server Management Objects loaded" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to load SMO assemblies" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Connect to Primary Server
Write-Host "`n[2/7] Connecting to Primary Server..." -ForegroundColor Cyan
try {
    $primarySvr = New-Object Microsoft.SqlServer.Management.Smo.Server("$PrimaryServer\$InstanceName")
    $primarySvr.ConnectionContext.LoginSecure = $true
    
    # Test connection
    $version = $primarySvr.Version
    Write-Host "Connected to $PrimaryServer - SQL Server $($primarySvr.VersionString)" -ForegroundColor Green
    Write-Host "Edition: $($primarySvr.EngineEdition)" -ForegroundColor Cyan
} catch {
    Write-Host "ERROR: Could not connect to Primary Server $PrimaryServer" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Check database and set FULL recovery
Write-Host "`n[3/7] Checking database configuration..." -ForegroundColor Cyan
try {
    $db = $primarySvr.Databases[$DatabaseName]
    if (-not $db) {
        Write-Host "ERROR: Database '$DatabaseName' not found on $PrimaryServer" -ForegroundColor Red
        Write-Host "Please run Create-DummyDatabase.ps1 first" -ForegroundColor Yellow
        exit 1
    }
    
    if ($db.RecoveryModel -ne [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Full) {
        Write-Host "Setting recovery model to FULL..." -ForegroundColor Gray
        $db.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Full
        $db.Alter()
        Write-Host "Database recovery model set to FULL" -ForegroundColor Green
    } else {
        Write-Host "Database recovery model is already FULL" -ForegroundColor Green
    }
} catch {
    Write-Host "ERROR: Failed to configure database" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create database backup
Write-Host "`n[4/7] Creating database backup..." -ForegroundColor Cyan
try {
    # Ensure backup directory exists
    $backupFile = "C:\SQLBackup\$DatabaseName.bak"
    if (-not (Test-Path "C:\SQLBackup")) {
        New-Item -Path "C:\SQLBackup" -ItemType Directory -Force | Out-Null
        Write-Host "Backup directory created" -ForegroundColor Green
    }
    
    # Create backup
    $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
    $backup.Database = $DatabaseName
    $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Database
    $backup.Devices.AddDevice($backupFile, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
    $backup.SqlBackup($primarySvr)
    
    Write-Host "Database backup created: $backupFile" -ForegroundColor Green
    
    # Create log backup
    $logBackupFile = "C:\SQLBackup\$DatabaseName.trn"
    $logBackup = New-Object Microsoft.SqlServer.Management.Smo.Backup
    $logBackup.Database = $DatabaseName
    $logBackup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Log
    $logBackup.Devices.AddDevice($logBackupFile, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
    $logBackup.SqlBackup($primarySvr)
    
    Write-Host "Transaction log backup created: $logBackupFile" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create backup" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Create Availability Group
Write-Host "`n[5/7] Creating Availability Group..." -ForegroundColor Cyan
try {
    # Check if AG already exists
    $ag = $primarySvr.AvailabilityGroups[$AGName]
    if ($ag) {
        Write-Host "WARNING: Availability Group '$AGName' already exists" -ForegroundColor Yellow
        Write-Host "Skipping AG creation" -ForegroundColor Gray
    } else {
        # Create new AG
        $ag = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroup($primarySvr, $AGName)
        
        # Add database to AG
        $agDb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityGroupDatabase($ag, $DatabaseName)
        $ag.AvailabilityGroupDatabases.Add($agDb)
        
        # Add primary replica
        $primaryReplica = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityReplica($ag, $PrimaryServer)
        $primaryReplica.Role = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaRole]::Primary
        $primaryReplica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::SynchronousCommit
        $primaryReplica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::Automatic
        $ag.AvailabilityGroupReplicas.Add($primaryReplica)
        
        # Add secondary replicas
        foreach ($secondaryServer in $SecondaryServers) {
            Write-Host "Adding secondary replica: $secondaryServer" -ForegroundColor Gray
            $secondaryReplica = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityReplica($ag, $secondaryServer)
            $secondaryReplica.Role = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaRole]::Secondary
            $secondaryReplica.AvailabilityMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaAvailabilityMode]::SynchronousCommit
            $secondaryReplica.FailoverMode = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaFailoverMode]::Automatic
            $ag.AvailabilityGroupReplicas.Add($secondaryReplica)
        }
        
        # Create the AG
        $ag.Create()
        Write-Host "Availability Group '$AGName' created successfully" -ForegroundColor Green
        
        Start-Sleep -Seconds 5
    }
} catch {
    Write-Host "ERROR: Failed to create Availability Group" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Wait and verify AG databases
Write-Host "`n[6/7] Verifying AG database synchronization..." -ForegroundColor Cyan
$maxAttempts = 30
$attempt = 0

do {
    try {
        $ag = $primarySvr.AvailabilityGroups[$AGName]
        if ($ag -and $ag.AvailabilityGroupDatabases.Count -gt 0) {
            $agDb = $ag.AvailabilityGroupDatabases[0]
            $syncState = $agDb.SynchronizationState
            Write-Host "Synchronization State: $syncState" -ForegroundColor Cyan
            
            if ($syncState -eq [Microsoft.SqlServer.Management.Smo.SynchronizationState]::Synchronized) {
                Write-Host "Database is synchronized across all replicas" -ForegroundColor Green
                break
            }
        }
    } catch {
        Write-Host "Waiting for synchronization..." -ForegroundColor Gray
    }
    
    $attempt++
    if ($attempt -lt $maxAttempts) {
        Start-Sleep -Seconds 2
    }
} while ($attempt -lt $maxAttempts)

# Summary
Write-Host "`n[7/7] Availability Group Configuration Complete" -ForegroundColor Cyan

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Availability Group Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "AG Name: $AGName" -ForegroundColor Cyan
Write-Host "Database: $DatabaseName" -ForegroundColor Cyan
Write-Host "Primary Server: $PrimaryServer" -ForegroundColor Cyan
Write-Host "Secondary Servers: $($SecondaryServers -join ', ')" -ForegroundColor Cyan
Write-Host "Synchronization Mode: Synchronous Commit" -ForegroundColor Cyan
Write-Host "Failover Mode: Automatic" -ForegroundColor Cyan

Write-Host "`nNEXT STEPS (Manual Configuration Required):" -ForegroundColor Yellow
Write-Host "1. Configure Availability Group Listener (requires DNS/Load Balancer)" -ForegroundColor Gray
Write-Host "2. Restore database backups on secondary servers" -ForegroundColor Gray
Write-Host "3. Join secondary replicas to the AG" -ForegroundColor Gray
Write-Host "4. Test failover: ALTER AVAILABILITY GROUP $AGName FAILOVER" -ForegroundColor Gray

Write-Host "`nUseful Queries:" -ForegroundColor Yellow
Write-Host "-- View AG status:" -ForegroundColor Gray
Write-Host "SELECT * FROM sys.availability_groups WHERE name = '$AGName'" -ForegroundColor Gray
Write-Host "`n-- View replica status:" -ForegroundColor Gray
Write-Host "SELECT * FROM sys.availability_replicas WHERE availability_group_id = (SELECT group_id FROM sys.availability_groups WHERE name = '$AGName')" -ForegroundColor Gray
Write-Host "`n-- View database state:" -ForegroundColor Gray
Write-Host "SELECT * FROM sys.dm_hadr_database_replica_states WHERE database_id = DB_ID('$DatabaseName')" -ForegroundColor Gray

Write-Host "========================================" -ForegroundColor Green
