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

Fortui uses an advanced two-stage build process with enterprise-grade reliability:

1. **Dependency Management**: `tools/build_fortui.sh` handles external C/C++ libraries with network resilience, concurrent safety, and automatic recovery
2. **Fortran Compilation**: FPM handles Fortran sources with CPP preprocessing and links against cached dependencies

### Enterprise Features

- **Network Resilience**: Automatic retry with exponential backoff (3 attempts, 1-30s delays)
- **Concurrent Safety**: File locking with 5-minute timeout and stale lock detection
- **Version Tracking**: Smart cache invalidation when build tools (git, make, gfortran, fpm) change
- **Corruption Recovery**: Automatic detection and repair of corrupted git repositories
- **Atomic Operations**: Safe cache updates using temporary files and atomic moves
- **Cross-Platform**: Linux, macOS, Windows with platform-specific optimizations
- **FPM Integration**: Preprocessor support via fpm.toml configuration

## Build Script Commands

The build script `tools/build_fortui.sh` provides several commands:

### Build Dependencies
```bash
./tools/build_fortui.sh build
```
- **termbox2**: TUI backend with visual widget rendering (always built)
- **fortran-raylib**: GUI backend bindings (conditional on raylib availability)
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

### Cache Status and Management
```bash
# View cache status and size information
./tools/build_fortui.sh status
```
Example output:
```
Cache Status:
  Location: /home/user/.cache/fortui
  Size: 45MB
  termbox2: 12MB
  fortran-raylib: 33MB
  Built: termbox2 fortran-raylib
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

**FORCE_REBUILD** - Ignore cache, rebuild everything
```bash
FORCE_REBUILD=1 ./tools/build_fortui.sh build
```

**OFFLINE_MODE** - Work with cached dependencies only (air-gapped environments)
```bash
OFFLINE_MODE=1 ./tools/build_fortui.sh build
```

**Repository Customization**
```bash
# Custom fortran-raylib
FRG_URL=https://github.com/user/fortran-raylib.git
FRG_REF=feature-branch ./tools/build_fortui.sh build

# Custom termbox2
TERMBOX_URL=https://github.com/user/termbox2.git
TERMBOX_REF=master ./tools/build_fortui.sh build
```

## GUI Backend Setup

### Installing raylib

The GUI backend requires raylib to be installed on your system. Here are platform-specific installation instructions:

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install libraylib-dev
```

**Fedora/RHEL:**
```bash
sudo dnf install raylib-devel
```

**macOS:**
```bash
brew install raylib
```

**Arch Linux:**
```bash
sudo pacman -S raylib
```

**Windows (MSYS2):**
```bash
pacman -S mingw-w64-x86_64-raylib
```

### Verifying GUI Support

After installing raylib, verify GUI backend detection:

```bash
# Check if raylib is detected
./tools/build_fortui.sh config
```

Expected output with GUI enabled:
```
Fortui Build Configuration:
  Platform: linux
  Cache: /home/user/.cache/fortui
  GUI Backend: ENABLED          # ← Should show ENABLED
  TUI Backend: ENABLED (always)
  Raylib: System (pkg-config)   # ← Detection method
```

If GUI shows as DISABLED:
```bash
# Check raylib installation
pkg-config --exists raylib && echo "raylib found" || echo "raylib missing"
pkg-config --modversion raylib  # Show version

# Force rebuild after installing raylib
FORCE_REBUILD=1 ./tools/build_fortui.sh build
```

### Quick GUI Test

Build and test GUI functionality:

```bash
# Build with GUI support
source fpm_env.sh
fpm build

# Test GUI backend
fpm run --example gui_demo
```

If the window doesn't appear, check your display environment:
```bash
echo $DISPLAY              # X11 (should show :0 or similar)
echo $WAYLAND_DISPLAY      # Wayland (should show wayland-0)
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

**fortran-raylib build fails**:
- Check network access to GitHub
- Use alternative repository: `FRG_URL=your-mirror-url ./tools/build_fortui.sh build`
- Default repository: `https://github.com/interkosmos/fortran-raylib.git`
- GUI will be disabled if this dependency fails

### Cache Issues

**Stale dependencies**:
```bash
# Force rebuild regardless of cache state
FORCE_REBUILD=1 ./tools/build_fortui.sh build

# Or clean cache and rebuild
./tools/build_fortui.sh clean && ./tools/build_fortui.sh build
```

