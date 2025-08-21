# fortui

A declarative UI library for modern Fortran with dual backends: terminal (TUI) and graphical (GUI).

## Features

- **Context Object Pattern**: Thread-safe architecture with multiple UI instance support
- **Backend Registry Pattern**: Runtime backend selection with automatic fallback (GUI→TUI→Error)
- **One codebase, dual backends**: Write once, run in terminal or GUI window with identical behavior
- **Immediate-mode API**: Simple, declarative widget calls with automatic state management
- **Thread safety**: OpenMP-compatible with isolated context objects per thread
- **Cross-backend units system**: Consistent sizing with dp, em, sp, px, cw, ch units
- **Monospace-first design**: Exact visual parity between TUI and GUI
- **Performance optimized**: Event-driven TUI with diffed output, VSync-aware GUI
- **Clean architecture**: Abstract interfaces, dependency injection, conditional compilation
- **Production ready**: Circular dependency resolution, graceful error handling

## Installation

### Quick Start (5 minutes)

**1. Clone and Build:**
```bash
git clone https://github.com/krystophny/fortui.git
cd fortui

# Automatic GUI/TUI build (detects raylib)
source fpm_env.sh         # Builds dependencies, configures FPM
fpm build                 # GUI+TUI if raylib found, TUI-only otherwise
```

**2. Test Installation:**
```bash
fpm test                  # Run test suite
fpm run --example gui_demo    # GUI example (if raylib available)
fpm run --example tui_demo    # TUI example (always works)
```

**3. Context-Aware Applications:**
```bash
# For OpenMP thread safety
export FPM_FFLAGS="-cpp -fopenmp $(./tools/build_fortui.sh flags)"
export FPM_LDFLAGS="$(./tools/build_fortui.sh ldflags) -fopenmp"
fpm build your_app.f90
```

### Prerequisites

**Required:**
- Modern Fortran compiler (gfortran 9+ or ifort)
- **TUI backend**: termbox2 library (built automatically)

**Optional (for GUI backend):**
- **raylib library**: Install via system package manager
  ```bash
  sudo apt install libraylib-dev    # Ubuntu/Debian
  brew install raylib               # macOS  
  sudo dnf install raylib-devel     # Fedora/RHEL
  ```
- **fortran-raygui bindings**: Fetched and built automatically when GUI enabled

### Build Methods

fortui provides multiple build methods for different workflows:

#### Method 1: Using FPM with Environment Setup (Recommended)
```bash
# Clone repository  
git clone https://github.com/krystophny/fortui.git
cd fortui

# Automatic GUI/TUI build (detects raylib)
source fpm_env.sh         # Builds dependencies, configures FPM
fpm build                 # GUI+TUI if raylib found, TUI-only otherwise
fpm test
fpm run --example gui_demo

# Force TUI-only build
DISABLE_GUI=1 source fpm_env.sh
fpm build                 # TUI backend only
```

#### Method 2: Using Make
```bash
# Build everything (dependencies + project)  
make                      # GUI+TUI if raylib available

# Run tests
make test

# Build TUI-only version
DISABLE_GUI=1 make
```

#### Method 3: Direct Build Script + FPM
```bash
# Build dependencies first
./tools/build_fortui.sh build

# Then use FPM with manual flags
export FPM_FFLAGS="-cpp -DTUI_ONLY"  # or -DENABLE_GUI for GUI support
export FPM_LDFLAGS="$(./tools/build_fortui.sh ldflags)"
fpm build
```

### Advanced Build System

Enterprise-grade build system with dependency management, network resilience, and cross-platform support:

#### Environment Variables
```bash
# Core controls
DISABLE_GUI=1           # Force TUI-only build
RAYLIB_ROOT=/opt/raylib # Custom raylib installation
GUI_CACHE=/tmp/deps     # Custom cache location

# Advanced features  
FORCE_REBUILD=1         # Ignore cache, rebuild everything
OFFLINE_MODE=1          # Work with cached dependencies only
DEBUG=1                 # Enable detailed build diagnostics

# Repository customization
FRG_URL=https://github.com/user/fortran-raylib.git
FRG_REF=feature-branch
TERMBOX_URL=https://github.com/user/termbox2.git  
TERMBOX_REF=custom-ref
```

