# fortui — design doc (v0.6.0)

## Goal
Declarative UI for modern Fortran, one codebase, two backends:
- **TUI**: termbox2 (event-driven, diffed output) - **ALWAYS AVAILABLE**
- **GUI**: raygui/raylib (vsynced, target FPS) - **CONDITIONAL ENHANCEMENT**

Monospace-first for exact TUI/GUI parity. Proportional text is a future opt-in.

## Build System Architecture

### Single Package Design
- One `fortui` package (no submodules or package splits)
- Custom build script `tools/build_fortui.sh` orchestrates dependency management
- FPM integration with build-script override and CPP preprocessing support
- **Fail-safe guarantee**: TUI backend always builds, GUI only when dependencies available
- **Zero external dependencies in repo**: All dependencies fetched and cached locally

### Dependency Management Strategy

#### TUI Backend Dependencies (Always Required)
- **termbox2**: Clone from `github.com/termbox/termbox2` on demand
- **Build process**: Compile `termbox2.h` to static library
- **Cache location**: `${GUI_CACHE:-$HOME/.cache/fortui}/termbox2/`
- **Version pinning**: Use specific commit SHA for reproducible builds
- **Cross-platform**: Linux first, extensible to macOS/Windows

#### GUI Backend Dependencies (Conditional)
- **Primary**: `lazy-fortran/fortran-raygui` Fortran bindings
- **System raylib**: Detect via pkg-config or RAYLIB_ROOT environment
- **Build process**: Clone fortran-raygui only when raylib available
- **Cache location**: `${GUI_CACHE:-$HOME/.cache/fortui}/fortran-raygui/`
- **Graceful degradation**: Missing raylib → TUI-only build (no failure)

#### Detection and Probing System
```bash
# Multi-method raylib detection (ordered by reliability):
1. pkg-config --exists raylib && pkg-config --cflags --libs raylib
2. RAYLIB_ROOT environment variable with lib/include validation
3. Standard system paths (/usr/local, /usr, /opt/raylib)
4. Homebrew paths (macOS: /opt/homebrew, /usr/local)
5. Development builds (./raylib, ../raylib relative to project)

# Headless environment detection:
- Check DISPLAY, WAYLAND_DISPLAY environment variables
- Probe for X11/Wayland libraries at runtime
- Fallback to TUI when GUI not possible
```

### Developer Control Interface

#### Environment Variables
```bash
# Force text-only build (skip GUI entirely)
DISABLE_GUI=1 fpm build

# Use prebuilt raylib installation
RAYLIB_ROOT=/usr/local fpm build

# Override fortran-raygui source and branch
FRG_URL=https://github.com/user/fork.git FRG_REF=feature-branch fpm build

# Control dependency cache location
GUI_CACHE=/tmp/fortui_deps fpm build

# Force dependency refresh (ignore cached builds)
FORCE_REBUILD=1 fpm build

# Verbose build output for debugging
FORTUI_VERBOSE=1 fpm build
```

#### Build Script Integration
- **FPM override**: `build-script = "tools/build_fortui.sh"`
- **CPP preprocessing**: `preprocess.cpp.suffixes = ["F90", "f90"]`
- **Conditional sources**: Backend files included based on available dependencies
- **Library linking**: Dynamic link flags set by build script

### Conditional Compilation Architecture

#### CPP Macro Strategy
```fortran
! Core compilation flags set by build system:
#ifdef ENABLE_GUI
  ! GUI backend implementation
  use raygui_bindings
#endif

#ifdef ENABLE_TUI  
  ! TUI backend implementation (always enabled)
  use termbox2_bindings
#endif

! Runtime backend selection:
#if defined(ENABLE_GUI) && defined(ENABLE_TUI)
  ! Dual backend support - runtime selection
#elif defined(ENABLE_TUI)
  ! TUI-only build
#else
  #error "At least TUI backend must be available"
#endif
```

#### Source File Organization
```
src/
├── fortui_core.f90          ! Always compiled
├── fortui_widgets.f90       ! Always compiled  
├── fortui_units.f90         ! Always compiled
├── backends/
│   ├── tui/
│   │   ├── tui_backend.F90      ! CPP: #ifdef ENABLE_TUI
│   │   └── termbox2_c.f90       ! Interface to termbox2 C library
│   └── gui/
│       ├── gui_backend.F90      ! CPP: #ifdef ENABLE_GUI  
│       └── raygui_interface.f90 ! Interface to fortran-raygui
└── fortui_runtime.F90       ! CPP: Backend selection logic
```

### Build Process Flow

#### Phase 1: Environment Assessment
```bash
# 1. Detect build environment and set baseline flags
export ENABLE_TUI=1  # Always available

# 2. Probe for GUI dependencies
if probe_raylib_installation; then
    if [ "$DISABLE_GUI" != "1" ]; then
        export ENABLE_GUI=1
        log "GUI backend: Enabled (raylib found)"
    else
        log "GUI backend: Disabled (DISABLE_GUI=1)"
    fi
else
    log "GUI backend: Unavailable (raylib not found)"
fi
```

#### Phase 2: Dependency Resolution
```bash
# 1. Ensure TUI dependencies (termbox2)
fetch_and_build_termbox2() {
    local cache_dir="${GUI_CACHE:-$HOME/.cache/fortui}/termbox2"
    local commit_sha="v2.0.0"  # Pin to stable release
    
    if needs_rebuild "$cache_dir" "$commit_sha"; then
        git clone https://github.com/termbox/termbox2.git "$cache_dir"
        cd "$cache_dir" && git checkout "$commit_sha"
        make clean && make
    fi
    
    export TB2_INCLUDE="$cache_dir"
    export TB2_LIB="$cache_dir/libtermbox2.a"
}

# 2. Fetch GUI dependencies if enabled
fetch_and_build_gui_deps() {
    if [ "$ENABLE_GUI" = "1" ]; then
        local cache_dir="${GUI_CACHE:-$HOME/.cache/fortui}/fortran-raygui"
        local repo_url="${FRG_URL:-https://github.com/lazy-fortran/fortran-raygui.git}"
        local ref="${FRG_REF:-main}"
        
        if needs_rebuild "$cache_dir" "$ref"; then
            git clone "$repo_url" "$cache_dir"
            cd "$cache_dir" && git checkout "$ref"
            # Build fortran-raygui against system raylib
            make clean && make RAYLIB_ROOT="$RAYLIB_ROOT"
        fi
        
        export FRG_INCLUDE="$cache_dir/include"
        export FRG_LIB="$cache_dir/lib"
    fi
}
```

