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