#### Build Commands
```bash
# Build all dependencies
./tools/build_fortui.sh build

# View configuration and status
./tools/build_fortui.sh config
./tools/build_fortui.sh status

# Get compiler flags
./tools/build_fortui.sh flags    # ENABLE_GUI=0|1
./tools/build_fortui.sh ldflags  # Linker flags

# Cache management
./tools/build_fortui.sh clean
```

#### Enterprise Features
- **Network resilience**: Automatic retry with exponential backoff (3 attempts, 1-30s delays)
- **Concurrent safety**: File locking with 5-minute timeout and stale lock detection
- **Version tracking**: Smart cache invalidation when build tools change
- **Corruption recovery**: Automatic detection and repair of corrupted git repositories
- **Cross-platform**: Linux, macOS, Windows with platform-specific optimizations
- **FPM integration**: Build-script override with CPP preprocessing support

**Complete Documentation**: [BUILD_GUIDE.md](BUILD_GUIDE.md) | [Integration Examples](INTEGRATION_EXAMPLES.md)

## Quick Start

```fortran
program backend_demo
  use fortui_core
  use fortui_units
  use fortui_unit_types
  implicit none

  type(node) :: ui, inner_layout
  type(node), allocatable :: children(:)
  logical :: running
  integer :: frame = 0

  ! Backend Registry Pattern - automatic selection with graceful fallback
  call ui_init("auto", cw_unit(60.0), ch_unit(20.0), "Backend Demo")
  ! GUI preferred → TUI fallback → Clear error message
  
  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)
    frame = frame + 1

    ! Create nested layout structure (works in both TUI and GUI)
    allocate(children(2))
    children(1) = node()  ! placeholder child
    children(2) = node()  ! placeholder child
    inner_layout = row(gap=cw(2.0), children=children)
    
    deallocate(children)
    allocate(children(3))
    children(1) = node()  ! header placeholder  
    children(2) = inner_layout
    children(3) = node()  ! footer placeholder
    
    ui = column(gap=ch(1.0), children=children)

    call ui_present(ui)
    running = .not. ui_should_close()
    
    deallocate(children)
  end do

  call ui_shutdown()
  print *, "Demo completed after", frame, "frames"
end program
```

## Context-Aware API (Thread Safety & Multiple Instances)

fortui implements the **Context Object Pattern** for thread safety and multiple UI instance support. The new context-aware API is fully backward compatible.

### Basic Context Usage

```fortran
program context_demo
  use fortui_core
  use fortui_context
  use fortui_widgets
  implicit none

  type(fortui_context_t), pointer :: ctx
  logical :: running, save_clicked

  ! Create explicit context for this UI instance
  ctx => create_context()
  
  ! Initialize with context-aware API
  call ui_init_with_context(ctx, "auto", 80, 25, "Context Demo")
  
  running = .true.
  do while (running)
    call ui_frame_begin_with_context(ctx)
    
    ! Use context-aware widgets
    save_clicked = button_with_context(ctx, "save", "Save File")
    if (save_clicked) print *, "File saved!"
    
    running = .not. ui_should_close_with_context(ctx)
  end do
  
  call ui_shutdown_with_context(ctx)
  call destroy_context(ctx)
end program
```

### Multiple UI Instances

**Compilation Requirements:**
```bash
# Build dependencies and enable GUI backend
./tools/build_fortui.sh build

# Compile with GUI support for multiple instances
export FPM_FFLAGS="-cpp $(./tools/build_fortui.sh flags)"
export FPM_LDFLAGS="$(./tools/build_fortui.sh ldflags)"
fpm build
```

