#!/bin/bash
# fpm_env.sh - Set up environment for FPM build with fortui dependencies
# Source this script before running FPM commands
# Usage: source fpm_env.sh

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/tools/build_fortui.sh"

echo "Setting up FPM environment for fortui..."

# Build dependencies
echo "Building dependencies..."
if ! "$BUILD_SCRIPT" build; then
    echo "Error: Failed to build dependencies" >&2
    return 1
fi

# Get CPP flags for conditional compilation
CPP_FLAGS=$("$BUILD_SCRIPT" flags)
if [[ "$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then
    export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DENABLE_GUI"
    echo "Configured for GUI+TUI build"
else
    export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DTUI_ONLY"
    echo "Configured for TUI-only build"
fi

# Get linker flags for dependencies
DEPENDENCY_LDFLAGS=$("$BUILD_SCRIPT" ldflags)
export FPM_LDFLAGS="${FPM_LDFLAGS:-} ${DEPENDENCY_LDFLAGS}"

# Static linking - no runtime library paths needed for termbox2

# Report configuration
echo "FPM environment configured:"
echo "  FPM_FFLAGS: ${FPM_FFLAGS}"
echo "  FPM_LDFLAGS: ${FPM_LDFLAGS}"
echo ""
echo "RECOMMENDED: Use ./fpm_build.sh instead of fpm directly"
echo "  ./fpm_build.sh build            - Build the project"
echo "  ./fpm_build.sh test             - Run tests"
echo "  ./fpm_build.sh run --example X  - Run example X"
echo ""
echo "Using static linking - no runtime library paths needed."