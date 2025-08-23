#!/bin/bash
# tools/build_fortui.sh - Fortui dependency management and build script
# Handles conditional GUI/TUI compilation with dependency management

set -euo pipefail

# Script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration defaults
DEFAULT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fortui"
DEFAULT_FRG_URL="https://github.com/interkosmos/fortran-raylib.git"
DEFAULT_FRG_REF="master"
DEFAULT_TERMBOX_URL="https://github.com/termbox/termbox2.git"
DEFAULT_TERMBOX_REF="master"

# Build system version for cache invalidation
BUILD_SYSTEM_VERSION="1.0.0"

# Environment variables (with defaults)
GUI_CACHE="${GUI_CACHE:-$DEFAULT_CACHE_DIR}"
DISABLE_GUI="${DISABLE_GUI:-0}"
RAYLIB_ROOT="${RAYLIB_ROOT:-}"
DEBUG="${DEBUG:-0}"
FRG_URL="${FRG_URL:-$DEFAULT_FRG_URL}"
FRG_REF="${FRG_REF:-$DEFAULT_FRG_REF}"
TERMBOX_URL="${TERMBOX_URL:-$DEFAULT_TERMBOX_URL}"
TERMBOX_REF="${TERMBOX_REF:-$DEFAULT_TERMBOX_REF}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
OFFLINE_MODE="${OFFLINE_MODE:-0}"

# Load modular libraries
source "${SCRIPT_DIR}/lib/security.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cache.sh"
source "${SCRIPT_DIR}/lib/dependency.sh"

# Main build function
build_dependencies() {
    # Acquire cache lock for concurrent safety
    if ! acquire_cache_lock "${GUI_CACHE}"; then
        return 1
    fi
    
    # Setup cleanup trap to ensure lock is released on interrupt
    trap 'release_cache_lock "${GUI_CACHE}"' INT TERM
    
    # Setup cache
    if ! setup_cache; then
        release_cache_lock "${GUI_CACHE}"
        return 1
    fi
    
    # Validate dependency compatibility
    validate_dependency_compatibility "${GUI_CACHE}"
    
    # Build termbox2 (always needed for TUI)
    echo "Building termbox2 dependency for TUI backend..." >&2
    if ! build_termbox2; then
        echo "Error: Failed to build termbox2 dependency" >&2
        echo "  This is required for TUI backend functionality" >&2
        echo "  Check network connectivity and git configuration" >&2
        echo "  Set DEBUG=1 for detailed build output" >&2
        release_cache_lock "${GUI_CACHE}"
        return 1
    fi
    echo "termbox2 build completed successfully" >&2
    
    # Build fortran-raylib (only if GUI enabled)
    if detect_raylib; then
        echo "Building fortran-raylib dependency for GUI backend..." >&2
        if ! build_fortran_raylib; then
            echo "Error: Failed to build fortran-raylib dependency" >&2
            echo "  This is required for GUI backend functionality" >&2
            echo "  Check raylib installation and pkg-config setup" >&2
            echo "  Set DEBUG=1 for detailed build output" >&2
            release_cache_lock "${GUI_CACHE}"
            return 1
        fi
        echo "fortran-raylib build completed successfully" >&2
    else
        echo "Skipping fortran-raylib build (GUI backend disabled)" >&2
    fi
    
    # Release lock before success return
    release_cache_lock "${GUI_CACHE}"
    trap - INT TERM
    
    return 0
}

