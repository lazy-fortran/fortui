# fortui Backend Selection Guide

Complete guide to choosing and configuring TUI vs GUI backends in fortui applications.

## Overview

fortui provides a unified API that works with two backends:
- **TUI Backend**: Terminal-based UI using termbox2
- **GUI Backend**: Graphical window using raylib/raygui

Your application code remains identical - only compilation and initialization change.

## Quick Start

```fortran
! Same code works for both backends
program universal_app
  use fortui_core
  implicit none
  
  call ui_init(backend="tui", width=80, height=25, title="My App")
  ! OR
  call ui_init(backend="gui", width=80, height=25, title="My App")
  
  ! ... rest of application is identical ...
  call ui_shutdown()
end program
```

## Backend Compilation

### TUI-Only Build (Default)

```bash
# Standard build - TUI backend only
fpm build
fpm run
fpm test

# Explicitly disable GUI even if raylib available
DISABLE_GUI=1 fpm build
```

**What you get:**
- Terminal-based interface
- Smaller binary size
- No GUI dependencies required
- Works on any system with termbox2

### GUI-Enabled Build

```bash
# Build with GUI support (when raylib available)
fpm build --flag "-DENABLE_GUI"
fpm run --flag "-DENABLE_GUI"
fpm test --flag "-DENABLE_GUI"

# Or set flag in fpm.toml for persistent GUI builds
```

**What you get:**
- Both TUI and GUI backends available
- Runtime backend selection via `ui_init(backend=...)`
- Graphical window with exact visual parity to TUI
- Requires raylib and raygui libraries

## Runtime Backend Selection

When compiled with GUI support, choose backend at runtime:

```fortran
program flexible_app
  use fortui_core
  implicit none
  character(len=32) :: backend_choice
  
  ! Get user preference (command line, config file, etc.)
  call get_arguments(backend_choice)
  
  ! Initialize with user's choice
  select case (trim(backend_choice))
  case ("tui", "terminal")
    call ui_init("tui", 80, 25, "Terminal Mode")
  case ("gui", "window") 
    call ui_init("gui", 100, 30, "Window Mode")
  case default
    call ui_init("tui", 80, 25, "Default Mode")  ! Safe fallback
  end select
  
  ! ... application logic identical for both backends ...
  call ui_shutdown()
end program
```

## Backend-Specific Configuration

### TUI Backend Configuration

```fortran
! TUI-specific initialization
call ui_init(backend="tui", width=80, height=25, title="Terminal App")

! TUI timing - event timeout controls responsiveness
call ui_frame_begin(timeout_ms=200)  ! Wait 200ms for user input

! TUI considerations:
! - title appears in terminal title bar
! - width/height in terminal cells
! - target_fps and vsync parameters ignored
! - ui_set_idle_policy() calls ignored
```

**TUI Sizing Examples:**
```fortran
! Standard terminal sizes
call ui_init("tui", 80, 25, "Standard")      ! Classic 80×25
call ui_init("tui", 120, 40, "Extended")     ! Modern extended  
call ui_init("tui", 100, 30, "Balanced")     ! Good compromise

! Responsive sizing based on terminal
integer :: term_width, term_height
call get_terminal_size(term_width, term_height)  ! Your implementation
call ui_init("tui", term_width, term_height, "Responsive")
```

### GUI Backend Configuration

```fortran
! GUI-specific initialization
call ui_init(backend="gui", width=100, height=30, title="GUI App", &
             target_fps=60, vsync=.true.)

! GUI power management
call ui_set_idle_policy("adaptive", idle_fps=12)

! GUI timing - controlled by target_fps, not timeout_ms
call ui_frame_begin(timeout_ms=0)  ! Value ignored in GUI mode

! GUI considerations:
! - title appears in window title bar
! - width/height in character-equivalent units
! - target_fps controls rendering rate (default: 60)
! - vsync enables smooth display (default: true)
! - idle policy saves power when inactive
```

**GUI Performance Tuning:**
```fortran
! High-performance real-time applications
call ui_init("gui", 120, 40, "Real-time", target_fps=120, vsync=.false.)
call ui_set_idle_policy("steady")  ! No frame rate reduction

! Power-efficient applications  
call ui_init("gui", 80, 25, "Efficient", target_fps=30, vsync=.true.)
call ui_set_idle_policy("adaptive", idle_fps=8)

! Balanced applications (recommended default)
call ui_init("gui", 100, 30, "Balanced", target_fps=60, vsync=.true.)
call ui_set_idle_policy("adaptive", idle_fps=12)
```

## Conditional Compilation Patterns

### Backend-Agnostic Code (Recommended)

```fortran
! Write once, runs on both backends
program universal_design
  use fortui_core
  use fortui_widgets
  implicit none
  
  type(node) :: ui
  type(view) :: plot_view
  logical :: running
  real :: gain = 1.0
  
  ! Backend choice configurable
  call ui_init("tui", 80, 25, "Universal App")  ! or "gui"
  
  running = .true.
  do while (running)
    call ui_frame_begin(200)
    
    ! UI code identical for both backends
    ui = column(children=[ &
           slider("gain", 0.1, 5.0, 0.1, gain), &
           viewport("plot", 60, 20, plot_view) ])
    
    call ui_present(ui)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
end program
```

### Backend-Specific Optimizations

