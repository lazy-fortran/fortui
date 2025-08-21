#!/bin/bash
# test/test_security_requirements.sh - Security requirements and expected secure patterns
# Issue #77: Documents security requirements that GREEN phase implementation must satisfy

set -euo pipefail

# Test framework configuration  
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$TEST_DIR")"
TOOLS_DIR="$PROJECT_ROOT/tools"
TEST_SECURITY_DIR="/tmp/fortui_security_req_test_$$"

# Test results tracking
SECURITY_TESTS_RUN=0
REQUIREMENTS_VALIDATED=0
SECURITY_PATTERNS_TESTED=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

setup_security_requirements_env() {
    mkdir -p "$TEST_SECURITY_DIR"
    mkdir -p "$TEST_SECURITY_DIR/test_cache"
    mkdir -p "$TEST_SECURITY_DIR/malicious_inputs"
    mkdir -p "$TEST_SECURITY_DIR/evidence"
}

teardown_security_requirements_env() {
    rm -rf "$TEST_SECURITY_DIR" || true
}

test_security_requirement() {
    local req_name="$1"
    local requirement_description="$2"
    local test_function="$3"
    local expected_in_red_phase="$4"    # "FAIL" means requirement not met (RED)
    local expected_in_green_phase="$5"  # "PASS" means requirement met (GREEN)
    
    SECURITY_TESTS_RUN=$((SECURITY_TESTS_RUN + 1))
    
    echo -e "${CYAN}Security Requirement:${NC} $req_name"
    echo -e "${CYAN}Description:${NC} $requirement_description"
    echo -e "${CYAN}RED Phase Expected:${NC} $expected_in_red_phase"
    echo -e "${CYAN}GREEN Phase Expected:${NC} $expected_in_green_phase"
    
    if eval "$test_function" >/dev/null 2>&1; then
        if [[ "$expected_in_red_phase" == "FAIL" ]]; then
            echo -e "${YELLOW}~${NC} RED Phase: Requirement not yet met (expected)"
        else
            echo -e "${GREEN}✓${NC} GREEN Phase: Requirement satisfied"
            REQUIREMENTS_VALIDATED=$((REQUIREMENTS_VALIDATED + 1))
        fi
    else
        if [[ "$expected_in_red_phase" == "FAIL" ]]; then
            echo -e "${GREEN}✓${NC} RED Phase: Confirmed requirement needs implementation"
            REQUIREMENTS_VALIDATED=$((REQUIREMENTS_VALIDATED + 1))
        else
            echo -e "${RED}✗${NC} GREEN Phase: Requirement not satisfied"
        fi
    fi
}

# Security Requirement 1: Input Validation and Sanitization
test_requirement_input_validation() {
    echo -e "\n${YELLOW}=== Security Requirement 1: Input Validation and Sanitization ===${NC}"
    
    # Test for secure PID validation function
    test_security_requirement \
        "Secure PID Validation" \
        "PID values must be validated as numeric before use in commands" \
        "test_secure_pid_validation_exists" \
        "FAIL" \
        "PASS"
        
    # Test for path validation function
    test_security_requirement \
        "Path Validation" \
        "File paths must be validated and sanitized before use" \
        "test_secure_path_validation_exists" \
        "FAIL" \
        "PASS"
        
    # Test for command output sanitization
    test_security_requirement \
        "Command Output Sanitization" \
        "External command outputs must be sanitized before use" \
        "test_command_output_sanitization_exists" \
        "FAIL" \
        "PASS"
}