```fortran
program multiple_windows
  use fortui_core
  use fortui_context
  implicit none

  type(fortui_context_t), pointer :: main_ctx, settings_ctx
  logical :: main_running, settings_running

  ! Create independent contexts
  main_ctx => create_context()
  settings_ctx => create_context()
  
  ! Initialize separate UI instances
  call ui_init_with_context(main_ctx, "gui", 800, 600, "Main Window")
  call ui_init_with_context(settings_ctx, "tui", 60, 20, "Settings")
  
  ! Run both UI instances independently
  main_running = .true.
  settings_running = .true.
  
  do while (main_running .or. settings_running)
    ! Main window frame
    if (main_running) then
      call ui_frame_begin_with_context(main_ctx)
      ! ... main window UI ...
      main_running = .not. ui_should_close_with_context(main_ctx)
    end if
    
    ! Settings window frame  
    if (settings_running) then
      call ui_frame_begin_with_context(settings_ctx)
      ! ... settings UI ...
      settings_running = .not. ui_should_close_with_context(settings_ctx)
    end if
  end do
  
  ! Clean shutdown
  call ui_shutdown_with_context(main_ctx)
  call ui_shutdown_with_context(settings_ctx)
  call destroy_context(main_ctx)
  call destroy_context(settings_ctx)
end program
```

### Thread Safety with OpenMP

**Compilation Requirements:**
```bash
# Build fortui with dependencies first
./tools/build_fortui.sh build

# Compile with OpenMP support
export FPM_FFLAGS="-cpp -fopenmp $(./tools/build_fortui.sh flags)"
export FPM_LDFLAGS="$(./tools/build_fortui.sh ldflags) -fopenmp"
fpm build

# Alternative: Use make with OpenMP
OPENMP=1 make
```

```fortran
program threaded_ui
  use fortui_core
  use fortui_context
  use omp_lib
  implicit none

  !$OMP PARALLEL
  block
    type(fortui_context_t), pointer :: thread_ctx
    integer :: thread_id
    character(len=32) :: title
    
    thread_id = omp_get_thread_num()
    write(title, '(A,I0)') "Thread ", thread_id
    
    ! Each thread gets its own context
    thread_ctx => create_context()
    call ui_init_with_context(thread_ctx, "tui", 40, 15, trim(title))
    
    ! Thread-safe UI operations
    call ui_frame_begin_with_context(thread_ctx)
    ! ... thread-specific UI ...
    
    call ui_shutdown_with_context(thread_ctx)
    call destroy_context(thread_ctx)
  end block
  !$OMP END PARALLEL
end program
```

### Backward Compatibility

```fortran
program legacy_api_still_works
  use fortui_core
  use fortui_widgets
  implicit none

  logical :: running, clicked

  ! Legacy API works unchanged via default context
  call ui_init("auto", 80, 25, "Legacy Demo")
  
  running = .true.
  do while (running)
    call ui_frame_begin()
    
    ! Legacy widget API (uses default context internally)
    clicked = button("legacy_btn", "Still Works!")
    if (clicked) print *, "Legacy button clicked!"
    
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
end program
```

### Widget Context API Completeness

**All widgets support both legacy and context-aware APIs:**

| Widget | Legacy API | Context-Aware API | Status |
|--------|------------|-------------------|--------|
| **button** | `button(id, label)` | `button_with_context(ctx, id, label)` | ✅ Complete |
| **text** | `text(id, content)` | `text_with_context(ctx, id, content)` | ✅ Complete |
| **slider** | `slider(id, min, max, step, value)` | `slider_with_context(ctx, id, min, max, step, value)` | ✅ Complete |
| **checkbox** | `checkbox(id, checked, label)` | `checkbox_with_context(ctx, id, checked, label)` | ✅ Complete |

**Layout functions use implicit context:**
- `column()` and `row()` always use the current context (legacy or explicit)
- No separate context-aware versions needed

### Context Management Best Practices

```fortran
! ✓ GOOD: Explicit context management
ctx => create_context()
call ui_init_with_context(ctx, ...)
! ... use context ...
call ui_shutdown_with_context(ctx)
call destroy_context(ctx)

! ✓ GOOD: Legacy API for simple applications  
call ui_init("auto", 80, 25, "Simple App")
! ... use default context ...
call ui_shutdown()

! ✗ AVOID: Mixing context-aware and legacy APIs
ctx => create_context()
call ui_init("auto", 80, 25, "Mixed")  ! Uses different context!
```

## Core Types

### node Type
The foundational building block for all UI elements:
```fortran
type :: node
    ! Layout metadata
    character(len=32) :: layout_type = "none"    ! "column", "row", "none"
    real :: gap_dp = 0.0                         ! Gap in dp units
    type(node), allocatable :: children(:)       ! Child elements
end type node
```

