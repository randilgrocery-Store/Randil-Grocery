@echo off
cd /d "%~dp0"
echo ============================================
echo   Randil Grocery POS - Build Installer
echo ============================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
    echo [1/3] Flutter NOT found on this PC.
    echo       Install Flutter first: https://docs.flutter.dev/get-started/install/windows
    pause
    exit /b 1
)

echo [1/3] Building the POS app (flutter build windows)...
call flutter build windows
if errorlevel 1 (
    echo.
    echo *** APP BUILD FAILED - see errors above ***
    pause
    exit /b 1
)

echo.
echo [2/3] Looking for Inno Setup 6...
set "ISCC="
if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" set "ISCC=%ProgramFiles%\Inno Setup 6\ISCC.exe"
if exist "%LocalAppData%\Programs\Inno Setup 6\ISCC.exe" set "ISCC=%LocalAppData%\Programs\Inno Setup 6\ISCC.exe"
if not defined ISCC (
    echo       Inno Setup 6 NOT found.
    echo       Install it from: https://jrsoftware.org/isdl.php  (free)
    echo       Then run this script again.
    pause
    exit /b 1
)
echo       Found: %ISCC%

echo.
echo [3/3] Creating installer...
"%ISCC%" installer.iss
if errorlevel 1 (
    echo.
    echo *** INSTALLER BUILD FAILED - see errors above ***
    pause
    exit /b 1
)

echo.
powershell -ExecutionPolicy Bypass -File "%~dp0verify-build.ps1"
echo.
echo Done. Installer is in: installer_output\
pause
