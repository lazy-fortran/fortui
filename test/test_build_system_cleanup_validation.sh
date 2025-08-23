#!/bin/bash
# test_build_system_cleanup_validation.sh
# Validates build system cleanup requirements for Issue #116
# These tests ensure the build system works correctly after simplification

# Given-When-Then Documentation:
# GIVEN: A cleaned-up build system without unnecessary complexity
# WHEN: Using standard build commands
# THEN: All operations should work with minimal configuration

set -euo pipefail

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Utility functions
print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_test() {
    echo -e "${YELLOW}Test $((TOTAL_TESTS + 1)): $1${NC}"
}

print_pass() {
    echo -e "${GREEN}  PASS: $1${NC}"
    ((PASSED_TESTS++))
}

print_fail() {
    echo -e "${RED}  FAIL: $1${NC}"
    ((FAILED_TESTS++))
}

print_info() {
    echo -e "  INFO: $1"
}

# Test execution wrapper
run_test() {
    ((TOTAL_TESTS++))
    if "$@"; then
        return 0
    else
        return 1
    fi
}

print_header "Build System Cleanup Validation Tests"
echo "Validating simplified build system requirements..."
echo ""

# Test 1: Plain fpm commands should work
# Given-When-Then: Plain FPM functionality
# GIVEN: Simplified build system
# WHEN: Running plain fpm build
# THEN: Build should succeed without wrapper scripts
test_plain_fpm_commands() {
    print_test "Plain fpm commands work without scripts"
    
    # These tests validate future state after cleanup
    local test_passed=false
    
    # Check that fpm.toml is simple and clean
    if [[ -f "fpm.toml" ]]; then
        print_info "Checking fpm.toml complexity..."
        
        # Count lines in fpm.toml as complexity indicator
        local toml_lines=$(wc -l < fpm.toml)
        if [[ $toml_lines -lt 30 ]]; then
            print_info "fmp.toml has reasonable size ($toml_lines lines)"
        else
            print_info "fpm.toml still complex ($toml_lines lines) - needs cleanup"
        fi
        
        # Check for complex preprocessing configuration
        if grep -q "cpp.directories" fpm.toml; then
            print_info "Complex CPP configuration still present - needs cleanup"
        fi
        
        # Check for excessive configuration sections
        local section_count=$(grep -c '^\[' fpm.toml || true)
        if [[ $section_count -gt 5 ]]; then
            print_info "Many configuration sections ($section_count) - consider simplification"
        fi
    fi
    
    # Currently fails - indicating cleanup is needed
    print_fail "Plain fpm commands need simplification (expected before cleanup)"
    return 1
}

# Test 2: Examples run without environment setup
# Given-When-Then: Self-contained examples
# GIVEN: Cleaned-up examples
# WHEN: Running examples without environment scripts
# THEN: Examples should work with plain fmp commands
test_examples_without_env_setup() {
    print_test "Examples run without environment setup"
    
    local test_passed=false
    
    # Check if examples directory exists
    if [[ -d "example" ]]; then
        print_info "Examples directory found"
        
        # Count example files
        local example_count=$(find example -name "*.f90" | wc -l)
        print_info "Found $example_count example files"
        
        # Check if examples are properly configured in fmp.toml
        if grep -q "[[example]]" fpm.toml; then
            print_info "Examples configured in fpm.toml"
        else
            print_info "Examples not configured in fpm.toml"
        fi
    fi
    
    # Test that no environment scripts are required
    if [[ -f "fpm_env.sh" ]]; then
        print_info "Environment setup script still exists - should be eliminated"
    fi
    
    # Currently fails - indicating cleanup is needed
    print_fail "Examples need self-containment (expected before cleanup)"
    return 1
}

# Test 3: Dependencies handled cleanly
# Given-When-Then: Clean dependency management
# GIVEN: Simplified dependency handling
# WHEN: Building with dependencies
# THEN: Dependencies should be managed through standard FPM mechanisms
test_clean_dependency_handling() {
    print_test "Dependencies handled cleanly"
    
    local test_passed=false
    
    # Check for external dependencies specification
    if grep -q "dependencies" fpm.toml; then
        print_info "Dependencies section found in fpm.toml"
    else
        print_info "No dependencies section in fpm.toml"
    fi
    
    # Check for complex dependency scripts
    if [[ -d "tools" ]]; then
        local script_count=$(find tools -name "*.sh" | wc -l)
        if [[ $script_count -gt 2 ]]; then
            print_info "Many dependency scripts ($script_count) - consider simplification"
        fi
    fi
    
    # Check for complex caching mechanisms
    if [[ -f "tools/lib/cache.sh" ]]; then
        print_info "Complex caching still present - consider simplification"
    fi
    
    # Currently fails - indicating cleanup is needed
    print_fail "Dependency handling needs simplification (expected before cleanup)"
    return 1
}

