# fortui

Immediate-mode UI library for modern Fortran with dual backends: terminal (TUI) and graphical (GUI).

## Quick Start

```bash
git clone https://github.com/krystophny/fortui.git
cd fortui
fpm build
fpm test
fpm run --example simple_test
```

## Usage

```fortran
program my_app
  use fortui
  implicit none

  real :: volume = 50.0
  logical :: muted = .false.

  call ui_init("tui", 80, 24, "My App")

  do while (.not. ui_should_close())
    call ui_frame_begin()

    if (button("save", label="Save")) print *, "Saved!"
    call text("title", "Settings")
    if (slider("vol", volume, 0.0, 100.0)) print *, "Volume:", volume
    if (checkbox("mute", muted, "Mute")) print *, "Muted:", muted

    call ui_present(node())
  end do

  call ui_shutdown()
end program
```

## Public API

Everything is available via `use fortui`:

```fortran
! Lifecycle
call ui_init(backend, width, height, title [, target_fps, vsync])
call ui_frame_begin([timeout_ms])
call ui_present(tree)
logical = ui_should_close()
call ui_shutdown()
call ui_set_idle_policy(mode [, idle_fps])

! Widgets - return .true. on interaction
logical = button(id [, label, width, height])
call text(id [, value, text_size, width, height])
logical = slider(id [, min_val, max_val, step_val, value, width, height])
logical = checkbox(id, checked [, label, width, height])
logical = viewport(id, width, height, view_state)

! Layout
type(node) = column([gap, children])
type(node) = row([gap, children])
```

### Types

Only two types are exposed:

```fortran
type :: node
    character(len=32) :: layout_type = "none"
    real :: gap_dp = 0.0
    type(node), allocatable :: children(:)
end type node

type :: view
    real :: scale_x = 1.0
    real :: scale_y = 1.0
    real :: off_x = 0.0
    real :: off_y = 0.0
end type view
```

## Layout

```fortran
type(node) :: ui

! Vertical layout with gap
ui = column(gap=1.0, children=[row(gap=2.0), row(gap=2.0)])

! Horizontal layout
ui = row(gap=2.0, children=[node(), node()])
```

## Backends

- **TUI** (termbox2): Always available. Event-driven terminal rendering with diff-based output.
- **GUI** (raylib): Optional. Planned for future implementation.

```fortran
call ui_init("tui", 80, 24, "Terminal App")
call ui_init("auto", 80, 24, "Auto-detect")
```

## Prerequisites

- Modern Fortran compiler (gfortran 9+)
- fpm (Fortran Package Manager)
- termbox2 (embedded in project)

## License

[License TBD]

## Status

In development. Core API is stable. TUI widget rendering and input handling are the next milestones.
