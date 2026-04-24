# SQL Server AG Setup - Quick Reference

## Scripts Summary

| Script | Run On | Purpose | Time |
|--------|--------|---------|------|
| **Install-SQLServer.ps1** | Each VM (all 3) | Install SQL Server 2022 Enterprise using config file | 20-30 min |
| **Create-DummyDatabase.ps1** | Primary Only | Create test DB with sample data | 2-3 min |
| **Configure-AG.ps1** | Primary Only | Create AG and configure replication | 5-10 min |
| **Configure-Secondary-Node.ps1** | Each Secondary | Restore DB and join AG | 5-10 min per node |
| **Verify-AGHealth.ps1** | Any Node | Verify AG health and sync status | 1 min |

---

## Execution Order

### Phase 1: Installation (Parallel - ~30 min)
```
On VM1 (uksouth):
  .\Install-SQLServer.ps1

On VM2 (westeurope):
  .\Install-SQLServer.ps1

On VM3 (northeu):
  .\Install-SQLServer.ps1
```

### Phase 2: Database & AG Setup (Primary Only - ~10 min)
```
On VM1 (Primary - uksouth):
  .\Create-DummyDatabase.ps1
  .\Configure-AG.ps1 -PrimaryServer "vm-sql-uksouth" `
                     -SecondaryServers "vm-sql-westeurope", "vm-sql-northeu"
```

### Phase 3: Secondary Configuration (Sequential - ~15 min)
```
On VM2 (uksouth):
  .\Configure-Secondary-Node.ps1 -PrimaryServer "vm-sql-uksouth"

On VM3 (northeu):
  .\Configure-Secondary-Node.ps1 -PrimaryServer "vm-sql-uksouth"
```

### Phase 4: Verification (~2 min)
```
On Any VM:
  .\Verify-AGHealth.ps1 -PrimaryServer "vm-sql-uksouth"
```

---

## Credentials

```
SQL SA Account:
  Username: sa
  Password: P@ssw0rd123!

RDP/Bastion:
  Username: adminuser
  Password: Password123!
```

---

## Key Configuration Details

### SQL Server
- **Version**: 2022 Enterprise Edition
- **Instance**: MSSQLSERVER (default)
- **Authentication**: Mixed (Windows + SQL)
- **TCP/IP**: Enabled
- **Port**: 1433

### Database
- **Name**: TestDB_AG
- **Recovery Model**: FULL
- **Tables**: Customers, Orders, OrderItems
- **Sample Records**: 12+ rows

### Availability Group
- **Name**: AG_POC
- **Synchronization**: Synchronous Commit
- **Failover Mode**: Automatic
- **Replicas**: 3 (Primary + 2 Secondary)
- **Backup Path**: \\vm-sql-uksouth\SQLBackup

---

## Common Commands

### Check AG Status (SQL Server)
```sql
-- All replicas and their roles
SELECT replica_server_name, role_desc, operational_state_desc
FROM sys.dm_hadr_availability_replica_states

-- Database sync status
SELECT database_name, synchronization_state_desc, is_failover_ready
FROM sys.dm_hadr_database_replica_states
WHERE database_name = 'TestDB_AG'

-- Full AG details
SELECT * FROM sys.availability_groups
SELECT * FROM sys.availability_group_listeners
```

### Test Failover
```sql
-- Failover from primary to secondary
ALTER AVAILABILITY GROUP AG_POC FAILOVER
```

### Monitor Replication Lag
```sql
SELECT replica_server_name, database_name,
       DATEDIFF(SECOND, last_commit_time, GETDATE()) as LagSeconds
FROM sys.dm_hadr_database_replica_states
```

### Read from Secondary (Connection String)
```
Server=vm-sql-westeurope;Database=TestDB_AG;ApplicationIntent=ReadOnly
```

---

## Required Network Rules (NSG/Firewall)

**Inbound (on all SQL VMs):**
- Source: 10.0.0.0/24, 10.1.0.0/24, 10.2.0.0/24 (or appropriate subnets)
- Destination Ports:
  - 1433 (SQL Server)
  - 1434 (SQL Browser)
  - 5022 (Mirroring/AG)
- Protocol: TCP

---

## Troubleshooting Quick Tips

| Issue | Solution |
|-------|----------|
| SQL Server won't start | Check error logs at `C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\LOG\ERRORLOG` |
| Can't connect to instance | Verify TCP/IP is enabled and SQL Browser is running |
| AG not synchronizing | Check network connectivity, firewall rules, recovery model |
| Secondary database in RESTORING | Run `ALTER DATABASE TestDB_AG SET HADR AVAILABILITY GROUP = AG_POC` |
| Failover fails | Ensure all replicas are synchronized and online |

---

## Performance Monitoring

### Queries to Monitor
```sql
-- Real-time replication metrics
SELECT ar.replica_server_name, 
       drs.database_name,
       drs.synchronization_state_desc,
       DATEDIFF(SECOND, drs.last_commit_time, GETDATE()) as LagSec
FROM sys.availability_replicas ar
JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id

-- Check for errors
SELECT * FROM sys.dm_hadr_database_replica_states 
WHERE suspension_reason_desc IS NOT NULL

-- View AG listener configuration
SELECT listener_ip_address, port, dns_name 
FROM sys.availability_group_listeners
```

---

## Total Setup Time

| Phase | Duration |
|-------|----------|
| SQL Server Installation (parallel) | ~30 min |
| Database Creation | ~3 min |
| AG Configuration | ~5 min |
| Secondary Configuration (per node) | ~5-10 min |
| Synchronization wait | ~5-10 min |
| **Total** | **~60-75 min** |

---

## Cleanup

If you need to restart:
```sql
-- On PRIMARY
ALTER DATABASE TestDB_AG SET HADR OFF
DROP AVAILABILITY GROUP AG_POC

-- On SECONDARY
DROP DATABASE TestDB_AG
```

---

## Support Resources

- SQL Server Logs: `C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\LOG\`
- PowerShell Help: `Get-Help .\Configure-AG.ps1 -Full`
- Microsoft Docs: https://learn.microsoft.com/sql/database-engine/availability-groups/windows/
