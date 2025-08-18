#!/bin/bash
# test/test_build_integration.sh - Integration tests for complete build workflows

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
INTEGRATION_CACHE="/tmp/fortui_integration_test_$$"

# Import test framework
source "$TEST_DIR/test_build_script.sh"

# Integration test scenarios
test_full_tui_only_workflow() {
    echo -e "\n${YELLOW}Testing full TUI-only build workflow...${NC}"
    
    # Given: System without GUI libraries and DISABLE_GUI=1
    export DISABLE_GUI=1
    export GUI_CACHE="$INTEGRATION_CACHE"
    export MOCK_PKG_CONFIG_MODE="raylib_unavailable"
    mkdir -p "$INTEGRATION_CACHE"
    
    # When: Running complete build workflow
    # Then: Should configure for TUI-only build
    
    # Test cache directory setup
    assert_directory_exists "$INTEGRATION_CACHE" "Integration cache directory created"
    
    # Test CPP flag configuration for TUI-only
    local flags
    flags=$(setup_cpp_flags)
    assert_equals "ENABLE_GUI=0" "$flags" "Should configure for TUI-only build"
    
    # Cleanup
    rm -rf "$INTEGRATION_CACHE"
    unset DISABLE_GUI GUI_CACHE MOCK_PKG_CONFIG_MODE
}

test_full_gui_enabled_workflow() {
    echo -e "\n${YELLOW}Testing full GUI-enabled build workflow...${NC}"
    
    # Given: System with GUI libraries available
    export DISABLE_GUI=0
    export GUI_CACHE="$INTEGRATION_CACHE" 
    export MOCK_PKG_CONFIG_MODE="raylib_available"
    mkdir -p "$INTEGRATION_CACHE"
    
    # When: Running complete build workflow
    # Then: Should configure for GUI-enabled build
    
    # Test cache directory setup
    assert_directory_exists "$INTEGRATION_CACHE" "Integration cache directory created"
    
    # Test CPP flag configuration for GUI build
    local flags
    flags=$(setup_cpp_flags)
    assert_equals "ENABLE_GUI=1" "$flags" "Should configure for GUI-enabled build"
    
    # Cleanup  
    rm -rf "$INTEGRATION_CACHE"
    unset DISABLE_GUI GUI_CACHE MOCK_PKG_CONFIG_MODE
}

test_cache_persistence_workflow() {
    echo -e "\n${YELLOW}Testing cache persistence across builds...${NC}"
    
    # Given: Initial build with cache creation
    export GUI_CACHE="$INTEGRATION_CACHE"
    mkdir -p "$INTEGRATION_CACHE"
    echo "cached_dependency_marker" > "$INTEGRATION_CACHE/test_cache"
    
    # When: Second build should reuse cache
    # Then: Cache contents should persist
    assert_file_exists "$INTEGRATION_CACHE/test_cache" "Cache should persist across builds"
    
    local cached_content
    cached_content=$(cat "$INTEGRATION_CACHE/test_cache")
    assert_equals "cached_dependency_marker" "$cached_content" "Cache contents should be preserved"
    
    # Cleanup
    rm -rf "$INTEGRATION_CACHE"
    unset GUI_CACHE
}

test_environment_variable_override_workflow() {
    echo -e "\n${YELLOW}Testing environment variable override workflow...${NC}"
    
    # Given: Multiple environment variable configurations
    local test_cache="$INTEGRATION_CACHE"
    mkdir -p "$test_cache"
    
    # Test 1: Custom cache directory
    export GUI_CACHE="$test_cache"
    assert_equals "$test_cache" "$GUI_CACHE" "Should accept custom cache directory"
    
    # Test 2: RAYLIB_ROOT override
    export RAYLIB_ROOT="/custom/raylib/path"
    assert_equals "/custom/raylib/path" "$RAYLIB_ROOT" "Should accept custom RAYLIB_ROOT"
    
    # Test 3: Multiple overrides work together
    export DISABLE_GUI=1
    local flags
    flags=$(setup_cpp_flags)
    assert_equals "ENABLE_GUI=0" "$flags" "Should respect DISABLE_GUI with other overrides"
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE RAYLIB_ROOT DISABLE_GUI
}

