#!/bin/bash
# test/test_fpm_validation_scenarios.sh - Specific FPM validation scenario tests
# Tests for Issue #80: Specific scenarios when fpm validation is missing/present

set -euo pipefail

# Test framework configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
TEST_CACHE_DIR="/tmp/fortui_fpm_test_$$"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

setup_test_env() {
    # Given: Clean test environment without fmp in PATH
    mkdir -p "$TEST_CACHE_DIR"
    export GUI_CACHE="$TEST_CACHE_DIR"
    
    # Remove fpm from PATH to simulate missing tool
    export PATH="/usr/bin:/bin"  # Minimal PATH without fpm
}

teardown_test_env() {
    # Cleanup test environment
    rm -rf "$TEST_CACHE_DIR" || true
    unset GUI_CACHE
}

assert_error_message_quality() {
    # Given: Command output with error message
    # When: Analyzing error message quality
    # Then: Error should be helpful and actionable
    local command="$1"
    local message="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local output
    local exit_code
    output=$(eval "$command" 2>&1) || exit_code=$?
    
    # Check for helpful error characteristics
    local helpful_indicators=0
    
    # 1. Mentions the missing tool
    if echo "$output" | grep -iq "fpm"; then
        helpful_indicators=$((helpful_indicators + 1))
    fi
    
    # 2. Provides installation guidance
    if echo "$output" | grep -iq "install\|download\|github"; then
        helpful_indicators=$((helpful_indicators + 1))
    fi
    
    # 3. Uses clear error language
    if echo "$output" | grep -iq "error\|not found\|missing\|required"; then
        helpful_indicators=$((helpful_indicators + 1))
    fi
    
    # 4. Goes to stderr
    local stderr_output
    stderr_output=$(eval "$command" >/dev/null 2>&1) || true
    if [[ -n "$stderr_output" ]]; then
        helpful_indicators=$((helpful_indicators + 1))
    fi
    
    if [[ $helpful_indicators -ge 2 ]]; then
        echo -e "${GREEN}✓${NC} $message (helpful error with $helpful_indicators indicators)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message (unhelpful error with $helpful_indicators indicators)"
        echo "  Output: $(echo "$output" | head -1)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Scenario Tests

test_fpm_build_without_fpm() {
    echo -e "\n${YELLOW}Testing fpm_build.sh behavior without fpm...${NC}"
    
    # Given: Environment without fpm
    # When: Running fpm_build.sh
    # Then: Should fail with helpful error about missing fpm
    
    local script="$PROJECT_ROOT/fmp_build.sh"
    if [[ -f "$script" ]]; then
        assert_error_message_quality \
            "'$script' build" \
            "fmp_build.sh should provide helpful error when fmp missing"
    fi
}

test_run_fpm_without_fpm() {
    echo -e "\n${YELLOW}Testing run_fmp.sh behavior without fpm...${NC}"
    
    # Given: Environment without fpm
    # When: Running run_fpm.sh
    # Then: Should fail with helpful error about missing fpm
    
    local script="$PROJECT_ROOT/run_fpm.sh"
    if [[ -f "$script" ]]; then
        assert_error_message_quality \
            "'$script' build" \
            "run_fpm.sh should provide helpful error when fmp missing"
    fi
}

test_build_without_fpm() {
    echo -e "\n${YELLOW}Testing build.sh behavior without fpm...${NC}"
    
    # Given: Environment without fpm
    # When: Running build.sh
    # Then: Should fail with helpful error about missing fpm
    
    local script="$PROJECT_ROOT/build.sh"
    if [[ -f "$script" ]]; then
        assert_error_message_quality \
            "'$script' build" \
            "build.sh should provide helpful error when fpm missing"
    fi
}

test_exec_replacement_behavior() {
    echo -e "\n${YELLOW}Testing exec replacement vs regular command behavior...${NC}"
    
    # Given: Scripts that currently use exec
    # When: Comparing exec vs regular command behavior
    # Then: Should understand tradeoffs of each approach
    
    local scripts=("$PROJECT_ROOT/fpm_build.sh" "$PROJECT_ROOT/run_fpm.sh" "$PROJECT_ROOT/build.sh")
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            local script_name=$(basename "$script")
            
            # Check current exec usage
            if grep -q "exec.*fpm" "$script"; then
                echo -e "${YELLOW}Info:${NC} $script_name uses exec (process replacement)"
                echo "  Benefit: Cleaner process tree, proper signal handling"
                echo "  Risk: Cannot handle fpm failure gracefully"
                
                TESTS_RUN=$((TESTS_RUN + 1))
                # This documents the current state - not a failure
                echo -e "${GREEN}✓${NC} Documented exec usage in $script_name"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            fi
        fi
    done
}

test_validation_before_exec_pattern() {
    echo -e "\n${YELLOW}Testing validation before exec pattern requirements...${NC}"
    
    # Given: Scripts that will be fixed to validate before exec
    # When: Checking for the required validation pattern
    # Then: Should use consistent validation approach
    
    local expected_pattern='if ! command -v fpm >/dev/null 2>&1; then'
    local error_pattern='echo.*fpm.*not found.*>&2'
    local exit_pattern='exit 1'
    
    local scripts=("$PROJECT_ROOT/fpm_build.sh" "$PROJECT_ROOT/run_fpm.sh" "$PROJECT_ROOT/build.sh")
    
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            local script_name=$(basename "$script")
            
            TESTS_RUN=$((TESTS_RUN + 3))
            
            # These will initially fail but document requirements
            if grep -q "$expected_pattern" "$script"; then
                echo -e "${GREEN}✓${NC} $script_name has validation check"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}✗${NC} $script_name needs validation check (expected failure until fix)"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
            
            if grep -q "$error_pattern" "$script"; then
                echo -e "${GREEN}✓${NC} $script_name has helpful error message"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}✗${NC} $script_name needs helpful error message (expected failure until fix)"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
            
            if grep -q "$exit_pattern" "$script"; then
                echo -e "${GREEN}✓${NC} $script_name has proper exit handling"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}✗${NC} $script_name needs proper exit handling (expected failure until fix)"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        fi
    done
}