**Permission issues**:
```bash
# Use custom cache location
GUI_CACHE=/tmp/fortui_cache ./tools/build_fortui.sh build
```

**Cache corruption**:
```bash
# View cache status to identify corruption
./tools/build_fortui.sh status

# Automatic recovery (built-in)
./tools/build_fortui.sh build  # Will detect and repair corruption

# Manual recovery if needed
./tools/build_fortui.sh clean && FORCE_REBUILD=1 ./tools/build_fortui.sh build
```

### Dependency Compatibility Issues

**Raylib/fortran-raylib version conflicts**:
```bash
# Check compatibility automatically during build
./tools/build_fortui.sh build  # Warns about incompatible versions

# Force specific versions if needed
FRG_REF=v1.0.0 ./tools/build_fortui.sh build
```

### Network Issues

**Connection failures**:
```bash
# Enable debug mode to see retry attempts
DEBUG=1 ./tools/build_fortui.sh build

# Work offline with existing cache
OFFLINE_MODE=1 ./tools/build_fortui.sh build
```

**Corporate firewalls**:
```bash
# Use alternative repository URLs
FRG_URL=https://internal-mirror/fortran-raylib.git ./tools/build_fortui.sh build
TERMBOX_URL=https://internal-mirror/termbox2.git ./tools/build_fortui.sh build
```

### Concurrent Build Issues

**Build lock timeouts**:
```bash
# Check for stale lock files (auto-removed after 5 minutes)
ls ~/.cache/fortui/.build.lock

# Use separate cache for parallel CI builds
GUI_CACHE=/tmp/fortui_$BUILD_ID ./tools/build_fortui.sh build
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

### Performance Optimization

```bash
# Force rebuild for performance testing
FORCE_REBUILD=1 time ./tools/build_fortui.sh build

# Monitor cache size growth
./tools/build_fortui.sh status

# Offline builds for CI/CD speed
# (Download dependencies once, then use offline mode)
./tools/build_fortui.sh build        # Initial download
OFFLINE_MODE=1 ./tools/build_fortui.sh build  # Fast offline rebuild
```

### Enterprise/CI Configuration

```bash
# Separate cache per build to prevent conflicts
export GUI_CACHE="/tmp/fortui_cache_${BUILD_NUMBER}"

# Network-resilient builds with retry
DEBUG=1 ./tools/build_fortui.sh build

# Fail-safe offline mode for air-gapped environments
OFFLINE_MODE=1 DISABLE_GUI=1 ./tools/build_fortui.sh build
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

The advanced build script provides enterprise-grade features:

### Core Capabilities
- **Conditional compilation**: Sets ENABLE_GUI preprocessor flag based on raylib availability
- **Smart caching**: Version-aware cache invalidation using tool fingerprints
- **Platform detection**: Handles Linux/macOS/Windows differences automatically
- **Flexible configuration**: Extensive environment variable control
- **Clean separation**: Dependencies separate from main Fortran compilation
- **FPM integration**: Designed to work alongside FPM without conflicts

### Advanced Implementation Details
- **Network resilience**: Exponential backoff retry for git operations (3 attempts, 1-30s delays)
- **Concurrent safety**: File locking with 5-minute timeout and stale lock detection  
- **Corruption recovery**: Automatic detection and repair of corrupted git repositories
- **Version tracking**: Cache invalidation when build tools (git, make, gfortran, fpm) change
- **Atomic operations**: Safe cache updates using temporary files and atomic moves
- **Dependency compatibility**: Version checking for raylib/fortran-raylib compatibility
- **Cross-platform paths**: Consistent behavior across Windows/Unix systems

Dependencies are built in `${GUI_CACHE}` (default `~/.cache/fortui`) with this structure:
```
~/.cache/fortui/
├── termbox2/           # termbox2 source and built library
├── fortran-raylib/     # fortran-raylib source and built library  
├── termbox2_built      # Build marker for termbox2
├── fortran_raylib_built # Build marker for fortran-raylib
├── .tool_versions      # Tool version fingerprint for cache invalidation
└── .build.lock         # Concurrent access lock (auto-removed)
```

### Cache Management Details
- **Build markers**: Prevent unnecessary rebuilds when dependencies unchanged
- **Version tracking**: `.tool_versions` contains hashes of git, make, gfortran, fpm versions
- **Lock files**: `.build.lock` contains PID for concurrent access safety
- **Atomic updates**: All cache modifications use temporary files for consistency
- **Corruption detection**: Git repository integrity checked on each access