#### Phase 3: FPM Configuration Generation
```bash
# Generate dynamic fmp.toml additions based on available backends
generate_fmp_config() {
    cat > fpm_backend.toml <<EOF
[preprocess]
[preprocess.cpp]
suffixes = ["F90", "f90"]
directories = ["src"]

[build]
preprocessor = "cpp"
link = [$(generate_link_flags)]

[dependencies]
$(generate_dependencies)
EOF
}

generate_link_flags() {
    local flags=""
    
    # TUI backend (always available)
    flags="\"$TB2_LIB\""
    
    # GUI backend (conditional)
    if [ "$ENABLE_GUI" = "1" ]; then
        flags="$flags, \"$FRG_LIB/libfortran-raygui.a\""
        flags="$flags, $(pkg-config --libs raylib)"
    fi
    
    echo "$flags"
}
```

#### Phase 4: Compilation with Backend Selection
```bash
# Set CPP flags for conditional compilation
export FFLAGS="${FFLAGS:-} -DENABLE_TUI"
if [ "$ENABLE_GUI" = "1" ]; then
    export FFLAGS="$FFLAGS -DENABLE_GUI"
fi

# Add include paths for C libraries
export FFLAGS="$FFLAGS -I$TB2_INCLUDE"
if [ "$ENABLE_GUI" = "1" ]; then
    export FFLAGS="$FFLAGS -I$FRG_INCLUDE"
fi

# Execute FPM build with dynamic configuration
fpm build --flag "$FFLAGS"
```

### Cache Management and Performance

#### Intelligent Caching Strategy
```bash
# Cache invalidation triggers:
needs_rebuild() {
    local cache_dir="$1"
    local expected_ref="$2"
    
    # Missing cache directory
    [ ! -d "$cache_dir" ] && return 0
    
    # Force rebuild requested
    [ "$FORCE_REBUILD" = "1" ] && return 0
    
    # Different commit/ref than cached
    local current_ref=$(cd "$cache_dir" && git rev-parse HEAD)
    [ "$current_ref" != "$(resolve_ref $expected_ref)" ] && return 0
    
    # Missing built artifacts
    [ ! -f "$cache_dir/libtermbox2.a" ] && return 0  # TUI
    [ "$ENABLE_GUI" = "1" ] && [ ! -f "$cache_dir/lib/libfortran-raygui.a" ] && return 0
    
    return 1  # Cache is valid
}

# Parallel dependency building
build_dependencies_parallel() {
    fetch_and_build_termbox2 &
    local tb2_pid=$!
    
    if [ "$ENABLE_GUI" = "1" ]; then
        fetch_and_build_gui_deps &
        local gui_pid=$!
        wait $gui_pid
    fi
    
    wait $tb2_pid
}
```

#### Cross-Platform Considerations
```bash
# Platform-specific adaptations
detect_platform() {
    case "$(uname -s)" in
        Linux*)   PLATFORM=linux;;
        Darwin*)  PLATFORM=macos;;
        CYGWIN*)  PLATFORM=windows;;
        MINGW*)   PLATFORM=windows;;
        *)        PLATFORM=unknown;;
    esac
    export PLATFORM
}

# Platform-specific raylib detection
probe_raylib_macos() {
    # Check Homebrew installations
    for prefix in /opt/homebrew /usr/local; do
        if [ -f "$prefix/lib/libraylib.a" ] && [ -f "$prefix/include/raylib.h" ]; then
            export RAYLIB_ROOT="$prefix"
            return 0
        fi
    done
    return 1
}

probe_raylib_linux() {
    # Check pkg-config first (most reliable)
    if pkg-config --exists raylib 2>/dev/null; then
        export RAYLIB_CFLAGS="$(pkg-config --cflags raylib)"
        export RAYLIB_LIBS="$(pkg-config --libs raylib)"
        return 0
    fi
    
    # Check standard system paths
    for prefix in /usr/local /usr /opt/raylib; do
        if [ -f "$prefix/lib/libraylib.so" ] && [ -f "$prefix/include/raylib.h" ]; then
            export RAYLIB_ROOT="$prefix"
            return 0
        fi
    done
    return 1
}
```

### Error Handling and Robustness

#### Build Failure Recovery
```bash
# Graceful degradation strategy
handle_build_failure() {
    local component="$1"
    local error_code="$2"
    
    case "$component" in
        "termbox2")
            echo "FATAL: TUI backend required but termbox2 build failed"
            echo "Try: FORCE_REBUILD=1 fpm build"
            exit 1
            ;;
        "fortran-raygui"|"raylib")
            echo "WARNING: GUI backend disabled due to build failure"
            echo "Continuing with TUI-only build..."
            export ENABLE_GUI=0
            ;;
    esac
}

# Network failure handling
fetch_with_retry() {
    local url="$1"
    local dest="$2"
    local attempts=3
    
    for i in $(seq 1 $attempts); do
        if git clone "$url" "$dest"; then
            return 0
        else
            echo "Fetch attempt $i/$attempts failed, retrying..."
            rm -rf "$dest"
            sleep $((i * 2))  # Exponential backoff
        fi
    done
    
    echo "ERROR: Failed to fetch $url after $attempts attempts"
    return 1
}
```

### Success Criteria and Validation

#### Build System Validation Tests
```bash
# Automated test scenarios:
test_tui_only_build() {
    DISABLE_GUI=1 fpm build
    [ $? -eq 0 ] || fail "TUI-only build failed"
    
    # Verify no GUI symbols in binary
    ! objdump -t build/fortui | grep -q "gui_" || fail "GUI symbols in TUI-only build"
}

test_dual_backend_build() {
    fpm build
    [ $? -eq 0 ] || fail "Dual backend build failed"
    
    # Verify both backends available
    objdump -t build/fortui | grep -q "tui_" || fail "Missing TUI symbols"
    objdump -t build/fortui | grep -q "gui_" || fail "Missing GUI symbols"
}

test_cache_persistence() {
    fpm build  # First build
    local cache_mtime=$(stat -c %Y "$HOME/.cache/fortui/termbox2/libtermbox2.a")
    
    fmp build  # Second build
    local new_mtime=$(stat -c %Y "$HOME/.cache/fortui/termbox2/libtermbox2.a")
    
    [ "$cache_mtime" -eq "$new_mtime" ] || fail "Cache not reused"
}

test_environment_controls() {
    RAYLIB_ROOT=/nonexistent fpm build
    [ $? -eq 0 ] || fail "Build failed with invalid RAYLIB_ROOT"
    
    FRG_URL=https://github.com/invalid/repo.git fpm build
    [ $? -eq 0 ] || fail "Build failed with invalid FRG_URL"
}
```

