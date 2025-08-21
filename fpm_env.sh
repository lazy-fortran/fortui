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

# Configure runtime library paths (LD_LIBRARY_PATH)
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/fortui"
RUNTIME_LIBS=""

# Add termbox2 library path
if [[ -d "${CACHE_DIR}/termbox2" ]]; then
    RUNTIME_LIBS="${CACHE_DIR}/termbox2"
fi

# Add raylib/fortran-raylib paths if GUI enabled
if [[ "$CPP_FLAGS" == "ENABLE_GUI=1" ]]; then
    # Add raylib path if using RAYLIB_ROOT
    if [[ -n "${RAYLIB_ROOT:-}" && -d "${RAYLIB_ROOT}/lib" ]]; then
        RUNTIME_LIBS="${RUNTIME_LIBS:+${RUNTIME_LIBS}:}${RAYLIB_ROOT}/lib"
    fi
    
    # Add fortran-raylib path if it exists
    if [[ -d "${CACHE_DIR}/fortran-raylib" ]]; then
        FRG_LIB_PATH="${CACHE_DIR}/fortran-raylib/build/gfortran_"*"/fortran-raylib"
        for path in ${FRG_LIB_PATH}; do
            if [[ -d "$path" ]]; then
                RUNTIME_LIBS="${RUNTIME_LIBS:+${RUNTIME_LIBS}:}${path}"
                break
            fi
        done
    fi
fi

# Export LD_LIBRARY_PATH with runtime libraries
if [[ -n "${RUNTIME_LIBS}" ]]; then
    export LD_LIBRARY_PATH="${RUNTIME_LIBS}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

# Report configuration
echo "FPM environment configured:"
echo "  FPM_FFLAGS: ${FPM_FFLAGS}"
echo "  FPM_LDFLAGS: ${FPM_LDFLAGS}"
if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
    echo "  LD_LIBRARY_PATH: ${LD_LIBRARY_PATH}"
fi
echo ""
echo "RECOMMENDED: Use ./fpm_build.sh instead of fpm directly"
echo "  ./fpm_build.sh build            - Build the project"
echo "  ./fpm_build.sh test             - Run tests"
echo "  ./fpm_build.sh run --example X  - Run example X"
echo ""
echo "This ensures proper runtime library paths (LD_LIBRARY_PATH) are set."
echo "If you still prefer direct FPM commands, they will work for building"
echo "but may fail at runtime due to missing shared library paths."