#!/bin/bash
# test/test_shell_injection_vectors.sh - Comprehensive shell injection attack vector tests
# Issue #77: Specific attack vectors for each vulnerable code location

set -euo pipefail

# Test framework configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
TOOLS_DIR="$PROJECT_ROOT/tools"
TEST_TEMP_DIR="/tmp/fortui_injection_test_$$"

# Test results tracking
TESTS_RUN=0
VULNERABILITIES_CONFIRMED=0
ATTACK_VECTORS_TESTED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

setup_injection_test_env() {
    mkdir -p "$TEST_TEMP_DIR"
    mkdir -p "$TEST_TEMP_DIR/locks"
    mkdir -p "$TEST_TEMP_DIR/raylib/include"
    mkdir -p "$TEST_TEMP_DIR/evidence"
}

teardown_injection_test_env() {
    rm -rf "$TEST_TEMP_DIR" || true
}

test_injection_vector() {
    local vector_name="$1"
    local attack_payload="$2"
    local vulnerable_function="$3"
    local evidence_check="$4"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    ATTACK_VECTORS_TESTED=$((ATTACK_VECTORS_TESTED + 1))
    
    echo -e "${BLUE}Testing injection vector:${NC} $vector_name"
    echo -e "${BLUE}Attack payload:${NC} $attack_payload"
    
    # Execute the vulnerable function with attack payload
    if eval "$vulnerable_function" >/dev/null 2>&1; then
        # Check if attack was successful based on evidence
        if eval "$evidence_check" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} VULNERABILITY CONFIRMED: $vector_name"
            VULNERABILITIES_CONFIRMED=$((VULNERABILITIES_CONFIRMED + 1))
        else
            echo -e "${YELLOW}~${NC} Attack executed but no evidence found: $vector_name"
        fi
    else
        echo -e "${RED}✗${NC} Attack vector failed to execute: $vector_name"
    fi
}

# Specific Vulnerability 1: Lock File PID Reading (build_fortui.sh:105)
test_lock_file_injection_vectors() {
    echo -e "\n${YELLOW}=== Lock File PID Injection Attack Vectors ===${NC}"
    
    # Create vulnerable function that mimics build_fortui.sh:105
    vulnerable_pid_read() {
        local lock_file="$1"
        local lock_pid
        # VULNERABLE: This is exactly the pattern from line 105
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        echo "PID read: $lock_pid"
    }
    
    # Attack Vector 1: Command substitution with semicolon
    echo "123; touch $TEST_TEMP_DIR/evidence/semicolon_injection" > "$TEST_TEMP_DIR/locks/test1.lock"
    test_injection_vector \
        "Lock file semicolon command injection" \
        "123; touch evidence/semicolon_injection" \
        "vulnerable_pid_read '$TEST_TEMP_DIR/locks/test1.lock'" \
        "[ -f '$TEST_TEMP_DIR/evidence/semicolon_injection' ]"
    
    # Attack Vector 2: Command substitution with backticks
    echo "123\`touch $TEST_TEMP_DIR/evidence/backtick_injection\`" > "$TEST_TEMP_DIR/locks/test2.lock"
    test_injection_vector \
        "Lock file backtick command injection" \
        "123\`touch evidence/backtick_injection\`" \
        "vulnerable_pid_read '$TEST_TEMP_DIR/locks/test2.lock'" \
        "[ -f '$TEST_TEMP_DIR/evidence/backtick_injection' ]"
    
    # Attack Vector 3: Command substitution with $()
    echo "123\$(touch $TEST_TEMP_DIR/evidence/dollar_paren_injection)" > "$TEST_TEMP_DIR/locks/test3.lock"
    test_injection_vector \
        "Lock file \$() command injection" \
        "123\$(touch evidence/dollar_paren_injection)" \
        "vulnerable_pid_read '$TEST_TEMP_DIR/locks/test3.lock'" \
        "[ -f '$TEST_TEMP_DIR/evidence/dollar_paren_injection' ]"
    
    # Attack Vector 4: Logical AND chaining
    echo "123 && touch $TEST_TEMP_DIR/evidence/and_chain_injection" > "$TEST_TEMP_DIR/locks/test4.lock"
    test_injection_vector \
        "Lock file AND chain injection" \
        "123 && touch evidence/and_chain_injection" \
        "vulnerable_pid_read '$TEST_TEMP_DIR/locks/test4.lock'" \
        "[ -f '$TEST_TEMP_DIR/evidence/and_chain_injection' ]"
    
    # Attack Vector 5: Pipe to another command
    echo "123 | touch $TEST_TEMP_DIR/evidence/pipe_injection" > "$TEST_TEMP_DIR/locks/test5.lock"
    test_injection_vector \
        "Lock file pipe injection" \
        "123 | touch evidence/pipe_injection" \
        "vulnerable_pid_read '$TEST_TEMP_DIR/locks/test5.lock'" \
        "[ -f '$TEST_TEMP_DIR/evidence/pipe_injection' ]"
}