### Implementation Priority and MVP Strategy

#### Phase 1: Core Build Infrastructure (Critical MVP)
1. **Create `tools/build_fortui.sh`** with basic dependency management
2. **Update `fpm.toml`** with build-script override and CPP preprocessing
3. **Implement termbox2 fetching and building** (TUI backend requirement)
4. **Basic raylib detection** (pkg-config and RAYLIB_ROOT support)
5. **CPP conditional compilation** for TUI/GUI separation

#### Phase 2: Robustness and Developer Experience
1. **Advanced raylib detection** (multiple search paths, platform-specific)
2. **fortran-raygui integration** with caching and version control
3. **Comprehensive error handling** and graceful degradation
4. **Environment variable controls** for developer workflow
5. **Build system validation tests**

#### Phase 3: Optimization and Polish
1. **Parallel dependency building** for faster build times
2. **Intelligent cache invalidation** and management
3. **Cross-platform adaptation** (macOS, Windows support)
4. **Build performance profiling** and optimization
5. **Advanced developer debugging** tools

This architecture ensures that fortui never fails to build while providing powerful conditional compilation and dependency management capabilities. The TUI backend serves as the robust foundation, with GUI enhancements layered on top when system capabilities allow.

⸻

## UI Context Integration with Backend Measurement

### Overview

The UI context system provides runtime measurement and conversion between unit types and backend-specific coordinates. This architecture integrates with the abstract type system from Issue #21 to enable context-aware unit conversion during initialization and runtime updates.

**Core Principle**: Abstract type integration with backend-specific measurement for optimal cross-platform unit handling and context-aware rendering.

### Context Architecture Design

#### Abstract Type Integration Framework
```fortran
! Enhanced ui_init with abstract unit type support
subroutine ui_init(backend, width, height, title, target_fps, vsync)
  character(*), intent(in) :: backend
  class(unit_type), intent(in) :: width, height    ! Abstract unit interface
  character(*), intent(in) :: title
  integer, intent(in), optional :: target_fps
  logical, intent(in), optional :: vsync
  
  type(ui_context) :: ctx
  real :: width_dp, height_dp
  
  ! Initialize context based on backend
  select case(backend)
    case("tui")
      call setup_tui_context(ctx)
    case("gui") 
      call setup_gui_context(ctx)
  end select
  
  ! Store context globally for API access
  call ui_set_context(ctx)
  
  ! Convert window dimensions using abstract interface
  width_dp = width%to_dp(ctx)    ! Abstract interface call
  height_dp = height%to_dp(ctx)  ! Abstract interface call
  
  ! Initialize backend with dp dimensions
  call init_backend(backend, width_dp, height_dp, ctx)
end subroutine
```

#### Backend-Specific Context Setup

**TUI Context Initialization**:
```fortran
subroutine setup_tui_context(ctx)
  type(ui_context), intent(out) :: ctx
  
  ! Measure terminal cell dimensions in dp equivalents
  call measure_terminal_cells(ctx%cell_w_dp, ctx%cell_h_dp)
  
  ! TUI-specific defaults
  ctx%dpi_scale = 1.0       ! No DPI scaling in terminal
  ctx%em_dp = ctx%cell_h_dp * 0.8  ! Approximate font size from cell height
  ctx%text_scale = 1.0      ! No accessibility scaling in terminal
end subroutine
```

**GUI Context Initialization**:
```fortran
subroutine setup_gui_context(ctx)
  type(ui_context), intent(out) :: ctx
  
  ! Detect system settings via platform-specific APIs
  call detect_system_dpi(ctx%dpi_scale)
  call measure_font_metrics(ctx%em_dp)
  call detect_text_scaling(ctx%text_scale)
  
  ! Calculate equivalent cell sizes for TUI compatibility
  ctx%cell_w_dp = ctx%em_dp * 0.6  ! Monospace width ratio
  ctx%cell_h_dp = ctx%em_dp * 1.2  ! Line height ratio
end subroutine
```

### Cross-Platform Measurement Routines

#### Terminal Cell Measurement (TUI)
```fortran
subroutine measure_terminal_cells(cell_w_dp, cell_h_dp)
  real, intent(out) :: cell_w_dp, cell_h_dp
  
  ! Platform-specific terminal measurement strategies:
  ! 1. Query terminal for cell pixel dimensions via escape sequences
  ! 2. Use terminfo/termcap database queries where available
  ! 3. Fallback to conservative defaults for unknown terminals
  
  ! Implementation: termbox2 integration for precise cell measurements
  call tb_query_cell_size(cell_w_dp, cell_h_dp)
  
  ! Sanity check and fallback
  if (cell_w_dp <= 0.0 .or. cell_h_dp <= 0.0) then
    cell_w_dp = 8.0   ! Default monospace character width
    cell_h_dp = 16.0  ! Default line height
  end if
end subroutine
```

#### System DPI Detection (GUI)
```fortran
subroutine detect_system_dpi(dpi_scale)
  real, intent(out) :: dpi_scale
  
  ! Platform-specific DPI detection
  dpi_scale = 1.0  ! Default for 96 DPI baseline
  
#ifdef __linux__
  ! Linux: X11/Wayland DPI queries
  call linux_detect_dpi(dpi_scale)
#elif defined(_WIN32)
  ! Windows: GetDpiForWindow API
  call windows_detect_dpi(dpi_scale)
#elif defined(__APPLE__)
  ! macOS: NSScreen backingScaleFactor
  call macos_detect_dpi(dpi_scale)
#endif
end subroutine

! Platform-specific implementations
#ifdef __linux__
subroutine linux_detect_dpi(dpi_scale)
  real, intent(out) :: dpi_scale
  ! Implementation: X11 XDisplayWidth/XDisplayWidthMM ratio
  ! Or Wayland wl_output logical_size/physical_size
  dpi_scale = query_x11_dpi_scale()
end subroutine
#endif
```

