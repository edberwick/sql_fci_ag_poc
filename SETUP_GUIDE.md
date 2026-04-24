# SQL Server High Availability Setup - Availability Group POC

This directory contains standalone PowerShell scripts to set up SQL Server 2022 Enterprise with Availability Groups across multiple regions on Azure.

## Prerequisites

- Windows Server 2022 VMs deployed via Terraform
- Administrator access to all VMs
- Network connectivity between all SQL Server instances
- Minimum 2 GB RAM per VM (4 GB recommended)
- Minimum 10 GB disk space per VM

## Scripts Overview

### 1. Install-SQLServer.ps1
Downloads and installs SQL Server 2022 Enterprise Edition on the target VM.

**Usage:**
```powershell
.\Install-SQLServer.ps1
```

**What it does:**
- Downloads SQL Server 2022 installer
- Installs required .NET Framework 3.5
- Installs SQL Server 2022 Enterprise Edition
- Enables TCP/IP protocol
- Configures Mixed Mode Authentication (Windows + SQL)
- Starts SQL Server and SQL Browser services
- Sets services to start automatically

**Credentials:**
- SA Account: sa
- SA Password: P@ssw0rd123!

**Installation Time:** 10-30 minutes

---

### 2. Create-DummyDatabase.ps1
Creates a test database with sample schema and data for AG configuration.

**Usage:**
```powershell
.\Create-DummyDatabase.ps1
```

**What it does:**
- Connects to local SQL Server instance
- Creates database: TestDB_AG
- Sets recovery model to FULL (required for AG)
- Creates 3 sample tables:
  - dbo.Customers
  - dbo.Orders
  - dbo.OrderItems
- Inserts sample data
- Prepares database for Availability Group

**Database Features:**
- Full recovery model (AG requirement)
- Referential integrity with foreign keys
- Sample data for testing replication

---

### 3. Configure-AG.ps1
Configures SQL Server Availability Group across multiple instances.

**Usage:**
```powershell
.\Configure-AG.ps1 `
  -PrimaryServer "vm-sql-uksouth" `
  -SecondaryServers "vm-sql-westeurope", "vm-sql-northeu" `
  -AGName "AG_POC" `
  -DatabaseName "TestDB_AG"
```

**Parameters:**
- **PrimaryServer** (required): Hostname of primary SQL instance
- **SecondaryServers** (required): Array of secondary server hostnames
- **AGName** (optional): Availability Group name (default: AG_POC)
- **DatabaseName** (optional): Database to add to AG (default: TestDB_AG)
- **ListenerName** (optional): AG listener name (default: AG_POC_Listener)
- **ListenerPort** (optional): Listener port (default: 1433)
- **InstanceName** (optional): SQL instance name (default: MSSQLSERVER)

**What it does:**
- Creates database backups (full + transaction log)
- Creates Availability Group with specified replicas
- Configures synchronous commit mode
- Configures automatic failover
- Verifies database synchronization
- Generates useful monitoring queries

---

## Step-by-Step Setup Guide

### Step 1: Prepare All VMs

For each VM (Primary and Secondary replicas):

1. **Connect via RDP/Bastion**
   - Use Azure Bastion to connect to each VM
   - Username: adminuser
   - Password: Password123!

2. **Disable Windows Firewall** (or add rules for SQL ports 1433, 1434)
   ```powershell
   Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled $False
   ```

3. **Download scripts** to each VM
   - Copy all 3 PowerShell scripts to C:\Temp\

---

### Step 2: Install SQL Server on All Nodes

**On each VM (execute as Administrator):**

```powershell
cd C:\Temp
# Right-click PowerShell ISE and select "Run as Administrator"
.\Install-SQLServer.ps1
```

**Wait for completion** (~20-30 minutes per server)

Repeat for all secondary servers.

---

### Step 3: Create Test Database (PRIMARY NODE ONLY)

**On Primary Server only:**

```powershell
cd C:\Temp
.\Create-DummyDatabase.ps1
```

This creates the database that will be replicated to secondary nodes.

---

### Step 4: Create Availability Group (PRIMARY NODE ONLY)

**On Primary Server:**

```powershell
cd C:\Temp
.\Configure-AG.ps1 `
  -PrimaryServer "vm-sql-uksouth" `
  -SecondaryServers "vm-sql-westeurope", "vm-sql-northeu"
```

**Note:** This script must run on the PRIMARY server only. It will:
- Create backups of the database
- Create the Availability Group
- Configure replication

---

### Step 5: Manual Secondary Node Configuration

For each SECONDARY node:

1. **Restore database from backup**
   ```sql
   -- Run on secondary server
   RESTORE DATABASE TestDB_AG 
   FROM DISK = '\\vm-sql-uksouth\c$\SQLBackup\TestDB_AG.bak'
   WITH NORECOVERY, REPLACE
   
   RESTORE LOG TestDB_AG
   FROM DISK = '\\vm-sql-uksouth\c$\SQLBackup\TestDB_AG.trn'
   WITH NORECOVERY
   ```

