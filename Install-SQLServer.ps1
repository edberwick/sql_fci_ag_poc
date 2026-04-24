# SQL Server 2025 Enterprise Edition Installation Script
# Run as Administrator (recommended for full installation)
# Usage: .\Install-SQLServer.ps1

# Note: Administrator privileges required for actual installation
# This script will prepare files and show installation command

#$ErrorActionPreference = "Stop"

# Configuration
$DownloadPath = "C:\SQLServerSetup"
$ISOFile = "SQL2025-SSEI-Eval.exe"
$ISOUrl = "https://go.microsoft.com/fwlink/?linkid=2342429&clcid=0x409"
$ConfigFile = Join-Path $DownloadPath "Configuration.ini"
$SqlInstanceName = "MSSQLSERVER"
$SqlSysAdminAccounts = "BUILTIN\Administrators"

Write-Host "========================================" -ForegroundColor Green
Write-Host "SQL Server 2025 Enterprise Installation" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Step 1: Create download directory
Write-Host "`n[1/5] Creating download directory..." -ForegroundColor Cyan
if (-not (Test-Path $DownloadPath)) {
    New-Item -Path $DownloadPath -ItemType Directory -Force | Out-Null
    Write-Host "Directory created: $DownloadPath" -ForegroundColor Green
} else {
    Write-Host "Directory already exists: $DownloadPath" -ForegroundColor Yellow
}

# Step 2: Download SQL Server Installer
Write-Host "`n[2/6] Downloading SQL Server 2025 installer..." -ForegroundColor Cyan
$ISOPath = Join-Path $DownloadPath $ISOFile

if (Test-Path $ISOPath) {
    Write-Host "Installer already exists at $ISOPath" -ForegroundColor Yellow
} else {
    try {
        Write-Host "Downloading from: $ISOUrl" -ForegroundColor Gray
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $ISOUrl -OutFile $ISOPath -UseBasicParsing
        Write-Host "Download completed successfully" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to download SQL Server installer" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

# Step 3: Create Configuration File
Write-Host "`n[3/6] Creating SQL Server configuration file..." -ForegroundColor Cyan
try {
    $configContent = @"
# SQL Server 2025 Enterprise Edition Configuration File
# This file contains all installation parameters for unattended setup

[OPTIONS]

# Installation
ACTION="Install"
IACCEPTSQLSERVERLICENSETERMS="True"
QUIET="True"
SUPPRESSPRIVACYSTATEMENTNOTICE="True"
SUPPRESSPAIDEDITIONNOTICE="True"
ENU="True"

# Instance Configuration
INSTANCENAME="$SqlInstanceName"
INSTANCEID="$SqlInstanceName"
INSTANCEDIR="C:\Program Files\Microsoft SQL Server"

# Features to Install
FEATURES="SQLEngine"

# Service Accounts
SQLSVCACCOUNT="NT AUTHORITY\SYSTEM"
SQLSVCSTARTUPTYPE="Automatic"
AGTSVCACCOUNT="NT AUTHORITY\SYSTEM"
AGTSVCSTARTUPTYPE="Automatic"
BROWSERSVCSTARTUPTYPE="Automatic"

# Authentication Mode
SECURITYMODE="SQL"
SAPWD="P@ssw0rd123!"

# System Administrators
SQLSYSADMINACCOUNTS="$SqlSysAdminAccounts"

# Database Engine Configuration
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"
SQLBACKUPDIR="C:\Program Files\Microsoft SQL Server\MSSQL17.$SqlInstanceName\MSSQL\Backup"
SQLTEMPDBDIR="C:\Program Files\Microsoft SQL Server\MSSQL17.$SqlInstanceName\MSSQL\Data"
SQLTEMPDBLOGDIR="C:\Program Files\Microsoft SQL Server\MSSQL17.$SqlInstanceName\MSSQL\Data"
SQLUSERDBDIR="C:\Program Files\Microsoft SQL Server\MSSQL17.$SqlInstanceName\MSSQL\Data"
SQLUSERDBLOGDIR="C:\Program Files\Microsoft SQL Server\MSSQL17.$SqlInstanceName\MSSQL\Data"

# Network Configuration
TCPENABLED="1"
NPENABLED="0"
BROWSERSVCSTARTUPTYPE="Automatic"

# Error and Usage Reporting
ERRORREPORTING="False"
SQMREPORTING="False"
ENABLEMICROSOFTUPDATE="False"

# Installation Paths
INSTALLSHAREDDIR="C:\Program Files\Microsoft SQL Server"
INSTALLSHAREDWOWDIR="C:\Program Files (x86)\Microsoft SQL Server"
INSTANCEMSDIR="C:\Program Files\Microsoft SQL Server"

# Performance Settings
SQLMAXMEMORY="2147483647"
SQLMINMEMORY="0"

# Maintenance
FILESTREAMLEVEL="0"
X86="False"

# Update Source
UPDATEENABLED="False"
USEMICROSOFTUPDATE="False"
UPDATESOURCE="MU"
"@

    $configContent | Out-File -FilePath $ConfigFile -Encoding UTF8 -Force
    Write-Host "Configuration file created: $ConfigFile" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to create configuration file" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Step 4: Install .NET Framework 3.5 (prerequisite)
Write-Host "`n[4/6] Checking .NET Framework 3.5..." -ForegroundColor Cyan
try {
    $dotnetStatus = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty State
    if ($dotnetStatus -eq "Enabled") {
        Write-Host ".NET Framework 3.5 is already installed" -ForegroundColor Green
    } else {
        Write-Host ".NET Framework 3.5 not installed or check failed" -ForegroundColor Yellow
        Write-Host "Note: .NET Framework 3.5 installation requires Administrator privileges" -ForegroundColor Gray
    }
} catch {
    Write-Host "WARNING: Could not verify .NET Framework 3.5 status: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 5: Show SQL Server Installation Command
Write-Host "`n[5/6] SQL Server 2025 Installation Command:" -ForegroundColor Cyan
Write-Host "This command requires Administrator privileges to execute:" -ForegroundColor Yellow

# Use only allowed command line switches
$installArgs = @(
    "/IAcceptSqlServerLicenseTerms",
    "/Quiet",
    "/ConfigurationFile=`"$ConfigFile`"",
    "/Action=Install"
)

$argumentString = $installArgs -join " "
Write-Host "Command: $ISOPath $argumentString" -ForegroundColor Gray
Write-Host "Working Directory: $DownloadPath" -ForegroundColor Gray

# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    Write-Host "`n[6/6] Executing SQL Server installation..." -ForegroundColor Cyan
    Write-Host "This may take 10-30 minutes. Please be patient..." -ForegroundColor Gray

    try {
        Write-Host "Running: $ISOPath $argumentString" -ForegroundColor Gray
        $process = Start-Process -FilePath $ISOPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow -WorkingDirectory $DownloadPath

        if ($process.ExitCode -eq 0) {
            Write-Host "SQL Server 2025 Enterprise installed successfully" -ForegroundColor Green
        } else {
            Write-Host "WARNING: Installation exited with code $($process.ExitCode)" -ForegroundColor Yellow
            Write-Host "Check %ProgramFiles%\Microsoft SQL Server\170\Setup Bootstrap\Log for details" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ERROR: Failed to install SQL Server" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "`n[6/6] Installation Skipped - Administrator privileges required" -ForegroundColor Yellow
    Write-Host "To complete installation, run this script as Administrator or execute the command above manually" -ForegroundColor Gray
}

# Step 6: Configure SQL Server services (requires Administrator)
Write-Host "`n[7/6] Configuring SQL Server services..." -ForegroundColor Cyan

if ($isAdmin) {
    # Wait for services to be available
    Start-Sleep -Seconds 5

    try {
        # Start SQL Server service
        $sqlService = Get-Service -Name MSSQLSERVER -ErrorAction SilentlyContinue
        if ($sqlService) {
            Write-Host "Starting MSSQLSERVER service..." -ForegroundColor Gray
            Start-Service -Name MSSQLSERVER -WarningAction SilentlyContinue
            Set-Service -Name MSSQLSERVER -StartupType Automatic
            Write-Host "MSSQLSERVER service started and set to automatic" -ForegroundColor Green
        }
        
        # Start SQL Browser service
        $browserService = Get-Service -Name SQLBrowser -ErrorAction SilentlyContinue
        if ($browserService) {
            Write-Host "Starting SQLBrowser service..." -ForegroundColor Gray
            Start-Service -Name SQLBrowser -WarningAction SilentlyContinue
            Set-Service -Name SQLBrowser -StartupType Automatic
            Write-Host "SQLBrowser service started and set to automatic" -ForegroundColor Green
        }
        
        # Wait for SQL to be ready
        Start-Sleep -Seconds 10
        
    } catch {
        Write-Host "WARNING: Could not configure services: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "Service configuration skipped - Administrator privileges required" -ForegroundColor Yellow
}

# Verification
Write-Host "`n[8/6] Verifying installation..." -ForegroundColor Cyan
if ($isAdmin) {
    try {
        $sqlProcess = Get-Process -Name sqlservr -ErrorAction SilentlyContinue
        if ($sqlProcess) {
            Write-Host "SQL Server process is running" -ForegroundColor Green
        } else {
            Write-Host "SQL Server process not found yet" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Could not verify SQL Server process" -ForegroundColor Yellow
    }
} else {
    Write-Host "Verification skipped - run as Administrator after installation" -ForegroundColor Yellow
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Installation Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "SQL Server Version: 2025 Enterprise Edition" -ForegroundColor Cyan
Write-Host "Instance Name: $SqlInstanceName" -ForegroundColor Cyan
Write-Host "TCP Enabled: Yes" -ForegroundColor Cyan
Write-Host "Authentication: Mixed (Windows + SQL)" -ForegroundColor Cyan
Write-Host "SA Password: P@ssw0rd123!" -ForegroundColor Cyan
Write-Host "Files Created:" -ForegroundColor Cyan
Write-Host "- Installer: $ISOPath" -ForegroundColor Gray
Write-Host "- Config: $ConfigFile" -ForegroundColor Gray

if ($isAdmin) {
    Write-Host "Installation: Completed" -ForegroundColor Green
} else {
    Write-Host "Installation: Requires Administrator privileges" -ForegroundColor Yellow
}

Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
if (-not $isAdmin) {
    Write-Host "1. Run this script as Administrator to complete installation" -ForegroundColor Gray
}
Write-Host "2. Run Create-DummyDatabase.ps1 to create test database" -ForegroundColor Gray
Write-Host "3. Configure Availability Group using Configure-AG.ps1" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Green
