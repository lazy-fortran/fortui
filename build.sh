#!/bin/bash
# build.sh - Simple build script wrapper for fortui
# Pure FPM-based build

set -euo pipefail

# Check FPM is available
if ! command -v fpm >/dev/null 2>&1; then
    echo "Error: FPM not found. Please install FPM from https://github.com/fortran-lang/fpm" >&2
    exit 1
fi

export FPM_FFLAGS="${FPM_FFLAGS:-} -cpp -DENABLE_TUI=1"
echo "FPM build configuration:" >&2

echo "  FFLAGS: ${FPM_FFLAGS}" >&2
echo "  LDFLAGS: ${FPM_LDFLAGS:-}" >&2

# Run FPM build
echo "Running FPM build..." >&2
exec fpm build "$@"
