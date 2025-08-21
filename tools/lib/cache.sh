#!/bin/bash
# tools/lib/cache.sh - Cache management functions for fortui build system
# Handles cache validation, locking, size reporting, and dependency checksums

# Import guard (prevent multiple includes)
[[ "${_FORTUI_CACHE_LOADED:-}" == "1" ]] && return 0
readonly _FORTUI_CACHE_LOADED=1

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
            # Security: Use safe PID reading with validation
            if lock_pid=$(safe_read_pid "$lock_file"); then
                if ! kill -0 "$lock_pid" 2>/dev/null; then
                    [[ "${DEBUG}" == "1" ]] && \
                        echo "DEBUG: Removing stale lock (PID $lock_pid)" >&2
                    rm -f "$lock_file"
                    continue
                fi
            else
                # Invalid PID format - remove corrupted lock file
                [[ "${DEBUG}" == "1" ]] && \
                    echo "DEBUG: Removing corrupted lock file: $lock_file" >&2
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
        # Security: Use safe PID reading with validation
        if lock_pid=$(safe_read_pid "$lock_file"); then
            if [[ "$lock_pid" == "$$" ]]; then
                rm -f "$lock_file"
                [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Released cache lock: $lock_file" >&2
            else
                [[ "${DEBUG}" == "1" ]] && \
                    echo "DEBUG: Lock owned by different process (PID $lock_pid)" >&2
            fi
        else
            # Invalid PID format - remove corrupted lock file for safety
            [[ "${DEBUG}" == "1" ]] && \
                echo "DEBUG: Removing corrupted lock file during release: $lock_file" >&2
            rm -f "$lock_file"
        fi
    fi
    return 0
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
    local frg_dir="${cache_dir}/fortran-raylib"
    
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
        echo "  fortran-raylib: $frg_size" >&2
    else
        echo "  fortran-raylib: not cached" >&2
    fi
    
    # Check for build markers
    local markers=()
    [[ -f "${cache_dir}/termbox2_built" ]] && markers+=("termbox2")
    [[ -f "${cache_dir}/fortran_raylib_built" ]] && markers+=("fortran-raylib")
    
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
        [[ "${DEBUG}" == "1" ]] && \
            echo "DEBUG: Repository directory does not exist: $repo_dir" >&2
        return 1
    fi
    
    # Get current commit hash
    local current_hash
    current_hash=$(calculate_repo_checksum "$repo_dir")
    
    if [[ "$current_hash" == "not_a_git_repo" || \
          "$current_hash" == "no_git_hash" ]]; then
        echo "Warning: Could not validate checksum for $dep_name" \
             "(not a git repository)" >&2
        return 0  # Don't fail build, just warn
    fi
    
    # For git repositories, we validate by checking if we're on the expected ref
    local current_ref
    current_ref=$(cd "$repo_dir" && \
        call_git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    if [[ "$current_ref" != "$expected_ref" ]]; then
        # If we're on a specific commit (detached HEAD), check if it matches
        # expected ref
        local ref_hash
        ref_hash=$(cd "$repo_dir" && \
            call_git rev-parse "origin/$expected_ref" 2>/dev/null || echo "unknown")
        
        if [[ "$current_hash" != "$ref_hash" ]]; then
            echo "Warning: $dep_name checksum mismatch. Expected ref:" \
                 "$expected_ref, Current: $current_ref ($current_hash)" >&2
            [[ "${DEBUG}" == "1" ]] && \
                echo "DEBUG: This may indicate repository corruption" \
                     "or unexpected changes" >&2
        elif [[ "${DEBUG}" == "1" ]]; then
            echo "DEBUG: $dep_name checksum valid" \
                 "(detached HEAD at correct commit)" >&2
        fi
    elif [[ "${DEBUG}" == "1" ]]; then
        echo "DEBUG: $dep_name checksum valid (on expected ref: $expected_ref)" >&2
    fi
    
    return 0
}

# Handle corrupted dependency by removing and re-cloning
handle_corrupted_dependency() {
    local repo_dir="$1"
    local repo_url="$2"
    local repo_ref="$3"
    local dep_name="$4"
    
    echo "Detected corrupted $dep_name repository." \
         "Attempting recovery..." >&2
    
    # Remove corrupted directory
    if [[ -d "$repo_dir" ]]; then
        rm -rf "$repo_dir"
    fi
    
    # Re-clone repository
    if ! call_git clone "$repo_url" "$repo_dir"; then
        echo "Error: Failed to re-clone $dep_name repository" \
             "after corruption" >&2
        return 1
    fi
    
    # Checkout expected ref
    if ! (cd "$repo_dir" && call_git checkout "$repo_ref"); then
        echo "Error: Failed to checkout $dep_name ref:" \
             "$repo_ref after recovery" >&2
        return 1
    fi
    
    echo "$dep_name repository recovered successfully" >&2
    return 0
}

# Setup cache directory with validation
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
        rm -f "${GUI_CACHE}/fortran_raylib_built"
    fi
    
    # Update version tracking
    update_cache_versions "${GUI_CACHE}"
    
    [[ "${DEBUG}" == "1" ]] && echo "DEBUG: Cache directory: ${GUI_CACHE}" >&2
    return 0
}