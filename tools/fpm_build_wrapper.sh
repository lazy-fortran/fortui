#!/bin/bash
# tools/fpm_build_wrapper.sh - FPM build-script wrapper for fortui
# This script is invoked by FPM as a build-script override
# It manages dependencies and sets up environment for FPM compilation

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_SCRIPT="$SCRIPT_DIR/build_fortui.sh"

# Export project root for FPM
export FORTUI_PROJECT_ROOT="$PROJECT_ROOT"

# Debug output
if [[ "${DEBUG:-0}" == "1" ]] || [[ "${FORTUI_VERBOSE:-0}" == "1" ]]; then
    echo "FPM build-script wrapper invoked" >&2
    echo "  Script dir: $SCRIPT_DIR" >&2
    echo "  Project root: $PROJECT_ROOT" >&2
    echo "  FPM_COMPILER: ${FPM_COMPILER:-not set}" >&2
    echo "  FPM_FFLAGS: ${FPM_FFLAGS:-not set}" >&2
    echo "  FPM_LDFLAGS: ${FPM_LDFLAGS:-not set}" >&2
fi

# Step 1: Build dependencies
echo "Building fortui dependencies..." >&2
if ! "$BUILD_SCRIPT" build; then
    echo "Error: Failed to build dependencies" >&2
    exit 1
fi

# Step 2: Get CPP flags for conditional compilation
CPP_FLAGS=$("$BUILD_SCRIPT" flags)
if [[ "$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then
    export FPM_CPP_FLAGS="-DENABLE_GUI"
else
    export FPM_CPP_FLAGS="-DTUI_ONLY"
fi

# Step 3: Get linker flags for dependencies
DEPENDENCY_LDFLAGS=$("$BUILD_SCRIPT" ldflags)

# Step 4: Set up FPM environment variables
# Append to existing FPM_FFLAGS if set, otherwise create new
if [[ -n "${FPM_FFLAGS:-}" ]]; then
    export FPM_FFLAGS="${FPM_FFLAGS} ${FPM_CPP_FLAGS}"
else
    export FPM_FFLAGS="${FPM_CPP_FLAGS}"
fi

# Append to existing FPM_LDFLAGS if set, otherwise create new
if [[ -n "${FPM_LDFLAGS:-}" ]]; then
    export FPM_LDFLAGS="${FPM_LDFLAGS} ${DEPENDENCY_LDFLAGS}"
else
    export FPM_LDFLAGS="${DEPENDENCY_LDFLAGS}"
fi

# Step 5: Report configuration to FPM
echo "FPM environment configured:" >&2
echo "  CPP flags: ${FPM_CPP_FLAGS}" >&2
echo "  Dependency flags: ${DEPENDENCY_LDFLAGS}" >&2

# Debug output of final flags
if [[ "${DEBUG:-0}" == "1" ]] || [[ "${FORTUI_VERBOSE:-0}" == "1" ]]; then
    echo "Final FPM environment:" >&2
    echo "  FPM_FFLAGS: ${FPM_FFLAGS}" >&2
    echo "  FPM_LDFLAGS: ${FPM_LDFLAGS}" >&2
fi

# Exit successfully - FPM will now continue with compilation
exit 0