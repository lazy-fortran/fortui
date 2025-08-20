#!/bin/bash
# build.sh - Main build script for fortui with FPM integration
# This script manages dependencies and invokes FPM with proper environment

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/tools/build_fortui.sh"

# Parse command line arguments
FPM_ARGS=""
BUILD_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --deps-only)
            BUILD_ONLY=1
            ;;
        *)
            FPM_ARGS="$FPM_ARGS $arg"
            ;;
    esac
done

# Step 1: Build dependencies
echo "Building fortui dependencies..." >&2
if ! "$BUILD_SCRIPT" build; then
    echo "Error: Failed to build dependencies" >&2
    exit 1
fi

# If only building dependencies, exit now
if [[ "$BUILD_ONLY" == "1" ]]; then
    echo "Dependencies built successfully" >&2
    exit 0
fi

# Step 2: Get CPP flags for conditional compilation
CPP_FLAGS=$("$BUILD_SCRIPT" flags)
if [[ "$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then
    export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DENABLE_GUI"
else
    export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DTUI_ONLY"
fi

# Step 3: Get linker flags for dependencies
DEPENDENCY_LDFLAGS=$("$BUILD_SCRIPT" ldflags)
export FPM_LDFLAGS="${FPM_LDFLAGS:-} ${DEPENDENCY_LDFLAGS}"

# Step 4: Show configuration
echo "FPM build configuration:" >&2
echo "  CPP flags: ${FPM_FFLAGS}" >&2
echo "  Link flags: ${FPM_LDFLAGS}" >&2

# Step 5: Run FPM with the configured environment
echo "Running FPM build..." >&2
exec fpm build ${FPM_ARGS}