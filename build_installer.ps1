# ============================================================
#  Sendate Windows Installer Build Script (PowerShell)
#  This script builds the Flutter app and creates the setup EXE
# ============================================================

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Sendate Windows Installer Builder" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Check Flutter ---
Write-Host "[1/4] Checking Flutter..." -ForegroundColor Yellow
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "ERROR: Flutter is not in PATH." -ForegroundColor Red
    Write-Host "Please add Flutter to your system PATH or run from a terminal where Flutter is available."
    Write-Host 'Example: $env:Path += ";C:\path\to\flutter\bin"'
    exit 1
}
Write-Host "      Flutter found: $($flutterCmd.Source)" -ForegroundColor Green
Write-Host ""

# --- Step 2: Check Inno Setup ---
Write-Host "[2/4] Checking Inno Setup 6..." -ForegroundColor Yellow
$isccPaths = @(
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
)
$iscc = $null
foreach ($path in $isccPaths) {
    if (Test-Path $path) {
        $iscc = $path
        break
    }
}

if (-not $iscc) {
    Write-Host "ERROR: Inno Setup 6 not found." -ForegroundColor Red
    Write-Host "Please download and install from: https://jrsoftware.org/isdl.php"
    Write-Host "Install to the default location."
    Write-Host ""
    
    $install = Read-Host "Would you like to download Inno Setup now? (y/n)"
    if ($install -eq 'y') {
        Start-Process "https://jrsoftware.org/isdl.php"
        Write-Host "Please install Inno Setup and run this script again."
    }
    exit 1
}
Write-Host "      Inno Setup found: $iscc" -ForegroundColor Green
Write-Host ""

# --- Step 3: Build Flutter Windows Release ---
Write-Host "[3/4] Building Flutter Windows release..." -ForegroundColor Yellow
Write-Host "      This may take a few minutes..." -ForegroundColor Gray
Write-Host ""

$buildProcess = Start-Process -FilePath "flutter" -ArgumentList "build", "windows", "--release" -NoNewWindow -Wait -PassThru
if ($buildProcess.ExitCode -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Flutter build failed!" -ForegroundColor Red
    Write-Host "Please fix build errors above and try again."
    exit 1
}
Write-Host ""
Write-Host "      Build successful!" -ForegroundColor Green
Write-Host ""

# --- Step 4: Verify build output exists ---
$buildOutput = Join-Path $PSScriptRoot "build\windows\x64\runner\Release\sendate.exe"
if (-not (Test-Path $buildOutput)) {
    Write-Host "ERROR: Build output not found at expected location." -ForegroundColor Red
    Write-Host "Expected: $buildOutput"
    Write-Host "The build may have used a different architecture. Check build\windows\ folder."
    exit 1
}

# --- Step 5: Create Installer ---
Write-Host "[4/4] Creating installer with Inno Setup..." -ForegroundColor Yellow
$issFile = Join-Path $PSScriptRoot "windows\installer\sendate_installer.iss"

$innoProcess = Start-Process -FilePath $iscc -ArgumentList "`"$issFile`"" -NoNewWindow -Wait -PassThru
if ($innoProcess.ExitCode -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Inno Setup compilation failed!" -ForegroundColor Red
    exit 1
}

$outputFile = Join-Path $PSScriptRoot "build\installer\Sendate-1.0.0-Setup.exe"
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  SUCCESS! Installer created:" -ForegroundColor Green
Write-Host "  $outputFile" -ForegroundColor White
Write-Host "============================================" -ForegroundColor Green
Write-Host ""

# Open output folder
if (Test-Path $outputFile) {
    $openFolder = Read-Host "Open output folder? (y/n)"
    if ($openFolder -eq 'y') {
        explorer.exe "/select,$outputFile"
    }
}
