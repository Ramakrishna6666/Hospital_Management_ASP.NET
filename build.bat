@echo off
REM Build script for Clinic Management System - Workspace Root Level
REM This script resolves the MSB1003 error by navigating to the correct directory
REM and explicitly specifying the solution file

echo ==========================================
echo Building Clinic Management System
echo ==========================================
echo.

REM Change to the directory where this script is located
cd /d "%~dp0"

REM Navigate to the Code directory where the solution file is located
set CODE_DIR=%~dp0Code

if not exist "%CODE_DIR%" (
    echo ERROR: Code directory not found at: %CODE_DIR%
    exit /b 1
)

cd /d "%CODE_DIR%"

echo Working directory: %CD%
echo.

REM Check if solution file exists
if exist "ClinicManagementSystem.sln" (
    set SOLUTION_FILE=ClinicManagementSystem.sln
) else if exist "DBProject\DBProject.sln" (
    echo Found: DBProject\DBProject.sln
    cd DBProject
    set SOLUTION_FILE=DBProject.sln
) else if exist "Clinic Management System.sln" (
    echo Found: Clinic Management System.sln
    set SOLUTION_FILE=Clinic Management System.sln
) else (
    echo ERROR: No solution file found
    exit /b 1
)

echo Using solution file: %SOLUTION_FILE%
echo.

REM Check if dotnet is available
where dotnet >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Using dotnet CLI to build...
    echo Command: dotnet build "%SOLUTION_FILE%"
    echo.
    dotnet build "%SOLUTION_FILE%"
    set BUILD_RESULT=%ERRORLEVEL%
) else (
    REM Check if msbuild is available
    where msbuild >nul 2>nul
    if %ERRORLEVEL% EQU 0 (
        echo Using MSBuild to build...
        echo Command: msbuild "%SOLUTION_FILE%"
        echo.
        msbuild "%SOLUTION_FILE%"
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
