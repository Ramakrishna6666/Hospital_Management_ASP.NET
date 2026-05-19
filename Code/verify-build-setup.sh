#!/bin/bash

# Verification script for Clinic Management System build setup
# This script checks that all necessary files are in place for a successful build

echo "=========================================="
echo "Build Setup Verification"
echo "=========================================="
echo ""

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "Working directory: $SCRIPT_DIR"
echo ""

# Check for solution files
echo "Checking for solution files..."
if [ -f "ClinicManagementSystem.sln" ]; then
    echo "✓ ClinicManagementSystem.sln found (NEW - recommended)"
else
    echo "✗ ClinicManagementSystem.sln NOT found"
fi

if [ -f "Clinic Management System.sln" ]; then
    echo "✓ Clinic Management System.sln found (OLD - preserved)"
else
    echo "✗ Clinic Management System.sln NOT found"
fi

if [ -f "DBProject/DBProject.sln" ]; then
    echo "✓ DBProject/DBProject.sln found (alternative)"
else
    echo "✗ DBProject/DBProject.sln NOT found"
fi

echo ""

# Check for project file
echo "Checking for project files..."
if [ -f "DBProject/DBProject.csproj" ]; then
    echo "✓ DBProject/DBProject.csproj found (NEW - recommended)"
else
    echo "✗ DBProject/DBProject.csproj NOT found"
fi

if [ -f "DBProject/Clinic Management System.csproj" ]; then
    echo "✓ DBProject/Clinic Management System.csproj found (OLD)"
else
    echo "  DBProject/Clinic Management System.csproj not found (expected - was renamed)"
fi

echo ""

# Check for build scripts
echo "Checking for build scripts..."
if [ -f "build.sh" ]; then
    echo "✓ build.sh found (parent level)"
else
    echo "✗ build.sh NOT found"
fi

if [ -f "build.bat" ]; then
    echo "✓ build.bat found (parent level)"
else
    echo "✗ build.bat NOT found"
fi

if [ -f "DBProject/build.sh" ]; then
    echo "✓ DBProject/build.sh found (project level)"
else
    echo "✗ DBProject/build.sh NOT found"
fi

if [ -f "DBProject/build.bat" ]; then
    echo "✓ DBProject/build.bat found (project level)"
else
    echo "✗ DBProject/build.bat NOT found"
fi

echo ""

# Check for packages directory
echo "Checking for packages directory..."
if [ -d "packages" ]; then
    echo "✓ packages directory found"
    PACKAGE_COUNT=$(ls -1 packages | wc -l)
    echo "  Found $PACKAGE_COUNT packages"
else
    echo "✗ packages directory NOT found"
fi

echo ""

# Check solution file references
echo "Checking solution file references..."
if [ -f "ClinicManagementSystem.sln" ]; then
    PROJECT_REF=$(grep "DBProject.csproj" ClinicManagementSystem.sln)
    if [ -n "$PROJECT_REF" ]; then
        echo "✓ ClinicManagementSystem.sln correctly references DBProject.csproj"
    else
        echo "✗ ClinicManagementSystem.sln does NOT reference DBProject.csproj"
    fi
fi

echo ""

# Check for dotnet or msbuild
echo "Checking for build tools..."
if command -v dotnet &> /dev/null; then
    DOTNET_VERSION=$(dotnet --version 2>/dev/null)
    echo "✓ dotnet CLI found (version: $DOTNET_VERSION)"
else
    echo "✗ dotnet CLI NOT found"
fi

if command -v msbuild &> /dev/null; then
    echo "✓ msbuild found"
else
    echo "  msbuild not found (not required if dotnet is available)"
fi

echo ""
echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "Recommended build command:"
echo "  ./build.sh"
echo ""
echo "Or directly:"
echo "  dotnet build ClinicManagementSystem.sln"
echo ""