#### Font Metrics Measurement (GUI)
```fortran
subroutine measure_font_metrics(em_dp)
  real, intent(out) :: em_dp
  
  ! Measure actual font metrics in current rendering context
  ! Use raylib/raygui font measurement functions for precision
  em_dp = measure_default_font_em()
  
  ! Sanity check and fallback
  if (em_dp <= 0.0) then
    em_dp = 16.0  ! Default reasonable base font size
  end if
end subroutine

real function measure_default_font_em() result(em_size)
  ! Integration with raylib font measurement
  ! MeasureTextEx() with default font and size
  em_size = real(MeasureText("M", default_font_size))
end function
```

#### Accessibility Text Scaling Detection
```fortran
subroutine detect_text_scaling(text_scale)
  real, intent(out) :: text_scale
  
  ! Query system accessibility settings
  text_scale = 1.0  ! Default no scaling
  
#ifdef __linux__
  ! Linux: gsettings text-scaling-factor
  call linux_detect_text_scaling(text_scale)
#elif defined(_WIN32)
  ! Windows: SystemParametersInfo for font scaling
  call windows_detect_text_scaling(text_scale)
#elif defined(__APPLE__)
  ! macOS: NSUserDefaults preferredContentSizeCategory
  call macos_detect_text_scaling(text_scale)
#endif
end subroutine
```

### Context-Aware Rendering Integration

#### TUI Rendering with Context
```fortran
subroutine render_tui_element(x_dp, y_dp, w_dp, h_dp, ctx)
  real, intent(in) :: x_dp, y_dp, w_dp, h_dp
  type(ui_context), intent(in) :: ctx
  
  ! Convert dp coordinates to cell positions with snapping
  integer :: x_cells, y_cells, w_cells, h_cells
  
  x_cells = nint(x_dp / ctx%cell_w_dp)
  y_cells = nint(y_dp / ctx%cell_h_dp)
  w_cells = max(1, nint(w_dp / ctx%cell_w_dp))
  h_cells = max(1, nint(h_dp / ctx%cell_h_dp))
  
  ! Render using termbox2 with cell coordinates
  call tb_render_rect(x_cells, y_cells, w_cells, h_cells)
end subroutine
```

#### GUI Rendering with Context
```fortran
subroutine render_gui_element(x_dp, y_dp, w_dp, h_dp, ctx)
  real, intent(in) :: x_dp, y_dp, w_dp, h_dp
  type(ui_context), intent(in) :: ctx
  
  ! Convert dp coordinates to pixel positions (subpixel precision)
  real :: x_pixels, y_pixels, w_pixels, h_pixels
  
  x_pixels = x_dp * ctx%dpi_scale
  y_pixels = y_dp * ctx%dpi_scale
  w_pixels = w_dp * ctx%dpi_scale
  h_pixels = h_dp * ctx%dpi_scale
  
  ! Render using raylib with precise pixel coordinates
  call DrawRectangle(int(x_pixels), int(y_pixels), &
                     int(w_pixels), int(h_pixels), color)
end subroutine
```

### Abstract Type System Integration

#### Enhanced Unit Processing with Context
```fortran
! Helper function for converting any abstract unit to dp with context
real function unit_to_dp_with_context(unit_arg) result(dp_value)
  class(unit_type), intent(in) :: unit_arg
  type(ui_context) :: ctx
  
  call ui_get_context(ctx)
  dp_value = unit_arg%to_dp(ctx)  ! Abstract interface call
end function

! Widget integration example with abstract unit handling
subroutine process_widget_size(width_arg, height_arg, w_dp, h_dp)
  class(unit_type), intent(in), optional :: width_arg, height_arg
  real, intent(out) :: w_dp, h_dp
  type(ui_context) :: ctx
  
  call ui_get_context(ctx)
  
  if (present(width_arg)) then
    w_dp = width_arg%to_dp(ctx)   ! Abstract interface conversion
  else
    w_dp = auto_width(ctx)        ! Context-aware default
  end if
  
  if (present(height_arg)) then
    h_dp = height_arg%to_dp(ctx)  ! Abstract interface conversion
  else
    h_dp = auto_height(ctx)       ! Context-aware default
  end if
end subroutine
```

### Context Lifecycle Management

#### Runtime Context Updates
```fortran
! Support for runtime context updates (DPI changes, accessibility changes)
subroutine ui_update_context(new_ctx)
  type(ui_context), intent(in) :: new_ctx
  call ui_set_context(new_ctx)
  
  ! Trigger layout recalculation for affected widgets
  call invalidate_widget_layouts()
end subroutine

! Event-driven context updates
subroutine handle_system_dpi_change()
  type(ui_context) :: ctx
  call ui_get_context(ctx)
  call detect_system_dpi(ctx%dpi_scale)  ! Re-measure DPI
  call ui_update_context(ctx)
end subroutine
```

#### Context Validation and Error Handling
```fortran
subroutine validate_context(ctx, is_valid)
  type(ui_context), intent(in) :: ctx
  logical, intent(out) :: is_valid
  
  is_valid = .true.
  
  ! Sanity check context values
  if (ctx%dpi_scale <= 0.0 .or. ctx%dpi_scale > 10.0) is_valid = .false.
  if (ctx%em_dp <= 0.0 .or. ctx%em_dp > 200.0) is_valid = .false.
  if (ctx%text_scale <= 0.0 .or. ctx%text_scale > 5.0) is_valid = .false.
  if (ctx%cell_w_dp <= 0.0 .or. ctx%cell_h_dp <= 0.0) is_valid = .false.
  
  if (.not. is_valid) then
    ! Log warning and apply fallback context
    call apply_fallback_context()
  end if
end subroutine
```

### Implementation Architecture

