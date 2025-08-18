# fortui

A declarative UI library for modern Fortran with dual backends: terminal (TUI) and graphical (GUI).

## Features

- **One codebase, two backends**: Write once, run in terminal or GUI window
- **Immediate-mode API**: Simple, declarative widget calls with automatic state management
- **Monospace-first design**: Exact visual parity between TUI and GUI
- **Performance optimized**: Event-driven TUI with diffed output, VSync-aware GUI
- **Clean API**: Two modules, stable interface, minimal dependencies

## Installation

### Prerequisites

- Modern Fortran compiler (gfortran 9+ or ifort)
- **TUI backend**: termbox2 library
- **GUI backend**: raylib and raygui libraries

### Build

```bash
# Clone repository
git clone https://github.com/krystophny/fortui.git
cd fortui

# Build dependencies (termbox2 for TUI, fortran-raygui for GUI)
./tools/build_fortui.sh build

# Build fortui library
fpm build

# Run examples and tests
fpm run --example hello_world
fpm test
```

**Build Documentation:**
- [BUILD_GUIDE.md](BUILD_GUIDE.md) - Comprehensive build configuration and troubleshooting
- [INTEGRATION_EXAMPLES.md](INTEGRATION_EXAMPLES.md) - Copy-paste examples for Makefile, CMake, CI/CD integration

## Quick Start

```fortran
program hello_world
  use fortui_core
  use fortui_widgets
  implicit none

  class(node), allocatable :: ui
  logical :: running

  call ui_init(backend="tui", width=50, height=20, title="Hello fortui")
  
  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)

    ui = column(children=[ &
           text("hello", "Hello, fortui!"), &
           button("quit", "Exit") ])

    if (button("quit", "Exit")) running = .false.

    call ui_present(ui)
    running = running .and. .not. ui_should_close()
  end do

  call ui_shutdown()
end program
```

## Core Types

### node Type
The foundational building block for all UI elements:
```fortran
type :: node
    ! Minimal structure - extensible for widgets
    ! Backend-agnostic design
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

### Grid Units
All dimensions use **grid units (gu)**:
- **TUI**: 1 gu = 1 terminal cell
- **GUI**: 1 gu = 1 monospace character width/height

## API Reference

### Lifecycle Management

```fortran
! Initialize UI system
call ui_init(backend, width, height, title [, target_fps, vsync])

! Optional: Configure GUI idle policy
call ui_set_idle_policy(mode [, idle_fps])  ! GUI only

! Frame lifecycle
call ui_frame_begin(timeout_ms)  ! TUI: event timeout; GUI: ignored
call ui_present(tree)            ! Render UI tree
logical :: should_exit = ui_should_close()

! Cleanup
call ui_shutdown()
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

```fortran
program core_types_demo  
  use fortui_core
  implicit none

  type(view) :: plot_view
  type(node) :: ui_root
  logical :: running
  integer :: frame_count = 0

  call ui_init(backend="tui", width=80, height=25, title="Core Types Demo")

  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)

    ! Update view state (zoom oscillation for demo)
    frame_count = frame_count + 1
    plot_view%scale_x = 1.0 + sin(real(frame_count) * 0.05) * 0.5
    plot_view%scale_y = plot_view%scale_x
    plot_view%off_x = cos(real(frame_count) * 0.03) * 20.0

    ! UI tree will be built using fortui_widgets module (coming soon)
    ! ui_root = column(children=[ &
    !   text("info", "Core types implemented!"), &
    !   viewport("plot", 60, 15, plot_view) ])

    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do

  call ui_shutdown()
  
  print *, "Demo completed after", frame_count, "frames"
  print *, "Final view state: scale=", plot_view%scale_x, "offset=", plot_view%off_x
end program
```

## Backend Selection

### Terminal UI (TUI)
```fortran
call ui_init(backend="tui", width=80, height=25, title="My App")
```
- Event-driven with smart timeouts
- Minimal terminal writes via diffing
- Full mouse support

### Graphical UI (GUI)  
```fortran
call ui_init(backend="gui", width=800, height=600, title="My App", &
             target_fps=60, vsync=.true.)
call ui_set_idle_policy("adaptive", idle_fps=12)  ! Optional power saving
```
- VSync-aware rendering
- Configurable frame rate
- Adaptive idle policies

## Current Implementation Status

✅ **fortui_core module**: Complete with `node` and `view` types, lifecycle management  
🚧 **fortui_widgets module**: In development (layout and interactive widgets)  
✅ **Backend selection**: TUI/GUI conditional compilation working  
✅ **Build system**: Automatic dependency detection and configuration  

## Architecture

- **fortui_core**: ✅ Lifecycle management, core types, frame handling  
- **fortui_widgets**: 🚧 Layout containers and interactive controls (coming soon)
- **Dual backends**: ✅ termbox2 (TUI) and raylib/raygui (GUI) support
- **Monospace baseline**: ✅ Ensures pixel-perfect TUI/GUI consistency

## Documentation

- **[Core Types API](docs/CORE_TYPES_API.md)**: Complete `node` and `view` type documentation
- **[Lifecycle API](docs/LIFECYCLE_API.md)**: UI initialization and frame management
- **[Backend Selection](docs/BACKEND_SELECTION.md)**: TUI vs GUI compilation guide  
- **[Developer Guide](docs/DEVELOPER_GUIDE.md)**: Integration patterns and best practices
- **[Build Guide](BUILD_GUIDE.md)**: Dependency setup and build configuration

## License

[License TBD]

## Contributing

[Contributing guidelines TBD]

## Status

🚧 **In Development** - This library is under active development. APIs may change before v1.0 release.