# Get compiler flags for dependencies
get_dependency_flags() {
    local cache_dir="${GUI_CACHE}"
    local flags=""
    
    # termbox2 flags - static linking only
    if [[ -d "${cache_dir}/termbox2" ]]; then
        flags+=" -I${cache_dir}/termbox2"
        # Use static library directly - no runtime dependencies
        flags+=" ${cache_dir}/termbox2/libtermbox2.a"
    fi
    
    # raylib/fortran-raylib flags (only if GUI enabled)
    if detect_raylib; then
        # Add raylib flags
        if [[ -n "${RAYLIB_ROOT}" ]]; then
            # Security: Validate RAYLIB_ROOT path before use
            local validated_raylib_root
            if validated_raylib_root=$(validate_path "${RAYLIB_ROOT}" 2>/dev/null) && [[ -n "$validated_raylib_root" ]]; then
                flags+=" -I${validated_raylib_root}/include -L${validated_raylib_root}/lib -lraylib"
            else
                echo "Error: Invalid RAYLIB_ROOT path: ${RAYLIB_ROOT}" >&2
                return 1
            fi
        elif command -v pkg-config >/dev/null 2>&1 && \
             call_pkg_config --exists raylib; then
            # Security: Safely capture and sanitize pkg-config output
            local pkg_flags
            if pkg_flags=$(call_pkg_config --cflags --libs raylib 2>/dev/null) && [[ -n "$pkg_flags" ]]; then
                # Security: Sanitize command output before use
                local sanitized_flags
                if sanitized_flags=$(sanitize_command_output "$pkg_flags" 2>/dev/null) && [[ -n "$sanitized_flags" ]]; then
                    flags+=" $sanitized_flags"
                    [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Added sanitized pkg-config flags: $sanitized_flags" >&2
                else
                    [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Failed to sanitize pkg-config flags" >&2
                fi
            else
                [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Failed to get pkg-config flags for raylib" >&2
            fi
        fi
        
        # Add fortran-raylib flags
        if [[ -d "${cache_dir}/fortran-raylib" ]]; then
            flags+=" -I${cache_dir}/fortran-raylib/src"
            # Add fortran-raylib library path if it exists
            local frg_lib_path
            frg_lib_path="${cache_dir}/fortran-raylib/build/gfortran_*/fortran-raylib"
            # Use find instead of ls for safe glob expansion
            if find ${frg_lib_path%/*} -name "*.a" -path "*/fortran-raylib/*" 2>/dev/null | head -1 | read -r lib_file; then
                local lib_dir
                lib_dir=$(dirname "$lib_file" 2>/dev/null)
                if [[ -n "$lib_dir" ]] && [[ -d "$lib_dir" ]]; then
                    flags+=" -L${lib_dir} -lfortran-raylib"
                fi
            fi
        fi
    fi
    
    # Add OpenMP support for thread safety tests
    flags+=" -fopenmp"
    
    echo "${flags}"
}

# Print configuration summary
print_config() {
    echo "Fortui Build Configuration:" >&2
    echo "  Platform: $(detect_platform)" >&2
    echo "  Cache: ${GUI_CACHE}" >&2
    
    local gui_enabled=false
    if detect_raylib; then
        gui_enabled=true
        echo "  GUI Backend: ENABLED" >&2
    else
        echo "  GUI Backend: DISABLED" >&2
    fi
    echo "  TUI Backend: ENABLED (always)" >&2
    
    if [[ "$gui_enabled" == "true" ]]; then
        if [[ -n "${RAYLIB_ROOT}" ]]; then
            echo "  Raylib: Custom (${RAYLIB_ROOT})" >&2
        else
            echo "  Raylib: System (pkg-config)" >&2
        fi
    fi
    
    if [[ "${DEBUG}" == "1" ]]; then
        echo "  Debug mode: ON" >&2
        echo "  Environment variables:" >&2
        echo "    DISABLE_GUI=${DISABLE_GUI}" >&2
        echo "    RAYLIB_ROOT=${RAYLIB_ROOT}" >&2
        echo "    FRG_URL=${FRG_URL}" >&2
        echo "    FRG_REF=${FRG_REF}" >&2
    fi
    return 0
}

# Main execution when run directly
main() {
    local action="${1:-build}"
    
    case "${action}" in
        "build")
            print_config
            if build_dependencies; then
                echo "All dependencies built successfully" >&2
                return 0
            else
                echo "Build failed" >&2
                return 1
            fi
            ;;
        "flags")
            setup_cpp_flags
            return 0
            ;;
        "fpmflags")
            setup_fpm_flags
            return 0
            ;;
        "ldflags")
            get_dependency_flags
            return 0
            ;;
        "config")
            print_config
            return 0
            ;;
        "clean")
            if [[ -d "${GUI_CACHE}" ]]; then
                echo "Cleaning cache: ${GUI_CACHE}" >&2
                rm -rf "${GUI_CACHE}"
                echo "Cache cleaned" >&2
            else
                echo "Cache directory does not exist: ${GUI_CACHE}" >&2
            fi
            return 0
            ;;
        "status")
            report_cache_status "${GUI_CACHE}"
            return 0
            ;;
        *)
            echo "Usage: $0 [build|flags|fpmflags|ldflags|config|clean|status]" >&2
            echo "  build    - Build all dependencies" >&2
            echo "  flags    - Print CPP flags (ENABLE_GUI=0|1)" >&2
            echo "  fpmflags - Print FPM compiler flags (-cpp -DENABLE_GUI/-DTUI_ONLY)" >&2
            echo "  ldflags  - Print linker flags for dependencies" >&2
            echo "  config   - Print configuration summary" >&2
            echo "  clean    - Clean dependency cache" >&2
            echo "  status   - Show cache status and size information" >&2
            echo "" >&2
            echo "Environment variables:" >&2
            echo "  DISABLE_GUI   - Set to 1 to disable GUI backend" >&2
            echo "  RAYLIB_ROOT   - Path to custom raylib installation" >&2
            echo "  GUI_CACHE     - Cache directory (default: ~/.cache/fortui)" >&2
            echo "  DEBUG         - Set to 1 to enable debug output" >&2
            echo "  FRG_URL       - fortran-raylib repository URL" >&2
            echo "  FRG_REF       - fortran-raylib git reference" >&2
            echo "  FORCE_REBUILD - Set to 1 to force rebuild all dependencies" >&2
            echo "  OFFLINE_MODE  - Set to 1 to use only cached dependencies" >&2
            return 1
            ;;
    esac
}

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi