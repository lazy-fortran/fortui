#!/bin/bash
# tools/lib/security.sh - Security functions for fortui build system
# Provides input validation, sanitization, and secure operations for Issue #77

# Import guard (prevent multiple includes)
[[ "${_FORTUI_SECURITY_LOADED:-}" == "1" ]] && return 0
readonly _FORTUI_SECURITY_LOADED=1

# Security: Safe PID reading with validation (prevents injection attacks)
safe_read_pid() {
    local lock_file="$1"
    local lock_pid
    
    if [[ ! -f "$lock_file" ]]; then
        return 1
    fi
    
    # Read PID with proper input validation
    if read -r lock_pid < "$lock_file" 2>/dev/null; then
        # Security: Validate PID is numeric only (prevent injection)
        if [[ "$lock_pid" =~ ^[0-9]+$ ]] && [[ ${#lock_pid} -le 10 ]]; then
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Valid PID read: $lock_pid" >&2
            echo "$lock_pid"
            return 0
        else
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Invalid PID format in lock file: $lock_file" >&2
            return 2  # Invalid PID format
        fi
    fi
    
    [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Failed to read PID from: $lock_file" >&2
    return 1  # Read failed
}

# Security: Safe command output sanitization
sanitize_command_output() {
    local output="$1"
    
    # Security: Remove potentially dangerous characters from command output
    # Keep only safe characters for compiler flags: alphanumeric, spaces, hyphens, underscores, dots, equals
    output="${output//[$'\t\r\n']/ }"  # Replace newlines/tabs with spaces
    
    # Use sed for character class removal (bash parameter expansion doesn't support [^...])
    output=$(echo "$output" | sed 's/[^a-zA-Z0-9 ._=/-]//g')
    
    # Remove multiple consecutive spaces
    while [[ "$output" =~ "  " ]]; do
        output="${output//  / }"
    done
    
    # Trim leading/trailing spaces
    output="${output# }"
    output="${output% }"
    
    echo "$output"
}

# Security: Safe path validation and canonicalization  
validate_path() {
    local input_path="$1"
    local canonical_path
    
    # Security: Basic path validation
    if [[ -z "$input_path" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Empty path provided" >&2
        return 1
    fi
    
    # Security: Reject paths with command injection patterns
    if [[ "$input_path" =~ [\$\`\;] || "$input_path" =~ \&\& || "$input_path" =~ \|\| ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Path contains unsafe characters: $input_path" >&2
        return 2  # Unsafe characters detected
    fi
    
    # Security: Try to canonicalize path if it exists
    if [[ -e "$input_path" ]]; then
        if canonical_path=$(realpath "$input_path" 2>/dev/null); then
            echo "$canonical_path"
        else
            echo "$input_path"
        fi
    else
        echo "$input_path"
    fi
    
    return 0
}