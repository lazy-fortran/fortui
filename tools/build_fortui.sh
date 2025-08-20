#!/bin/bash
# tools/build_fortui.sh - Fortui dependency management and build script
# Handles conditional GUI/TUI compilation with dependency management

set -euo pipefail

# Configuration defaults
DEFAULT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fortui"
DEFAULT_FRG_URL="https://github.com/lazy-fortran/fortran-raygui.git"
DEFAULT_FRG_REF="main"
DEFAULT_TERMBOX_URL="https://github.com/termbox/termbox2.git"
DEFAULT_TERMBOX_REF="master"

# Environment variables (with defaults)
GUI_CACHE="${GUI_CACHE:-$DEFAULT_CACHE_DIR}"
DISABLE_GUI="${DISABLE_GUI:-0}"
RAYLIB_ROOT="${RAYLIB_ROOT:-}"
DEBUG="${DEBUG:-0}"
FRG_URL="${FRG_URL:-$DEFAULT_FRG_URL}"
FRG_REF="${FRG_REF:-$DEFAULT_FRG_REF}"
TERMBOX_URL="${TERMBOX_URL:-$DEFAULT_TERMBOX_URL}"
TERMBOX_REF="${TERMBOX_REF:-$DEFAULT_TERMBOX_REF}"

# Platform detection
detect_platform() {
    case "$(uname -s)" in
        Linux*)   echo "linux" ;;
        Darwin*)  echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *)        echo "unknown" ;;
    esac
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

