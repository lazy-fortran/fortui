#!/bin/bash
# test/test_cross_platform.sh - Cross-platform build system tests
# Tests for Issue #12: Linux, macOS, Windows path handling and platform detection

set -euo pipefail

# Test configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
PLATFORM_TEST_CACHE="/tmp/fortui_platform_test_$$"

# Import base test framework
source "$TEST_DIR/test_build_script.sh"

# Cross-Platform Build System Test Suite

test_platform_detection_accuracy() {
    echo -e "\n${YELLOW}Testing platform detection accuracy...${NC}"
    
    # Given: Various platform environments
    # When: Detecting current platform
    # Then: Should correctly identify platform-specific behaviors
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Test current platform detection
    local detected_platform
    detected_platform=$(source "$build_script" && detect_platform)
    
    # Validate detected platform matches expected values
    case "$detected_platform" in
        "linux"|"macos"|"windows"|"unknown")
            assert_equals "linux" "$detected_platform" "Should detect Linux platform on current system"
            ;;
        *)
            echo -e "${RED}✗${NC} Invalid platform detection result: $detected_platform"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            ;;
    esac
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test platform-specific behavior switches
    if grep -q "case.*uname" "$build_script" 2>/dev/null; then
        assert_command_success "grep -A 10 'case.*uname' '$build_script'" "Build script should have platform-specific logic"
    else
        echo -e "${RED}✗${NC} Platform-specific logic not implemented (RED phase)"
        echo "  Expected: Platform detection with uname-based case statement"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_linux_specific_functionality() {
    echo -e "\n${YELLOW}Testing Linux-specific build functionality...${NC}"
    
    # Given: Linux environment
    # When: Building dependencies
    # Then: Should use Linux-appropriate paths and tools
    
    local test_cache="$PLATFORM_TEST_CACHE/linux"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    # Test pkg-config availability and usage on Linux
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Linux should support pkg-config for raylib detection
    export MOCK_PKG_CONFIG_MODE="raylib_available"
    
    local raylib_detected
    if source "$build_script" && detect_raylib; then
        echo -e "${GREEN}✓${NC} Linux raylib detection via pkg-config works"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Linux raylib detection failed"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test Linux-specific library paths
    local dep_flags
    dep_flags=$(source "$build_script" && get_dependency_flags)
    
    if [[ "$dep_flags" == *"-L"* && "$dep_flags" == *"-l"* ]]; then
        assert_command_success "echo '$dep_flags' | grep -E '(-L.*-l)'" "Linux should use -L/-l linker flags"
    else
        echo -e "${RED}✗${NC} Linux linker flags format incorrect"
        echo "  Expected: -L and -l flags in dependency flags"
        echo "  Actual: $dep_flags"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE MOCK_PKG_CONFIG_MODE
}