#### File Organization
```
src/
├── fortui_core.f90           ! ui_init integration with abstract types
├── fortui_context.f90        ! Context lifecycle and measurement
├── fortui_units.f90          ! Abstract unit type interfaces  
├── backends/
│   ├── tui/
│   │   ├── tui_context.f90       ! TUI-specific context setup
│   │   └── tui_measurement.f90   ! Terminal cell measurement
│   └── gui/
│       ├── gui_context.f90       ! GUI-specific context setup
│       └── gui_measurement.f90   ! DPI and font measurement
└── platform/
    ├── linux_measurement.f90     ! Linux-specific DPI/accessibility
    ├── windows_measurement.f90   ! Windows-specific APIs
    └── macos_measurement.f90     ! macOS-specific APIs
```

#### Key Integration Points

**1. ui_init() Enhancement**:
- Accept `class(unit_type)` for width/height parameters
- Automatic context setup based on backend selection
- Abstract interface calls for unit conversion
- Context validation and fallback handling

**2. Backend Integration**:
- TUI backend: Terminal cell measurement via termbox2
- GUI backend: System DPI and font metric detection via raylib
- Cross-platform measurement abstraction

**3. Runtime Adaptability**:
- Context update mechanism for DPI changes
- Event-driven accessibility setting updates
- Layout invalidation and recalculation

**4. Performance Optimization**:
- Context caching to minimize repeated measurements
- Lazy evaluation of expensive platform queries
- Minimal conversion overhead for frequent operations

### Advanced Features

#### Multi-Monitor DPI Awareness
```fortran
! Per-monitor DPI handling for multi-display setups
type :: monitor_context
  integer :: monitor_id
  real :: dpi_scale
  real :: physical_width_mm, physical_height_mm
end type

subroutine detect_monitor_contexts(contexts)
  type(monitor_context), allocatable, intent(out) :: contexts(:)
  ! Platform-specific multi-monitor detection
end subroutine
```

#### Dynamic Context Switching
```fortran
! Handle window movement between monitors with different DPI
subroutine update_context_for_monitor(monitor_id)
  integer, intent(in) :: monitor_id
  type(ui_context) :: ctx
  
  call ui_get_context(ctx)
  call get_monitor_dpi_scale(monitor_id, ctx%dpi_scale)
  call ui_update_context(ctx)
end subroutine
```

### Testing and Validation Strategy

#### Unit Testing
- **Context initialization**: Validate context setup for both backends
- **Measurement accuracy**: Test platform-specific measurement routines
- **Abstract type integration**: Verify unit conversion via abstract interface
- **Error handling**: Test graceful fallback when measurements fail

#### Integration Testing
- **Cross-backend consistency**: Ensure equivalent visual results
- **Runtime updates**: Test DPI change and accessibility updates
- **Performance validation**: Verify conversion overhead acceptable
- **Platform compatibility**: Test on Linux, Windows, macOS

### Success Criteria

**Core Functionality**:
- [ ] Context automatically initialized during ui_init() for both backends
- [ ] Abstract type integration: ui_init accepts `class(unit_type)` parameters
- [ ] TUI cell measurements produce accurate cell-to-dp conversion ratios
- [ ] GUI DPI detection works correctly on high-DPI displays
- [ ] Font metrics measurement produces correct em_dp values
- [ ] Accessibility text scaling integrated correctly

**Cross-Platform Support**:
- [ ] Platform-specific measurement routines implemented (Linux/Windows/macOS)
- [ ] Fallback defaults work when measurements unavailable
- [ ] Context validation prevents invalid measurement values

**Performance and Reliability**:
- [ ] Context-aware rendering produces consistent visual results
- [ ] Context update mechanism functional for runtime changes
- [ ] Performance acceptable for frequent unit conversions
- [ ] Memory usage optimized for context storage and caching

**Abstract Type System**:
- [ ] **NO class(*) usage** - only abstract `unit_type` interface
- [ ] Abstract interface calls work correctly throughout codebase
- [ ] Type safety maintained with abstract unit type system
- [ ] Conversion accuracy validated across all unit types

### Dependencies and Blocking Issues

**Requires**:
- **Issue #21**: Units system with abstract types (CRITICAL dependency)
- **Issue #1**: Core types and ui_context definition
- **Issue #2**: Lifecycle functions (ui_init, ui_get_context, ui_set_context)

**Blocked by**:
- **Issue #6**: TUI backend for terminal measurement integration
- **Issue #11**: GUI backend for raylib measurement integration

**Enables**:
- **Issue #3**: Layout constructors with proper unit conversion
- **Issues #4-9**: All widgets with context-aware unit handling
- Future canvas and advanced rendering features

**Priority**: **CRITICAL** - Required for functional abstract unit system and cross-platform consistency.

⸻

## Viewport Widget Architecture (Issue #9)

### Overview

Implement viewport widget with unified class(*) interface for pan/zoom functionality with cross-backend rendering support, providing immediate-mode view updates and consistent interaction behavior. The viewport widget is a essential component for data visualization and interactive content.

### Core Design Principles

**Unified Interface**: Single viewport() function accepting class(*) dimensions for maximum API simplicity and consistency with other widgets.

**Required Dimensions**: Width and height must be specified (no auto-sizing) to ensure deterministic viewport behavior.

**View State Management**: Direct update of view parameter during interaction with frame-based change detection.

**Cross-Backend Parity**: Consistent viewport behavior in TUI (cell-based) and GUI (pixel-based) with appropriate rendering strategies.

### API Design

#### Viewport Function Signature
```fortran
logical function viewport(id, width, height, view)
  character(*), intent(in) :: id
  class(*), intent(in) :: width, height     ! any unit type or real
  type(view), intent(inout) :: view         ! wheel=zoom, drag=pan
  ! returns .true. if view changed this frame
end function
```

#### View Type Definition
```fortran
type :: view
  real :: scale_x = 1.0, scale_y = 1.0  ! zoom factors
  real :: off_x = 0.0, off_y = 0.0      ! pan offsets in view coordinates
end type
```

#### Usage Examples
```fortran
! Simple viewport with cell units (TUI-friendly)
if (viewport("plot", 80.0 .cw., 24.0 .ch., plot_view)) then
  call redraw_plot_content()
end if

! Viewport with dp units (cross-backend)
if (viewport("chart", 400.0, 300.0, chart_view)) then
  call update_chart_display()
end if

! Mixed unit viewport
if (viewport("mini", 20.0 .em., 15.0 .em., mini_view)) then
  call render_minimap()
end if
```

### Implementation Architecture

