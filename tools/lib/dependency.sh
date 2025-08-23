#!/bin/bash
# tools/lib/dependency.sh - Dependency build functions for fortui build system
# Handles termbox2 and fortran-raylib building and validation

# Import guard (prevent multiple includes)
[[ "${_FORTUI_DEPENDENCY_LOADED:-}" == "1" ]] && return 0
readonly _FORTUI_DEPENDENCY_LOADED=1

# Validate termbox2 build environment and check for existing build
validate_termbox2_build() {
    local cache_dir="$1"
    local build_marker="${cache_dir}/termbox2_built"
    
    # Check if already built (unless forced rebuild)
    if [[ -f "${build_marker}" && "${FORCE_REBUILD}" != "1" ]]; then
        [[ "${DEBUG}" == "1" ]] && \
            echo "DEBUG: termbox2 already built (marker exists)" >&2
        return 0
    fi
    
    if [[ "${FORCE_REBUILD}" == "1" && -f "${build_marker}" ]]; then
        [[ "${DEBUG}" == "1" ]] && \
            echo "DEBUG: Force rebuild - removing existing termbox2 build marker" >&2
        rm -f "${build_marker}"
    fi
    
    return 1  # Needs building
}

# Clone or update termbox2 repository
setup_termbox2_repo() {
    local termbox_dir="$1"
    
    # Clone or update termbox2
    if [[ -d "${termbox_dir}" ]]; then
        # Validate existing repository before updating
        if ! validate_dependency_checksum "${termbox_dir}" \
             "${TERMBOX_REF}" "termbox2"; then
            if [[ "${OFFLINE_MODE}" == "1" ]]; then
                echo "Warning: termbox2 repository validation failed" \
                     "in offline mode, using existing repository" >&2
            else
                echo "Warning: termbox2 repository validation failed," \
                     "attempting recovery..." >&2
                if ! handle_corrupted_dependency "${termbox_dir}" \
                     "${TERMBOX_URL}" "${TERMBOX_REF}" "termbox2"; then
                    return 1
                fi
            fi
        else
            if [[ "${OFFLINE_MODE}" == "1" ]]; then
                [[ "${DEBUG}" == "1" ]] && \
                    echo "DEBUG: Offline mode - skipping termbox2" \
                         "repository update" >&2
            else
                if ! (cd "${termbox_dir}" && call_git fetch && \
                      call_git reset --hard "origin/${TERMBOX_REF}"); then
                    echo "Error: Failed to update termbox2 repository" >&2
                    return 1
                fi
            fi
        fi
    else
        if [[ "${OFFLINE_MODE}" == "1" ]]; then
            echo "Error: termbox2 repository not found and" \
                 "offline mode is enabled" >&2
            echo "       Please run with OFFLINE_MODE=0 first to" \
                 "download dependencies" >&2
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
    if ! validate_dependency_checksum "${termbox_dir}" \
         "${TERMBOX_REF}" "termbox2"; then
        echo "Warning: termbox2 repository validation failed" \
             "after clone/update" >&2
    fi
    
    return 0
}

# Build termbox2 library
build_termbox2() {
    local cache_dir="${GUI_CACHE}"
    local termbox_dir="${cache_dir}/termbox2"
    local build_marker="${cache_dir}/termbox2_built"
    
    # Validate build environment
    if validate_termbox2_build "${cache_dir}"; then
        return 0  # Already built
    fi
    
    echo "Building termbox2..." >&2
    
    # Setup repository
    if ! setup_termbox2_repo "${termbox_dir}"; then
        return 1
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

# Check for problematic gfortran versions
check_gfortran_compatibility() {
    local gfortran_version
    if gfortran_version=$(gfortran -dumpversion 2>/dev/null); then
        case "$gfortran_version" in
            15.2.*)
                echo "Warning: gfortran $gfortran_version has known compilation issues" \
                     "with external fortran-raylib" >&2
                echo "         Using internal raylib bindings instead" \
                     "(in src/fortui_gui.f90)" >&2
                return 1  # Skip external fortran-raylib build
                ;;
        esac
    fi
    return 0  # Compatible version
}

# Validate fortran-raylib build environment
validate_fortran_raylib_build() {
    local cache_dir="$1"
    local build_marker="${cache_dir}/fortran_raylib_built"
    
    # Only build if GUI is enabled
    if ! detect_raylib; then
        [[ "${DEBUG}" == "1" ]] && \
            echo "DEBUG: Skipping fortran-raylib build (GUI disabled)" >&2
        return 0
    fi
    
    # Check for problematic gfortran versions
    if ! check_gfortran_compatibility; then
        # Create build marker to indicate we've handled this
        atomic_write "${build_marker}" "skipped_gfortran_15.2_workaround"
        return 0
    fi
    
    # Check if already built (unless forced rebuild)
    if [[ -f "${build_marker}" && "${FORCE_REBUILD}" != "1" ]]; then
        [[ "${DEBUG}" == "1" ]] && \
            echo "DEBUG: fortran-raylib already built (marker exists)" >&2
        return 0
    fi
    
    if [[ "${FORCE_REBUILD}" == "1" && -f "${build_marker}" ]]; then
        [[ "${DEBUG}" == "1" ]] && \
            echo "DEBUG: Force rebuild - removing existing" \
                 "fortran-raylib build marker" >&2
        rm -f "${build_marker}"
    fi
    
    return 1  # Needs building
}

