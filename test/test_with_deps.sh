#!/bin/bash
# test_with_deps.sh - Run FPM tests with proper dependency linking
# This script ensures termbox2 and raylib dependencies are properly linked

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build dependencies first
echo "Building fortui dependencies..."
if ! "$SCRIPT_DIR/tools/build_fortui.sh" build; then
    echo "Error: Failed to build dependencies" >&2
    exit 1
fi

# Get build flags
CPP_FLAGS=$("$SCRIPT_DIR/tools/build_fortui.sh" flags)
if [[ "$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then
    export FPM_FFLAGS="-cpp -DENABLE_GUI"
else
    export FPM_FFLAGS="-cpp -DTUI_ONLY"
fi

# Get linker flags
export FPM_LDFLAGS=$("$SCRIPT_DIR/tools/build_fortui.sh" ldflags)

echo "Running tests with proper dependency linking..."
echo "CPP flags: $FPM_FFLAGS"
echo "Linker flags: $FPM_LDFLAGS"

# Run FPM with all arguments passed through
exec fpm "$@"