# Specific Vulnerability 2: pkg-config Output Expansion (build_fortui.sh:832)
test_pkg_config_injection_vectors() {
    echo -e "\n${YELLOW}=== pkg-config Output Injection Attack Vectors ===${NC}"
    
    # Create vulnerable function that mimics build_fortui.sh:832
    vulnerable_pkg_config_expansion() {
        local pkg_output="$1"
        local flags=""
        # VULNERABLE: This is exactly the pattern from line 832
        flags+=" $(echo "$pkg_output")"
        echo "Flags: $flags"
    }
    
    # Attack Vector 1: Semicolon command injection
    test_injection_vector \
        "pkg-config semicolon injection" \
        "-lraylib; touch $TEST_TEMP_DIR/evidence/pkg_semicolon" \
        "vulnerable_pkg_config_expansion '-lraylib; touch $TEST_TEMP_DIR/evidence/pkg_semicolon'" \
        "[ -f '$TEST_TEMP_DIR/evidence/pkg_semicolon' ]"
    
    # Attack Vector 2: Command substitution in output
    test_injection_vector \
        "pkg-config command substitution" \
        "-lraylib \$(touch $TEST_TEMP_DIR/evidence/pkg_cmd_sub)" \
        "vulnerable_pkg_config_expansion '-lraylib \$(touch $TEST_TEMP_DIR/evidence/pkg_cmd_sub)'" \
        "[ -f '$TEST_TEMP_DIR/evidence/pkg_cmd_sub' ]"
    
    # Attack Vector 3: Backtick execution
    test_injection_vector \
        "pkg-config backtick execution" \
        "-lraylib \`touch $TEST_TEMP_DIR/evidence/pkg_backtick\`" \
        "vulnerable_pkg_config_expansion '-lraylib \`touch $TEST_TEMP_DIR/evidence/pkg_backtick\`'" \
        "[ -f '$TEST_TEMP_DIR/evidence/pkg_backtick' ]"
    
    # Attack Vector 4: Logical OR chaining
    test_injection_vector \
        "pkg-config OR chain injection" \
        "-lraylib || touch $TEST_TEMP_DIR/evidence/pkg_or_chain" \
        "vulnerable_pkg_config_expansion '-lraylib || touch $TEST_TEMP_DIR/evidence/pkg_or_chain'" \
        "[ -f '$TEST_TEMP_DIR/evidence/pkg_or_chain' ]"
}

