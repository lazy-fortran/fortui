#!/bin/bash
# build.sh - Simple build script wrapper for fortui
# Pure FPM-based build with embedded termbox2 backend

set -euo pipefail

# Check FPM is available
if ! command -v fpm >/dev/null 2>&1; then
    echo "Error: FPM not found. Please install FPM from https://github.com/fortran-lang/fpm" >&2
    exit 1
fi

# Set TUI-only mode by default (GUI disabled)
export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DTUI_ONLY -DENABLE_TUI=1"

# Show build configuration
echo "FPM build configuration:" >&2
echo "  CPP flags: ${FPM_FFLAGS}" >&2

# Run FPM build
echo "Running FPM build..." >&2
exec fpm build "$@"