#!/bin/bash
# tools/lib/utils.sh - Utility functions for fortui build system
# Provides platform detection, git operations, pkg-config wrappers, and network retry logic

# Import guard (prevent multiple includes)
[[ "${_FORTUI_UTILS_LOADED:-}" == "1" ]] && return 0
readonly _FORTUI_UTILS_LOADED=1

# Platform detection
detect_platform() {
    case "$(uname -s)" in
        Linux*)   echo "linux" ;;
        Darwin*)  echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
}

# Tool version detection for cache invalidation
get_tool_versions() {
    local versions=""
    
    # Git version
    if command -v git >/dev/null 2>&1; then
        versions+="git:$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1);"
    fi
    
    # Make version
    if command -v make >/dev/null 2>&1; then
        versions+="make:$(make --version | grep -oE '[0-9]+\.[0-9]+' | head -1);"
    fi
    
    # GCC version
    if command -v gcc >/dev/null 2>&1; then
        versions+="gcc:$(gcc -dumpversion | head -1);"
    fi
    
    # Gfortran version
    if command -v gfortran >/dev/null 2>&1; then
        versions+="gfortran:$(gfortran -dumpversion | head -1);"
    fi
    
    # FPM version
    if command -v fpm >/dev/null 2>&1; then
        versions+="fpm:$(fpm --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1);"
    fi
    
    # PKG-CONFIG version
    if command -v pkg-config >/dev/null 2>&1; then
        versions+="pkg-config:$(pkg-config --version | head -1);"
    fi
    
    # Build system version for cache invalidation
    versions+="build:${BUILD_SYSTEM_VERSION};"
    
    echo "$versions"
}

# Wrapper for pkg-config (allows mocking in tests)
call_pkg_config() {
    if declare -f mock_pkg_config >/dev/null; then
        # Mock function expects single string argument containing the command
        mock_pkg_config "$*"
    else
        pkg-config "$@"
    fi
}

# Network retry logic with exponential backoff
retry_with_backoff() {
    local max_attempts=3
    local base_delay=1
    local max_delay=30
    local attempt=1
    local delay=$base_delay
    
    while [[ $attempt -le $max_attempts ]]; do
        if [[ "${DEBUG}" == "1" ]]; then
            echo "DEBUG: Network operation attempt $attempt/$max_attempts" >&2
        fi
        
        if "$@"; then
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            echo "Error: Network operation failed after $max_attempts attempts" >&2
            return 1
        fi
        
        echo "Network operation failed, retrying in ${delay}s..." >&2
        sleep "$delay"
        
        # Exponential backoff with jitter
        delay=$((delay * 2))
        if [[ $delay -gt $max_delay ]]; then
            delay=$max_delay
        fi
        
        attempt=$((attempt + 1))
    done
}

# Network operation with timeout
call_git_with_timeout() {
    local timeout=300  # 5 minute timeout
    local git_cmd=("$@")
    
    if command -v timeout >/dev/null 2>&1; then
        timeout "$timeout" git "${git_cmd[@]}"
    else
        # Fallback for systems without timeout command
        git "${git_cmd[@]}"
    fi
}

# Wrapper for git (allows mocking in tests)
call_git() {
    if declare -f mock_git >/dev/null; then
        mock_git "$@"
    else
        # Check for offline mode
        case "$1" in
            clone|fetch|pull)
                if [[ "${OFFLINE_MODE}" == "1" ]]; then
                    echo "Error: Network operation '$1' not available" \
                         "in offline mode" >&2
                    return 1
                fi
                retry_with_backoff call_git_with_timeout "$@"
                ;;
            *)
                git "$@"
                ;;
        esac
    fi
}

# Raylib detection function
detect_raylib() {
    # Honor DISABLE_GUI environment variable first
    if [[ "${DISABLE_GUI}" == "1" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: GUI disabled via DISABLE_GUI=1" >&2
        return 1
    fi
    
    # Check RAYLIB_ROOT if specified
    if [[ -n "${RAYLIB_ROOT}" ]]; then
        # Security: Validate RAYLIB_ROOT path before use
        local validated_raylib_root
        if validated_raylib_root=$(validate_path "${RAYLIB_ROOT}"); then
            local raylib_header="${validated_raylib_root}/include/raylib.h"
            if [[ -f "$raylib_header" ]]; then
                [[ "${DEBUG}" == "1" ]] && \
                    echo "DEBUG: Found raylib via RAYLIB_ROOT: ${validated_raylib_root}" >&2
                return 0
            else
                [[ "${DEBUG}" == "1" ]] && \
                    echo "DEBUG: RAYLIB_ROOT specified but raylib.h not found: $raylib_header" >&2
                return 1
            fi
        else
            [[ "${DEBUG}" == "1" ]] && \
                echo "DEBUG: Invalid RAYLIB_ROOT path: ${RAYLIB_ROOT}" >&2
            return 1
        fi
    fi
    
    # Check system raylib via pkg-config
    if command -v pkg-config >/dev/null 2>&1; then
        if call_pkg_config --exists raylib >/dev/null 2>&1; then
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Found raylib via pkg-config" >&2
            return 0
        fi
    fi
    
    [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Raylib not detected" >&2
    return 1
}

# CPP flags setup function  
setup_cpp_flags() {
    if detect_raylib; then
        echo "ENABLE_GUI=1"
    else
        echo "ENABLE_GUI=0"
    fi
}

# FPM-specific compiler flags
setup_fpm_flags() {
    if detect_raylib; then
        echo "-cpp -DENABLE_GUI"
    else
        echo "-cpp -DTUI_ONLY"
    fi
}

# Command validation utilities for build script robustness (Issue #80)
validate_command_available() {
    # Given: Command name to check
    # When: Validating command availability in PATH
    # Then: Returns 0 if available, 1 if not
    local cmd="$1"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

require_command() {
    # Given: Command name, optional display name, optional install hint
    # When: Validating command is available before exec
    # Then: Exits with helpful error if command not found
    local cmd="$1"
    local display_name="${2:-$cmd}"
    local install_hint="${3:-"Please install $display_name and ensure it's in your PATH"}"
    
    if ! validate_command_available "$cmd"; then
        echo "Error: $display_name (command '$cmd') not found in PATH" >&2
        echo "" >&2
        echo "$install_hint" >&2
        echo "" >&2
        echo "Current PATH: $PATH" >&2
        return 1
    fi
    
    return 0
}