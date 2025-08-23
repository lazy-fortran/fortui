#!/bin/bash
# test_build_system_cleanup_master.sh
# Master test suite for build system cleanup validation (Issue #116)
# Orchestrates all build system cleanup tests

# Given-When-Then Documentation:
# GIVEN: A complete set of build system cleanup tests
# WHEN: Running the master test suite
# THEN: All aspects of build simplification should be validated

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test tracking
TOTAL_TEST_SUITES=0
PASSED_TEST_SUITES=0
FAILED_TEST_SUITES=0
TOTAL_INDIVIDUAL_TESTS=0
PASSED_INDIVIDUAL_TESTS=0
FAILED_INDIVIDUAL_TESTS=0

# Utility functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_suite_header() {
    echo ""
    echo -e "${CYAN}--- Test Suite $((TOTAL_TEST_SUITES + 1)): $1 ---${NC}"
}

print_pass() {
    echo -e "${GREEN}PASS: $1${NC}"
}

print_fail() {
    echo -e "${RED}FAIL: $1${NC}"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

print_summary() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Build System Cleanup Test Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Test Suites:"
    echo -e "  Total: $TOTAL_TEST_SUITES"
    echo -e "  Passed: ${GREEN}$PASSED_TEST_SUITES${NC}"
    echo -e "  Failed: ${RED}$FAILED_TEST_SUITES${NC}"
    echo ""
    echo "Individual Tests:"
    echo -e "  Total: $TOTAL_INDIVIDUAL_TESTS"
    echo -e "  Passed: ${GREEN}$PASSED_INDIVIDUAL_TESTS${NC}"
    echo -e "  Failed: ${RED}$FAILED_INDIVIDUAL_TESTS${NC}"
    echo ""
    
    if [[ $FAILED_TEST_SUITES -eq 0 ]]; then
        echo -e "${GREEN}All build system cleanup test suites PASSED!${NC}"
        echo "Build system simplification validation is complete."
    else
        echo -e "${YELLOW}Some test suites show areas needing cleanup work.${NC}"
        echo "These failures are expected before implementation of Issue #116."
        echo "Tests will pass after build system simplification is complete."
    fi
}

# Test execution wrapper
run_test_suite() {
    local suite_name="$1"
    local test_command="$2"
    local expected_to_fail="${3:-true}" # Most tests expected to fail before cleanup
    
    ((TOTAL_TEST_SUITES++))
    print_suite_header "$suite_name"
    
    local exit_code=0
    if eval "$test_command"; then
        ((PASSED_TEST_SUITES++))
        print_pass "$suite_name completed successfully"
        if [[ "$expected_to_fail" == "true" ]]; then
            print_info "Unexpectedly passed - build system may already be simplified"
        fi
    else
        exit_code=$?
        ((FAILED_TEST_SUITES++))
        print_fail "$suite_name failed with exit code $exit_code"
        if [[ "$expected_to_fail" == "true" ]]; then
            print_info "Expected failure before build system cleanup implementation"
        else
            print_info "Unexpected failure - needs investigation"
        fi
    fi
    
    return $exit_code
}

# Test runner for Fortran tests
run_fortran_test() {
    local test_file="$1"
    local test_name="$2"
    
    print_info "Compiling and running $test_name..."
    
    # Use project build system for targeted test execution
    if [[ -f "$PROJECT_ROOT/Makefile" ]]; then
        # Try using project Makefile for test compilation
        if cd "$PROJECT_ROOT" && make build >/dev/null 2>&1; then
            print_info "Project built successfully for testing"
        else
            print_info "Project build failed - using direct compilation"
        fi
    fi
    
    # Try direct compilation with gfortran if available
    if command -v gfortran >/dev/null 2>&1; then
        local test_binary="${test_file%%.f90}"
        if gfortran -o "$test_binary" "$test_file" 2>/dev/null; then
            if "./$test_binary"; then
                rm -f "$test_binary" 2>/dev/null
                return 0
            else
                local exit_code=$?
                rm -f "$test_binary" 2>/dev/null
                return $exit_code
            fi
        else
            print_info "Compilation failed for $test_name"
            return 1
        fi
    else
        print_info "No Fortran compiler available for $test_name"
        return 1
    fi
}

