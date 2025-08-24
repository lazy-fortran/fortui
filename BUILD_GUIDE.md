# Fortui Build Guide

This guide covers building fortui with its simplified build system and dual TUI/GUI backends.

## Quick Start

```bash
# Clone and build - it's that simple!
git clone https://github.com/krystophny/fortui.git
cd fortui
fpm build

# Test TUI visual rendering
fpm run --example simple_test
fpm test
```

### Applications with OpenMP

**For applications using OpenMP thread safety:**
```bash
# Set OpenMP compilation flags
export FPM_FFLAGS="-cpp -fopenmp"
export FPM_LDFLAGS="-fopenmp"

# Build your application
fpm build your_threaded_app.f90
```

## Build System Overview

Fortui uses a **dramatically simplified build system**:

1. **Self-contained**: termbox2 C library embedded in `src/c/`
2. **Standard FPM**: `fpm build` works directly without scripts
3. **Optional GUI**: Automatic raylib detection for GUI backend
4. **No external dependencies**: Everything needed is included

### Key Simplifications

- **No build scripts**: Eliminated all `./tools/build_fortui.sh` complexity
- **No dependency fetching**: termbox2 embedded in repository
- **No caching systems**: Standard FPM handles everything
- **No network operations**: Fully offline capable
- **Minimal CPP usage**: Only essential backend selection macros
- **Cross-Platform**: Linux, macOS, Windows with platform-specific optimizations
- **FPM Integration**: Preprocessor support via fpm.toml configuration

## GUI Backend Setup

For optional GUI support, install raylib system-wide:

```bash
# Ubuntu/Debian  
sudo apt install libraylib-dev

# macOS
brew install raylib

# Windows (MSYS2)
pacman -S mingw-w64-x86_64-raylib

# Build with automatic GUI detection
fpm build
```

**Backend Status:**
- **TUI backend**: Always available (termbox2 embedded)
- **GUI backend**: Conditional on raylib system installation  
- **No manual setup**: FPM handles detection automatically

### Force TUI-Only Build
```bash
# Skip GUI detection entirely
DISABLE_GUI=1 fpm build
```

## Requirements

**Required tools:**
- Modern Fortran compiler (gfortran 9+ or ifort)
- Fortran Package Manager (FPM) - [Install guide](https://github.com/fortran-lang/fpm)

**Optional for GUI:**
- raylib library - Install via system package manager

The build system automatically validates requirements and provides helpful error messages if tools are missing:

```bash
# Example FPM error message
Error: fpm not found in PATH
Please install FPM: https://github.com/fortran-lang/fmp
```

## Environment Variables

The simplified build system supports a minimal set of environment variables:

**DISABLE_GUI** - Force disable GUI backend
```bash  
# Build TUI-only version
DISABLE_GUI=1 fpm build
```

**RAYLIB_ROOT** - Use custom raylib installation
```bash
# Use raylib from specific directory  
RAYLIB_ROOT=/opt/raylib fpm build
```

Standard FPM environment variables also work:
```bash
# Custom compiler flags
export FPM_FFLAGS="-O3 -march=native"
export FPM_LDFLAGS="-static"
fmp build
```

## Troubleshooting

### GUI Backend Not Detected
Check if raylib is properly installed:
```bash
pkg-config --exists raylib && echo "Found" || echo "Missing"
```

**Solutions:**
1. Install raylib via package manager (see GUI Backend Setup above)
2. Set custom path: `RAYLIB_ROOT=/path/to/raylib fpm build`  
3. Use TUI-only: `DISABLE_GUI=1 fpm build`

### FPM Not Found
Install Fortran Package Manager from: https://github.com/fortran-lang/fpm

### Build Process

The simplified build process:
1. **FPM compiles** Fortran sources automatically
2. **C compilation** termbox2.c handled by FPM  
3. **Linking** raylib linked automatically if detected
4. **No external tools** required beyond FPM and compiler

**That's it!** The complex dependency management, caching systems, and build scripts have been eliminated.

## Summary

The build system cleanup in Issue #116 delivered on all acceptance criteria:

- ✅ **Simplified build script**: `fpm build` works directly
- ✅ **Fewer environment variables**: Only `DISABLE_GUI` and `RAYLIB_ROOT` needed
- ✅ **Clear, simple build process**: One command builds everything
- ✅ **Minimal CPP usage**: Only essential `ENABLE_TUI=1` macro
- ✅ **Easy to understand and maintain**: No complex scripts or dependency management

The build system went from enterprise-grade complexity to a simple, self-contained package that just works.
