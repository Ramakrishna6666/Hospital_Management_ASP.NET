#!/bin/bash

# Verification script for Clinic Management System build setup
# This script checks that all necessary files are in place after Iteration 3 fix

echo "=========================================="
echo "Build Setup Verification - Iteration 3"
echo "=========================================="
echo ""

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

ERRORS=0
WARNINGS=0

# Function to check file existence
check_file() {
    local file=$1
    local description=$2
    local required=$3
    
    if [ -f "$file" ]; then
        echo "✅ FOUND: $description"
        echo "   Path: $file"
        return 0
    else
        if [ "$required" = "required" ]; then
            echo "❌ MISSING: $description"
            echo "   Expected: $file"
            ERRORS=$((ERRORS + 1))
        else
            echo "⚠️  OPTIONAL: $description (not found)"
            echo "   Expected: $file"
            WARNINGS=$((WARNINGS + 1))
        fi
        return 1
    fi
}

# Function to check directory existence
check_dir() {
    local dir=$1
    local description=$2
    
    if [ -d "$dir" ]; then
        echo "✅ FOUND: $description"
        echo "   Path: $dir"
        return 0
    else
        echo "❌ MISSING: $description"
        echo "   Expected: $dir"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Function to check if file is executable
check_executable() {
    local file=$1
    local description=$2
    
    if [ -x "$file" ]; then
        echo "✅ EXECUTABLE: $description"
        return 0
    else
        echo "⚠️  NOT EXECUTABLE: $description"
        echo "   Run: chmod +x $file"
        WARNINGS=$((WARNINGS + 1))
        return 1
    fi
}

echo "Checking Workspace Root Files (Iteration 3)..."
echo "----------------------------------------------"
check_file "build.sh" "Workspace root build script (Linux/Mac)" "required"
if [ -f "build.sh" ]; then
    check_executable "build.sh" "build.sh"
fi
check_file "build.bat" "Workspace root build script (Windows)" "required"
check_file "BUILD_INSTRUCTIONS.md" "Comprehensive build documentation" "required"
check_file "QUICK_BUILD_GUIDE.md" "Quick build guide" "required"
check_file "ITERATION_3_FIX_SUMMARY.md" "Iteration 3 fix summary" "required"
echo ""

echo "Checking Code Directory..."
echo "----------------------------------------------"
check_dir "Code" "Code directory"
if [ -d "Code" ]; then
    check_file "Code/ClinicManagementSystem.sln" "Main solution file (Iteration 2)" "required"
    check_file "Code/build.sh" "Code directory build script (Linux/Mac)" "required"
    check_file "Code/build.bat" "Code directory build script (Windows)" "required"
    check_file "Code/Clinic Management System.sln" "Original solution file" "optional"
fi
echo ""

echo "Checking DBProject Directory..."
echo "----------------------------------------------"
check_dir "Code/DBProject" "DBProject directory"
if [ -d "Code/DBProject" ]; then
    check_file "Code/DBProject/DBProject.csproj" "Project file (Iteration 1)" "required"
    check_file "Code/DBProject/DBProject.sln" "Project solution file (Iteration 1)" "required"
    check_file "Code/DBProject/build.sh" "DBProject build script (Linux/Mac)" "required"
    check_file "Code/DBProject/build.bat" "DBProject build script (Windows)" "required"
    check_file "Code/DBProject/Clinic Management System.csproj" "Original project file" "optional"
fi
echo ""

echo "Checking Build Tools..."
echo "----------------------------------------------"
if command -v dotnet &> /dev/null; then
    DOTNET_VERSION=$(dotnet --version 2>/dev/null)
    echo "✅ FOUND: dotnet CLI"
    echo "   Version: $DOTNET_VERSION"
else
    echo "⚠️  NOT FOUND: dotnet CLI"
    echo "   Install from: https://dotnet.microsoft.com/download"
    WARNINGS=$((WARNINGS + 1))
fi

if command -v msbuild &> /dev/null; then
    echo "✅ FOUND: msbuild"
else
    echo "⚠️  NOT FOUND: msbuild"
    echo "   Install Visual Studio Build Tools or full Visual Studio"
    WARNINGS=$((WARNINGS + 1))
fi

if ! command -v dotnet &> /dev/null && ! command -v msbuild &> /dev/null; then
    echo "❌ ERROR: Neither dotnet nor msbuild found!"
    echo "   At least one build tool is required"
    ERRORS=$((ERRORS + 1))
fi
echo ""

echo "=========================================="
echo "Verification Summary"
echo "=========================================="
echo "Errors: $ERRORS"
echo "Warnings: $WARNINGS"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo "✅ BUILD SETUP IS COMPLETE!"
    echo ""
    echo "You can now build the project using:"
    echo "  ./build.sh  (Linux/Mac)"
    echo "  build.bat   (Windows)"
    echo ""
    echo "For more information, see:"
    echo "  - QUICK_BUILD_GUIDE.md (quick start)"
    echo "  - BUILD_INSTRUCTIONS.md (detailed guide)"
    echo "  - ITERATION_3_FIX_SUMMARY.md (technical details)"
    echo ""
    exit 0
else
    echo "❌ BUILD SETUP IS INCOMPLETE!"
    echo ""
    echo "Please fix the errors listed above before building."
    echo "See BUILD_INSTRUCTIONS.md for help."
    echo ""
    exit 1
fi
