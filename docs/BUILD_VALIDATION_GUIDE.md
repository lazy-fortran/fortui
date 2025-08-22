# Build Validation and Error Handling Guide

This guide covers the robust error handling and validation features built into fortui's build system.

## Overview

Fortui build scripts include comprehensive validation to prevent common build failures and provide helpful error messages when issues occur. All validation happens automatically - no user configuration required.

## Command Validation

### FPM Validation

**What It Validates**: All build scripts check that Fortran Package Manager (FPM) is available before attempting to use it.

**Scripts Protected**:
- `fmp_build.sh` - Validates before `exec fpm`
- `run_fpm.sh` - Validates before `exec fpm`  
- `build.sh` - Validates before `exec fpm build`

**Example Error and Solution**:
```bash
# Running any FPM build script without FMP installed:
./fpm_build.sh

# Error message:
Error: Fortran Package Manager (fpm) (command 'fpm') not found in PATH

Please install FPM: https://github.com/fortran-lang/fpm

Current PATH: /usr/local/bin:/usr/bin:/bin
```

**How to Fix**:
```bash
# Install FPM following official instructions
curl -fsSL https://github.com/fortran-lang/fpm/releases/latest/download/fpm-installer.sh | bash

# Or use package manager (where available)
# Ubuntu/Debian: sudo apt install fpm
# Fedora: sudo dnf install fpm  
# macOS: brew install fortran-lang/tap/fpm

# Verify installation
fpm --version
```

### Path Validation

**What It Validates**: Environment variables containing file paths are checked for safety and validity.

**Example**:
```bash
# Safe path - works normally
RAYLIB_ROOT=/opt/raylib ./tools/build_fortui.sh build

# Unsafe path - automatically rejected  
RAYLIB_ROOT="; rm -rf /" ./tools/build_fortui.sh build
# Error: Path contains unsafe characters: ; rm -rf /
```

## Error Message Improvements

### Before and After Comparison

**Traditional Shell Errors** (what you used to see):
```bash
./fpm_build.sh: line 43: fpm: command not found
bash: exec: fmp: not found
```

**Fortui Validation Errors** (what you see now):
```bash
Error: Fortran Package Manager (fpm) (command 'fpm') not found in PATH

Please install FPM: https://github.com/fortran-lang/fpm

Current PATH: /usr/local/bin:/usr/bin:/bin
```

### Error Message Components

1. **Clear Problem Statement**: What exactly is missing
2. **Installation Instructions**: Direct link to installation guide
3. **Diagnostic Information**: Current PATH for debugging
4. **Proper Exit Codes**: Scripts exit with status 1 for error handling

## Validation Functions Reference

### `validate_command_available`

**Purpose**: Check if command exists in PATH
**Usage**:
```bash
if validate_command_available git; then
    echo "Git is available"
else  
    echo "Git not found"
fi
```

### `require_command`

**Purpose**: Validate command with helpful error message
**Usage**:
```bash
# Basic usage
require_command fpm

# With custom display name
require_command fpm "Fortran Package Manager" 

# With custom installation hint
require_command fpm "Fortran Package Manager" \
    "Install from: https://github.com/fortran-lang/fpm"
```

**Parameters**:
1. `cmd` - Command name to check
2. `display_name` - User-friendly name (optional, defaults to cmd)
3. `install_hint` - Installation instructions (optional)

## Common Error Scenarios

### Scenario 1: FPM Not Installed

**Trigger**: Running any build script when FPM not in PATH
**Error**: 
```
Error: Fortran Package Manager (fpm) (command 'fmp') not found in PATH
```
**Solution**: Install FMP using official instructions

### Scenario 2: FPM in Non-Standard Location

**Trigger**: FPM installed but not in standard PATH
**Error**: Same as Scenario 1
**Solution**:
```bash
# Add FPM directory to PATH
export PATH="/path/to/fpm/bin:$PATH"

# Or create symlink to standard location
sudo ln -s /path/to/fpm/bin/fpm /usr/local/bin/fpm

# Verify
which fpm
fpm --version
```

### Scenario 3: Corrupted FPM Installation

**Trigger**: FPM exists but is not executable
**Error**: Permission denied or execution errors
**Solution**:
```bash
# Check FPM permissions
ls -la $(which fpm)

# Fix permissions if needed
chmod +x $(which fpm)

# Reinstall if corrupted
rm $(which fpm)
# Reinstall using official method
```

### Scenario 4: Missing Build Dependencies

**Trigger**: FPM available but system lacks required tools
**Solution**: The validation system guides you to install missing tools:
```bash
# Example: missing git
Error: Git (command 'git') not found in PATH

Please install Git and ensure it's in your PATH

Current PATH: /usr/local/bin:/usr/bin:/bin
```

## Integration with Build Process

### Build Script Integration

All FPM wrapper scripts follow this pattern:
```bash
#!/bin/bash
source tools/lib/utils.sh

# Build dependencies 
./tools/build_fortui.sh build

# Configure environment
export FPM_FFLAGS="..."
export FPM_LDFLAGS="..."

# Validate before exec - THIS IS THE KEY IMPROVEMENT
require_command fpm "Fortran Package Manager" \
    "Please install FPM: https://github.com/fortran-lang/fpm" || exit 1

# Safe to exec now
exec fpm "$@"
```

### Error Handling Workflow

1. **Early Validation**: Commands validated before environment setup
2. **Helpful Errors**: Clear messages with actionable solutions
3. **Graceful Exit**: Proper exit codes for automation/CI
4. **PATH Diagnosis**: Current PATH shown for debugging

## Benefits for Users

### Development Experience

- **Faster Debugging**: Know immediately what's missing
- **Clear Solutions**: Direct links to installation instructions  
- **No Cryptic Errors**: Understand exactly what went wrong
- **Consistent Behavior**: Same validation across all build scripts

### CI/CD Integration

- **Proper Exit Codes**: Build failures clearly indicated
- **Dependency Checking**: Validate environment before builds
- **Early Failure**: Fail fast when dependencies missing
- **Automation Friendly**: Consistent error messages for parsing

### Security Benefits

- **Input Validation**: Environment variables checked for safety
- **Path Safety**: Prevent shell injection through path variables
- **Controlled Execution**: Commands validated before exec
- **Defensive Programming**: Graceful handling of unexpected inputs

## Advanced Usage

### Custom Validation

Build your own validation using the utility functions:
```bash
# Source the utilities
source tools/lib/utils.sh

# Validate custom tools
require_command make "GNU Make" \
    "Install build-essential package" || exit 1
    
require_command pkg-config "pkg-config" \
    "Install pkg-config package" || exit 1

# Your build logic here
```

### Debugging Validation

Enable debug mode to see validation details:
```bash
DEBUG=1 ./fpm_build.sh
# Shows validation steps and decisions
```

### Testing Validation

The validation system includes comprehensive tests:
```bash
# Run validation tests
./test/test_build_script_validation.sh
./test/test_fpm_validation_scenarios.sh

# Test specific scenarios
./test/test_error_handling.sh
```

## Summary

Fortui's build validation system transforms cryptic shell errors into helpful guidance, making the build process more reliable and user-friendly. The system validates commands before use, provides clear error messages with solutions, and maintains security through input validation.

**Key Improvements**:
- FPM validation before exec in all wrapper scripts
- Helpful error messages with installation links
- PATH diagnosis for debugging
- Graceful error handling with proper exit codes
- Security validation for environment variables

All validation happens automatically - users benefit from improved error messages without any configuration required.