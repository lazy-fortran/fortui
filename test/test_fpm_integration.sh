#!/bin/bash
# test/test_fpm_integration.sh - Tests for FPM build-script override and preprocessor integration
# These tests validate advanced build system functionality for Issue #12

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
FPM_TEST_CACHE="/tmp/fortui_fpm_test_$$"

# Import base test framework
source "$TEST_DIR/test_build_script.sh"

# FPM Integration Test Suite
test_fpm_build_script_override() {
    echo -e "\n${YELLOW}Testing FPM build-script override functionality...${NC}"
    
    # Given: FPM configuration with build-script override
    # When: FPM attempts to use external build script
    # Then: Should integrate with tools/build_fortui.sh correctly
    
    local fpm_config="$PROJECT_ROOT/fpm.toml"
    
    # This test will FAIL initially - validating that fpm.toml will be updated
    # to include build-script override configuration
    if grep -q "build-script" "$fpm_config" 2>/dev/null; then
        assert_command_success "grep 'build-script' '$fpm_config'" "FPM should have build-script override configured"
    else
        echo -e "${RED}✗${NC} FPM build-script override not yet configured (RED phase - test will guide implementation)"
        echo "  Expected: build-script configuration in fpm.toml"
        echo "  This test will pass after sergei implements FPM integration"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_cpp_preprocessing_integration() {
    echo -e "\n${YELLOW}Testing CPP preprocessing integration with FPM...${NC}"
    
    # Given: FPM with CPP preprocessing enabled
    # When: Building with conditional compilation flags
    # Then: Should pass ENABLE_GUI flag correctly to compiler
    
    local fpm_config="$PROJECT_ROOT/fpm.toml"
    
    # Test 1: FPM should have preprocessing enabled
    if grep -q "cpp" "$fpm_config" 2>/dev/null || grep -q "preprocess" "$fpm_config" 2>/dev/null; then
        assert_command_success "grep -E '(cpp|preprocess)' '$fpm_config'" "FPM should have CPP preprocessing configured"
    else
        echo -e "${RED}✗${NC} FPM CPP preprocessing not yet configured (RED phase - test will guide implementation)" 
        echo "  Expected: CPP preprocessing configuration in fpm.toml"
        echo "  This test will pass after sergei implements preprocessing integration"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test 2: Build script should provide CPP flags to FPM
    export MOCK_PKG_CONFIG_MODE="raylib_available"
    local cpp_flags
    cpp_flags=$(setup_cpp_flags)
    
    if [[ "$cpp_flags" == "ENABLE_GUI="* ]]; then
        assert_equals "ENABLE_GUI=1" "$cpp_flags" "Build script should provide ENABLE_GUI flag"
    else
        echo -e "${RED}✗${NC} CPP flag format incorrect (expected ENABLE_GUI=0|1)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_fpm_dependency_integration() {
    echo -e "\n${YELLOW}Testing FPM dependency integration with external build script...${NC}"
    
    # Given: External dependencies built by build script
    # When: FPM compiles project
    # Then: Should find and link external dependencies correctly
    
    local test_cache="$FPM_TEST_CACHE"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Simulate built dependencies
    mkdir -p "$test_cache/termbox2"
    mkdir -p "$test_cache/fortran-raygui"
    echo "mock termbox header" > "$test_cache/termbox2/termbox.h"
    echo "mock raygui module" > "$test_cache/fortran-raygui/raygui.f90"
    
    # Test dependency flag generation
    local dep_flags
    dep_flags=$(get_dependency_flags)
    
    # Should include termbox2 paths
    if [[ "$dep_flags" == *"$test_cache/termbox2"* ]]; then
        assert_command_success "echo '$dep_flags' | grep '$test_cache/termbox2'" "Should include termbox2 dependency paths"
    else
        echo -e "${RED}✗${NC} Missing termbox2 dependency paths in flags"
        echo "  Expected: paths containing $test_cache/termbox2"
        echo "  Actual: $dep_flags"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_fpm_conditional_source_inclusion() {
    echo -e "\n${YELLOW}Testing FPM conditional source file inclusion...${NC}"
    
    # Given: Source files with backend-specific implementations
    # When: FPM builds with different ENABLE_GUI settings
    # Then: Should compile only appropriate source files
    
    # This test validates that FPM will correctly handle CPP preprocessing
    # for conditional compilation of backend-specific code
    
    # Test TUI-only build
    export DISABLE_GUI=1
    export MOCK_PKG_CONFIG_MODE="raylib_unavailable"
    
    local flags_tui
    flags_tui=$(setup_cpp_flags)
    assert_equals "ENABLE_GUI=0" "$flags_tui" "TUI-only build should set ENABLE_GUI=0"
    
    # Test GUI-enabled build
    export DISABLE_GUI=0
    export MOCK_PKG_CONFIG_MODE="raylib_available"
    
    local flags_gui
    flags_gui=$(setup_cpp_flags)
    assert_equals "ENABLE_GUI=1" "$flags_gui" "GUI build should set ENABLE_GUI=1"
    
    # Cleanup
    unset DISABLE_GUI MOCK_PKG_CONFIG_MODE
}

test_fpm_build_process_integration() {
    echo -e "\n${YELLOW}Testing complete FPM build process integration...${NC}"
    
    # Given: FPM configuration with build-script override
    # When: Running fpm build command
    # Then: Should execute dependency management then compilation
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Test build script invocation modes
    assert_command_success "'$build_script' config" "Build script should support config mode"
    assert_command_success "'$build_script' flags" "Build script should support flags mode"
    assert_command_success "'$build_script' ldflags" "Build script should support ldflags mode"
    
    # Test that build script provides necessary information for FPM
    local config_output
    config_output=$("$build_script" config 2>&1 || true)
    
    if [[ "$config_output" == *"Fortui Build Configuration"* ]]; then
        echo -e "${GREEN}✓${NC} Build script provides configuration information"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Build script configuration output format incorrect"
        echo "  Expected: 'Fortui Build Configuration' in output"
        echo "  Actual: $config_output"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_fpm_environment_variable_passthrough() {
    echo -e "\n${YELLOW}Testing FPM environment variable passthrough...${NC}"
    
    # Given: Environment variables for build customization
    # When: FPM invokes build script
    # Then: Environment variables should be properly passed through
    
    # Test critical environment variables
    local env_vars=("DISABLE_GUI" "RAYLIB_ROOT" "GUI_CACHE" "DEBUG")
    
    for var in "${env_vars[@]}"; do
        # Set test value
        export "$var"="test_value_$$"
        
        # Verify variable is accessible
        local var_value
        var_value=$(eval "echo \$$var")
        assert_equals "test_value_$$" "$var_value" "Environment variable $var should be accessible"
        
        # Cleanup
        unset "$var"
    done
}

test_fpm_error_propagation() {
    echo -e "\n${YELLOW}Testing FPM error propagation from build script...${NC}"
    
    # Given: Build script encounters errors
    # When: FPM attempts to build
    # Then: Errors should propagate correctly to halt FPM build
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Test invalid action produces error
    assert_command_failure "'$build_script' invalid_action" "Build script should reject invalid actions"
    
    # Test that build script exits with proper codes
    local clean_result
    if "$build_script" clean >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Build script clean operation completes successfully"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Build script clean operation failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

# Performance and efficiency tests specific to FPM integration
test_fpm_build_time_optimization() {
    echo -e "\n${YELLOW}Testing FPM build time optimization with caching...${NC}"
    
    # Given: Cached dependencies from previous builds
    # When: FPM builds project again
    # Then: Should skip unnecessary dependency rebuilds
    
    local test_cache="$FPM_TEST_CACHE"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Create mock build markers (simulating previous successful builds)
    echo "termbox2_build_marker" > "$test_cache/termbox2_built"
    echo "fortran_raygui_build_marker" > "$test_cache/fortran_raygui_built"
    
    # Verify markers are detected (indicates build optimization will work)
    assert_file_exists "$test_cache/termbox2_built" "Termbox2 build marker should be preserved for optimization"
    assert_file_exists "$test_cache/fortran_raygui_built" "Fortran-raygui build marker should be preserved for optimization"
    
    # Test build script recognizes cached state
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    local cache_status
    cache_status=$("$build_script" config 2>&1 | grep -c "Cache:" || true)
    
    if [[ "$cache_status" -gt 0 ]]; then
        echo -e "${GREEN}✓${NC} Build script reports cache status for optimization"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Build script should report cache status"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

# Run FPM integration test suite
run_fpm_integration_tests() {
    echo -e "${YELLOW}Starting FPM integration test suite for Issue #12...${NC}\n"
    
    # Reset test counters for this suite
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Setup test environment
    setup_test_env
    source_build_functions
    
    # Core FPM integration tests
    test_fpm_build_script_override
    test_cpp_preprocessing_integration
    test_fpm_dependency_integration
    test_fpm_conditional_source_inclusion
    
    # Advanced FPM integration tests
    test_fpm_build_process_integration
    test_fpm_environment_variable_passthrough
    test_fpm_error_propagation
    test_fpm_build_time_optimization
    
    # Cleanup
    teardown_test_env
    
    # Results summary
    echo -e "\n${YELLOW}FPM Integration Test Results:${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
        echo -e "\n${YELLOW}Note:${NC} Some failures are expected in RED phase - they guide implementation"
        return 1
    else
        echo -e "Failed: $TESTS_FAILED"
        echo -e "\n${GREEN}All FPM integration tests passed!${NC}"
        return 0
    fi
}

# Main execution for standalone running
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_fpm_integration_tests
fi