```fortran
program optimized_app
  use fortui_core
  implicit none
  
  character(len=3) :: backend
  integer :: width, height, fps
  
  ! Detect available backends and optimize accordingly
#ifdef ENABLE_GUI
  ! GUI available - use larger window, higher FPS
  backend = "gui"
  width = 120; height = 40; fps = 60
#else
  ! TUI only - use conservative sizing
  backend = "tui"  
  width = 80; height = 25; fps = 0  ! fps ignored in TUI
#endif
  
  call ui_init(backend, width, height, "Optimized App", target_fps=fps)
  
#ifdef ENABLE_GUI
  if (backend == "gui") then
    call ui_set_idle_policy("adaptive", idle_fps=12)
  end if
#endif
  
  ! ... rest of application ...
  call ui_shutdown()
end program
```

### Feature Detection

```fortran
function has_gui_support() result(gui_available)
  logical :: gui_available
#ifdef ENABLE_GUI
  gui_available = .true.
#else
  gui_available = .false.
#endif
end function

program feature_detection
  use fortui_core
  implicit none
  
  if (has_gui_support()) then
    print *, "GUI backend available"
    call ui_init("gui", 100, 30, "GUI Mode")
  else
    print *, "TUI backend only"
    call ui_init("tui", 80, 25, "TUI Mode")
  end if
  
  ! ... application logic ...
  call ui_shutdown()
end program
```

## Build System Integration

### fpm Integration

```toml
# fpm.toml - TUI-only default
[build]
auto-executables = true
auto-tests = true

# For persistent GUI builds, add:
[fortran]
implicit-typing = false

[build]
flag = ["-DENABLE_GUI"]  # Uncomment for GUI builds
```

### Makefile Integration

```makefile
# Makefile backend selection
FORTRAN_COMPILER = gfortran
FPM = fpm

# TUI build (default)
build-tui:
	$(FPM) build

# GUI build  
build-gui:
	$(FPM) build --flag "-DENABLE_GUI"

# Automatic detection
build-auto:
	@if pkg-config --exists raylib; then \
		echo "Building with GUI support"; \
		$(FPM) build --flag "-DENABLE_GUI"; \
	else \
		echo "Building TUI-only"; \
		$(FPM) build; \
	fi

# Force TUI even if GUI available
build-tui-force:
	DISABLE_GUI=1 $(FPM) build
```

### CI/CD Pipeline

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test-tui:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install termbox2
        run: sudo apt-get install -y libterm* # install termbox2
      - name: Build TUI only
        run: fpm build
      - name: Test TUI
        run: fpm test
        
  test-gui:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3  
      - name: Install dependencies
        run: |
          sudo apt-get install -y libraylib-dev
          sudo apt-get install -y libterm* # termbox2
      - name: Build with GUI
        run: fpm build --flag "-DENABLE_GUI"
      - name: Test GUI
        run: fpm test --flag "-DENABLE_GUI"
```

## Grid Units Consistency

Both backends use identical grid unit (gu) measurements:

```fortran
! Grid units ensure visual parity
call ui_init("tui", 80, 25, "Terminal")  ! 80 chars × 25 lines
call ui_init("gui", 80, 25, "Window")    ! Same visual size

! Layouts look identical
ui = column(children=[ &
       text("title", "Hello fortui"), &           ! Same text positioning
       button("ok", "OK") ])                      ! Same button size

! viewport dimensions consistent  
ui = viewport("plot", 60, 20, plot_view)         ! 60×20 gu in both backends
```

**Visual Parity Examples:**
```fortran
! A 10×3 button appears identical in TUI and GUI
ui = button("save", "Save File")  ! 10 chars wide, 3 lines tall

! A 80×25 application has same usable space
call ui_init("tui", 80, 25, "App")  ! Terminal: 80 columns × 25 rows  
call ui_init("gui", 80, 25, "App")  ! GUI: equivalent pixel dimensions
```

## Environment Variables

Control backend selection via environment:

```bash
# Force TUI even when GUI available
export DISABLE_GUI=1
fpm build    # Builds TUI-only

# Force GUI detection
export RAYLIB_ROOT=/usr/local
fpm build --flag "-DENABLE_GUI"

# Cache directory for build dependencies
export FORTUI_CACHE_DIR=~/.cache/fortui
fpm build
```

## Troubleshooting

### GUI Build Issues

```bash
# Check if raylib is available
pkg-config --exists raylib && echo "raylib found" || echo "raylib missing"

# Install raylib on Ubuntu/Debian
sudo apt-get install libraylib-dev

# Install raylib on macOS
brew install raylib

# Force TUI build if GUI dependencies problematic
DISABLE_GUI=1 fpm build
```

### Runtime Backend Issues

```fortran
! Safe backend selection with fallback
subroutine safe_init(preferred_backend)
  character(*), intent(in) :: preferred_backend
  
  select case (trim(preferred_backend))
  case ("gui")
#ifdef ENABLE_GUI
    call ui_init("gui", 100, 30, "GUI App")
#else
    print *, "GUI not available, using TUI"
    call ui_init("tui", 80, 25, "TUI App")
#endif
  case default
    call ui_init("tui", 80, 25, "TUI App")  ! Always available
  end select
end subroutine
```

## Best Practices

1. **Write backend-agnostic code**: Avoid conditional compilation in application logic
2. **Use runtime selection**: Let users choose TUI or GUI at startup
3. **Provide safe fallbacks**: Always support TUI mode as minimum functionality
4. **Optimize for both**: TUI benefits from longer timeouts, GUI from higher FPS
5. **Test both modes**: Ensure identical behavior across backends
6. **Document requirements**: Clearly state which dependencies enable which features

## Next Steps

- **Core Types**: Learn fundamental types in [CORE_TYPES_API.md](CORE_TYPES_API.md)
- **Lifecycle**: Understand initialization in [LIFECYCLE_API.md](LIFECYCLE_API.md)
- **Build Setup**: Configure dependencies in [BUILD_GUIDE.md](BUILD_GUIDE.md)