@echo off
REM ============================================================
REM  Sendate Windows Installer Build Script
REM  This script builds the Flutter app and creates the setup EXE
REM ============================================================

echo ============================================
echo   Sendate Windows Installer Builder
echo ============================================
echo.

REM --- Step 1: Check Flutter ---
echo [1/4] Checking Flutter...
where flutter >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: Flutter is not in PATH.
    echo Please add Flutter to your system PATH or run from a terminal where Flutter is available.
    echo Example: set PATH=%%PATH%%;C:\path\to\flutter\bin
    pause
    exit /b 1
)
echo       Flutter found.
echo.

REM --- Step 2: Check Inno Setup ---
echo [2/4] Checking Inno Setup 6...
set "ISCC="
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    set "ISCC=C:\Program Files\Inno Setup 6\ISCC.exe"
)

if "%ISCC%"=="" (
    echo ERROR: Inno Setup 6 not found.
    echo Please download and install from: https://jrsoftware.org/isdl.php
    echo Install to the default location.
    pause
    exit /b 1
)
echo       Inno Setup found: %ISCC%
echo.

REM --- Step 3: Build Flutter Windows Release ---
echo [3/4] Building Flutter Windows release...
echo       This may take a few minutes...
echo.
call flutter build windows --release
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Flutter build failed!
    echo Please fix build errors above and try again.
    pause
    exit /b 1
)
echo.
echo       Build successful!
echo.

REM --- Step 4: Create Installer ---
echo [4/4] Creating installer with Inno Setup...
"%ISCC%" "%~dp0windows\installer\sendate_installer.iss"
if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Inno Setup compilation failed!
    pause
    exit /b 1
)

echo.
echo ============================================
echo   SUCCESS! Installer created at:
echo   build\installer\Sendate-1.0.0-Setup.exe
echo ============================================
echo.
pause
