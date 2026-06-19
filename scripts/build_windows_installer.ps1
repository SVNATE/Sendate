# Sendate Windows Installer Build Script
# Run this from the project root on Windows: .\scripts\build_windows_installer.ps1

param(
    [switch]$SkipBuild,
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Sendate Windows Installer Builder" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Verify Flutter
Write-Host "[1/4] Checking Flutter..." -ForegroundColor Yellow
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "  $flutterVersion" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Flutter not found in PATH. Install Flutter first." -ForegroundColor Red
    exit 1
}

# Step 2: Flutter build
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "[2/4] Building Flutter Windows release..." -ForegroundColor Yellow
    
    Set-Location $ProjectRoot
    flutter clean
    flutter pub get
    flutter build windows --release
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Flutter build failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Build successful!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[2/4] Skipping Flutter build (--SkipBuild flag)" -ForegroundColor DarkGray
}

# Step 3: Verify build output exists
Write-Host ""
Write-Host "[3/4] Verifying build output..." -ForegroundColor Yellow
$BuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
if (-not (Test-Path (Join-Path $BuildDir "sendate.exe"))) {
    Write-Host "  ERROR: sendate.exe not found at $BuildDir" -ForegroundColor Red
    Write-Host "  Run without -SkipBuild flag to build first." -ForegroundColor Red
    exit 1
}
Write-Host "  Found sendate.exe" -ForegroundColor Green

# Step 4: Build installer with Inno Setup
if (-not $SkipInstaller) {
    Write-Host ""
    Write-Host "[4/4] Building installer with Inno Setup..." -ForegroundColor Yellow
    
    # Find Inno Setup compiler
    $InnoCompiler = $null
    $PossiblePaths = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
    )
    
    foreach ($path in $PossiblePaths) {
        if (Test-Path $path) {
            $InnoCompiler = $path
            break
        }
    }
    
    if (-not $InnoCompiler) {
        Write-Host "  ERROR: Inno Setup 6 not found." -ForegroundColor Red
        Write-Host "  Download from: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  After installing Inno Setup, run this script again." -ForegroundColor Yellow
        Write-Host "  Or compile manually: Open windows\installer\sendate_installer.iss in Inno Setup" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "  Using: $InnoCompiler" -ForegroundColor Green
    
    $IssFile = Join-Path $ProjectRoot "windows\installer\sendate_installer.iss"
    
    # Create output directory
    $OutputDir = Join-Path $ProjectRoot "build\installer"
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir | Out-Null
    }
    
    & $InnoCompiler $IssFile
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Inno Setup compilation failed." -ForegroundColor Red
        exit 1
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Installer built successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Output: build\installer\Sendate-1.0.0-Setup.exe" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "[4/4] Skipping installer (--SkipInstaller flag)" -ForegroundColor DarkGray
}
