@echo off
REM SPDX-License-Identifier: GPL-3.0-or-later
setlocal EnableExtensions
cd /d "%~dp0"

echo.
echo ============================================================
echo   ExtFS for Windows 0.9.2 - Build / Validate / Package
echo ============================================================
echo.

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo ERROR: Windows PowerShell was not found.
    echo.
    pause
    exit /b 1
)

if /I "%~1"=="driver" goto driveronly
if /I "%~1"=="setup" goto fullsetup
if not "%~1"=="" goto usage

goto fullsetup

:driveronly
echo Building and validating the x64 Release driver only...
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Build-And-Validate.ps1" -Configuration Release
goto result

:fullsetup
echo Building, validating, test-signing and packaging the x64 Release driver...
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\Build-ExperimentalSetup.ps1"
goto result

:usage
echo Usage:
echo   BUILD-EXTFS.cmd          Build, validate, sign and create the setup EXE
echo   BUILD-EXTFS.cmd setup    Same as above
echo   BUILD-EXTFS.cmd driver   Build and validate extfs.sys only
echo.
pause
exit /b 2

:result
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
    echo ============================================================
    echo   BUILD FAILED - exit code %RC%
    echo ============================================================
    echo.
    echo Copy everything shown above and give it to HAL.
    echo The build scripts will identify missing WDK, MSBuild, SDK,
    echo SignTool or NSIS components where possible.
    echo.
    pause
    exit /b %RC%
)

echo ============================================================
echo   BUILD COMPLETED SUCCESSFULLY
 echo ============================================================
echo.
if exist "%~dp0ExtFS-for-Windows-0.9.2-experimental-x64-setup.exe" (
    echo Installer:
    echo   %~dp0ExtFS-for-Windows-0.9.2-experimental-x64-setup.exe
) else if exist "%~dp0release\driver\extfs.sys" (
    echo Driver:
    echo   %~dp0release\driver\extfs.sys
)
echo.
pause
exit /b 0