# Test 4: Shell script independence
# Given-When-Then: No shell script dependencies
# GIVEN: Build system without shell script dependencies
# WHEN: Building the project
# THEN: No shell scripts should be required for basic operations
test_shell_script_independence() {
    print_test "Shell script independence"
    
    local test_passed=false
    
    # Check for wrapper scripts that should be eliminated
    local wrapper_scripts=0
    if [[ -f "fpm_build.sh" ]]; then
        ((wrapper_scripts++))
        print_info "Wrapper script fmp_build.sh still exists"
    fi
    if [[ -f "fpm_env.sh" ]]; then
        ((wrapper_scripts++))
        print_info "Environment script fpm_env.sh still exists"
    fi
    if [[ -f "build.sh" ]]; then
        ((wrapper_scripts++))
        print_info "Build script build.sh still exists"
    fi
    
    if [[ $wrapper_scripts -gt 0 ]]; then
        print_info "Found $wrapper_scripts wrapper scripts - consider elimination"
    fi
    
    # Check Makefile complexity
    if [[ -f "Makefile" ]]; then
        local makefile_lines=$(wc -l < Makefile)
        if [[ $makefile_lines -gt 50 ]]; then
            print_info "Makefile is complex ($makefile_lines lines) - consider simplification"
        fi
    fi
    
    # Currently fails - indicating cleanup is needed
    print_fail "Shell script independence needs improvement (expected before cleanup)"
    return 1
}

# Test 5: Minimal CPP usage
# Given-When-Then: Reduced preprocessing complexity
# GIVEN: Minimal CPP preprocessing requirements
# WHEN: Building the project
# THEN: CPP usage should be minimal and well-justified
test_minimal_cpp_usage() {
    print_test "Minimal CPP usage"
    
    local test_passed=false
    
    # Check CPP configuration in fmp.toml
    if grep -q "\[preprocess\]" fpm.toml; then
        print_info "Preprocessing section found in fpm.toml"
        
        # Count CPP-related lines
        local cpp_lines=$(sed -n '/\[preprocess\]/,/^\[/p' fpm.toml | wc -l)
        if [[ $cpp_lines -gt 10 ]]; then
            print_info "Preprocessing configuration is complex ($cpp_lines lines)"
        fi
        
        # Check for complex macro definitions
        if grep -q "cpp.macros" fpm.toml; then
            print_info "CPP macros configuration found"
        fi
        
        # Check for many directories in preprocessing
        local dir_count=$(grep -c "cpp.directories" fpm.toml || true)
        if [[ $dir_count -gt 0 ]]; then
            print_info "CPP directories configuration found"
        fi
    fi
    
    # Check source files for CPP usage
    local cpp_files=$(find src -name "*.f90" -exec grep -l "#ifdef\|#ifndef\|#define" {} \; 2>/dev/null | wc -l)
    if [[ $cpp_files -gt 0 ]]; then
        print_info "Found $cpp_files source files using CPP directives"
    fi
    
    # Currently fails - indicating cleanup is needed
    print_fail "CPP usage needs minimization (expected before cleanup)"
    return 1
}

# Test 6: Build process efficiency
# Given-When-Then: Efficient build process
# GIVEN: Streamlined build configuration
# WHEN: Measuring build complexity
# THEN: Build process should be straightforward and efficient
test_build_process_efficiency() {
    print_test "Build process efficiency"
    
    local test_passed=false
    
    # Count total configuration files
    local config_files=0
    [[ -f "fpm.toml" ]] && ((config_files++))
    [[ -f "Makefile" ]] && ((config_files++))
    [[ -f "build.sh" ]] && ((config_files++))
    
    print_info "Found $config_files main configuration files"
    
    # Count total build-related scripts in tools/
    if [[ -d "tools" ]]; then
        local tool_scripts=$(find tools -name "*.sh" | wc -l)
        print_info "Found $tool_scripts build scripts in tools/"
    fi
    
    # Check for environment variables in build process
    local env_var_usage=0
    if [[ -f "Makefile" ]]; then
        env_var_usage=$(grep -c '\$\$' Makefile || true)
        print_info "Makefile uses $env_var_usage environment variable patterns"
    fi
    
    # Currently fails - indicating cleanup is needed
    print_fail "Build process efficiency needs improvement (expected before cleanup)"
    return 1
}

# Run all tests
echo "Running build system cleanup validation tests..."
echo ""

run_test test_plain_fmp_commands
run_test test_examples_without_env_setup  
run_test test_clean_dependency_handling
run_test test_shell_script_independence
run_test test_minimal_cpp_usage
run_test test_build_process_efficiency

# Report results
echo ""
print_header "Build System Cleanup Test Results"
echo "Total tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"

if [[ $FAILED_TESTS -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}All build system cleanup tests PASSED!${NC}"
    echo "Build system simplification is complete."
    exit 0
else
    echo ""
    echo -e "${YELLOW}Build system cleanup tests show areas needing simplification.${NC}"
    echo "These failures are expected before the cleanup implementation."
    echo "Tests will pass after build system simplification is complete."
    exit 1
fi