### view Type  
Manages pan and zoom state for plot areas:
```fortran
type :: view
    real :: scale_x = 1.0  ! Zoom factor X-axis
    real :: scale_y = 1.0  ! Zoom factor Y-axis  
    real :: off_x = 0.0    ! Pan offset X-axis
    real :: off_y = 0.0    ! Pan offset Y-axis
end type view
```

## Layout System

Build UI hierarchies with `column()` and `row()` layout functions. The layout system is **fully implemented and production-ready**:

```fortran
use fortui_core
use fortui_units

! Column layout with gap spacing - arranges children vertically
ui = column(gap=dp(12.0), children=[ &
  node(), node(), node() ])

! Row layout with TUI-friendly units - arranges children horizontally
ui = row(gap=cw(2.0), children=[ &
  node(), node() ])
  
! Complex nested layouts - mix columns and rows freely
type(node) :: sidebar, content, ui_root

! Create sidebar navigation
sidebar = column(gap=ch(1.0), children=[ &
  node(), node(), node() ])  ! Nav items

! Create main content area
content = column(gap=dp(16.0), children=[ &
  node(), node() ])  ! Content sections

! Combine horizontally for dashboard layout
ui_root = row(gap=cw(3.0), children=[sidebar, content])
```

### Gap Parameters
Supports all unit types with runtime type checking:
```fortran
! All unit types supported via class(*) parameter
layout = column(gap=dp(12.0))   ! density-independent pixels
layout = column(gap=em(1.0))    ! relative to font size
layout = column(gap=cw(2.0))    ! cell widths (TUI-friendly)
layout = column(gap=16.0)       ! bare real (treated as dp)
```

### Memory Management
- **Automatic:** Children arrays deep-copied and managed automatically
- **Safe:** Source arrays can be deallocated immediately after layout creation
- **Efficient:** Optimized for immediate-mode UI rebuilding every frame

**Complete Documentation:** [Layout API Guide](docs/LAYOUT_API.md)

## Widget System

### Button Widget

Interactive button with click detection and auto-sizing:

```fortran
use fortui_widgets

logical :: save_clicked, big_clicked

! Legacy API - returns logical for click detection
save_clicked = button("save_btn", label="Save")
if (save_clicked) then
    print *, "Save button clicked!"
end if

! Context-aware API for explicit control
save_clicked = button_with_context(ctx, "save_btn", label="Save")
if (save_clicked) then
    print *, "Context-specific button clicked!"
end if

! Custom size with real values (width/height in dp)
big_clicked = button("big_btn", width=80.0, height=40.0)
if (big_clicked) then
    ! Handle click
end if
```

### Text Widget

Display text content with auto-sizing and multiline support:

```fortran
type(text_node_t) :: label_widget, info_widget, terminal_widget

! Basic text display
label_widget = text("label", "Hello World!")

! Custom size with multiline content (text_size in points)
info_widget = text("info", "Line 1" // char(10) // "Line 2", text_size=16.0)

! Auto-sizing with width in dp
terminal_widget = text("terminal", "Terminal Text", width=200.0)
```

### Slider Widget

Interactive numeric input with range control and step quantization:

```fortran
real :: volume = 50.0, temperature = 20.0
logical :: volume_changed, temp_changed

! Returns logical for value change detection
volume_changed = slider("volume", 0.0, 100.0, 5.0, volume, width=120.0)
if (volume_changed) then
    print *, "Volume changed to:", volume
end if

! Continuous values (step_val = 0.0)
temp_changed = slider("temp", 15.0, 30.0, 0.0, temperature)
if (temp_changed) then
    print *, "Temperature:", temperature, "°C"
end if
```

### Checkbox Widget

Boolean input with toggle functionality:

```fortran
logical :: sound_enabled = .true., enabled = .false.
logical :: sound_toggled, notif_toggled

! Checkbox returns logical for toggle detection
sound_toggled = checkbox("sound", sound_enabled, label="Enable Sound")
if (sound_toggled) then
    print *, "Sound setting changed to:", sound_enabled
end if

! Auto-sizing with label
notif_toggled = checkbox("notifications", enabled, label="Email Notifications")
if (notif_toggled) then
    print *, "Notifications enabled:", enabled
end if
```