#### Size Processing with class(*)
```fortran
subroutine process_viewport_size(width_arg, height_arg, ctx, w_dp, h_dp)
  class(*), intent(in) :: width_arg, height_arg
  type(ui_context), intent(in) :: ctx
  real, intent(out) :: w_dp, h_dp
  
  ! Convert to dp using runtime type checking
  w_dp = convert_to_dp(width_arg, ctx)
  h_dp = convert_to_dp(height_arg, ctx)
  
  ! Ensure minimum usable size
  w_dp = max(w_dp, ctx%em_dp * 2.0)  ! Minimum 2em width
  h_dp = max(h_dp, ctx%em_dp * 1.5)  ! Minimum 1.5em height
end subroutine
```

#### Cross-Backend Rendering Strategy

**TUI Implementation (Cell-Based)**:
- Convert dp dimensions to cells with snapping
- Render viewport with ASCII borders
- Handle mouse interaction within cell boundaries
- Character-based content area

**GUI Implementation (Pixel-Based)**:
- Convert dp dimensions to pixels with precision
- Pixel-perfect viewport with hardware clipping
- Smooth pan and zoom with sub-pixel precision
- Hardware-accelerated content transformation

### Interaction Processing

#### Pan Calculation
```fortran
subroutine update_pan(view, mouse_delta_x, mouse_delta_y, viewport_width, viewport_height)
  type(view), intent(inout) :: view
  real, intent(in) :: mouse_delta_x, mouse_delta_y, viewport_width, viewport_height
  
  ! Convert pixel delta to view coordinates
  view%off_x = view%off_x - mouse_delta_x / (viewport_width * view%scale_x)
  view%off_y = view%off_y - mouse_delta_y / (viewport_height * view%scale_y)
end subroutine
```

#### Zoom Calculation (Around Mouse Position)
```fortran
subroutine update_zoom(view, zoom_factor, mouse_x, mouse_y, viewport_width, viewport_height)
  type(view), intent(inout) :: view
  real, intent(in) :: zoom_factor, mouse_x, mouse_y, viewport_width, viewport_height
  
  real :: old_scale_x, old_scale_y, view_x, view_y
  
  old_scale_x = view%scale_x
  old_scale_y = view%scale_y
  
  view%scale_x = view%scale_x * zoom_factor
  view%scale_y = view%scale_y * zoom_factor
  
  ! Adjust offset to zoom around mouse position
  view_x = mouse_x / viewport_width
  view_y = mouse_y / viewport_height
  
  view%off_x = view%off_x + view_x * (1.0/old_scale_x - 1.0/view%scale_x)
  view%off_y = view%off_y + view_y * (1.0/old_scale_y - 1.0/view%scale_y)
end subroutine
```

### Content Integration Framework

**Rendering Hooks**: Framework for user content drawing within viewport
**Coordinate Transformation**: Automatic view-to-screen coordinate mapping
**Content Clipping**: Automatic content bounds management at viewport boundaries
**Performance Optimization**: Efficient redraw and caching strategies for content

### File Organization

```
src/
├── fortui_widgets.f90       ! Viewport implementation with unified interface
├── fortui_units.f90         ! class(*) conversion integration
├── backends/
│   ├── tui/
│   │   └── tui_viewport.f90     ! TUI-specific viewport rendering
│   └── gui/
│       └── gui_viewport.f90     ! GUI-specific viewport rendering
└── viewport/
    ├── viewport_core.f90        ! Core viewport logic and state
    ├── viewport_interaction.f90 ! Pan/zoom interaction processing
    └── viewport_transform.f90   ! Coordinate transformation utilities
```

### Implementation Strategy

1. **Core Viewport Logic**: Implement size processing and state management
2. **TUI Backend Integration**: Cell-based rendering with ASCII borders  
3. **GUI Backend Integration**: Pixel-based rendering with hardware acceleration
4. **Interaction Processing**: Mouse and keyboard pan/zoom support
5. **Content Framework**: Rendering hooks for user content
6. **Performance Optimization**: Efficient update and redraw strategies

### Success Criteria

- [ ] viewport() function accepts class(*) for width/height parameters correctly
- [ ] Required dimensions handled properly (no auto-sizing edge cases)
- [ ] Bare real values treated as dp() correctly in all contexts
- [ ] Runtime unit conversion maintains viewport proportions across backends
- [ ] Pan interaction smooth and responsive in both TUI and GUI
- [ ] Zoom interaction centers correctly around mouse position
- [ ] Keyboard navigation (arrow keys, +/- zoom) functional
- [ ] View state updates trigger correct return value (.true. on change)
- [ ] TUI rendering provides usable content area with clear borders
- [ ] GUI rendering supports hardware-accelerated content transformation
- [ ] Coordinate transformation from view to screen coordinates accurate
- [ ] Content clipping works correctly at viewport boundaries
- [ ] Error handling clear for unsupported dimension types
- [ ] Performance acceptable for real-time pan/zoom operations
- [ ] Visual feedback clear for user interaction and viewport state
- [ ] Client code significantly cleaner than alternative approaches
- [ ] API learning curve minimal for new users

### Dependencies

**Requires**: #1 (Core types), #2 (Lifecycle functions), #3 (Layout), #21 (Units system with class(*)), #22 (Context integration)
**Blocked by**: #6 (TUI backend), #11 (GUI backend) for unit-aware rendering and input
**Enables**: #10 (Demo application with interactive viewports)
**Priority**: **HIGH** - Essential widget for data visualization

⸻

## 1) units system

### unit types & ergonomic api

**Core principle**: One declarative UI works on GUI, Web, and TUI with consistent behavior.

**API Design Philosophy**: Prioritize client code readability and ease of use over pure type safety.

**Default Unit Behavior**: Bare `real` values automatically treated as `.dp.` (density-independent pixels) for maximum convenience - no need to write `.dp.` for basic usage.

```fortran
! Ergonomic unit operators returning class(*) for API simplicity
real :: width, gap, text_size, border, cols, rows

width = 40.0 .dp.      ! density-independent pixels
gap = 2.5 .em.         ! relative to base font size  
text_size = 14.0 .sp.  ! scaled pixels (accessibility)
border = 2.0 .px.      ! physical pixels
cols = 10.0 .cw.       ! cell widths (TUI-friendly)
rows = 3.0 .ch.        ! cell heights (TUI-friendly)

! Bare real values automatically default to .dp. for convenience
width = 40.0           ! equivalent to 40.0 .dp.
gap = 2.5 .em.         ! explicit unit overrides default
border = 320.0         ! equivalent to 320.0 .dp.

! Postfix operators return class(*) for maximum API flexibility
! Runtime type checking handles conversion safety
```

