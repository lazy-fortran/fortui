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
    
    # Compiler version (gfortran)
    if command -v gfortran >/dev/null 2>&1; then
        versions+="gfortran:$(gfortran --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1);"
    fi
    
    # FPM version
    if command -v fpm >/dev/null 2>&1; then
        versions+="fpm:$(fpm --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1);"
    fi
    
    echo "${versions}build_system:${BUILD_SYSTEM_VERSION}"
}

# Check if cache is valid based on tool versions
is_cache_valid() {
    local cache_dir="$1"
    local version_file="${cache_dir}/.tool_versions"
    
    if [[ ! -f "$version_file" ]]; then
        return 1
    fi
    
    local current_versions
    current_versions="$(get_tool_versions)"
    local cached_versions
    cached_versions="$(cat "$version_file")"
    
    [[ "$current_versions" == "$cached_versions" ]]
}

# Cache locking mechanism for concurrent access safety
acquire_cache_lock() {
    local cache_dir="$1"
    local lock_file="${cache_dir}/.build.lock"
    local timeout=300  # 5 minute timeout
    local wait_time=1
    local elapsed=0
    
    mkdir -p "$cache_dir" 2>/dev/null
    
    while [[ $elapsed -lt $timeout ]]; do
        # Try to create lock file atomically
        if (set -C; echo "$$" > "$lock_file") 2>/dev/null; then
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Acquired cache lock: $lock_file" >&2
            return 0
        fi
        
        # Check if lock is stale (process no longer exists)
        if [[ -f "$lock_file" ]]; then
            local lock_pid
            lock_pid=$(cat "$lock_file" 2>/dev/null)
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Removing stale lock (PID $lock_pid)" >&2
                rm -f "$lock_file"
                continue
            fi
        fi
        
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Waiting for cache lock..." >&2
        sleep "$wait_time"
        elapsed=$((elapsed + wait_time))
    done
    
    echo "Error: Failed to acquire cache lock after ${timeout}s" >&2
    return 1
}

# Release cache lock
release_cache_lock() {
    local cache_dir="$1"
    local lock_file="${cache_dir}/.build.lock"
    
    if [[ -f "$lock_file" ]]; then
        local lock_pid
        lock_pid=$(cat "$lock_file" 2>/dev/null)
        if [[ "$lock_pid" == "$$" ]]; then
            rm -f "$lock_file"
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Released cache lock: $lock_file" >&2
        else
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Lock owned by different process (PID $lock_pid)" >&2
        fi
    fi
}

# Atomic file operations for safe cache updates
atomic_write() {
    local target_file="$1"
    local content="$2"
    local temp_file="${target_file}.tmp.$$"
    
    # Write to temporary file
    echo "$content" > "$temp_file" || return 1
    
    # Atomic move
    mv "$temp_file" "$target_file" || return 1
    
    return 0
}

# Update cache version information atomically
update_cache_versions() {
    local cache_dir="$1"
    local version_file="${cache_dir}/.tool_versions"
    local versions
    
    versions=$(get_tool_versions)
    atomic_write "$version_file" "$versions"
}