**Parameter Types:**
- **Widget functions**: Accept plain `real` values for width/height (e.g., `width=80.0`)
- **Layout functions**: Accept unit types via `class(*)` (e.g., `gap=dp(12.0)`, `gap=cw(2.0)`)

**Complete Documentation:** 
- [Button Widget API](docs/BUTTON_WIDGET.md)
- [Text Widget API](docs/TEXT_WIDGET.md)
- [Slider Widget API](docs/SLIDER_WIDGET.md)
- [Checkbox Widget API](docs/CHECKBOX_WIDGET.md)

### Units System

fortui provides abstract unit types with polymorphic dispatch for precise cross-backend sizing:

```fortran
use fortui_core
use fortui_unit_types

! Abstract unit types - polymorphic dispatch
call ui_init("auto", dp_unit(800.0), em_unit(30.0), "My App")
call ui_init("gui", inches_unit(8.5), cm_unit(21.0), "Mixed Units")

! All unit types supported
width = dp_unit(40.0)      ! density-independent pixels
gap = em_unit(2.5)         ! relative to font size  
text_size = sp_unit(14.0)  ! scaled pixels (accessibility)
border = px_unit(2.0)      ! physical pixels
cols = cw_unit(10.0)       ! cell widths (TUI-friendly)
rows = ch_unit(3.0)        ! cell heights (TUI-friendly)

! Physical units with DPI awareness
paper_width = inches_unit(8.5)     ! physical inches
paper_height = cm_unit(21.0)       ! physical centimeters
border_size = mm_unit(5.0)         ! millimeters
font_size = points_unit(12.0)      ! typography points

! Legacy constructor functions still supported
width = dp(40.0)           ! equivalent to dp_unit(40.0)
gap = em(2.5)              ! equivalent to em_unit(2.5)
```

**Abstract Type Integration:**
- **Polymorphic dispatch**: `class(unit_type)` parameters work throughout API
- **Context-aware conversion**: Each unit type converts via backend measurement
- **Type safety**: NO `class(*)` usage - only abstract `unit_type`

## API Reference

### Lifecycle Management

```fortran
! ===== Legacy API (uses default context) =====
! Initialize UI system - integer units (backward compatible)
call ui_init(backend, width, height, title [, target_fps, vsync])

! Initialize UI system - abstract units
call ui_init(backend, width_unit, height_unit, title [, target_fps, vsync])
! backend: "auto" | "tui" | "gui" ("auto" recommended)
! width_unit, height_unit: class(unit_type) - any abstract unit type

! Frame lifecycle
call ui_frame_begin(timeout_ms)  ! TUI: event timeout; GUI: ignored
call ui_present(tree)            ! Render UI tree
logical :: should_exit = ui_should_close()

! Cleanup
call ui_shutdown()

! ===== Context-Aware API (explicit context management) =====
! Context management
type(fortui_context_t), pointer :: ctx
ctx => create_context()
call destroy_context(ctx)

! Initialize with explicit context
call ui_init_with_context(ctx, backend, width, height, title [, target_fps, vsync])

! Frame lifecycle with context
call ui_frame_begin_with_context(ctx [, timeout_ms])
call ui_present_with_context(ctx, tree)
logical :: should_exit = ui_should_close_with_context(ctx)

! Cleanup with context
call ui_shutdown_with_context(ctx)

! Optional: Configure GUI idle policy (ignored in TUI mode)
call ui_set_idle_policy(mode [, idle_fps])  ! "adaptive" | "steady"
```

### Core Type Usage

```fortran
! Node type - building block for UI elements
type(node) :: ui_root
! (Will be extended by widget types from fortui_widgets module)

! View type - pan/zoom state management
type(view) :: plot_view
plot_view%scale_x = 2.0    ! Zoom in X by 2x
plot_view%off_x = 100.0    ! Pan right by 100 units

! Memory management is automatic - no manual cleanup needed
```

## Complete Example

**Compilation Requirements:**
```bash
# Build fortui first
./tools/build_fortui.sh build

# Compile with proper flags for abstract units
export FPM_FFLAGS="-cpp $(./tools/build_fortui.sh flags)"
export FPM_LDFLAGS="$(./tools/build_fortui.sh ldflags)"
fpm build complete_demo.f90

# Or use the simplified environment setup
source fpm_env.sh
fpm build complete_demo.f90
```

