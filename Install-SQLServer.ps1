# SQL Server 2022 Enterprise Edition Installation Script
# Run as Administrator
# Usage: .\Install-SQLServer.ps1

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# Configuration
$DownloadPath = "C:\SQLServerSetup"
$ISOFile = "SQL2022-SSEI-Eval.exe"
$ISOUrl = "https://go.microsoft.com/fwlink/p/?linkid=2215158&clcid=0x409"
$SqlInstanceName = "MSSQLSERVER"
$SqlSysAdminAccounts = "BUILTIN\Administrators"

Write-Host "========================================" -ForegroundColor Green
Write-Host "SQL Server 2022 Enterprise Installation" -ForegroundColor Green
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
Write-Host "`n[2/5] Downloading SQL Server 2022 installer..." -ForegroundColor Cyan
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

# Step 3: Install .NET Framework 3.5 (prerequisite)
Write-Host "`n[3/5] Installing .NET Framework 3.5..." -ForegroundColor Cyan
try {
    $dotnetStatus = Get-WindowsOptionalFeature -Online -FeatureName NetFx3 | Select-Object -ExpandProperty State
    if ($dotnetStatus -eq "Enabled") {
        Write-Host ".NET Framework 3.5 is already installed" -ForegroundColor Green
    } else {
        Write-Host "Installing .NET Framework 3.5..." -ForegroundColor Gray
        Enable-WindowsOptionalFeature -Online -FeatureName NetFx3 -NoRestart -WarningAction SilentlyContinue | Out-Null
        Write-Host ".NET Framework 3.5 installed successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "WARNING: Could not verify .NET Framework 3.5 status: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Step 4: Install SQL Server
Write-Host "`n[4/5] Installing SQL Server 2022 Enterprise..." -ForegroundColor Cyan
Write-Host "This may take 10-30 minutes. Please be patient..." -ForegroundColor Gray

$installArgs = @(
    "/Q",
    "/ACTION=Install",
    "/IACCEPTSQLSERVERLICENSETERMS",
    "/INSTANCENAME=$SqlInstanceName",
    "/FEATURES=SQLEngine,FullText,PolyBase",
    "/SQLSYSADMINACCOUNTS=$SqlSysAdminAccounts",
    "/TCPENABLED=1",
    "/SECURITYMODE=SQL",
    "/SAPWD=P@ssw0rd123!",
    "/SQLCOLLATION=SQL_Latin1_General_CP1_CI_AS",
    "/IAcceptSQLServerLicenseTerms=True"
)

try {
    Write-Host "Running: $ISOPath $($installArgs -join ' ')" -ForegroundColor Gray
    $process = Start-Process -FilePath $ISOPath -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0) {
        Write-Host "SQL Server 2022 Enterprise installed successfully" -ForegroundColor Green
    } else {
        Write-Host "WARNING: Installation exited with code $($process.ExitCode)" -ForegroundColor Yellow
        Write-Host "Check %ProgramFiles%\Microsoft SQL Server\160\Setup Bootstrap\Log for details" -ForegroundColor Yellow
    }
} catch {
    Write-Host "ERROR: Failed to install SQL Server" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# Step 5: Enable SQL Server and SQL Browser services
Write-Host "`n[5/5] Configuring SQL Server services..." -ForegroundColor Cyan

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

# Verification
Write-Host "`n[6/5] Verifying installation..." -ForegroundColor Cyan
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

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Installation Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "SQL Server Version: 2022 Enterprise Edition" -ForegroundColor Cyan
Write-Host "Instance Name: $SqlInstanceName" -ForegroundColor Cyan
Write-Host "TCP Enabled: Yes" -ForegroundColor Cyan
Write-Host "Authentication: Mixed (Windows + SQL)" -ForegroundColor Cyan
Write-Host "SA Password: P@ssw0rd123!" -ForegroundColor Cyan
Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Run Create-DummyDatabase.ps1 to create test database" -ForegroundColor Gray
Write-Host "2. Configure Availability Group using Configure-AG.ps1" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Green