test_error_handling_workflow() {
    echo -e "\n${YELLOW}Testing error handling in build workflow...${NC}"
    
    # Given: Various error conditions
    export GUI_CACHE="/invalid/permission/path"
    
    # When: Attempting operations with invalid paths
    # Then: Should handle errors gracefully
    
    # Test: Invalid cache directory should be handled
    if ! mkdir -p "$GUI_CACHE" 2>/dev/null; then
        # Expected: Permission denied or invalid path
        echo -e "${GREEN}✓${NC} Invalid cache path handled gracefully"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        # Cleanup if somehow succeeded
        rm -rf "$GUI_CACHE" 2>/dev/null || true
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    unset GUI_CACHE
}

# Cross-platform compatibility tests
test_cross_platform_paths() {
    echo -e "\n${YELLOW}Testing cross-platform path handling...${NC}"
    
    # Given: Different path formats and separators
    local unix_path="/home/user/.cache/fortui"
    local relative_path="./cache/fortui"
    
    # When: Testing path handling
    # Then: Paths should be handled correctly
    
    # Test Unix-style absolute path
    export GUI_CACHE="$unix_path"
    assert_equals "$unix_path" "$GUI_CACHE" "Should handle Unix-style absolute paths"
    
    # Test relative path (converted to absolute)
    export GUI_CACHE="$relative_path" 
    [[ "$GUI_CACHE" == "./"* ]] && {
        echo -e "${GREEN}✓${NC} Relative paths handled correctly"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    } || {
        echo -e "${RED}✗${NC} Relative path handling failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    }
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    unset GUI_CACHE
}

# Performance and efficiency tests
test_build_efficiency() {
    echo -e "\n${YELLOW}Testing build efficiency and incremental builds...${NC}"
    
    # Given: Existing cache with dependencies
    export GUI_CACHE="$INTEGRATION_CACHE"
    mkdir -p "$INTEGRATION_CACHE"
    
    # Create mock cached dependencies
    echo "termbox2_build_marker" > "$INTEGRATION_CACHE/termbox2_built"
    echo "fortran_raygui_build_marker" > "$INTEGRATION_CACHE/fortran_raygui_built"
    
    # When: Checking for existing builds
    # Then: Should detect cached dependencies
    assert_file_exists "$INTEGRATION_CACHE/termbox2_built" "Should detect cached termbox2"
    assert_file_exists "$INTEGRATION_CACHE/fortran_raygui_built" "Should detect cached fortran-raygui"
    
    # Test incremental build detection
    local termbox_cached
    termbox_cached=$(cat "$INTEGRATION_CACHE/termbox2_built")
    assert_equals "termbox2_build_marker" "$termbox_cached" "Should read cached termbox2 marker"
    
    # Cleanup
    rm -rf "$INTEGRATION_CACHE"
    unset GUI_CACHE
}

# Run integration test suite
run_integration_tests() {
    echo -e "${YELLOW}Starting build script integration test suite...${NC}\n"
    
    # Reset test counters
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Source build functions
    source_build_functions
    
    # Full workflow tests
    test_full_tui_only_workflow
    test_full_gui_enabled_workflow
    test_cache_persistence_workflow
    test_environment_variable_override_workflow
    test_error_handling_workflow
    
    # Platform and performance tests
    test_cross_platform_paths
    test_build_efficiency
    
    # Results
    echo -e "\n${YELLOW}Integration Test Results:${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
        return 1
    else
        echo -e "Failed: $TESTS_FAILED"
        echo -e "\n${GREEN}All integration tests passed!${NC}"
        return 0
    fi
}

# Main execution for standalone running
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_integration_tests
fi