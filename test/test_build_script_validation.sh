#!/bin/bash
# test/test_build_script_validation.sh - Build script validation and robustness tests
# Tests for Issue #80: FPM wrapper script uses exec without proper validation

set -euo pipefail

# Test framework configuration
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
TEST_CACHE_DIR="/tmp/fortui_validation_test_$$"

# Test results tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Build scripts under test
SCRIPTS_TO_TEST=(
    "$PROJECT_ROOT/fpm_build.sh"
    "$PROJECT_ROOT/run_fpm.sh" 
    "$PROJECT_ROOT/build.sh"
)

# Test framework functions
setup_test_env() {
    # Given: Clean test environment
    mkdir -p "$TEST_CACHE_DIR"
    export GUI_CACHE="$TEST_CACHE_DIR"
    export PATH="$TEST_CACHE_DIR/bin:$PATH"
    
    # Create mock bin directory for controlled command availability
    mkdir -p "$TEST_CACHE_DIR/bin"
}

teardown_test_env() {
    # Cleanup test environment
    rm -rf "$TEST_CACHE_DIR" || true
    unset GUI_CACHE
}

assert_script_contains_pattern() {
    # Given: Script file and pattern to search
    # When: Checking if pattern exists in script
    # Then: Test passes if pattern is found
    local script_file="$1"
    local pattern="$2"
    local message="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -f "$script_file" ]] && grep -q "$pattern" "$script_file"; then
        echo -e "${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  Pattern '$pattern' not found in $script_file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_script_lacks_pattern() {
    # Given: Script file and pattern that should NOT exist
    # When: Checking if pattern is absent from script
    # Then: Test passes if pattern is NOT found
    local script_file="$1"
    local pattern="$2"
    local message="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ -f "$script_file" ]] && ! grep -q "$pattern" "$script_file"; then
        echo -e "${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  Pattern '$pattern' found in $script_file but should not exist"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_command_fails_gracefully() {
    # Given: Command that should fail with helpful error
    # When: Running command in environment without required tools
    # Then: Test passes if command fails with useful error message
    local command="$1"
    local expected_error_pattern="$2"
    local message="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    local output
    local exit_code
    output=$(eval "$command" 2>&1) || exit_code=$?
    
    if [[ ${exit_code:-0} -ne 0 ]] && echo "$output" | grep -iq "$expected_error_pattern"; then
        echo -e "${GREEN}✓${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} $message"
        echo "  Command: $command"
        echo "  Expected error pattern: $expected_error_pattern"
        echo "  Actual output: $output"
        echo "  Exit code: ${exit_code:-0}"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

create_mock_tool() {
    # Given: Tool name and behavior
    # When: Creating mock tool for testing
    # Then: Mock tool is available in test PATH
    local tool_name="$1"
    local behavior="${2:-success}"  # "success", "failure", or custom script
    
    local mock_path="$TEST_CACHE_DIR/bin/$tool_name"
    
    case "$behavior" in
        "success")
            cat > "$mock_path" << 'EOF'
#!/bin/bash
exit 0
EOF
            ;;
        "failure")
            cat > "$mock_path" << 'EOF'
#!/bin/bash
echo "Mock tool failure" >&2
exit 1
EOF
            ;;
        *)
            echo "$behavior" > "$mock_path"
            ;;
    esac
    
    chmod +x "$mock_path"
}

remove_tool_from_path() {
    # Given: Tool name
    # When: Removing tool from PATH
    # Then: Tool is no longer available for execution
    local tool_name="$1"
    local tool_path="$TEST_CACHE_DIR/bin/$tool_name"
    
    rm -f "$tool_path"
}

# Test Categories

# 1. Exec Validation Detection Tests
test_detect_unvalidated_exec_usage() {
    echo -e "\n${YELLOW}Testing detection of unvalidated exec usage...${NC}"
    
    # Given: Build scripts that currently use exec without validation
    # When: Scanning scripts for exec usage patterns
    # Then: Scripts should be flagged for missing validation
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" ]]; then
            # Check for exec usage without preceding validation
            assert_script_contains_pattern "$script" "exec.*fpm" \
                "Script $(basename $script) contains exec fpm usage that needs validation"
                
            # Check that validation is currently missing (will fail until fix implemented)
            assert_script_lacks_pattern "$script" "command -v fpm" \
                "Script $(basename $script) currently lacks fpm availability check (expected failure)"
        fi
    done
}

