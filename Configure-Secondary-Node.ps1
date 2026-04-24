# SQL Server Secondary Node Configuration for Availability Group
# Run on SECONDARY nodes AFTER primary has created the AG
# Usage: .\Configure-Secondary-Node.ps1 -PrimaryServer "vm-sql-uksouth" -DatabaseName "TestDB_AG" -AGName "AG_POC"

param(
    [Parameter(Mandatory=$true)]
    [string]$PrimaryServer,
    
    [Parameter(Mandatory=$true)]
    [string]$DatabaseName = "TestDB_AG",
    
    [string]$AGName = "AG_POC",
    [string]$InstanceName = "MSSQLSERVER",
    [string]$BackupShare = "\\$PrimaryServer\SQLBackup"
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Green
Write-Host "SQL Server Secondary Node Configuration" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Primary Server: $PrimaryServer" -ForegroundColor Cyan
Write-Host "Local Instance: $env:COMPUTERNAME\$InstanceName" -ForegroundColor Cyan
Write-Host "AG Name: $AGName" -ForegroundColor Cyan
Write-Host "Database: $DatabaseName" -ForegroundColor Cyan
Write-Host ""

# Load SQL SMO
Write-Host "[1/4] Loading SQL Server Management Objects..." -ForegroundColor Cyan
try {
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Sdk.Sfc") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
    Write-Host "SQL Server Management Objects loaded" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to load SMO assemblies" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Connect to local SQL instance
Write-Host "`n[2/4] Connecting to local SQL instance..." -ForegroundColor Cyan
try {
    $secondarySvr = New-Object Microsoft.SqlServer.Management.Smo.Server("$env:COMPUTERNAME\$InstanceName")
    $secondarySvr.ConnectionContext.LoginSecure = $true
    
    # Test connection
    $version = $secondarySvr.Version
    Write-Host "Connected to $env:COMPUTERNAME\$InstanceName - SQL Server $($secondarySvr.VersionString)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Could not connect to local SQL instance" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Restore database
Write-Host "`n[3/4] Restoring database from primary backup..." -ForegroundColor Cyan

$backupFile = "$BackupShare\$DatabaseName.bak"
$logBackupFile = "$BackupShare\$DatabaseName.trn"

Write-Host "Backup Location: $backupFile" -ForegroundColor Gray

try {
    # Check if database already exists
    $existingDb = $secondarySvr.Databases[$DatabaseName]
    if ($existingDb) {
        Write-Host "WARNING: Database '$DatabaseName' already exists on this server" -ForegroundColor Yellow
        Write-Host "Dropping existing database..." -ForegroundColor Gray
        
        # Drop database
        $secondarySvr.KillDatabase($DatabaseName)
        Write-Host "Existing database dropped" -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
    
    # Restore database from backup with NORECOVERY for AG
    Write-Host "Restoring database with NORECOVERY (AG mode)..." -ForegroundColor Gray
    
    $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
    $restore.Database = $DatabaseName
    $restore.Action = [Microsoft.SqlServer.Management.Smo.RestoreActionType]::Database
    $restore.NoRecovery = $true
    $restore.ReplaceDatabase = $true
    $restore.Devices.AddDevice($backupFile, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
    
    $restore.SqlRestore($secondarySvr)
    Write-Host "Database restored successfully" -ForegroundColor Green
    
    # Restore transaction log with NORECOVERY
    Write-Host "Restoring transaction log..." -ForegroundColor Gray
    
    $logRestore = New-Object Microsoft.SqlServer.Management.Smo.Restore
    $logRestore.Database = $DatabaseName
    $logRestore.Action = [Microsoft.SqlServer.Management.Smo.RestoreActionType]::Log
    $logRestore.NoRecovery = $true
    $logRestore.Devices.AddDevice($logBackupFile, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
    
    $logRestore.SqlRestore($secondarySvr)
    Write-Host "Transaction log restored successfully" -ForegroundColor Green
    
} catch {
    Write-Host "ERROR: Failed to restore database" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nTroubleshooting:" -ForegroundColor Yellow
    Write-Host "- Verify backup files exist at: $BackupShare" -ForegroundColor Gray
    Write-Host "- Verify network access to primary server: $PrimaryServer" -ForegroundColor Gray
    Write-Host "- Check SQL Server error logs for details" -ForegroundColor Gray
    exit 1
}

# Join to Availability Group
Write-Host "`n[4/4] Joining database to Availability Group..." -ForegroundColor Cyan

try {
    $joinQuery = @"
    ALTER AVAILABILITY GROUP [$AGName] JOIN;
    GO
    ALTER DATABASE [$DatabaseName] SET HADR AVAILABILITY GROUP = [$AGName];
    GO
"@
    
    Write-Host "Executing AG join commands..." -ForegroundColor Gray
    $secondarySvr.ExecuteNonQuery($joinQuery)
    
    Write-Host "Database successfully joined to Availability Group" -ForegroundColor Green
    
    # Wait for synchronization
    Write-Host "Waiting for database synchronization..." -ForegroundColor Gray
    Start-Sleep -Seconds 10
    
} catch {
    Write-Host "ERROR: Failed to join AG" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "`nNote: This may be normal if database is still in RESTORING state" -ForegroundColor Yellow
    Write-Host "Run the following queries manually when ready:" -ForegroundColor Yellow
    Write-Host "  ALTER AVAILABILITY GROUP [$AGName] JOIN" -ForegroundColor Gray
    Write-Host "  ALTER DATABASE [$DatabaseName] SET HADR AVAILABILITY GROUP = [$AGName]" -ForegroundColor Gray
}

# Verification
Write-Host "`n[+] Verifying configuration..." -ForegroundColor Cyan

try {
    $db = $secondarySvr.Databases[$DatabaseName]
    if ($db) {
        Write-Host "Database Status:" -ForegroundColor Green
        Write-Host "  - Name: $($db.Name)" -ForegroundColor Cyan
        Write-Host "  - State: $($db.State)" -ForegroundColor Cyan
        Write-Host "  - Recovery Model: $($db.RecoveryModel)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "WARNING: Could not verify database status: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Secondary Node Configuration Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Server: $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "Instance: $InstanceName" -ForegroundColor Cyan
Write-Host "Database: $DatabaseName" -ForegroundColor Cyan
Write-Host "AG Name: $AGName" -ForegroundColor Cyan

Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Repeat this script on each secondary server" -ForegroundColor Gray
Write-Host "2. On PRIMARY server, verify AG status:" -ForegroundColor Gray
Write-Host "   SELECT * FROM sys.dm_hadr_availability_replica_states" -ForegroundColor Gray
Write-Host "3. Check database synchronization:" -ForegroundColor Gray
Write-Host "   SELECT database_name, synchronization_state_desc FROM sys.dm_hadr_database_replica_states" -ForegroundColor Gray
Write-Host "4. Test failover when all replicas are synchronized" -ForegroundColor Gray

Write-Host "`nUseful Commands:" -ForegroundColor Yellow
Write-Host "-- Check current server role:" -ForegroundColor Gray
Write-Host "SELECT @@SERVERNAME AS ServerName, SERVERPROPERTY('MachineName') AS MachineName" -ForegroundColor Gray
Write-Host "`n-- Check database AG status:" -ForegroundColor Gray
Write-Host "SELECT database_name, replica_role_desc, synchronization_state_desc FROM sys.dm_hadr_database_replica_states WHERE database_name = '$DatabaseName'" -ForegroundColor Gray

Write-Host "========================================" -ForegroundColor Green