print_header "Build System Cleanup Validation Master Suite"
echo "Testing all aspects of build system simplification for Issue #116"
echo ""
echo "These tests validate the requirements for build system cleanup:"
echo "  1. Plain fpm build should work without scripts"
echo "  2. Examples should run without environment variables"  
echo "  3. Dependencies should be handled cleanly"
echo "  4. Shell script dependencies should be eliminated"
echo "  5. CPP usage should be minimal"
echo ""
echo "Expected behavior: Most tests will FAIL before cleanup implementation"
echo "After Issue #116 implementation, these tests should PASS"

# Change to test directory
cd "$SCRIPT_DIR"

# Test Suite 1: Build System Simplification (Fortran)
run_test_suite "Build System Simplification Tests" \
    "run_fortran_test 'test_build_system_simplification.f90' 'Build System Simplification'"

# Test Suite 2: Build System Cleanup Validation (Shell)
run_test_suite "Build System Cleanup Validation" \
    "./test_build_system_cleanup_validation.sh"

# Test Suite 3: Build Integration Simplified (Fortran)  
run_test_suite "Build Integration Simplified Tests" \
    "run_fortran_test 'test_build_integration_simplified.f90' 'Build Integration Simplified'"

# Test Suite 4: CPP Usage Minimal (Fortran)
run_test_suite "Minimal CPP Usage Tests" \
    "run_fortran_test 'test_cpp_usage_minimal.f90' 'CPP Usage Minimal'"

# Test Suite 5: Current Build System Analysis (for comparison)
run_test_suite "Current Build System Analysis" \
    "analyze_current_build_system" \
    "false" # This one should pass to show current state

# Analysis function for current build system
analyze_current_build_system() {
    print_info "Analyzing current build system complexity..."
    
    local complexity_score=0
    local analysis_passed=true
    
    # Count configuration files
    local config_files=0
    [[ -f "$PROJECT_ROOT/fpm.toml" ]] && ((config_files++))
    [[ -f "$PROJECT_ROOT/Makefile" ]] && ((config_files++))
    [[ -f "$PROJECT_ROOT/build.sh" ]] && ((config_files++))
    print_info "Configuration files: $config_files"
    
    # Count wrapper scripts
    local wrapper_scripts=0
    [[ -f "$PROJECT_ROOT/fpm_build.sh" ]] && ((wrapper_scripts++))
    [[ -f "$PROJECT_ROOT/fpm_env.sh" ]] && ((wrapper_scripts++))
    print_info "Wrapper scripts: $wrapper_scripts"
    
    # Count tool scripts
    local tool_scripts=0
    if [[ -d "$PROJECT_ROOT/tools" ]]; then
        tool_scripts=$(find "$PROJECT_ROOT/tools" -name "*.sh" 2>/dev/null | wc -l)
    fi
    print_info "Tool scripts: $tool_scripts"
    
    # Analyze fpm.toml complexity
    if [[ -f "$PROJECT_ROOT/fpm.toml" ]]; then
        local toml_lines=$(wc -l < "$PROJECT_ROOT/fpm.toml")
        print_info "fpm.toml size: $toml_lines lines"
        
        local sections=$(grep -c '^\[' "$PROJECT_ROOT/fmp.toml" 2>/dev/null || true)
        print_info "fpm.toml sections: $sections"
    fi
    
    # Calculate overall complexity score
    complexity_score=$((config_files + wrapper_scripts + tool_scripts))
    print_info "Overall complexity score: $complexity_score"
    
    if [[ $complexity_score -gt 10 ]]; then
        print_info "High complexity detected - cleanup recommended"
    elif [[ $complexity_score -gt 5 ]]; then
        print_info "Moderate complexity detected - cleanup beneficial"
    else
        print_info "Low complexity detected - minimal cleanup needed"
    fi
    
    return 0  # Analysis always succeeds
}

# Generate final summary
print_summary

# Determine exit code based on results
if [[ $FAILED_TEST_SUITES -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}Build system cleanup validation completed successfully!${NC}"
    exit 0
else
    echo ""
    echo -e "${YELLOW}Build system cleanup validation completed with expected failures.${NC}"
    echo "These test failures indicate areas where Issue #116 cleanup is needed."
    exit 1
fi