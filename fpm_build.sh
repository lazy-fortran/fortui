#!/bin/bash
# fpm_build.sh - Wrapper to properly build with FPM using dependencies
# Usage: ./fpm_build.sh [fpm_args...]
set -e

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/tools/build_fortui.sh"

echo "Building fortui with FPM..."

# Build dependencies first
if ! "$BUILD_SCRIPT" build; then
    echo "Error: Failed to build dependencies" >&2
    exit 1
fi

# Get CPP flags for conditional compilation
CPP_FLAGS=$("$BUILD_SCRIPT" flags)
if [[ "$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then
    export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DENABLE_GUI"
else
    export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DTUI_ONLY"
fi

# Get linker flags for dependencies
DEPENDENCY_LDFLAGS=$("$BUILD_SCRIPT" ldflags)
export FPM_LDFLAGS="${FPM_LDFLAGS:-} ${DEPENDENCY_LDFLAGS}"

# Set runtime library path for shared libraries
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fortui"
if [[ -d "${CACHE_DIR}/termbox2" ]]; then
    export LD_LIBRARY_PATH="${CACHE_DIR}/termbox2:${LD_LIBRARY_PATH:-}"
fi

echo "Environment configured:"
echo "  FPM_FFLAGS: ${FPM_FFLAGS}"
echo "  FPM_LDFLAGS: ${FPM_LDFLAGS}"
echo "  LD_LIBRARY_PATH: ${LD_LIBRARY_PATH:-}"
echo ""

# Run FPM with the configured environment
# Use env to explicitly pass environment variables to ensure propagation
exec env FPM_FFLAGS="${FPM_FFLAGS}" FPM_LDFLAGS="${FPM_LDFLAGS}" LD_LIBRARY_PATH="${LD_LIBRARY_PATH}" fpm "$@"