### context-aware conversion

All units normalize to **dp** (density-independent pixels) internally:

```fortran
type :: ui_context
  real :: dpi_scale = 1.0    ! GUI: system DPI scale; TUI: 1.0  
  real :: em_dp = 16.0       ! base font size in dp
  real :: text_scale = 1.0   ! accessibility text scaling
  real :: cell_w_dp = 8.0    ! TUI: cell width in dp
  real :: cell_h_dp = 16.0   ! TUI: cell height in dp
end type
```

**Conversion via runtime type checking**:
- `.dp.` values: direct (base unit)
- `.em.` values: `value * ctx%em_dp` 
- `.sp.` values: `value * ctx%text_scale`
- `.px.` values: `value / ctx%dpi_scale`
- `.cw.` values: `value * ctx%cell_w_dp` (TUI)
- `.ch.` values: `value * ctx%cell_h_dp` (TUI)
- Bare real values: treated as value .dp.

**Internal conversion function**:
```fortran
real function convert_to_dp(unit_value, ctx) result(dp_val)
  class(*), intent(in) :: unit_value
  type(ui_context), intent(in) :: ctx
  ! Runtime type checking determines conversion method
end function
```

### cross-backend placement strategy

**TUI snapping**: Final dp values snap to cell boundaries
```fortran
! 42.7 .dp. with cell_w_dp=8.0 → 5.34 cells → snap to 5 cells
real :: dp_value
dp_value = convert_to_dp(42.7 .dp., ctx)
cell_x = nint(dp_value / ctx%cell_w_dp)
```

**GUI/Web precision**: Subpixel positioning maintained
```fortran  
! 42.7 .dp. with dpi_scale=1.5 → 64.05 pixels (exact)
real :: dp_value
dp_value = convert_to_dp(42.7 .dp., ctx)
pixel_x = dp_value * ctx%dpi_scale
```

### mixed unit arguments

All layout and widget functions accept any unit type via class(*) polymorphism:

```fortran
ui = column(gap=1.0 .ch., children=[ &
       row(gap=2.0 .cw., children=[ &
         button("btn1"), &
         viewport("plot", 80.0 .cw., 24.0 .ch., view) ]), &
       text("status", "Mixed units work!") ])
```

**Unit construction syntax**:
- `40.0 .dp.` - density-independent pixels
- `2.5 .em.` - relative to base font size  
- `14.0 .sp.` - scaled pixels (accessibility)
- `320.0 .px.` - physical pixels
- `10.0 .cw.` - cell widths (TUI-friendly)
- `3.0 .ch.` - cell heights (TUI-friendly)
- `42.0` - bare real values treated as 42.0 .dp.

⸻

## 2) public api

### modules

```fortran
use fortui_core      ! init/shutdown, frame, present, pacing, ui_element/node/view types
use fortui_widgets   ! column/row/viewport + button/slider/checkbox/text interfaces
use fortui_units     ! unit types (dp, em, sp, px, cw, ch) and ui_context
```

### types

```fortran
! Abstract UI element hierarchy
type, abstract :: ui_element
end type

type, extends(ui_element) :: node
end type

type :: view                 ! pan/zoom for plot areas
  real :: scale_x = 1.0, scale_y = 1.0
  real :: off_x   = 0.0, off_y   = 0.0
end type

type :: ui_context           ! cross-backend unit conversion
  real :: dpi_scale = 1.0    ! GUI: system DPI scale; TUI: 1.0
  real :: em_dp = 16.0       ! base font size in dp
  real :: text_scale = 1.0   ! accessibility text scaling
  real :: cell_w_dp = 8.0    ! TUI: cell width in dp
  real :: cell_h_dp = 16.0   ! TUI: cell height in dp
end type

! Internal unit type for runtime identification (implementation detail)
type :: unit_value
  real :: value
  character(len=2) :: unit_type  ! "dp", "em", "sp", "px", "cw", "ch"
end type

! Unit operator interfaces returning class(*) for API simplicity
interface operator(.dp.); module procedure make_dp; end interface
interface operator(.em.); module procedure make_em; end interface  
interface operator(.sp.); module procedure make_sp; end interface
interface operator(.px.); module procedure make_px; end interface
interface operator(.cw.); module procedure make_cw; end interface
interface operator(.ch.); module procedure make_ch; end interface
```

### lifecycle & pacing

```fortran
subroutine ui_init(backend, width, height, title, target_fps, vsync)
  character(*), intent(in) :: backend        ! "tui" | "gui"
  class(*), intent(in) :: width, height      ! any unit type (dp, em, sp, px, cw, ch) or real
  character(*), intent(in) :: title
  integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
  logical,      intent(in), optional :: vsync        ! gui: default .true.; tui: ignored
end

subroutine ui_get_context(ctx)
  type(ui_context), intent(out) :: ctx
end

subroutine ui_set_context(ctx)
  type(ui_context), intent(in) :: ctx
end

subroutine ui_set_idle_policy(mode, idle_fps)        ! gui only
  character(*), intent(in) :: mode                   ! "steady" | "adaptive"
  integer,      intent(in), optional :: idle_fps     ! e.g., 12
end

subroutine ui_frame_begin(timeout_ms)
  integer, intent(in) :: timeout_ms                  ! tui uses; gui ignores
end

subroutine ui_present(tree)
  class(ui_element), intent(in) :: tree
end

logical function ui_should_close()
end

subroutine ui_shutdown()
end
```

### layout constructors

```fortran
! Layout constructors with abstract UI elements and mixed unit support
function column(gap, children) result(n)
  class(*), intent(in), optional :: gap               ! any unit type or real
  class(ui_element), intent(in), optional :: children(:)
  type(node) :: n
end

function row(gap, children) result(n)
  class(*), intent(in), optional :: gap               ! any unit type or real
  class(ui_element), intent(in), optional :: children(:)
  type(node) :: n
end
```

### widgets (immediate-mode: declaration = draw = state update)