# Clone or update fortran-raylib repository
setup_fortran_raylib_repo() {
    local frg_dir="$1"
    
    # Clone or update fortran-raylib
    if [[ -d "${frg_dir}" ]]; then
        # Validate existing repository before updating
        if ! validate_dependency_checksum "${frg_dir}" \
             "${FRG_REF}" "fortran-raylib"; then
            if [[ "${OFFLINE_MODE}" == "1" ]]; then
                echo "Warning: fortran-raylib repository validation failed" \
                     "in offline mode, using existing repository" >&2
            else
                echo "Warning: fortran-raylib repository validation failed," \
                     "attempting recovery..." >&2
                if ! handle_corrupted_dependency "${frg_dir}" \
                     "${FRG_URL}" "${FRG_REF}" "fortran-raylib"; then
                    return 1
                fi
            fi
        else
            if [[ "${OFFLINE_MODE}" == "1" ]]; then
                [[ "${DEBUG}" == "1" ]] && \
                    echo "DEBUG: Offline mode - skipping fortran-raylib" \
                         "repository update" >&2
            else
                if ! (cd "${frg_dir}" && call_git fetch && \
                      call_git reset --hard "origin/${FRG_REF}"); then
                    echo "Error: Failed to update fortran-raylib repository" >&2
                    return 1
                fi
            fi
        fi
    else
        if [[ "${OFFLINE_MODE}" == "1" ]]; then
            echo "Error: fortran-raylib repository not found and" \
                 "offline mode is enabled" >&2
            echo "       Please run with OFFLINE_MODE=0 first to" \
                 "download dependencies" >&2
            return 1
        fi
        
        if ! call_git clone "${FRG_URL}" "${frg_dir}"; then
            echo "Error: Failed to clone fortran-raylib repository" >&2
            return 1
        fi
        if ! (cd "${frg_dir}" && call_git checkout "${FRG_REF}"); then
            echo "Error: Failed to checkout fortran-raylib ref: ${FRG_REF}" >&2
            return 1
        fi
    fi
    
    # Final validation after clone/update
    if ! validate_dependency_checksum "${frg_dir}" \
         "${FRG_REF}" "fortran-raylib"; then
        echo "Warning: fortran-raylib repository validation failed" \
             "after clone/update" >&2
    fi
    
    return 0
}

# Build fortran-raylib using appropriate build system
build_fortran_raylib_project() {
    local frg_dir="$1"
    
    # Build fortran-raylib (assuming it has a Makefile or fpm build)
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
        echo "Error: Failed to build fortran-raylib" >&2
        return 1
    fi
    
    return 0
}

# Build fortran-raylib library
build_fortran_raylib() {
    local cache_dir="${GUI_CACHE}"
    local frg_dir="${cache_dir}/fortran-raylib"
    local build_marker="${cache_dir}/fortran_raylib_built"
    
    # Validate build environment
    if validate_fortran_raylib_build "${cache_dir}"; then
        return 0  # Already built or skipped
    fi
    
    echo "Building fortran-raylib..." >&2
    
    # Setup repository
    if ! setup_fortran_raylib_repo "${frg_dir}"; then
        return 1
    fi
    
    # Build project
    if ! build_fortran_raylib_project "${frg_dir}"; then
        return 1
    fi
    
    # Create build marker atomically
    atomic_write "${build_marker}" "fortran_raylib_build_marker"
    echo "fortran-raylib built successfully" >&2
}

# Dependency compatibility validation
validate_dependency_compatibility() {
    local cache_dir="$1"
    
    # Check raylib/fortran-raylib compatibility
    if detect_raylib; then
        local raylib_version=""
        local frg_supported_versions=">=3.0.0"  # fortran-raylib supports raylib 3.0+
        
        # Get raylib version
        if [[ -n "${RAYLIB_ROOT}" ]]; then
            # Security: Validate RAYLIB_ROOT path before use
            local validated_raylib_root
            if validated_raylib_root=$(validate_path "${RAYLIB_ROOT}"); then
                # Try to extract version from headers
                local raylib_header="${validated_raylib_root}/include/raylib.h"
                if [[ -f "$raylib_header" ]]; then
                    # Security: Use safe grep with quoted paths
                    raylib_version=$(grep -oE \
                        '#define RAYLIB_VERSION "[0-9]+\.[0-9]+\.[0-9]+"' \
                        "$raylib_header" 2>/dev/null | \
                        grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                fi
            else
                [[ "${DEBUG}" == "1" ]] && \
                    echo "DEBUG: Invalid RAYLIB_ROOT path for version detection: ${RAYLIB_ROOT}" >&2
            fi
        elif command -v pkg-config >/dev/null 2>&1 && \
             call_pkg_config --exists raylib; then
            raylib_version=$(call_pkg_config --modversion raylib 2>/dev/null)
        fi
        
        if [[ -n "$raylib_version" ]]; then
            local raylib_major raylib_minor
            raylib_major=$(echo "$raylib_version" | cut -d. -f1)
            raylib_minor=$(echo "$raylib_version" | cut -d. -f2)
            
            # Check if raylib version is compatible (3.0.0+)
            if [[ "$raylib_major" -lt 3 ]]; then
                echo "Warning: Raylib version $raylib_version may not be" \
                     "compatible with fortran-raylib (requires >=3.0.0)" >&2
                echo "         Build may fail. Consider upgrading raylib." >&2
            elif [[ "${DEBUG}" == "1" ]]; then
                echo "DEBUG: Raylib version $raylib_version is compatible" \
                     "with fortran-raylib" >&2
            fi
        elif [[ "${DEBUG}" == "1" ]]; then
            echo "DEBUG: Could not determine raylib version" \
                 "for compatibility check" >&2
        fi
    fi
    
    # Check termbox2 compatibility with platform
    local platform
    platform=$(detect_platform)
    if [[ "$platform" == "windows" && "${DEBUG}" == "1" ]]; then
        echo "DEBUG: termbox2 may require additional setup" \
             "on Windows platform" >&2
    fi
    
    return 0
}