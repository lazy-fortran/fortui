# Fortui Build Guide

This guide covers building fortui with its dual TUI/GUI backends using the automated dependency management system.

## Quick Start

```bash
# Build termbox2 dependency for TUI backend
./tools/build_fortui.sh build

# Compile with TUI backend support
fpm build

# Test TUI visual rendering
fpm run --example tui_rendering_demo
fpm test
```

## Build System Overview

Fortui uses a two-stage build process:

1. **Dependency Management**: `tools/build_fortui.sh` handles external C/C++ libraries (termbox2, raylib, fortran-raygui)
2. **Fortran Compilation**: FPM handles Fortran sources and links against built dependencies

## Build Script Commands

The build script `tools/build_fortui.sh` provides several commands:

### Build Dependencies
```bash
./tools/build_fortui.sh build
```
- **termbox2**: TUI backend with visual widget rendering (always built)
- **fortran-raygui**: GUI backend (conditional on raylib availability)
- **Caching**: `~/.cache/fortui` with smart rebuild detection
- **Mock support**: Testing without real termbox2 dependency

### Check Configuration
```bash
./tools/build_fortui.sh config
```
Example output:
```
Fortui Build Configuration:
  Platform: linux
  Cache: /home/user/.cache/fortui
  GUI Backend: ENABLED
  TUI Backend: ENABLED (always)
  Raylib: System (pkg-config)
```

### Get Compiler Flags
```bash
# Get preprocessor flags for conditional compilation
./tools/build_fortui.sh flags
# Output: ENABLE_GUI=1 (or ENABLE_GUI=0 if GUI disabled)

# Get linker flags for dependencies
./tools/build_fortui.sh ldflags  
# Output: -I/path/to/headers -L/path/to/libs -ltermbox2 -lraylib
```

### Clean Cache
```bash
./tools/build_fortui.sh clean
```

## Environment Configuration

### Core Variables

**DISABLE_GUI** - Force disable GUI backend
```bash
# Build TUI-only version
DISABLE_GUI=1 ./tools/build_fortui.sh build
```

**RAYLIB_ROOT** - Use custom raylib installation
```bash
# Use raylib from specific directory
RAYLIB_ROOT=/opt/raylib ./tools/build_fortui.sh build
```

**GUI_CACHE** - Custom cache directory
```bash
# Use different cache location
GUI_CACHE=/tmp/fortui_deps ./tools/build_fortui.sh build
```

**DEBUG** - Enable debug output
```bash
# See detailed build information
DEBUG=1 ./tools/build_fortui.sh build
```

### Advanced Variables

**FRG_URL** - Custom fortran-raygui repository
```bash
FRG_URL=https://github.com/user/fortran-raygui.git ./tools/build_fortui.sh build
```

**FRG_REF** - Specific git reference for fortran-raygui
```bash
FRG_REF=v1.0.0 ./tools/build_fortui.sh build
```

**TERMBOX_URL** - Custom termbox2 repository  
```bash
TERMBOX_URL=https://github.com/user/termbox2.git ./tools/build_fortui.sh build
```

**TERMBOX_REF** - Specific git reference for termbox2
```bash
TERMBOX_REF=master ./tools/build_fortui.sh build
```

## Integration Examples

### Basic FPM Integration

The build script is designed to work alongside FPM. A typical workflow:

```bash
# 1. Build dependencies
./tools/build_fortui.sh build

# 2. Get flags for FPM configuration (if needed)
CPP_FLAGS=$(./tools/build_fortui.sh flags)
LINK_FLAGS=$(./tools/build_fortui.sh ldflags)

# 3. Build with FPM
fpm build
```

### Makefile Integration

```makefile
# Makefile example
FORTUI_FLAGS = $(shell ./tools/build_fortui.sh flags)
FORTUI_LDFLAGS = $(shell ./tools/build_fortui.sh ldflags)

build: deps
	fpm build --flag "$(FORTUI_FLAGS)" --link-flag "$(FORTUI_LDFLAGS)"

deps:
	./tools/build_fortui.sh build

clean-deps:
	./tools/build_fortui.sh clean

.PHONY: build deps clean-deps
```