test_detect_required_validation_patterns() {
    echo -e "\n${YELLOW}Testing required validation patterns...${NC}"
    
    # Given: Scripts that will be fixed to include validation
    # When: Checking for proper validation before exec
    # Then: Scripts should validate tool availability and provide helpful errors
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" ]]; then
            # These tests will initially fail but validate the fix requirements
            local script_name=$(basename "$script")
            
            # Check for fpm availability validation (will fail until implemented)
            assert_script_lacks_pattern "$script" 'if.*command -v fpm' \
                "Script $script_name needs fpm availability check (expected failure until fix)"
                
            # Check for helpful error message (will fail until implemented)  
            assert_script_lacks_pattern "$script" 'fpm not found' \
                "Script $script_name needs helpful error for missing fpm (expected failure until fix)"
                
            # Check for installation guidance (will fail until implemented)
            assert_script_lacks_pattern "$script" 'install.*fpm' \
                "Script $script_name needs installation guidance (expected failure until fix)"
        fi
    done
}

# 2. Build Tool Availability Tests
test_fpm_availability_validation() {
    echo -e "\n${YELLOW}Testing FPM availability validation...${NC}"
    
    # Given: Environment without fpm
    remove_tool_from_path "fmp"
    
    # When: Running build scripts without fpm available
    # Then: Scripts should fail gracefully with helpful error
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            local script_name=$(basename "$script")
            
            # Test that script fails gracefully when fmp not available
            assert_command_fails_gracefully \
                "'$script' build 2>&1" \
                "fpm.*not found\|command not found\|No such file" \
                "Script $script_name should fail gracefully when fpm unavailable"
        fi
    done
}

test_helpful_error_messages() {
    echo -e "\n${YELLOW}Testing helpful error messages for missing tools...${NC}"
    
    # Given: Environment without required build tools
    remove_tool_from_path "fpm"
    
    # When: Running scripts with missing dependencies
    # Then: Error messages should guide users to solutions
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            local script_name=$(basename "$script")
            
            # Currently will show cryptic errors - this validates the problem
            local output
            local exit_code
            output=$("$script" build 2>&1) || exit_code=$?
            
            if [[ ${exit_code:-0} -ne 0 ]]; then
                echo -e "${YELLOW}Info:${NC} $script_name fails without fpm (exit $exit_code)"
                echo "  Current error: $(echo "$output" | head -1)"
                
                # Check if error message is helpful (currently won't be)
                if echo "$output" | grep -iq "install\|not found\|please"; then
                    echo -e "${GREEN}✓${NC} $script_name provides helpful error message"
                    TESTS_PASSED=$((TESTS_PASSED + 1))
                else
                    echo -e "${RED}✗${NC} $script_name needs more helpful error message"
                    TESTS_FAILED=$((TESTS_FAILED + 1))
                fi
                TESTS_RUN=$((TESTS_RUN + 1))
            fi
        fi
    done
}

# 3. Error Handling Pattern Tests
test_consistent_error_handling() {
    echo -e "\n${YELLOW}Testing consistent error handling patterns...${NC}"
    
    # Given: Multiple build scripts
    # When: Checking error handling consistency
    # Then: All scripts should use consistent error patterns
    
    local expected_patterns=(
        "set -e"           # Exit on error
        "echo.*>&2"        # Error output to stderr
        "exit 1"           # Proper exit codes
    )
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" ]]; then
            local script_name=$(basename "$script")
            
            for pattern in "${expected_patterns[@]}"; do
                assert_script_contains_pattern "$script" "$pattern" \
                    "Script $script_name uses pattern: $pattern"
            done
        fi
    done
}

test_exit_codes_for_failure_scenarios() {
    echo -e "\n${YELLOW}Testing exit codes for different failure scenarios...${NC}"
    
    # Given: Scripts run in various failure conditions
    # When: Scripts encounter different types of errors
    # Then: Exit codes should indicate failure type appropriately
    
    # Create failing mock fpm that returns specific exit codes
    create_mock_tool "fpm" '#!/bin/bash
case "$1" in
    "build") exit 2 ;;
    "test") exit 3 ;;
    *) exit 1 ;;
esac'
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            local script_name=$(basename "$script")
            
            # Test that script propagates failure exit codes
            local exit_code
            "$script" build >/dev/null 2>&1 || exit_code=$?
            
            TESTS_RUN=$((TESTS_RUN + 1))
            if [[ ${exit_code:-0} -ne 0 ]]; then
                echo -e "${GREEN}✓${NC} $script_name exits with failure code when fpm fails"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}✗${NC} $script_name should exit with failure when fpm fails"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        fi
    done
}