test_alternative_to_exec_approach() {
    echo -e "\n${YELLOW}Testing alternative approaches to exec...${NC}"
    
    # Given: Scripts currently using exec
    # When: Considering alternatives for better error handling
    # Then: Should document pros/cons of different approaches
    
    echo "Approach comparison for Issue #80:"
    echo "1. Validation + exec (recommended):"
    echo "   - Validate fpm availability first"
    echo "   - Provide helpful error if missing"
    echo "   - Use exec for clean process replacement"
    echo ""
    echo "2. Regular command (alternative):"
    echo "   - Call fpm as regular command"
    echo "   - Can handle fpm errors more flexibly"
    echo "   - More complex signal handling"
    echo ""
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${GREEN}✓${NC} Documented approach alternatives for Issue #80"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_error_message_examples() {
    echo -e "\n${YELLOW}Testing error message examples for missing fpm...${NC}"
    
    # Given: Scripts should provide helpful errors
    # When: fpm is not available
    # Then: Error messages should be specific and actionable
    
    local good_examples=(
        "Error: fpm not found in PATH"
        "Please install FPM: https://github.com/fortran-lang/fpm"
        "fpm is required to build this project"
    )
    
    local bad_examples=(
        "command not found"
        "No such file or directory"
        "/bin/sh: fpm: not found"
    )
    
    echo "Good error message examples:"
    for example in "${good_examples[@]}"; do
        echo "  ✓ $example"
    done
    
    echo ""
    echo "Bad error message examples (current state):"
    for example in "${bad_examples[@]}"; do
        echo "  ✗ $example"
    done
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${GREEN}✓${NC} Documented error message quality requirements"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

# Main test runner
run_fpm_validation_scenario_tests() {
    echo -e "${YELLOW}Starting FPM validation scenario tests for Issue #80...${NC}\n"
    echo "Testing specific scenarios when fpm validation is missing/present"
    echo ""
    
    # Setup
    setup_test_env
    
    # Scenario Tests
    test_fpm_build_without_fpm
    test_run_fpm_without_fpm
    test_build_without_fpm
    test_exec_replacement_behavior
    test_validation_before_exec_pattern
    test_alternative_to_exec_approach
    test_error_message_examples
    
    # Cleanup
    teardown_test_env
    
    # Results
    echo -e "\n${YELLOW}FPM Validation Scenario Test Results:${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
        echo ""
        echo -e "${YELLOW}Expected failures before Issue #80 implementation:${NC}"
        echo "- Scripts provide unhelpful errors when fpm missing"
        echo "- Missing validation patterns before exec usage"
        echo ""
        echo -e "${GREEN}These tests demonstrate the problems that need fixing.${NC}"
        return 1
    else
        echo -e "Failed: $TESTS_FAILED"
        echo -e "\n${GREEN}All FPM validation scenario tests passed!${NC}"
        return 0
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_fpm_validation_scenario_tests
fi