```fortran
program core_types_demo  
  use fortui_core
  use fortui_unit_types
  implicit none

  type(view) :: plot_view
  type(node) :: ui_root
  logical :: running
  integer :: frame_count = 0

  ! Automatic backend selection with mixed abstract units
  call ui_init("auto", cw_unit(80.0), ch_unit(25.0), "Core Types Demo")
  
  ! Optional: Configure power-saving for GUI mode (ignored in TUI)
  call ui_set_idle_policy("adaptive", idle_fps=12)

  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)

    ! Update view state (zoom oscillation for demo)
    frame_count = frame_count + 1
    plot_view%scale_x = 1.0 + sin(real(frame_count) * 0.05) * 0.5
    plot_view%scale_y = plot_view%scale_x
    plot_view%off_x = cos(real(frame_count) * 0.03) * 20.0

    ! Build UI with text widgets
    ! ui_root = column(children=[ &
    !   text("title", "fortui Demo - Frame " // int_to_str(frame_count)), &
    !   text("view_info", "Scale: " // real_to_str(plot_view%scale_x) // &
    !                     " Offset: " // real_to_str(plot_view%off_x)), &
    !   viewport("plot", 60, 15, plot_view) ])

    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do

  call ui_shutdown()
  
  print *, "Demo completed after", frame_count, "frames"
  print *, "Final view state: scale=", plot_view%scale_x, "offset=", plot_view%off_x
end program
```

## Backend Architecture

fortui uses a **Backend Registry Pattern** for runtime backend selection with automatic fallback. This architecture resolves circular dependencies and provides clean separation between core functionality and backend implementations.

### Backend Registry System

```fortran
! Automatic backend detection with graceful fallback
call ui_init("auto", 80, 25, "My App")  ! GUI→TUI→Error with clear feedback

! Environment variable override
export FORTUI_BACKEND=tui
call ui_init("auto", 80, 25, "My App")  ! Forces TUI backend
```

**Architecture Benefits:**
- **Runtime Selection**: Choose backend dynamically based on availability
- **Graceful Fallback**: GUI→TUI→Error with clear user feedback  
- **Extensible**: Easy to add new backends without modifying core
- **Clean Separation**: Backend implementations are self-contained
- **Conditional Compilation**: GUI backend only compiled with `ENABLE_GUI=1`

### Terminal UI (TUI) Backend
```fortran
call ui_init("tui", 80, 25, "Terminal App")
```
- **Always Available**: No external dependencies beyond termbox2
- **Visual Layout**: Characters (`|`, `-`, `*`) show widget structure
- **Event-Driven**: Smart timeouts with keyboard/mouse support
- **Cell-Perfect**: Exact coordinate snapping to terminal grid
- **Optimized Rendering**: Front/back buffer diffing minimizes terminal writes

### Graphical UI (GUI) Backend  
```fortran
call ui_init("gui", 800, 600, "Graphics App", target_fps=60, vsync=.true.)
call ui_set_idle_policy("adaptive", idle_fps=12)  ! Power-saving mode
```
- **Conditional Compilation**: Only builds with raylib available (`-DENABLE_GUI`)
- **Environment Detection**: Automatically disabled in headless/SSH/CI environments
- **Monospace Alignment**: Pixel-perfect consistency with TUI rendering  
- **Performance Features**: VSync, configurable FPS, adaptive idle policies
- **Cross-Platform**: Linux, macOS, Windows via raylib integration

### Backend Selection Logic

1. **Environment Variables**: `FORTUI_BACKEND=tui|gui` overrides selection
2. **Availability Check**: Each backend reports runtime availability  
3. **Auto-Detection**: GUI preferred → TUI fallback → clear error message
4. **Headless Detection**: SSH/CI/no-display environments auto-select TUI

## Current Implementation Status