**Unified Interface**: Single widget functions accept class(*) for maximum API simplicity.

```fortran
! Button widget with unified interface
logical function button(id, label, width, height)
  character(*), intent(in) :: id
  character(*), intent(in), optional :: label     ! default: label=id
  class(*), intent(in), optional :: width, height ! any unit type or real
  ! returns .true. when clicked this frame
end function

! Slider widget with unified interface
logical function slider(id, min, max, step, value, width, height)
  character(*), intent(in) :: id
  real, intent(in) :: min, max, step
  real, intent(inout) :: value
  class(*), intent(in), optional :: width, height  ! any unit type or real
  ! draws slider and updates 'value' if interacted; returns .true. on change
end function

! Checkbox widget with unified interface
subroutine checkbox(id, checked, width, height)
  character(*), intent(in) :: id
  logical, intent(inout) :: checked
  class(*), intent(in), optional :: width, height  ! any unit type or real
  ! toggles 'checked' in place if interacted
end subroutine

! Text widget with unified interface
subroutine text(id, value, text_size)
  character(*), intent(in) :: id, value
  class(*), intent(in), optional :: text_size  ! any unit type or real
end subroutine

! Viewport widget with unified interface
logical function viewport(id, width, height, view)
  character(*), intent(in) :: id
  class(*), intent(in) :: width, height            ! any unit type or real
  type(view), intent(inout) :: view                ! wheel=zoom, drag=pan
  ! returns .true. if view changed
end function
```

**ids** are stable strings per widget (state keyed by id).
**units**: All units normalize to dp internally via runtime conversion:
- `40.0 .dp.` - density-independent pixels (base unit)
- `2.5 .em.` - relative to base font size (em_dp * 2.5)
- `14.0 .sp.` - scaled pixels (dp * text_scale)
- `320.0 .px.` - physical pixels (px / dpi_scale)
- `10.0 .cw.` - cell widths (TUI: cw * cell_w_dp)
- `3.0 .ch.` - cell heights (TUI: ch * cell_h_dp)
- `42.0` - bare real values treated as 42.0 .dp. (default)

**Examples of equivalent widget calls**:
```fortran
! These are equivalent:
button("ok", width=120.0)           ! real defaults to dp
button("ok", width=120.0 .dp.)      ! explicit dp

! Mixed usage:
button("ok", width=120.0, height=2.5 .em.)  ! width=dp, height=em
```

**cross-backend placement**:
- **TUI**: snaps to cell boundaries (integer cells)
- **GUI/Web**: subpixel precision maintained

⸻

## 3) example (single-call style)

```fortran
program demo
  use fortui_core
  use fortui_widgets
  implicit none

  real    :: gain = 1.0
  logical :: grid = .false.
  type(view) :: v
  class(ui_element), allocatable :: ui
  logical :: running

  call ui_init(backend="tui", width=100.0 .cw., height=35.0 .ch., title="plot demo")
  ! gui option: call ui_set_idle_policy("adaptive", idle_fps=12)

  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)

    ui = column(gap=1.0 .ch., children=[ &
           row(gap=2.0 .cw., children=[ &
             button("zoom_in"), &
             button("zoom_out", "-"), &
             slider("gain", 0.1, 5.0, 0.1, gain), &
             checkbox("grid", grid) ]), &
           viewport("plot", 80.0 .cw., 24.0 .ch., v), &
           text("status", status_line(gain, v, grid)) ])

    ! react to button returns (others already updated their state)
    if (button("zoom_in"))       call zoom(v, 1.2)
    if (button("zoom_out", "-")) call zoom(v, 1.0/1.2)

    call ui_present(ui)
    running = .not. ui_should_close()
  end do

  call ui_shutdown()

contains
  subroutine zoom(v,f); type(view),intent(inout)::v; real,intent(in)::f
    v%scale_x=v%scale_x*f; v%scale_y=v%scale_y*f
  end
  function status_line(g, v, show) result(s)
    real,intent(in)::g; type(view),intent(in)::v; logical,intent(in)::show
    character(len=:),allocatable::s; character(len=96)::buf
    write(buf,'("gain=",F4.2,"  scale=(",F4.2,",",F4.2,")  off=(",F5.1,",",F5.1,")  grid=",L1)') &
      g, v%scale_x, v%scale_y, v%off_x, v%off_y, show
    s=trim(buf)
  end
end program
```

**note**: each widget call is the single source of truth.
- **slider** updates gain directly.
- **checkbox** toggles grid.
- **viewport** updates v.
- Only **button** needs an if to trigger actions.
- All units automatically convert to dp for consistent backend behavior.

⸻

## 4) backend behavior

### gui (raygui/raylib)
- **vsync**=.true (default), **target_fps** (default 60; 120 ok).
- **steady** mode (default) or **adaptive** idle via ui_set_idle_policy.
- **units**: dp → pixels via ui_context (dpi_scale, em_dp, text_scale)
- **precision**: subpixel positioning and rendering
- **context setup**: auto-detect system DPI, font metrics

### tui (termbox2)
- **event-driven**: idle 250–1000 ms; coalesce 10–20 ms; dragging 16–33 ms.
- front/back cell buffers; per-line hashes; run diffs; coalesced writes.
- sgr1006 mouse; bracketed paste.
- **units**: dp → cells via ui_context (cell_w_dp, cell_h_dp)
- **snapping**: automatic snap to cell boundaries (integer coordinates)
- **context setup**: measure terminal cell dimensions

⸻

## 5) future work (kept open)
- **proportional text** (gui opt-in): ui_init(..., proportional=.true.), measure_text.
- **2d canvas** (tui+gui): canvas2d_begin/end, line/rect/polyline/text_at/image_gray, transform hook; basis for show().
- **3d canvas** (gui first): canvas3d_begin/end, tri_mesh/lines3d/bbox; optional ascii 3d later.
- **show()** (matplotlib-like): figure/axes model, modal/non-modal; uses canvases.
- **layout enrichment**: alignment, spacer(flex), padding/margin, theme tokens.
- **text input/listbox**: single-line editor, list selection.

⸻

## 6) invariants
- **small, stable public api**.
- **ids** own per-widget retained state.
- **tui** minimizes writes; **gui** respects target fps.
- **monospace** baseline; proportional is additive.