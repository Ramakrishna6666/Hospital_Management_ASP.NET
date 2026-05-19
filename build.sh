#!/bin/bash

# Build script for Clinic Management System - Workspace Root Level
# This script resolves the MSB1003 error by navigating to the correct directory
# and explicitly specifying the solution file

echo "=========================================="
echo "Building Clinic Management System"
echo "=========================================="
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Navigate to the Code directory where the solution file is located
CODE_DIR="$SCRIPT_DIR/Code"

if [ ! -d "$CODE_DIR" ]; then
    echo "ERROR: Code directory not found at: $CODE_DIR"
    exit 1
fi

cd "$CODE_DIR"

echo "Working directory: $CODE_DIR"
echo ""

# Check if solution file exists
if [ ! -f "ClinicManagementSystem.sln" ]; then
    echo "ERROR: Solution file 'ClinicManagementSystem.sln' not found"
    echo "Looking for alternative solution files..."
    
    if [ -f "DBProject/DBProject.sln" ]; then
        echo "Found: DBProject/DBProject.sln"
        cd DBProject
        SOLUTION_FILE="DBProject.sln"
    elif [ -f "Clinic Management System.sln" ]; then
        echo "Found: Clinic Management System.sln"
        SOLUTION_FILE="Clinic Management System.sln"
    else
        echo "ERROR: No solution file found"
        exit 1
    fi
else
    SOLUTION_FILE="ClinicManagementSystem.sln"
fi

echo "Using solution file: $SOLUTION_FILE"
echo ""

# Check if dotnet is available
if command -v dotnet &> /dev/null; then
    echo "Using dotnet CLI to build..."
    echo "Command: dotnet build \"$SOLUTION_FILE\""
    echo ""
    dotnet build "$SOLUTION_FILE"
    BUILD_RESULT=$?
elif command -v msbuild &> /dev/null; then
    echo "Using MSBuild to build..."
    echo "Command: msbuild \"$SOLUTION_FILE\""
    echo ""
    msbuild "$SOLUTION_FILE"
    BUILD_RESULT=$?
else
    echo "ERROR: Neither dotnet nor msbuild found in PATH"
    echo "Please install .NET SDK or MSBuild"
    exit 1
fi

echo ""
echo "=========================================="
if [ $BUILD_RESULT -eq 0 ]; then
    echo "Build completed successfully!"
else
    echo "Build failed with exit code: $BUILD_RESULT"
fi
echo "=========================================="

exit $BUILD_RESULT