test_macos_specific_functionality() {
    echo -e "\n${YELLOW}Testing macOS-specific build functionality...${NC}"
    
    # Given: Simulated macOS environment
    # When: Building dependencies with macOS-specific considerations
    # Then: Should handle macOS paths and frameworks correctly
    
    local test_cache="$PLATFORM_TEST_CACHE/macos"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating macOS-specific logic
    if grep -q "Darwin\|macos\|framework" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(Darwin|macos|framework)' '$build_script'" "Build script should have macOS-specific logic"
    else
        echo -e "${RED}✗${NC} macOS-specific build logic not yet implemented (RED phase)"
        echo "  Expected: macOS/Darwin-specific paths and framework handling"
        echo "  This test will pass after sergei implements macOS support"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test Homebrew path handling for macOS
    if grep -q "brew\|/opt/homebrew\|/usr/local" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(brew|/opt/homebrew|/usr/local)' '$build_script'" "Build script should support Homebrew paths"
    else
        echo -e "${RED}✗${NC} Homebrew path support not yet implemented (RED phase)"
        echo "  Expected: Homebrew path detection for macOS dependencies"
        echo "  This test will pass after sergei implements Homebrew support"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test macOS framework linking
    if grep -q "framework.*raylib\|-framework" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(framework.*raylib|-framework)' '$build_script'" "Build script should support macOS frameworks"
    else
        echo -e "${RED}✗${NC} macOS framework linking not yet implemented (RED phase)"
        echo "  Expected: macOS framework linking for raylib"
        echo "  This test will pass after sergei implements framework support"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_windows_specific_functionality() {
    echo -e "\n${YELLOW}Testing Windows-specific build functionality...${NC}"
    
    # Given: Simulated Windows environment  
    # When: Building dependencies with Windows-specific considerations
    # Then: Should handle Windows paths and libraries correctly
    
    local test_cache="$PLATFORM_TEST_CACHE/windows"
    mkdir -p "$test_cache"
    export GUI_CACHE="$test_cache"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating Windows-specific logic
    if grep -q "MINGW\|MSYS\|CYGWIN\|windows" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(MINGW|MSYS|CYGWIN|windows)' '$build_script'" "Build script should have Windows-specific logic"
    else
        echo -e "${RED}✗${NC} Windows-specific build logic not yet implemented (RED phase)"
        echo "  Expected: Windows/MINGW/MSYS-specific handling"
        echo "  This test will pass after sergei implements Windows support"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test Windows path handling (backslashes vs forward slashes)
    if grep -q "path.*sep\|backslash\|windows.*path" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(path.*sep|backslash|windows.*path)' '$build_script'" "Build script should handle Windows paths"
    else
        echo -e "${RED}✗${NC} Windows path handling not yet implemented (RED phase)"
        echo "  Expected: Windows-specific path separator handling"
        echo "  This test will pass after sergei implements Windows path support"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test Windows library extensions (.dll, .lib)
    if grep -q "\.dll\|\.lib\|\.exe" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '\.(dll|lib|exe)' '$build_script'" "Build script should handle Windows library extensions"
    else
        echo -e "${RED}✗${NC} Windows library extensions not yet implemented (RED phase)"
        echo "  Expected: Windows-specific library extension handling"
        echo "  This test will pass after sergei implements Windows library support"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE
}

test_cross_platform_path_handling() {
    echo -e "\n${YELLOW}Testing cross-platform path handling...${NC}"
    
    # Given: Different path formats across platforms
    # When: Processing paths in build script
    # Then: Should normalize and handle paths correctly
    
    local test_cache="$PLATFORM_TEST_CACHE"
    mkdir -p "$test_cache"
    
    # Test Unix-style paths
    local unix_path="/home/user/.cache/fortui"
    export GUI_CACHE="$unix_path"
    assert_equals "$unix_path" "$GUI_CACHE" "Should handle Unix-style absolute paths"
    
    # Test Windows-style paths (simulated)
    local windows_path="C:\\Users\\user\\AppData\\Local\\fortui"
    export TEST_WINDOWS_PATH="$windows_path"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Build script should normalize paths for cross-platform compatibility
    if grep -q "realpath\|readlink\|normalize" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(realpath|readlink|normalize)' '$build_script'" "Build script should normalize paths"
    else
        echo -e "${RED}✗${NC} Path normalization not yet implemented (RED phase)"
        echo "  Expected: Cross-platform path normalization"
        echo "  This test will pass after sergei implements path normalization"
        TESTS_FAILED $((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test relative path handling
    local relative_path="./cache/fortui"
    export GUI_CACHE="$relative_path"
    
    # Should convert relative to absolute paths for consistency
    if [[ "$GUI_CACHE" == "./"* ]]; then
        echo -e "${GREEN}✓${NC} Relative paths preserved for later normalization"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Relative path handling unexpected"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    rm -rf "$test_cache"
    unset GUI_CACHE TEST_WINDOWS_PATH
}

test_cross_platform_dependency_locations() {
    echo -e "\n${YELLOW}Testing cross-platform dependency location detection...${NC}"
    
    # Given: Platform-specific dependency installation locations
    # When: Detecting system dependencies
    # Then: Should check appropriate locations for each platform
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # Test Linux standard library paths
    local linux_paths=("/usr/lib" "/usr/local/lib" "/lib")
    for path in "${linux_paths[@]}"; do
        if grep -q "$path" "$build_script" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Build script includes Linux path: $path"
            TESTS_PASSED=$((TESTS_PASSED + 1))
        else
            echo -e "${RED}✗${NC} Linux library path not included: $path (RED phase)"
            echo "  Expected: Standard Linux library paths in build script"
            TESTS_FAILED=$((TESTS_FAILED + 1))
        fi
        TESTS_RUN=$((TESTS_RUN + 1))
    done
    
    # Test macOS standard paths  
    if grep -q "/opt/homebrew\|/usr/local" "$build_script" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Build script includes macOS Homebrew paths"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} macOS Homebrew paths not yet implemented (RED phase)"
        echo "  Expected: macOS Homebrew path detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test Windows standard paths
    if grep -q "Program Files\|ProgramData\|AppData" "$build_script" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Build script includes Windows standard paths"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Windows standard paths not yet implemented (RED phase)"
        echo "  Expected: Windows standard installation path detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_cross_platform_compiler_detection() {
    echo -e "\n${YELLOW}Testing cross-platform compiler detection...${NC}"
    
    # Given: Different compilers available on different platforms
    # When: Detecting available compilers
    # Then: Should identify and configure appropriate compilers
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    # This test will FAIL initially - validating compiler detection capability
    if grep -q "gfortran\|ifort\|gcc\|clang" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(gfortran|ifort|gcc|clang)' '$build_script'" "Build script should detect available compilers"
    else
        echo -e "${RED}✗${NC} Compiler detection not yet implemented (RED phase)"
        echo "  Expected: Detection of available Fortran/C compilers"
        echo "  This test will pass after sergei implements compiler detection"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test compiler-specific flags
    if grep -q "flag.*gfortran\|flag.*ifort" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(flag.*gfortran|flag.*ifort)' '$build_script'" "Build script should use compiler-specific flags"
    else
        echo -e "${RED}✗${NC} Compiler-specific flags not yet implemented (RED phase)"
        echo "  Expected: Compiler-specific compilation flags"
        echo "  This test will pass after sergei implements compiler-specific handling"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
}

test_cross_platform_environment_variables() {
    echo -e "\n${YELLOW}Testing cross-platform environment variable handling...${NC}"
    
    # Given: Platform-specific environment variable conventions
    # When: Setting and using environment variables
    # Then: Should handle platform differences correctly
    
    # Test XDG Base Directory specification (Linux)
    local xdg_cache_home="/tmp/test_xdg_cache"
    export XDG_CACHE_HOME="$xdg_cache_home"
    
    local build_script="$PROJECT_ROOT/tools/build_fortui.sh"
    
    if grep -q "XDG_CACHE_HOME" "$build_script" 2>/dev/null; then
        assert_command_success "grep 'XDG_CACHE_HOME' '$build_script'" "Build script should respect XDG_CACHE_HOME"
    else
        echo -e "${RED}✗${NC} XDG Base Directory support incomplete"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test HOME directory handling across platforms
    if grep -q "\$HOME\|%USERPROFILE%" "$build_script" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Build script handles HOME directory detection"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Cross-platform HOME detection not yet implemented (RED phase)"
        echo "  Expected: Support for both \$HOME and %USERPROFILE%"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Test PATH separator handling
    if grep -q "PATH.*separator\|path.*sep" "$build_script" 2>/dev/null; then
        assert_command_success "grep -E '(PATH.*separator|path.*sep)' '$build_script'" "Build script should handle PATH separators"
    else
        echo -e "${RED}✗${NC} PATH separator handling not yet implemented (RED phase)"
        echo "  Expected: Cross-platform PATH separator handling (: vs ;)"
        echo "  This test will pass after sergei implements PATH handling"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    TESTS_RUN=$((TESTS_RUN + 1))
    
    # Cleanup
    unset XDG_CACHE_HOME
}

# Run cross-platform test suite
run_cross_platform_tests() {
    echo -e "${YELLOW}Starting cross-platform build system test suite for Issue #12...${NC}\n"
    
    # Reset test counters for this suite
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Setup test environment
    setup_test_env
    source_build_functions
    
    # Core platform detection tests
    test_platform_detection_accuracy
    
    # Platform-specific functionality tests
    test_linux_specific_functionality
    test_macos_specific_functionality
    test_windows_specific_functionality
    
    # Cross-platform compatibility tests
    test_cross_platform_path_handling
    test_cross_platform_dependency_locations
    test_cross_platform_compiler_detection
    test_cross_platform_environment_variables
    
    # Cleanup
    teardown_test_env
    
    # Results summary
    echo -e "\n${YELLOW}Cross-Platform Test Results:${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
        echo -e "\n${YELLOW}Note:${NC} Many failures are expected in RED phase - they guide cross-platform implementation"
        return 1
    else
        echo -e "Failed: $TESTS_FAILED"
        echo -e "\n${GREEN}All cross-platform tests passed!${NC}"
        return 0
    fi
}

# Main execution for standalone running
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_cross_platform_tests
fi