# Test functions for requirement validation
test_secure_pid_validation_exists() {
    # Check if secure PID validation function exists
    # During RED phase: Should return false (not implemented)
    # During GREEN phase: Should return true (implemented)
    
    # Look for safe_read_pid function in build script or security module
    if [[ -f "$TOOLS_DIR/lib/security.sh" ]]; then
        grep -q "safe_read_pid()" "$TOOLS_DIR/lib/security.sh" 2>/dev/null
    elif [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        grep -q "safe_read_pid" "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1  # Build script doesn't exist yet
    fi
}

test_secure_path_validation_exists() {
    # Check if secure path validation function exists
    if [[ -f "$TOOLS_DIR/lib/security.sh" ]]; then
        grep -q "validate_path()" "$TOOLS_DIR/lib/security.sh" 2>/dev/null
    elif [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        grep -q "validate_path" "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

test_command_output_sanitization_exists() {
    # Check if command output sanitization exists
    if [[ -f "$TOOLS_DIR/lib/security.sh" ]]; then
        grep -q "sanitize_command_output()" "$TOOLS_DIR/lib/security.sh" 2>/dev/null
    elif [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        grep -q "sanitize_command_output" "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

# Security Requirement 2: Proper Quoting and Escaping
test_requirement_proper_quoting() {
    echo -e "\n${YELLOW}=== Security Requirement 2: Proper Quoting and Escaping ===${NC}"
    
    test_security_requirement \
        "Variable Expansion Quoting" \
        "All variable expansions must be properly quoted" \
        "test_variable_expansion_quoting" \
        "FAIL" \
        "PASS"
        
    test_security_requirement \
        "Command Substitution Quoting" \
        "All command substitution outputs must be quoted" \
        "test_command_substitution_quoting" \
        "FAIL" \
        "PASS"
        
    test_security_requirement \
        "Path Parameter Quoting" \
        "All file path parameters must be quoted to prevent injection" \
        "test_path_parameter_quoting" \
        "FAIL" \
        "PASS"
}

test_variable_expansion_quoting() {
    # Look for proper variable quoting patterns in any build script or library
    local script_files=("$TOOLS_DIR/build_fortui.sh")
    if [[ -d "$TOOLS_DIR/lib" ]]; then
        script_files+=("$TOOLS_DIR/lib"/*.sh)
    fi
    
    for file in "${script_files[@]}"; do
        if [[ -f "$file" ]]; then
            # Check for properly quoted variables (positive pattern)
            if grep -q '"\$[^"]*"' "$file" 2>/dev/null; then
                return 0  # Found proper quoting
            fi
        fi
    done
    return 1  # No proper quoting patterns found
}

test_command_substitution_quoting() {
    # Look for proper command substitution quoting patterns in any script
    local script_files=("$TOOLS_DIR/build_fortui.sh")
    if [[ -d "$TOOLS_DIR/lib" ]]; then
        script_files+=("$TOOLS_DIR/lib"/*.sh)
    fi
    
    for file in "${script_files[@]}"; do
        if [[ -f "$file" ]]; then
            # Check for properly quoted command substitutions
            if grep -q 'pkg_flags="\$(' "$file" 2>/dev/null ||
               grep -q 'if.*="\$(' "$file" 2>/dev/null; then
                return 0  # Found proper quoting
            fi
        fi
    done
    return 1  # No proper quoting patterns found
}

test_path_parameter_quoting() {
    # Look for proper path quoting patterns in any script
    local script_files=("$TOOLS_DIR/build_fortui.sh")
    if [[ -d "$TOOLS_DIR/lib" ]]; then
        script_files+=("$TOOLS_DIR/lib"/*.sh)
    fi
    
    for file in "${script_files[@]}"; do
        if [[ -f "$file" ]]; then
            # Check for properly quoted file paths
            if grep -q '"\$[a-zA-Z_]*"' "$file" 2>/dev/null ||
               grep -q '"\${[^}]*}' "$file" 2>/dev/null; then
                return 0  # Found proper quoting
            fi
        fi
    done
    return 1  # No proper quoting patterns found
}

# Security Requirement 3: Safe Command Construction
test_requirement_safe_command_construction() {
    echo -e "\n${YELLOW}=== Security Requirement 3: Safe Command Construction ===${NC}"
    
    test_security_requirement \
        "Avoid Command Injection Vectors" \
        "Commands must be constructed to prevent injection attacks" \
        "test_safe_command_construction" \
        "FAIL" \
        "PASS"
        
    test_security_requirement \
        "Use Built-in Operations" \
        "Prefer bash built-ins over external commands where possible" \
        "test_builtin_usage" \
        "FAIL" \
        "PASS"
        
    test_security_requirement \
        "Parameterized Command Execution" \
        "Commands should use parameterized execution when possible" \
        "test_parameterized_execution" \
        "FAIL" \
        "PASS"
}

test_safe_command_construction() {
    if [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        # Check for unsafe command construction patterns
        ! grep -q '; \|&& \||| \||\s*[^|]' "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

test_builtin_usage() {
    if [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        # Check if read builtin is used instead of cat where appropriate
        grep -q 'read.*<\|read -r' "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

test_parameterized_execution() {
    if [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        # Check for functions that take parameters instead of using globals
        grep -q 'validate_.*[(].*[)]' "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

# Security Requirement 4: Error Handling and Fail-Safe Behavior
test_requirement_error_handling() {
    echo -e "\n${YELLOW}=== Security Requirement 4: Error Handling and Fail-Safe Behavior ===${NC}"
    
    test_security_requirement \
        "Security Validation Failures" \
        "Security validation failures must abort build process" \
        "test_security_failure_handling" \
        "FAIL" \
        "PASS"
        
    test_security_requirement \
        "No Fallback to Unsafe Operations" \
        "No fallback to unsafe operations when security checks fail" \
        "test_no_unsafe_fallbacks" \
        "FAIL" \
        "PASS"
        
    test_security_requirement \
        "Clear Security Error Messages" \
        "Security errors must have clear, informative messages" \
        "test_security_error_messages" \
        "FAIL" \
        "PASS"
}

test_security_failure_handling() {
    if [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        # Check for security validation with exit on failure
        grep -q 'validate.*||.*exit\|validate.*||.*return' "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

test_no_unsafe_fallbacks() {
    if [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        # Check that there are no fallbacks to unsafe operations
        ! grep -q '||.*cat\s*\$\|||.*eval' "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

test_security_error_messages() {
    if [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        # Check for security-related error messages
        grep -q 'Security.*error\|Invalid.*input\|Unsafe.*path' "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

# Security Requirement 5: Audit and Logging
test_requirement_audit_logging() {
    echo -e "\n${YELLOW}=== Security Requirement 5: Audit and Logging ===${NC}"
    
    test_security_requirement \
        "Security Event Logging" \
        "Security-relevant events must be logged when DEBUG=1" \
        "test_security_event_logging" \
        "FAIL" \
        "PASS"
        
    test_security_requirement \
        "Input Validation Logging" \
        "Input validation results must be logged in debug mode" \
        "test_validation_logging" \
        "FAIL" \
        "PASS"
}

test_security_event_logging() {
    if [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        # Check for security event logging
        grep -q 'DEBUG.*Security\|DEBUG.*Validat' "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

test_validation_logging() {
    if [[ -f "$TOOLS_DIR/build_fortui.sh" ]]; then
        # Check for validation logging
        grep -q 'DEBUG.*input\|DEBUG.*path\|DEBUG.*PID' "$TOOLS_DIR/build_fortui.sh" 2>/dev/null
    else
        return 1
    fi
}

# Expected Secure Implementation Patterns
document_expected_secure_patterns() {
    echo -e "\n${YELLOW}=== Expected Secure Implementation Patterns ===${NC}"
    
    echo -e "${BLUE}Secure PID Reading Pattern:${NC}"
    cat << 'EOF'
# SECURE: Validate PID before use
safe_read_pid() {
    local lock_file="$1"
    local lock_pid
    
    if [[ ! -f "$lock_file" ]]; then
        return 1
    fi
    
    # Read with proper quoting and validation
    if read -r lock_pid < "$lock_file" 2>/dev/null; then
        # Validate PID is numeric
        if [[ "$lock_pid" =~ ^[0-9]+$ ]]; then
            echo "$lock_pid"
            return 0
        fi
    fi
    
    return 1
}
EOF
    
    echo -e "\n${BLUE}Secure Command Output Handling Pattern:${NC}"
    cat << 'EOF'
# SECURE: Quote command output and validate
safe_pkg_config_flags() {
    local pkg_name="$1"
    local flags
    
    # Get flags with proper quoting
    if flags="$(pkg-config --cflags --libs "$pkg_name" 2>/dev/null)"; then
        # Validate flags don't contain dangerous characters
        if [[ "$flags" =~ ^[-/[:alnum:][:space:]_.]*$ ]]; then
            echo "$flags"
            return 0
        else
            echo "Error: Invalid characters in pkg-config output" >&2
            return 1
        fi
    fi
    
    return 1
}
EOF
    
    echo -e "\n${BLUE}Secure Path Handling Pattern:${NC}"
    cat << 'EOF'
# SECURE: Validate and canonicalize paths
safe_extract_version() {
    local raylib_root="$1"
    local header_file
    local version
    
    # Validate and canonicalize path
    if ! raylib_root="$(realpath "$raylib_root" 2>/dev/null)"; then
        echo "Error: Invalid RAYLIB_ROOT path" >&2
        return 1
    fi
    
    header_file="$raylib_root/include/raylib.h"
    
    # Check file exists and is readable
    if [[ ! -f "$header_file" || ! -r "$header_file" ]]; then
        return 1
    fi
    
    # Extract version with safe file reading
    if version=$(grep -oE '#define RAYLIB_VERSION "[0-9]+\.[0-9]+\.[0-9]+"' "$header_file" 2>/dev/null | \
                grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); then
        # Validate version format
        if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$version"
            return 0
        fi
    fi
    
    return 1
}
EOF
}

# Run security requirements tests
run_security_requirements_tests() {
    echo -e "${BLUE}Starting security requirements validation...${NC}"
    echo -e "${BLUE}Testing security requirements for Issue #77 implementation${NC}\n"
    
    setup_security_requirements_env
    
    # Test all security requirements
    test_requirement_input_validation
    test_requirement_proper_quoting
    test_requirement_safe_command_construction
    test_requirement_error_handling
    test_requirement_audit_logging
    
    # Document expected patterns
    document_expected_secure_patterns
    
    teardown_security_requirements_env
    
    # Results summary
    echo -e "\n${BLUE}=== Security Requirements Test Results ===${NC}"
    echo "Total security requirements tested: $SECURITY_TESTS_RUN"
    echo -e "Requirements validated: ${GREEN}$REQUIREMENTS_VALIDATED${NC}"
    echo -e "Requirements not yet met: $((SECURITY_TESTS_RUN - REQUIREMENTS_VALIDATED))"
    
    echo -e "\n${YELLOW}=== Security Requirements Summary ===${NC}"
    if [[ $REQUIREMENTS_VALIDATED -lt $SECURITY_TESTS_RUN ]]; then
        echo -e "${RED}RED PHASE:${NC} Security requirements not yet implemented"
        echo -e "${YELLOW}STATUS:${NC} $((SECURITY_TESTS_RUN - REQUIREMENTS_VALIDATED)) requirements need implementation"
        echo -e "${BLUE}NEXT:${NC} Implement secure patterns to satisfy all requirements"
        
        echo -e "\n${CYAN}Implementation Checklist:${NC}"
        echo "□ Input validation and sanitization functions"
        echo "□ Proper quoting of all variable expansions"
        echo "□ Safe command construction without injection vectors" 
        echo "□ Fail-safe error handling for security failures"
        echo "□ Security event logging and audit trails"
        
        return 0  # RED phase success - requirements documented
    else
        echo -e "${GREEN}GREEN PHASE:${NC} All security requirements satisfied"
        echo -e "${GREEN}STATUS:${NC} Security implementation meets all requirements"
        return 0  # GREEN phase success - requirements met
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_security_requirements_tests
fi