# Wrapper for git (allows mocking in tests)
call_git() {
    if declare -f mock_git >/dev/null; then
        mock_git "$@"
    else
        git "$@"
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
        if [[ -f "${RAYLIB_ROOT}/include/raylib.h" ]]; then
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Found raylib via RAYLIB_ROOT: ${RAYLIB_ROOT}" >&2
            return 0
        else
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: RAYLIB_ROOT specified but raylib.h not found: ${RAYLIB_ROOT}/include/raylib.h" >&2
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

# Cache directory setup
setup_cache() {
    if ! mkdir -p "${GUI_CACHE}" 2>/dev/null; then
        echo "Error: Cannot create cache directory: ${GUI_CACHE}" >&2
        return 1
    fi
    [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Cache directory: ${GUI_CACHE}" >&2
}

# Dependency building functions
build_termbox2() {
    local cache_dir="${GUI_CACHE}"
    local termbox_dir="${cache_dir}/termbox2"
    local build_marker="${cache_dir}/termbox2_built"
    
    # Check if already built
    if [[ -f "${build_marker}" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: termbox2 already built (marker exists)" >&2
        return 0
    fi
    
    echo "Building termbox2..." >&2
    
    # Clone or update termbox2
    if [[ -d "${termbox_dir}" ]]; then
        if ! (cd "${termbox_dir}" && call_git fetch && call_git reset --hard "origin/${TERMBOX_REF}"); then
            echo "Error: Failed to update termbox2 repository" >&2
            return 1
        fi
    else
        if ! call_git clone "${TERMBOX_URL}" "${termbox_dir}"; then
            echo "Error: Failed to clone termbox2 repository" >&2
            return 1
        fi
        if ! (cd "${termbox_dir}" && call_git checkout "${TERMBOX_REF}"); then
            echo "Error: Failed to checkout termbox2 ref: ${TERMBOX_REF}" >&2
            return 1
        fi
    fi
    
    # Build termbox2
    if ! (cd "${termbox_dir}" && make); then
        echo "Error: Failed to build termbox2" >&2
        return 1
    fi
    
    # Create build marker
    echo "termbox2_build_marker" > "${build_marker}"
    echo "termbox2 built successfully" >&2
}

build_fortran_raygui() {
    local cache_dir="${GUI_CACHE}"
    local frg_dir="${cache_dir}/fortran-raygui"
    local build_marker="${cache_dir}/fortran_raygui_built"
    
    # Only build if GUI is enabled
    if ! detect_raylib; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Skipping fortran-raygui build (GUI disabled)" >&2
        return 0
    fi
    
    # Check if already built
    if [[ -f "${build_marker}" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: fortran-raygui already built (marker exists)" >&2
        return 0
    fi
    
    echo "Building fortran-raygui..." >&2
    
    # Clone or update fortran-raygui
    if [[ -d "${frg_dir}" ]]; then
        if ! (cd "${frg_dir}" && call_git fetch && call_git reset --hard "origin/${FRG_REF}"); then
            echo "Error: Failed to update fortran-raygui repository" >&2
            return 1
        fi
    else
        if ! call_git clone "${FRG_URL}" "${frg_dir}"; then
            echo "Error: Failed to clone fortran-raygui repository" >&2
            return 1
        fi
        if ! (cd "${frg_dir}" && call_git checkout "${FRG_REF}"); then
            echo "Error: Failed to checkout fortran-raygui ref: ${FRG_REF}" >&2
            return 1
        fi
    fi
    
    # Build fortran-raygui (assuming it has a Makefile or fpm build)
    local build_success=false
    if [[ -f "${frg_dir}/fpm.toml" ]]; then
        if (cd "${frg_dir}" && fpm build); then
            build_success=true
        fi
    elif [[ -f "${frg_dir}/Makefile" ]]; then
        if (cd "${frg_dir}" && make); then
            build_success=true
        fi
    else
        # No specific build system found - assume pre-built or Fortran source only
        build_success=true
    fi
    
    if [[ "${build_success}" == "false" ]]; then
        echo "Error: Failed to build fortran-raygui" >&2
        return 1
    fi
    
    # Create build marker
    echo "fortran_raygui_build_marker" > "${build_marker}"
    echo "fortran-raygui built successfully" >&2
}

# Main build function
build_dependencies() {
    # Setup cache
    if ! setup_cache; then
        return 1
    fi
    
    # Build termbox2 (always needed for TUI)
    if ! build_termbox2; then
        echo "Error: Failed to build termbox2 dependency" >&2
        return 1
    fi
    
    # Build fortran-raygui (only if GUI enabled)
    if ! build_fortran_raygui; then
        echo "Error: Failed to build fortran-raygui dependency" >&2
        return 1
    fi
    
    return 0
}

# Get compiler flags for dependencies
get_dependency_flags() {
    local cache_dir="${GUI_CACHE}"
    local flags=""
    
    # termbox2 flags
    if [[ -d "${cache_dir}/termbox2" ]]; then
        flags+=" -I${cache_dir}/termbox2"
        flags+=" -L${cache_dir}/termbox2 -ltermbox2"
    fi
    
    # raylib/fortran-raygui flags (only if GUI enabled)
    if detect_raylib; then
        # Add raylib flags
        if [[ -n "${RAYLIB_ROOT}" ]]; then
            flags+=" -I${RAYLIB_ROOT}/include -L${RAYLIB_ROOT}/lib -lraylib"
        elif command -v pkg-config >/dev/null 2>&1 && call_pkg_config --exists raylib; then
            flags+=" $(call_pkg_config --cflags --libs raylib)"
        fi
        
        # Add fortran-raygui flags
        if [[ -d "${cache_dir}/fortran-raygui" ]]; then
            flags+=" -I${cache_dir}/fortran-raygui/src"
            # Add fortran-raygui library path if it exists
            local frg_lib_path="${cache_dir}/fortran-raygui/build/gfortran_*/fortran-raygui"
            if ls ${frg_lib_path}/*.a >/dev/null 2>&1; then
                flags+=" -L${frg_lib_path} -lfortran-raygui"
            fi
        fi
    fi
    
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
            ;;
        "ldflags")
            get_dependency_flags
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
            ;;
        *)
            echo "Usage: $0 [build|flags|ldflags|config|clean]" >&2
            echo "  build   - Build all dependencies" >&2
            echo "  flags   - Print CPP flags (ENABLE_GUI=0|1)" >&2
            echo "  ldflags - Print linker flags for dependencies" >&2
            echo "  config  - Print configuration summary" >&2
            echo "  clean   - Clean dependency cache" >&2
            echo "" >&2
            echo "Environment variables:" >&2
            echo "  DISABLE_GUI   - Set to 1 to disable GUI backend" >&2
            echo "  RAYLIB_ROOT   - Path to custom raylib installation" >&2
            echo "  GUI_CACHE     - Cache directory (default: ~/.cache/fortui)" >&2
            echo "  DEBUG         - Set to 1 to enable debug output" >&2
            echo "  FRG_URL       - fortran-raygui repository URL" >&2
            echo "  FRG_REF       - fortran-raygui git reference" >&2
            return 1
            ;;
    esac
}

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi