@echo off
REM Build script for Clinic Management System
REM This script resolves the MSB1003 error by explicitly specifying the solution file

echo ==========================================
echo Building Clinic Management System
echo ==========================================
echo.

REM Change to the directory where this script is located
cd /d "%~dp0"

echo Working directory: %CD%
echo.

REM Check if dotnet is available
where dotnet >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Using dotnet CLI to build...
    echo Command: dotnet build ClinicManagementSystem.sln
    echo.
    dotnet build ClinicManagementSystem.sln
    set BUILD_RESULT=%ERRORLEVEL%
) else (
    REM Check if msbuild is available
    where msbuild >nul 2>nul
    if %ERRORLEVEL% EQU 0 (
        echo Using MSBuild to build...
        echo Command: msbuild ClinicManagementSystem.sln
        echo.
        msbuild ClinicManagementSystem.sln
        set BUILD_RESULT=%ERRORLEVEL%
    ) else (
        echo ERROR: Neither dotnet nor msbuild found in PATH
        echo Please install .NET SDK or MSBuild
        exit /b 1
    )
)

echo.
echo ==========================================
if %BUILD_RESULT% EQU 0 (
    echo Build completed successfully!
) else (
    echo Build failed with exit code: %BUILD_RESULT%
)
echo ==========================================

exit /b %BUILD_RESULT%
