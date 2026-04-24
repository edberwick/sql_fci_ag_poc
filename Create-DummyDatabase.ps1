# SQL Server Dummy Database Creation Script for AG Testing
# Run as Administrator on the PRIMARY SQL Server
# Usage: .\Create-DummyDatabase.ps1

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# Configuration
$ServerName = $env:COMPUTERNAME
$InstanceName = "MSSQLSERVER"
$DatabaseName = "TestDB_AG"
$DataPath = "C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\"
$SAPassword = "P@ssw0rd123!"

Write-Host "========================================" -ForegroundColor Green
Write-Host "SQL Server Test Database Creation" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Server: $ServerName" -ForegroundColor Cyan
Write-Host "Instance: $InstanceName" -ForegroundColor Cyan
Write-Host "Database: $DatabaseName" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check SQL Server connectivity
Write-Host "[1/5] Checking SQL Server connectivity..." -ForegroundColor Cyan
try {
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.Sdk.Sfc") | Out-Null
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
    
    $server = New-Object Microsoft.SqlServer.Management.Smo.Server("$ServerName\$InstanceName")
    $server.ConnectionContext.LoginSecure = $true
    
    # Test connection
    $version = $server.Version
    Write-Host "Connected to SQL Server $($server.VersionString)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Could not connect to SQL Server" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure SQL Server is running and accessible" -ForegroundColor Yellow
    exit 1
}

# Step 2: Check if database already exists
Write-Host "`n[2/5] Checking if database exists..." -ForegroundColor Cyan
$database = $server.Databases[$DatabaseName]

if ($database) {
    Write-Host "Database '$DatabaseName' already exists" -ForegroundColor Yellow
    Write-Host "Recreating it for AG testing..." -ForegroundColor Gray
    
    try {
        $server.KillDatabase($DatabaseName)
        Write-Host "Database dropped successfully" -ForegroundColor Green
        Start-Sleep -Seconds 2
    } catch {
        Write-Host "WARNING: Could not drop existing database: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "Database '$DatabaseName' does not exist" -ForegroundColor Green
}

# Step 3: Create the database
Write-Host "`n[3/5] Creating database '$DatabaseName'..." -ForegroundColor Cyan
try {
    $database = New-Object Microsoft.SqlServer.Management.Smo.Database($server, $DatabaseName)
    $database.Create()
    Write-Host "Database created successfully" -ForegroundColor Green
    
    # Set recovery model to FULL for AG
    $database.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Full
    $database.Alter()
    Write-Host "Recovery model set to FULL" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create database" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 4: Create sample tables and data
Write-Host "`n[4/5] Creating sample tables and data..." -ForegroundColor Cyan

$sqlQueries = @(
    "CREATE TABLE dbo.Customers (
        CustomerID INT PRIMARY KEY IDENTITY(1,1),
        CustomerName NVARCHAR(100) NOT NULL,
        Email NVARCHAR(100),
        CreatedDate DATETIME DEFAULT GETDATE()
    )",
    
    "CREATE TABLE dbo.Orders (
        OrderID INT PRIMARY KEY IDENTITY(1,1),
        CustomerID INT NOT NULL FOREIGN KEY REFERENCES dbo.Customers(CustomerID),
        OrderDate DATETIME DEFAULT GETDATE(),
        Amount DECIMAL(10,2),
        Status NVARCHAR(50) DEFAULT 'Pending'
    )",
    
    "CREATE TABLE dbo.OrderItems (
        OrderItemID INT PRIMARY KEY IDENTITY(1,1),
        OrderID INT NOT NULL FOREIGN KEY REFERENCES dbo.Orders(OrderID),
        ProductName NVARCHAR(100),
        Quantity INT,
        UnitPrice DECIMAL(10,2)
    )"
)

try {
    foreach ($query in $sqlQueries) {
        $server.Databases[$DatabaseName].ExecuteNonQuery($query)
    }
    Write-Host "Sample tables created successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create tables" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 5: Insert sample data
Write-Host "`n[5/5] Inserting sample data..." -ForegroundColor Cyan

$insertQueries = @(
    "INSERT INTO dbo.Customers (CustomerName, Email) VALUES ('John Smith', 'john@example.com')",
    "INSERT INTO dbo.Customers (CustomerName, Email) VALUES ('Jane Doe', 'jane@example.com')",
    "INSERT INTO dbo.Customers (CustomerName, Email) VALUES ('Bob Wilson', 'bob@example.com')",
    "INSERT INTO dbo.Orders (CustomerID, Amount, Status) VALUES (1, 250.00, 'Completed')",
    "INSERT INTO dbo.Orders (CustomerID, Amount, Status) VALUES (2, 150.00, 'Pending')",
    "INSERT INTO dbo.Orders (CustomerID, Amount, Status) VALUES (3, 500.00, 'Processing')",
    "INSERT INTO dbo.OrderItems (OrderID, ProductName, Quantity, UnitPrice) VALUES (1, 'Laptop', 1, 250.00)",
    "INSERT INTO dbo.OrderItems (OrderID, ProductName, Quantity, UnitPrice) VALUES (2, 'Mouse', 2, 75.00)",
    "INSERT INTO dbo.OrderItems (OrderID, ProductName, Quantity, UnitPrice) VALUES (3, 'Monitor', 1, 500.00)"
)

try {
    foreach ($query in $insertQueries) {
        $server.Databases[$DatabaseName].ExecuteNonQuery($query)
    }
    Write-Host "Sample data inserted successfully" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to insert data" -ForegroundColor Red
    Write-Host "Details: $($_.Exception.Message)" -ForegroundColor Red
}

# Verification
Write-Host "`n[+] Verifying database..." -ForegroundColor Cyan
try {
    $tableCount = $server.Databases[$DatabaseName].Tables | Where-Object { $_.IsSystemObject -eq $false } | Measure-Object | Select-Object -ExpandProperty Count
    $rowCount = $server.Databases[$DatabaseName].ExecuteWithResults("SELECT COUNT(*) as TableCount FROM (SELECT COUNT(*) cnt FROM dbo.Customers UNION ALL SELECT COUNT(*) FROM dbo.Orders UNION ALL SELECT COUNT(*) FROM dbo.OrderItems) t").Tables[0].Rows[0][0]
    
    Write-Host "Tables created: $tableCount" -ForegroundColor Green
    Write-Host "Sample records inserted: ~$rowCount" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Could not verify database: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Database Creation Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Database Name: $DatabaseName" -ForegroundColor Cyan
Write-Host "Recovery Model: FULL" -ForegroundColor Cyan
Write-Host "Tables: 3 (Customers, Orders, OrderItems)" -ForegroundColor Cyan
Write-Host "Status: Ready for Availability Group" -ForegroundColor Cyan
Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Create backup of database: BACKUP DATABASE $DatabaseName TO DISK = 'C:\Backup\$DatabaseName.bak'" -ForegroundColor Gray
Write-Host "2. Restore on secondary nodes" -ForegroundColor Gray
Write-Host "3. Run Configure-AG.ps1 to setup Availability Group" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Green