✅ **Context Object Pattern**: Thread-safe architecture with multiple UI instance support and complete global state elimination  
✅ **Backend Registry Pattern**: Complete circular dependency resolution with runtime backend selection  
✅ **fortui_core module**: Complete with `node` and `view` types, lifecycle management, layout constructors  
✅ **fortui_context module**: Context objects with widget state encapsulation and thread-local default contexts
✅ **fortui_backend**: Abstract interface with dynamic registry and capability system
✅ **fortui_tui/fortui_gui**: Backend implementations with conditional compilation
✅ **fortui_units module**: Complete with comprehensive cross-backend units system
✅ **Layout system**: `column()` and `row()` functions with gap parameters and children arrays - **PRODUCTION READY**
✅ **fortui_widgets module**: Button, text, slider, and checkbox widgets with context-aware and legacy APIs
✅ **Build system**: Automatic dependency detection and configuration

**Backend Architecture Status:**
- ✅ **Abstract Interface**: `backend_interface` with deferred procedures for all backends
- ✅ **Dynamic Registry**: Runtime backend registration with automatic array resizing
- ✅ **Capability System**: Feature flags (`graphics`, `colors`, `mouse`, `unicode`, `async_events`)
- ✅ **Runtime Selection**: Backend selection by name or auto-detection with graceful fallback
- ✅ **Conditional Compilation**: GUI backend only compiled with `#ifdef ENABLE_GUI`
- ✅ **Dependency Resolution**: Core imports only abstraction layer, eliminating circular dependencies

**Layout System Status:**
- ✅ **Functions Implemented:** `column()` and `row()` with full functionality
- ✅ **Gap Support:** All unit types via `class(*)` polymorphism and runtime type checking
- ✅ **Memory Management:** Deep copying with automatic cleanup
- ✅ **Performance Tested:** 500+ layouts/frame, 20+ nesting levels
- ✅ **Production Demo:** Working `layout_demo.f90` demonstrates real usage  

## Architecture

- **fortui_context**: ✅ Context Object Pattern with thread-safe state encapsulation and OpenMP support
- **fortui_backend**: ✅ Abstract interface with registry pattern for clean backend separation
- **fortui_backend_init**: ✅ Automatic registration system avoiding circular dependencies  
- **fortui_core**: ✅ Lifecycle management, core types, frame handling with context-aware and legacy APIs
- **fortui_tui**: ✅ Terminal backend with termbox2 integration (always available)
- **fortui_gui**: ✅ GUI backend with raylib integration (conditional compilation)
- **fortui_units**: ✅ Cross-backend units system with dp, em, sp, px, cw, ch support
- **fortui_widgets**: ✅ Button, text, slider, and checkbox widgets with context-aware and legacy APIs
- **Monospace baseline**: ✅ Ensures pixel-perfect TUI/GUI consistency

## Documentation

### Core Documentation
- **[Layout API Guide](docs/LAYOUT_API.md)**: Complete layout system documentation with examples
- **[Button Widget API](docs/BUTTON_WIDGET.md)**: Button widget with click detection and auto-sizing
- **[Units Guide](docs/UNITS_GUIDE.md)**: Complete units system documentation with examples
- **[Core Types API](docs/CORE_TYPES_API.md)**: Complete `node` and `view` type documentation
- **[Lifecycle API](docs/LIFECYCLE_API.md)**: UI initialization and frame management

### Backend Guides
- **[GUI Backend Guide](docs/GUI_BACKEND_GUIDE.md)**: Complete graphical UI backend with raylib integration, compilation, and troubleshooting
- **[TUI Backend Guide](docs/TUI_BACKEND_GUIDE.md)**: Complete terminal UI backend documentation with termbox2 integration
- **[Event System Guide](docs/EVENT_SYSTEM_GUIDE.md)**: Event-driven model for responsive TUI applications
- **[Coordinate System Guide](docs/COORDINATE_SYSTEM_GUIDE.md)**: Coordinate conversion and cell-based rendering system

### Integration & Development
- **[Application Integration](docs/APPLICATION_INTEGRATION.md)**: Complete examples for real applications
- **[Developer Guide](docs/DEVELOPER_GUIDE.md)**: Integration patterns and best practices
- **[Build Guide](BUILD_GUIDE.md)**: Dependency setup and build configuration

## License

[License TBD]

## Contributing

[Contributing guidelines TBD]

## Status

🚧 **In Development** - This library is under active development. APIs may change before v1.0 release.
