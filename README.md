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

## Core Concepts

### Grid Units
All dimensions use **grid units (gu)**:
- **TUI**: 1 gu = 1 terminal cell
- **GUI**: 1 gu = 1 monospace character width/height

### Widget IDs
Each widget requires a unique string ID for state management:
```fortran
! ID is used internally to maintain widget state
logical :: clicked = button("my_button", "Click me")
```

### Immediate Mode
Widgets are declared, rendered, and updated in a single call:
```fortran
! This single call: declares widget, renders it, updates value, returns change status
logical :: changed = slider("volume", 0.0, 1.0, 0.1, volume_level)
```

## API Reference

### Core Functions

```fortran
! Initialize UI system
call ui_init(backend, width, height, title [, target_fps, vsync])

! Frame lifecycle
call ui_frame_begin(timeout_ms)  ! TUI: event timeout; GUI: ignored
call ui_present(tree)            ! Render widget tree
logical :: should_exit = ui_should_close()

! Cleanup
call ui_shutdown()
```

### Layout Widgets

```fortran
! Vertical layout
type(node) :: col = column([gap], [children])

! Horizontal layout  
type(node) :: row = row([gap], [children])
```

### Control Widgets

```fortran
! Button - returns true when clicked
logical :: clicked = button(id [, label])

! Slider - updates value, returns true when changed
logical :: changed = slider(id, min_val, max_val, step, value)

! Checkbox - toggles value when clicked
call checkbox(id, checked_state)

! Text display
call text(id, content)

! Viewport with pan/zoom - returns true when view changed
logical :: view_changed = viewport(id, width, height, view_state)
```

## Complete Example

```fortran
program plot_demo
  use fortui_core
  use fortui_widgets
  implicit none

  real :: gain = 1.0
  logical :: show_grid = .false.
  type(view) :: plot_view
  class(node), allocatable :: ui
  logical :: running

  call ui_init(backend="tui", width=100, height=35, title="Plot Demo")

  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)

    ! Build UI tree declaratively
    ui = column(gap=1, children=[ &
           row(gap=1, children=[ &
             button("zoom_in", "+"), &
             button("zoom_out", "-"), &
             slider("gain", 0.1, 5.0, 0.1, gain), &
             checkbox("grid", show_grid) ]), &
           viewport("plot", 80, 24, plot_view), &
           text("status", format_status(gain, plot_view, show_grid)) ])

    ! React to interactions
    if (button("zoom_in", "+"))  call zoom(plot_view, 1.2)
    if (button("zoom_out", "-")) call zoom(plot_view, 1.0/1.2)

    call ui_present(ui)
    running = .not. ui_should_close()
  end do

  call ui_shutdown()

contains
  subroutine zoom(v, factor)
    type(view), intent(inout) :: v
    real, intent(in) :: factor
    v%scale_x = v%scale_x * factor
    v%scale_y = v%scale_y * factor
  end subroutine

  function format_status(g, v, grid) result(status)
    real, intent(in) :: g
    type(view), intent(in) :: v
    logical, intent(in) :: grid
    character(len=:), allocatable :: status
    character(len=128) :: buffer
    
    write(buffer, '("gain=",F4.2," scale=(",F4.2,",",F4.2,") grid=",L1)') &
          g, v%scale_x, v%scale_y, grid
    status = trim(buffer)
  end function
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

## Architecture

- **fortui_core**: Lifecycle management, core types, frame handling
- **fortui_widgets**: Layout containers and interactive controls
- **Dual backends**: termbox2 (TUI) and raylib/raygui (GUI)
- **Monospace baseline**: Ensures pixel-perfect TUI/GUI consistency

## License

[License TBD]

## Contributing

[Contributing guidelines TBD]

## Status

🚧 **In Development** - This library is under active development. APIs may change before v1.0 release.