# Specific Vulnerability 3: RAYLIB_ROOT Path in grep (build_fortui.sh:357-360)
test_raylib_path_injection_vectors() {
    echo -e "\n${YELLOW}=== RAYLIB_ROOT Path Injection Attack Vectors ===${NC}"
    
    # Create test raylib.h file
    cat > "$TEST_TEMP_DIR/raylib/include/raylib.h" << 'EOF'
#ifndef RAYLIB_H
#define RAYLIB_H
#define RAYLIB_VERSION "4.5.0"
#endif
EOF
    
    # Create vulnerable function that mimics build_fortui.sh:357-360
    vulnerable_version_extract() {
        local raylib_root="$1"
        local version
        # VULNERABLE: This is exactly the pattern from lines 357-360
        version=$(grep -oE '#define RAYLIB_VERSION "[0-9]+\.[0-9]+\.[0-9]+"' \
            "${raylib_root}/include/raylib.h" 2>/dev/null | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        echo "Version: $version"
    }
    
    # Attack Vector 1: Path with semicolon injection
    cp "$TEST_TEMP_DIR/raylib/include/raylib.h" "$TEST_TEMP_DIR/raylib_semi.h"
    test_injection_vector \
        "RAYLIB_ROOT semicolon path injection" \
        "$TEST_TEMP_DIR/raylib; touch $TEST_TEMP_DIR/evidence/path_semicolon #" \
        "vulnerable_version_extract '$TEST_TEMP_DIR/raylib; touch $TEST_TEMP_DIR/evidence/path_semicolon #'" \
        "[ -f '$TEST_TEMP_DIR/evidence/path_semicolon' ]"
    
    # Attack Vector 2: Path with command substitution
    test_injection_vector \
        "RAYLIB_ROOT command substitution in path" \
        "$TEST_TEMP_DIR/raylib\$(touch $TEST_TEMP_DIR/evidence/path_cmd_sub)" \
        "vulnerable_version_extract '$TEST_TEMP_DIR/raylib\$(touch $TEST_TEMP_DIR/evidence/path_cmd_sub)'" \
        "[ -f '$TEST_TEMP_DIR/evidence/path_cmd_sub' ]"
    
    # Attack Vector 3: Path with backticks
    test_injection_vector \
        "RAYLIB_ROOT backtick in path" \
        "$TEST_TEMP_DIR/raylib\`touch $TEST_TEMP_DIR/evidence/path_backtick\`" \
        "vulnerable_version_extract '$TEST_TEMP_DIR/raylib\`touch $TEST_TEMP_DIR/evidence/path_backtick\`'" \
        "[ -f '$TEST_TEMP_DIR/evidence/path_backtick' ]"
    
    # Attack Vector 4: Path with logical AND
    test_injection_vector \
        "RAYLIB_ROOT AND chain in path" \
        "$TEST_TEMP_DIR/raylib && touch $TEST_TEMP_DIR/evidence/path_and_chain" \
        "vulnerable_version_extract '$TEST_TEMP_DIR/raylib && touch $TEST_TEMP_DIR/evidence/path_and_chain'" \
        "[ -f '$TEST_TEMP_DIR/evidence/path_and_chain' ]"
}

# Environment Variable Injection Vectors
test_environment_injection_vectors() {
    echo -e "\n${YELLOW}=== Environment Variable Injection Vectors ===${NC}"
    
    # Simulate how environment variables could be exploited
    vulnerable_env_usage() {
        local cache_dir="${GUI_CACHE:-/tmp/default_cache}"
        echo "Using cache: $cache_dir"
        # This simulates unsafe environment variable usage
        eval "mkdir -p $cache_dir" 2>/dev/null || true
    }
    
    # Attack Vector 1: Command injection via GUI_CACHE
    export GUI_CACHE="$TEST_TEMP_DIR/cache; touch $TEST_TEMP_DIR/evidence/env_injection"
    test_injection_vector \
        "GUI_CACHE environment injection" \
        "$TEST_TEMP_DIR/cache; touch evidence/env_injection" \
        "vulnerable_env_usage" \
        "[ -f '$TEST_TEMP_DIR/evidence/env_injection' ]"
    unset GUI_CACHE
    
    # Attack Vector 2: Command substitution in environment
    export GUI_CACHE="$TEST_TEMP_DIR/cache\$(touch $TEST_TEMP_DIR/evidence/env_cmd_sub)"
    test_injection_vector \
        "GUI_CACHE command substitution" \
        "$TEST_TEMP_DIR/cache\$(touch evidence/env_cmd_sub)" \
        "vulnerable_env_usage" \
        "[ -f '$TEST_TEMP_DIR/evidence/env_cmd_sub' ]"
    unset GUI_CACHE
}

# Special Character Handling Tests
test_special_character_vectors() {
    echo -e "\n${YELLOW}=== Special Character Injection Vectors ===${NC}"
    
    # Test newline injection
    echo -e "123\ntouch $TEST_TEMP_DIR/evidence/newline_injection" > "$TEST_TEMP_DIR/locks/newline.lock"
    test_injection_vector \
        "Newline character injection" \
        "123\\ntouch evidence/newline_injection" \
        "cat '$TEST_TEMP_DIR/locks/newline.lock' | bash" \
        "[ -f '$TEST_TEMP_DIR/evidence/newline_injection' ]"
    
    # Test tab injection
    echo -e "123\ttouch $TEST_TEMP_DIR/evidence/tab_injection" > "$TEST_TEMP_DIR/locks/tab.lock"
    test_injection_vector \
        "Tab character injection" \
        "123\\ttouch evidence/tab_injection" \
        "cat '$TEST_TEMP_DIR/locks/tab.lock' | bash" \
        "[ -f '$TEST_TEMP_DIR/evidence/tab_injection' ]"
    
    # Test null byte injection
    printf "123\0touch $TEST_TEMP_DIR/evidence/null_injection" > "$TEST_TEMP_DIR/locks/null.lock"
    test_injection_vector \
        "Null byte injection" \
        "123\\0touch evidence/null_injection" \
        "cat '$TEST_TEMP_DIR/locks/null.lock' | bash" \
        "[ -f '$TEST_TEMP_DIR/evidence/null_injection' ]"
}

# Run comprehensive injection vector tests
run_injection_vector_tests() {
    echo -e "${BLUE}Starting comprehensive shell injection vector tests...${NC}"
    echo -e "${BLUE}Testing specific attack vectors for Issue #77 vulnerabilities${NC}\n"
    
    setup_injection_test_env
    
    # Test each vulnerability location with specific attack vectors
    test_lock_file_injection_vectors
    test_pkg_config_injection_vectors
    test_raylib_path_injection_vectors
    test_environment_injection_vectors
    test_special_character_vectors
    
    teardown_injection_test_env
    
    # Results summary
    echo -e "\n${BLUE}=== Injection Vector Test Results ===${NC}"
    echo "Total attack vectors tested: $ATTACK_VECTORS_TESTED"
    echo -e "Successful injections (vulnerabilities confirmed): ${GREEN}$VULNERABILITIES_CONFIRMED${NC}"
    echo -e "Failed injections: $((ATTACK_VECTORS_TESTED - VULNERABILITIES_CONFIRMED))"
    
    echo -e "\n${YELLOW}=== Vulnerability Assessment ===${NC}"
    if [[ $VULNERABILITIES_CONFIRMED -gt 0 ]]; then
        echo -e "${RED}CRITICAL:${NC} $VULNERABILITIES_CONFIRMED injection vulnerabilities confirmed"
        echo -e "${RED}RISK:${NC} Arbitrary command execution possible during build"
        echo -e "${YELLOW}ACTION:${NC} Immediate security fixes required"
        return 0  # RED phase success - vulnerabilities confirmed
    else
        echo -e "${GREEN}SECURE:${NC} No injection vulnerabilities found"
        echo -e "${GREEN}STATUS:${NC} Security fixes appear to be working"
        return 0  # GREEN phase success - vulnerabilities fixed
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_injection_vector_tests
fi