# Get cache size in human-readable format
get_cache_size() {
    local cache_dir="$1"
    
    if [[ ! -d "$cache_dir" ]]; then
        echo "0B"
        return
    fi
    
    # Use du to get size, fallback to manual calculation if not available
    if command -v du >/dev/null 2>&1; then
        local size_kb
        size_kb=$(du -sk "$cache_dir" 2>/dev/null | cut -f1)
        if [[ -n "$size_kb" && "$size_kb" =~ ^[0-9]+$ ]]; then
            # Convert to human readable format
            if [[ $size_kb -lt 1024 ]]; then
                echo "${size_kb}KB"
            elif [[ $size_kb -lt 1048576 ]]; then
                echo "$((size_kb / 1024))MB"
            else
                echo "$((size_kb / 1048576))GB"
            fi
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Monitor and report cache status
report_cache_status() {
    local cache_dir="$1"
    
    if [[ ! -d "$cache_dir" ]]; then
        echo "Cache directory does not exist: $cache_dir" >&2
        return
    fi
    
    local cache_size
    cache_size=$(get_cache_size "$cache_dir")
    
    echo "Cache Status:" >&2
    echo "  Location: $cache_dir" >&2
    echo "  Size: $cache_size" >&2
    
    # Report on individual components
    local termbox_dir="${cache_dir}/termbox2"
    local frg_dir="${cache_dir}/fortran-raygui"
    
    if [[ -d "$termbox_dir" ]]; then
        local termbox_size
        termbox_size=$(get_cache_size "$termbox_dir")
        echo "  termbox2: $termbox_size" >&2
    else
        echo "  termbox2: not cached" >&2
    fi
    
    if [[ -d "$frg_dir" ]]; then
        local frg_size
        frg_size=$(get_cache_size "$frg_dir")
        echo "  fortran-raygui: $frg_size" >&2
    else
        echo "  fortran-raygui: not cached" >&2
    fi
    
    # Check for build markers
    local markers=()
    [[ -f "${cache_dir}/termbox2_built" ]] && markers+=("termbox2")
    [[ -f "${cache_dir}/fortran_raygui_built" ]] && markers+=("fortran-raygui")
    
    if [[ ${#markers[@]} -gt 0 ]]; then
        echo "  Built: ${markers[*]}" >&2
    else
        echo "  Built: none" >&2
    fi
}

# Calculate SHA256 checksum of directory (git repo)
calculate_repo_checksum() {
    local repo_dir="$1"
    
    if [[ ! -d "$repo_dir/.git" ]]; then
        echo "not_a_git_repo"
        return 1
    fi
    
    # Use git to get consistent hash based on current commit
    (cd "$repo_dir" && call_git rev-parse HEAD 2>/dev/null) || echo "no_git_hash"
}

# Validate dependency checksum/integrity
validate_dependency_checksum() {
    local repo_dir="$1"
    local expected_ref="$2"
    local dep_name="$3"
    
    if [[ ! -d "$repo_dir" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Repository directory does not exist: $repo_dir" >&2
        return 1
    fi
    
    # Get current commit hash
    local current_hash
    current_hash=$(calculate_repo_checksum "$repo_dir")
    
    if [[ "$current_hash" == "not_a_git_repo" || "$current_hash" == "no_git_hash" ]]; then
        echo "Warning: Could not validate checksum for $dep_name (not a git repository)" >&2
        return 0  # Don't fail build, just warn
    fi
    
    # For git repositories, we validate by checking if we're on the expected ref
    local current_ref
    current_ref=$(cd "$repo_dir" && call_git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    if [[ "$current_ref" != "$expected_ref" ]]; then
        # If we're on a specific commit (detached HEAD), check if it matches expected ref
        local ref_hash
        ref_hash=$(cd "$repo_dir" && call_git rev-parse "origin/$expected_ref" 2>/dev/null || echo "unknown")
        
        if [[ "$current_hash" != "$ref_hash" ]]; then
            echo "Warning: $dep_name checksum mismatch. Expected ref: $expected_ref, Current: $current_ref ($current_hash)" >&2
            [[ "${DEBUG}" == "1" ]] && echo "DEBUG: This may indicate repository corruption or unexpected changes" >&2
        elif [[ "${DEBUG}" == "1" ]]; then
            echo "DEBUG: $dep_name checksum valid (detached HEAD at correct commit)" >&2
        fi
    elif [[ "${DEBUG}" == "1" ]]; then
        echo "DEBUG: $dep_name checksum valid (on expected ref: $expected_ref)" >&2
    fi
    
    return 0
}

# Detect and handle corrupted dependencies
handle_corrupted_dependency() {
    local repo_dir="$1"
    local repo_url="$2"
    local repo_ref="$3"
    local dep_name="$4"
    
    echo "Detected corrupted $dep_name repository. Attempting recovery..." >&2
    
    # Remove corrupted directory
    if [[ -d "$repo_dir" ]]; then
        rm -rf "$repo_dir"
    fi
    
    # Re-clone repository
    if ! call_git clone "$repo_url" "$repo_dir"; then
        echo "Error: Failed to re-clone $dep_name repository after corruption" >&2
        return 1
    fi
    
    # Checkout expected ref
    if ! (cd "$repo_dir" && call_git checkout "$repo_ref"); then
        echo "Error: Failed to checkout $dep_name ref: $repo_ref after recovery" >&2
        return 1
    fi
    
    echo "$dep_name repository recovered successfully" >&2
    return 0
}

# Dependency compatibility validation
validate_dependency_compatibility() {
    local cache_dir="$1"
    
    # Check raylib/fortran-raygui compatibility
    if detect_raylib; then
        local raylib_version=""
        local frg_supported_versions=">=3.0.0"  # fortran-raygui supports raylib 3.0+
        
        # Get raylib version
        if [[ -n "${RAYLIB_ROOT}" ]]; then
            # Try to extract version from headers
            if [[ -f "${RAYLIB_ROOT}/include/raylib.h" ]]; then
                raylib_version=$(grep -oE '#define RAYLIB_VERSION "[0-9]+\.[0-9]+\.[0-9]+"' "${RAYLIB_ROOT}/include/raylib.h" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            fi
        elif command -v pkg-config >/dev/null 2>&1 && call_pkg_config --exists raylib; then
            raylib_version=$(call_pkg_config --modversion raylib 2>/dev/null)
        fi
        
        if [[ -n "$raylib_version" ]]; then
            local raylib_major raylib_minor
            raylib_major=$(echo "$raylib_version" | cut -d. -f1)
            raylib_minor=$(echo "$raylib_version" | cut -d. -f2)
            
            # Check if raylib version is compatible (3.0.0+)
            if [[ "$raylib_major" -lt 3 ]]; then
                echo "Warning: Raylib version $raylib_version may not be compatible with fortran-raygui (requires >=3.0.0)" >&2
                echo "         Build may fail. Consider upgrading raylib." >&2
            elif [[ "${DEBUG}" == "1" ]]; then
                echo "DEBUG: Raylib version $raylib_version is compatible with fortran-raygui" >&2
            fi
        elif [[ "${DEBUG}" == "1" ]]; then
            echo "DEBUG: Could not determine raylib version for compatibility check" >&2
        fi
    fi
    
    # Check termbox2 compatibility with platform
    local platform
    platform=$(detect_platform)
    if [[ "$platform" == "windows" && "${DEBUG}" == "1" ]]; then
        echo "DEBUG: termbox2 may require additional setup on Windows platform" >&2
    fi
    
    return 0
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
                    echo "Error: Network operation '$1' not available in offline mode" >&2
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
    
    # Check if cache is valid based on tool versions
    if [[ "${FORCE_REBUILD}" == "1" ]] || ! is_cache_valid "${GUI_CACHE}"; then
        if [[ "${DEBUG}" == "1" ]]; then
            if [[ "${FORCE_REBUILD}" == "1" ]]; then
                echo "DEBUG: Force rebuild requested - invalidating cache" >&2
            else
                echo "DEBUG: Tool versions changed - invalidating cache" >&2
            fi
        fi
        
        # Remove build markers to force rebuild
        rm -f "${GUI_CACHE}/termbox2_built"
        rm -f "${GUI_CACHE}/fortran_raygui_built"
    fi
    
    # Update version tracking
    update_cache_versions "${GUI_CACHE}"
    
    [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Cache directory: ${GUI_CACHE}" >&2
}

# Dependency building functions
build_termbox2() {
    local cache_dir="${GUI_CACHE}"
    local termbox_dir="${cache_dir}/termbox2"
    local build_marker="${cache_dir}/termbox2_built"
    
    # Check if already built (unless forced rebuild)
    if [[ -f "${build_marker}" && "${FORCE_REBUILD}" != "1" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: termbox2 already built (marker exists)" >&2
        return 0
    fi
    
    if [[ "${FORCE_REBUILD}" == "1" && -f "${build_marker}" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Force rebuild - removing existing termbox2 build marker" >&2
        rm -f "${build_marker}"
    fi
    
    echo "Building termbox2..." >&2
    
    # Clone or update termbox2
    if [[ -d "${termbox_dir}" ]]; then
        # Validate existing repository before updating
        if ! validate_dependency_checksum "${termbox_dir}" "${TERMBOX_REF}" "termbox2"; then
            if [[ "${OFFLINE_MODE}" == "1" ]]; then
                echo "Warning: termbox2 repository validation failed in offline mode, using existing repository" >&2
            else
                echo "Warning: termbox2 repository validation failed, attempting recovery..." >&2
                if ! handle_corrupted_dependency "${termbox_dir}" "${TERMBOX_URL}" "${TERMBOX_REF}" "termbox2"; then
                    return 1
                fi
            fi
        else
            if [[ "${OFFLINE_MODE}" == "1" ]]; then
                [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Offline mode - skipping termbox2 repository update" >&2
            else
                if ! (cd "${termbox_dir}" && call_git fetch && call_git reset --hard "origin/${TERMBOX_REF}"); then
                    echo "Error: Failed to update termbox2 repository" >&2
                    return 1
                fi
            fi
        fi
    else
        if [[ "${OFFLINE_MODE}" == "1" ]]; then
            echo "Error: termbox2 repository not found and offline mode is enabled" >&2
            echo "       Please run with OFFLINE_MODE=0 first to download dependencies" >&2
            return 1
        fi
        
        if ! call_git clone "${TERMBOX_URL}" "${termbox_dir}"; then
            echo "Error: Failed to clone termbox2 repository" >&2
            return 1
        fi
        if ! (cd "${termbox_dir}" && call_git checkout "${TERMBOX_REF}"); then
            echo "Error: Failed to checkout termbox2 ref: ${TERMBOX_REF}" >&2
            return 1
        fi
    fi
    
    # Final validation after clone/update
    if ! validate_dependency_checksum "${termbox_dir}" "${TERMBOX_REF}" "termbox2"; then
        echo "Warning: termbox2 repository validation failed after clone/update" >&2
    fi
    
    # Build termbox2
    if ! (cd "${termbox_dir}" && make); then
        echo "Error: Failed to build termbox2" >&2
        return 1
    fi
    
    # Create build marker atomically
    atomic_write "${build_marker}" "termbox2_build_marker"
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
    
    # Check if already built (unless forced rebuild)
    if [[ -f "${build_marker}" && "${FORCE_REBUILD}" != "1" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: fortran-raygui already built (marker exists)" >&2
        return 0
    fi
    
    if [[ "${FORCE_REBUILD}" == "1" && -f "${build_marker}" ]]; then
        [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Force rebuild - removing existing fortran-raygui build marker" >&2
        rm -f "${build_marker}"
    fi
    
    echo "Building fortran-raygui..." >&2
    
    # Clone or update fortran-raygui
    if [[ -d "${frg_dir}" ]]; then
        # Validate existing repository before updating
        if ! validate_dependency_checksum "${frg_dir}" "${FRG_REF}" "fortran-raygui"; then
            if [[ "${OFFLINE_MODE}" == "1" ]]; then
                echo "Warning: fortran-raygui repository validation failed in offline mode, using existing repository" >&2
            else
                echo "Warning: fortran-raygui repository validation failed, attempting recovery..." >&2
                if ! handle_corrupted_dependency "${frg_dir}" "${FRG_URL}" "${FRG_REF}" "fortran-raygui"; then
                    return 1
                fi
            fi
        else
            if [[ "${OFFLINE_MODE}" == "1" ]]; then
                [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Offline mode - skipping fortran-raygui repository update" >&2
            else
                if ! (cd "${frg_dir}" && call_git fetch && call_git reset --hard "origin/${FRG_REF}"); then
                    echo "Error: Failed to update fortran-raygui repository" >&2
                    return 1
                fi
            fi
        fi
    else
        if [[ "${OFFLINE_MODE}" == "1" ]]; then
            echo "Error: fortran-raygui repository not found and offline mode is enabled" >&2
            echo "       Please run with OFFLINE_MODE=0 first to download dependencies" >&2
            return 1
        fi
        
        if ! call_git clone "${FRG_URL}" "${frg_dir}"; then
            echo "Error: Failed to clone fortran-raygui repository" >&2
            return 1
        fi
        if ! (cd "${frg_dir}" && call_git checkout "${FRG_REF}"); then
            echo "Error: Failed to checkout fortran-raygui ref: ${FRG_REF}" >&2
            return 1
        fi
    fi
    
    # Final validation after clone/update
    if ! validate_dependency_checksum "${frg_dir}" "${FRG_REF}" "fortran-raygui"; then
        echo "Warning: fortran-raygui repository validation failed after clone/update" >&2
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
    
    # Create build marker atomically
    atomic_write "${build_marker}" "fortran_raygui_build_marker"
    echo "fortran-raygui built successfully" >&2
}

# Main build function
build_dependencies() {
    # Acquire cache lock for concurrent safety
    if ! acquire_cache_lock "${GUI_CACHE}"; then
        return 1
    fi
    
    # Setup cleanup trap to ensure lock is released
    trap 'release_cache_lock "${GUI_CACHE}"' EXIT INT TERM
    
    # Setup cache
    if ! setup_cache; then
        release_cache_lock "${GUI_CACHE}"
        return 1
    fi
    
    # Validate dependency compatibility
    validate_dependency_compatibility "${GUI_CACHE}"
    
    # Build termbox2 (always needed for TUI)
    if ! build_termbox2; then
        echo "Error: Failed to build termbox2 dependency" >&2
        release_cache_lock "${GUI_CACHE}"
        return 1
    fi
    
    # Build fortran-raygui (only if GUI enabled)
    if ! build_fortran_raygui; then
        echo "Error: Failed to build fortran-raygui dependency" >&2
        release_cache_lock "${GUI_CACHE}"
        return 1
    fi
    
    # Release lock before success return (trap will also release)
    release_cache_lock "${GUI_CACHE}"
    trap - EXIT INT TERM
    
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
        "status")
            report_cache_status "${GUI_CACHE}"
            return 0
            ;;
        *)
            echo "Usage: $0 [build|flags|ldflags|config|clean|status]" >&2
            echo "  build   - Build all dependencies" >&2
            echo "  flags   - Print CPP flags (ENABLE_GUI=0|1)" >&2
            echo "  ldflags - Print linker flags for dependencies" >&2
            echo "  config  - Print configuration summary" >&2
            echo "  clean   - Clean dependency cache" >&2
            echo "  status  - Show cache status and size information" >&2
            echo "" >&2
            echo "Environment variables:" >&2
            echo "  DISABLE_GUI   - Set to 1 to disable GUI backend" >&2
            echo "  RAYLIB_ROOT   - Path to custom raylib installation" >&2
            echo "  GUI_CACHE     - Cache directory (default: ~/.cache/fortui)" >&2
            echo "  DEBUG         - Set to 1 to enable debug output" >&2
            echo "  FRG_URL       - fortran-raygui repository URL" >&2
            echo "  FRG_REF       - fortran-raygui git reference" >&2
            echo "  FORCE_REBUILD - Set to 1 to force rebuild all dependencies" >&2
            echo "  OFFLINE_MODE  - Set to 1 to use only cached dependencies" >&2
            return 1
            ;;
    esac
}

# Only run main if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi