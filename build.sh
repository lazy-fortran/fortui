#!/bin/bash
# build.sh - Simple build script wrapper for fortui
# Pure FPM-based build with embedded termbox2 backend

set -euo pipefail

# Check FPM is available
if ! command -v fpm >/dev/null 2>&1; then
    echo "Error: FPM not found. Please install FPM from https://github.com/fortran-lang/fpm" >&2
    exit 1
fi

# Check for --gui flag
if [[ "${1:-}" == "--gui" ]]; then
    shift
    export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DENABLE_TUI=1 -DENABLE_GUI=1"
    export FPM_LDFLAGS="${FPM_LDFLAGS:-} -lraylib"
    echo "FPM build configuration (TUI + GUI):" >&2
else
    export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DTUI_ONLY -DENABLE_TUI=1"
    echo "FPM build configuration (TUI-only):" >&2
fi

echo "  FFLAGS: ${FPM_FFLAGS}" >&2
echo "  LDFLAGS: ${FPM_LDFLAGS:-}" >&2

# Run FPM build
echo "Running FPM build..." >&2
exec fpm build "$@"