### CI/CD Integration

```yaml
# GitHub Actions example
- name: Build Dependencies
  run: ./tools/build_fortui.sh build

- name: Configure for TUI-only
  if: matrix.config == 'tui-only'
  run: echo "DISABLE_GUI=1" >> $GITHUB_ENV

- name: Build Project
  run: fpm build
```

## Platform-Specific Notes

### Linux
- System raylib detected via pkg-config
- termbox2 builds using system compiler (gcc/clang)
- Cache defaults to `~/.cache/fortui`

### macOS  
- Similar to Linux, uses Homebrew raylib if available
- May require Xcode command line tools for compilation

### Windows (Experimental)
- Requires MSYS2 or similar environment
- Set RAYLIB_ROOT to Windows raylib installation path
- Use forward slashes in paths for cross-platform compatibility

## Troubleshooting

### GUI Backend Not Detected

**Problem**: `GUI Backend: DISABLED` even when raylib is installed

**Solutions**:
1. Check raylib installation: `pkg-config --exists raylib && echo "Found" || echo "Not found"`
2. Set custom path: `RAYLIB_ROOT=/path/to/raylib ./tools/build_fortui.sh config`
3. Force disable if not needed: `DISABLE_GUI=1 ./tools/build_fortui.sh build`

### Build Failures

**termbox2 build fails**:
- Ensure C compiler (gcc/clang) is available
- Check build output: `DEBUG=1 ./tools/build_fortui.sh build`
- Clean and retry: `./tools/build_fortui.sh clean && ./tools/build_fortui.sh build`

**fortran-raygui build fails**:
- Check network access to GitHub
- Use alternative repository: `FRG_URL=your-mirror-url ./tools/build_fortui.sh build`
- GUI will be disabled if this dependency fails

### Cache Issues

**Stale dependencies**:
```bash
# Clean cache and rebuild
./tools/build_fortui.sh clean
./tools/build_fortui.sh build
```

**Permission issues**:
```bash
# Use custom cache location
GUI_CACHE=/tmp/fortui_cache ./tools/build_fortui.sh build
```

### FPM Integration Issues

**Missing flags**:
- Make sure dependencies are built first: `./tools/build_fortui.sh build`
- Check flag output: `./tools/build_fortui.sh flags` and `./tools/build_fortui.sh ldflags`

## Advanced Usage

### Development Workflow

```bash
# Development setup - build dependencies once
./tools/build_fortui.sh build

# During development - quick FPM builds
fpm build           # Uses cached dependencies
fpm run example     # Run examples
fpm test            # Run tests

# When dependencies change - rebuild only dependencies  
./tools/build_fortui.sh clean
./tools/build_fortui.sh build
```

### Backend Selection Control

```bash
# Build TUI-only version (faster, fewer dependencies)
DISABLE_GUI=1 ./tools/build_fortui.sh build
fpm build

# Force GUI version with custom raylib
RAYLIB_ROOT=/opt/raylib ./tools/build_fortui.sh build
fpm build
```

### Testing Different Configurations

```bash
# Test TUI backend only
DISABLE_GUI=1 ./tools/build_fortui.sh config

# Test with custom cache
GUI_CACHE=/tmp/test_cache ./tools/build_fortui.sh config

# Test with debug output
DEBUG=1 ./tools/build_fortui.sh build
```

## Build Script Architecture

The build script provides:
- **Conditional compilation**: Sets ENABLE_GUI preprocessor flag based on raylib availability
- **Smart caching**: Only rebuilds dependencies when needed using build markers
- **Platform detection**: Handles Linux/macOS/Windows differences automatically
- **Flexible configuration**: Extensive environment variable control
- **Clean separation**: Dependencies separate from main Fortran compilation
- **FPM integration**: Designed to work alongside FPM without conflicts

Dependencies are built in `${GUI_CACHE}` (default `~/.cache/fortui`) with this structure:
```
~/.cache/fortui/
├── termbox2/          # termbox2 source and built library
├── fortran-raygui/    # fortran-raygui source and built library  
├── termbox2_built     # Build marker for termbox2
└── fortran_raygui_built  # Build marker for fortran-raygui
```