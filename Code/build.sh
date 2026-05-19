#!/bin/bash

# Build script for Clinic Management System
# This script resolves the MSB1003 error by explicitly specifying the solution file

echo "=========================================="
echo "Building Clinic Management System"
echo "=========================================="
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "Working directory: $SCRIPT_DIR"
echo ""

# Check if dotnet is available
if command -v dotnet &> /dev/null; then
    echo "Using dotnet CLI to build..."
    echo "Command: dotnet build ClinicManagementSystem.sln"
    echo ""
    dotnet build ClinicManagementSystem.sln
    BUILD_RESULT=$?
elif command -v msbuild &> /dev/null; then
    echo "Using MSBuild to build..."
    echo "Command: msbuild ClinicManagementSystem.sln"
    echo ""
    msbuild ClinicManagementSystem.sln
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
