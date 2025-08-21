#!/bin/bash
# run_fpm.sh - Wrapper to run FPM with proper environment setup
# This script runs the build dependencies setup and then calls FPM with
# the correct environment variables

set -euo pipefail

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Step 1: Build dependencies and capture environment setup
echo "Setting up build environment..." >&2
if ! ./tools/build_fortui.sh build; then
    echo "Error: Failed to build dependencies" >&2
    exit 1
fi

# Step 2: Get compiler and linker flags
CPP_FLAGS=$(./tools/build_fortui.sh flags)
LINKER_FLAGS=$(./tools/build_fortui.sh ldflags)

# Step 3: Set up environment for FPM
if [[ "$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then
    export FPM_FFLAGS="${FPM_FFLAGS:-} -DENABLE_GUI"
else
    export FPM_FFLAGS="${FPM_FFLAGS:-} -DTUI_ONLY"  
fi

# Add linker flags
export FPM_LDFLAGS="${FPM_LDFLAGS:-} ${LINKER_FLAGS}"

# Step 4: Report configuration 
echo "FPM Environment:" >&2
echo "  FPM_FFLAGS: $FPM_FFLAGS" >&2
echo "  FPM_LDFLAGS: $FPM_LDFLAGS" >&2

# Step 5: Run FPM with all arguments passed through
exec fpm "$@"