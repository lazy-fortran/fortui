# Build System Integration Examples

Quick examples for integrating fortui's build system into your project.

## Basic Integration

### Simple Build Script
```bash
#!/bin/bash
# your-build.sh

# Build fortui dependencies first
./tools/build_fortui.sh build

# Get compilation flags
FORTUI_CPPFLAGS=$(./tools/build_fortui.sh flags)
FORTUI_LDFLAGS=$(./tools/build_fortui.sh ldflags)

# Build your project with FPM
fpm build --flag "$FORTUI_CPPFLAGS" --link-flag "$FORTUI_LDFLAGS"
```

### Makefile Integration
```makefile
# Makefile

# Get flags from build script
FORTUI_CPPFLAGS := $(shell ./tools/build_fortui.sh flags)
FORTUI_LDFLAGS := $(shell ./tools/build_fortui.sh ldflags)

.PHONY: all deps clean

all: deps
	fpm build --flag "$(FORTUI_CPPFLAGS)" --link-flag "$(FORTUI_LDFLAGS)"

deps:
	./tools/build_fortui.sh build

clean:
	fpm clean
	./tools/build_fortui.sh clean

check-config:
	./tools/build_fortui.sh config
```

## Advanced Integration

### CMake Integration
```cmake
# CMakeLists.txt

# Run fortui build script
execute_process(
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tools/build_fortui.sh build
    RESULT_VARIABLE BUILD_RESULT
)
if(NOT BUILD_RESULT EQUAL 0)
    message(FATAL_ERROR "Fortui dependency build failed")
endif()

# Get compiler flags
execute_process(
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tools/build_fortui.sh flags
    OUTPUT_VARIABLE FORTUI_CPPFLAGS
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

execute_process(
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/tools/build_fortui.sh ldflags  
    OUTPUT_VARIABLE FORTUI_LDFLAGS
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

# Apply to your target
target_compile_definitions(your_target PRIVATE ${FORTUI_CPPFLAGS})
target_link_libraries(your_target ${FORTUI_LDFLAGS})
```

### Meson Integration
```meson
# meson.build

# Run build script
run_command('tools/build_fortui.sh', 'build', check: true)

# Get flags
fortui_cppflags = run_command('tools/build_fortui.sh', 'flags', 
                             capture: true, check: true).stdout().strip()
fortui_ldflags = run_command('tools/build_fortui.sh', 'ldflags',
                            capture: true, check: true).stdout().strip()

# Use in your project
your_exe = executable('your_program',
  sources: ['src/main.f90'],
  fortran_args: [fortui_cppflags],
  link_args: [fortui_ldflags]
)
```

## CI/CD Examples

### GitHub Actions
```yaml
# .github/workflows/build.yml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    
    strategy:
      matrix:
        backend: [full, tui-only]
        
    steps:
    - uses: actions/checkout@v3
    
    - name: Install dependencies
      run: |
        sudo apt-get update
        sudo apt-get install -y gfortran pkg-config
        # Install raylib for GUI backend
        if [ "${{ matrix.backend }}" = "full" ]; then
          sudo apt-get install -y libraylib-dev
        fi
    
    - name: Configure backend
      run: |
        if [ "${{ matrix.backend }}" = "tui-only" ]; then
          echo "DISABLE_GUI=1" >> $GITHUB_ENV
        fi
    
    - name: Build fortui dependencies
      run: ./tools/build_fortui.sh build
      
    - name: Check configuration
      run: ./tools/build_fortui.sh config
    
    - name: Build project
      run: fpm build
      
    - name: Run tests
      run: fpm test
```

### GitLab CI
```yaml
# .gitlab-ci.yml
stages:
  - build
  - test

variables:
  GIT_SUBMODULE_STRATEGY: recursive

build:
  stage: build
  image: gcc:latest
  before_script:
    - apt-get update -qq && apt-get install -y -qq pkg-config libraylib-dev
  script:
    - ./tools/build_fortui.sh build  
    - fpm build
  artifacts:
    paths:
      - build/
    expire_in: 1 hour

test:
  stage: test
  image: gcc:latest
  dependencies:
    - build
  script:
    - fpm test
```

## Environment-Specific Builds

### Development vs Production
```bash
# development.sh - Quick builds with debug
DEBUG=1 ./tools/build_fortui.sh build
fpm build --profile debug

# production.sh - Optimized builds
./tools/build_fortui.sh build  
fpm build --profile release
```

### Multi-Configuration Builds
```bash
# build-all.sh - Build multiple configurations

configs=(
    "DISABLE_GUI=0"  # Full GUI+TUI
    "DISABLE_GUI=1"  # TUI-only
)

for config in "${configs[@]}"; do
    echo "Building with: $config"
    
    # Clean previous build
    ./tools/build_fortui.sh clean
    
    # Build with config
    env $config ./tools/build_fortui.sh build
    
    # Build and test
    fpm build --profile release
    fpm test
    
    # Archive result
    tar czf "fortui-${config// /-}.tar.gz" build/
done
```

## Custom Dependency Locations

### Using Custom raylib
```bash
# Build script with custom raylib location
export RAYLIB_ROOT=/opt/raylib-5.0
./tools/build_fortui.sh config  # Verify detection
./tools/build_fortui.sh build   # Build with custom raylib
```

### Development Dependencies
```bash
# Use development versions of dependencies
export FRG_URL=https://github.com/yourname/fortran-raygui.git
export FRG_REF=development
export TERMBOX_URL=https://github.com/yourname/termbox2.git
export TERMBOX_REF=feature-branch

./tools/build_fortui.sh clean
./tools/build_fortui.sh build
```

## Troubleshooting Integration

### Debug Build Issues
```bash
# Enable debug output for troubleshooting
DEBUG=1 ./tools/build_fortui.sh build

# Check what flags would be generated
./tools/build_fortui.sh config
./tools/build_fortui.sh flags
./tools/build_fortui.sh ldflags

# Verify dependencies are built correctly
ls -la ~/.cache/fortui/
```

### Containerized Builds
```dockerfile
# Dockerfile
FROM gcc:latest

RUN apt-get update && apt-get install -y \
    pkg-config \
    libraylib-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .

# Build dependencies
RUN ./tools/build_fortui.sh build

# Build project  
RUN fpm build

CMD ["./build/app"]
```

All examples assume you've copied `tools/build_fortui.sh` to your project or are building fortui itself.