2. **Join to Availability Group**
   ```sql
   ALTER AVAILABILITY GROUP AG_POC JOIN
   ALTER DATABASE TestDB_AG SET HADR AVAILABILITY GROUP = AG_POC
   ```

---

### Step 6: Verify AG Status (PRIMARY NODE)

```sql
-- Check AG status
SELECT * FROM sys.availability_groups WHERE name = 'AG_POC'

-- Check replica status
SELECT replica_server_name, role_desc, operational_state_desc
FROM sys.dm_hadr_availability_replica_states

-- Check database synchronization
SELECT database_name, synchronization_state_desc, is_failover_ready
FROM sys.dm_hadr_database_replica_states
WHERE database_id = DB_ID('TestDB_AG')
```

---

## Testing Failover

### Manual Failover to Secondary

```sql
-- Run on PRIMARY server
ALTER AVAILABILITY GROUP AG_POC FAILOVER
```

### Forced Failover (if Primary is down)

```sql
-- Run on SECONDARY server to force failover
ALTER AVAILABILITY GROUP AG_POC FAILOVER
```

### Test Read-Only on Secondary

```sql
-- Connection string to secondary with read intent
Server=vm-sql-westeurope;Database=TestDB_AG;ApplicationIntent=ReadOnly
```

---

## Network Configuration

### Firewall Rules Required

On all SQL Server VMs, allow inbound:
- **Port 1433**: SQL Server (TCP)
- **Port 1434**: SQL Browser (UDP)
- **Port 5022**: Database Mirroring (TCP)
- **Port 59999**: AG (TCP) - if not using default AG port

### For Azure

Add NSG inbound rules:
```
- Source: Internal Subnet (10.0.0.0/24, 10.1.0.0/24, etc.)
- Destination Ports: 1433, 1434, 5022
- Protocol: TCP
```

---

## Troubleshooting

### SQL Server won't start
```powershell
# Check service status
Get-Service MSSQLSERVER

# View error logs
Get-Content "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\LOG\ERRORLOG"

# Start service manually
Start-Service MSSQLSERVER
```

### Cannot connect to SQL instance
```powershell
# Verify TCP/IP is enabled
sqlcmd -S SERVER\MSSQLSERVER -U sa -P P@ssw0rd123! -Q "SELECT @@VERSION"

# Check if SQL Browser is running
Get-Service SQLBrowser | Select Status, StartType
```

### Database not synchronizing
```sql
-- Check synchronization state
SELECT database_name, synchronization_state_desc
FROM sys.dm_hadr_database_replica_states

-- Check for suspend reasons
SELECT database_id, suspension_reason_desc
FROM sys.dm_hadr_database_replica_states
WHERE suspension_reason_desc IS NOT NULL
```

### Backup restore fails
- Verify backup file exists on share
- Check file permissions
- Ensure database files don't already exist

---

## Performance Considerations

### VM Size Recommendations
- **Standard_B2s**: Development/POC (current)
- **Standard_D4s_v5**: Production (4 vCPU, 16 GB RAM)
- **Standard_E4s_v5**: Memory optimized (4 vCPU, 32 GB RAM)

### Storage Optimization
- Use **Premium_LRS** for production data files
- Use **Standard_LRS** for backup files
- Consider managed disks with premium tier

### Network Optimization
- Ensure low latency between regions (<50ms)
- Configure ExpressRoute for inter-region traffic
- Monitor replication lag

---

## Useful T-SQL Queries

### Monitor AG Health
```sql
SELECT 
    ag.name as AGName,
    ar.replica_server_name,
    ar.role_desc,
    ars.operational_state_desc,
    ars.connected_state_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
```

### Monitor Database Synchronization
```sql
SELECT 
    ar.replica_server_name,
    db.name as DatabaseName,
    drs.synchronization_state_desc,
    drs.last_hardened_lsn,
    drs.last_received_lsn
FROM sys.availability_replicas ar
JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id
JOIN sys.databases db ON drs.database_id = db.database_id
```

### View AG Listeners
```sql
SELECT listener_ip_address, port, dns_name
FROM sys.availability_group_listeners
```

---

## Cleanup

To remove Availability Group and cleanup:

```sql
-- On PRIMARY: Remove database from AG
ALTER DATABASE TestDB_AG SET HADR OFF

-- On PRIMARY: Drop AG
DROP AVAILABILITY GROUP AG_POC

-- On SECONDARY: Drop standalone database
DROP DATABASE TestDB_AG
```

---

## Support

For issues with:
- **SQL Server Installation**: Check %ProgramFiles%\Microsoft SQL Server\160\Setup Bootstrap\Log\
- **AG Configuration**: Review SQL Server error logs
- **Network Issues**: Check Azure NSG and firewall rules
- **Performance**: Monitor with Extended Events and DMVs

---

## Additional Resources

- [SQL Server Documentation](https://learn.microsoft.com/sql/)
- [Always-On Availability Groups](https://learn.microsoft.com/sql/database-engine/availability-groups/windows/overview-of-always-on-availability-groups-sql-server)
- [PowerShell SMO Reference](https://learn.microsoft.com/sql/powershell/sql-server-powershell)