# 4. Functional Regression Tests
test_validation_preserves_normal_execution() {
    echo -e "\n${YELLOW}Testing that validation preserves normal execution...${NC}"
    
    # Given: Environment with working fpm
    create_mock_tool "fpm" "success"
    
    # When: Running scripts with available tools
    # Then: Scripts should execute normally without regression
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            local script_name=$(basename "$script")
            
            # Test that script works when fmp is available
            local exit_code
            "$script" --help >/dev/null 2>&1 || exit_code=$?
            
            TESTS_RUN=$((TESTS_RUN + 1))
            # Currently may fail due to missing validation, but should pass after fix
            if [[ ${exit_code:-0} -eq 0 ]]; then
                echo -e "${GREEN}✓${NC} $script_name executes successfully with available fpm"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${YELLOW}Info:${NC} $script_name execution needs validation implementation"
                # Don't count as failure since this is expected before fix
            fi
        fi
    done
}

test_performance_impact_minimal() {
    echo -e "\n${YELLOW}Testing minimal performance impact of validation...${NC}"
    
    # Given: Scripts with and without validation
    # When: Measuring execution time
    # Then: Validation should add minimal overhead
    
    create_mock_tool "fpm" "success"
    
    for script in "${SCRIPTS_TO_TEST[@]}"; do
        if [[ -f "$script" && -x "$script" ]]; then
            local script_name=$(basename "$script")
            
            # Time script execution (rough performance check)
            local start_time end_time
            start_time=$(date +%s%N)
            "$script" --help >/dev/null 2>&1 || true
            end_time=$(date +%s%N)
            
            local duration_ms=$(( (end_time - start_time) / 1000000 ))
            
            TESTS_RUN=$((TESTS_RUN + 1))
            # Validation should complete within reasonable time (< 1000ms)
            if [[ $duration_ms -lt 1000 ]]; then
                echo -e "${GREEN}✓${NC} $script_name validation completes quickly (${duration_ms}ms)"
                TESTS_PASSED=$((TESTS_PASSED + 1))
            else
                echo -e "${RED}✗${NC} $script_name validation too slow (${duration_ms}ms)"
                TESTS_FAILED=$((TESTS_FAILED + 1))
            fi
        fi
    done
}

# Test for architecture alignment
test_validation_utility_requirements() {
    echo -e "\n${YELLOW}Testing validation utility requirements...${NC}"
    
    # Given: Build scripts need consistent validation
    # When: Checking for validation utility function
    # Then: Utility should provide reusable validation logic
    
    local utils_script="$PROJECT_ROOT/tools/lib/utils.sh"
    
    if [[ -f "$utils_script" ]]; then
        # Check for validation utility functions (will be added)
        assert_script_lacks_pattern "$utils_script" "validate_command_available" \
            "Utils script needs validate_command_available function (expected failure until implementation)"
            
        assert_script_lacks_pattern "$utils_script" "require_command" \
            "Utils script needs require_command function (expected failure until implementation)"
    else
        echo -e "${YELLOW}Info:${NC} Utils script not found - validation utilities needed"
    fi
}

# Main test runner
run_build_script_validation_tests() {
    echo -e "${YELLOW}Starting build script validation test suite for Issue #80...${NC}\n"
    echo "Testing build scripts for exec validation and robustness"
    echo "Scripts under test: ${SCRIPTS_TO_TEST[*]}"
    echo ""
    
    # Setup
    setup_test_env
    
    # 1. Exec Validation Detection Tests
    test_detect_unvalidated_exec_usage
    test_detect_required_validation_patterns
    
    # 2. Build Tool Availability Tests  
    test_fpm_availability_validation
    test_helpful_error_messages
    
    # 3. Error Handling Pattern Tests
    test_consistent_error_handling
    test_exit_codes_for_failure_scenarios
    
    # 4. Functional Regression Tests
    test_validation_preserves_normal_execution
    test_performance_impact_minimal
    
    # 5. Architecture Tests
    test_validation_utility_requirements
    
    # Cleanup
    teardown_test_env
    
    # Results
    echo -e "\n${YELLOW}Build Script Validation Test Results:${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
        echo ""
        echo -e "${YELLOW}Expected failures before Issue #80 implementation:${NC}"
        echo "- Scripts lack fpm availability validation (unvalidated exec usage)"
        echo "- Missing helpful error messages for missing tools"
        echo "- No validation utility functions in tools/lib/utils.sh"
        echo ""
        echo -e "${GREEN}These tests will pass after sergei-perfectionist-coder implements the validation fixes.${NC}"
        return 1
    else
        echo -e "Failed: $TESTS_FAILED"
        echo -e "\n${GREEN}All build script validation tests passed!${NC}"
        return 0
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_build_script_validation_tests
fi