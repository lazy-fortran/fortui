# fortui

Immediate-mode UI library for modern Fortran with dual backends: terminal (TUI via termbox2) and graphical (GUI via raylib).

## Quick Start

```bash
git clone git@github.com:lazy-fortran/fortui.git
cd fortui
fpm build
fpm run --example tui_demo
```

## Usage

```fortran
program my_app
use fortui
implicit none

type(node) :: tree
real :: volume = 50.0
logical :: muted = .false.

call ui_init("tui", 80, 24, "My App")
tree = column()

do while (.not. ui_should_close())
    call ui_frame_begin()

    call text("title", "Settings")
    if (button("save", "Save")) print *, "Saved!"
    if (slider("vol", value=volume)) print *, volume
    if (checkbox("mute", muted, "Mute")) print *, muted

    call ui_present(tree)
end do

call ui_shutdown()
end program
```

## Controls

- **Mouse click** - interact with widgets
- **Tab** - cycle keyboard focus
- **Enter / Space** - activate button or toggle checkbox
- **Left / Right** - adjust slider
- **ESC / Ctrl+C** - quit

## Public API

Everything via `use fortui`:

```fortran
! Lifecycle
call ui_init(backend, width, height, title [, target_fps, vsync])
call ui_frame_begin([timeout_ms])
call ui_present(tree)
ui_should_close()  ! returns logical
call ui_shutdown()

! Widgets (return .true. on interaction)
button(id [, label, width, height])
text(id [, value, text_size, width, height])  ! subroutine
slider(id [, min_val, max_val, step_val, value, width, height])
checkbox(id, checked [, label, width, height])
viewport(id, width, height, view_state)

! Layout
column([gap, children])  ! returns node
row([gap, children])      ! returns node
column_begin([gap]) / column_end()
row_begin([gap]) / row_end()

! Types: node, view
```

## Backends

**TUI** (termbox2) - always available, terminal rendering:
```bash
fpm run --example tui_demo
```

**GUI** (raylib) - optional, graphical window:
```bash
sudo pacman -S raylib  # or equivalent
make build-gui
FPM_FFLAGS="-cpp -DENABLE_TUI=1 -DENABLE_GUI=1" \
FPM_LDFLAGS="-lraylib" fpm run --example gui_demo
```

## Architecture

10 source modules, ~3200 lines. No OO abstractions, no procedure pointers, no class(*) polymorphism. Simple integer dispatch for backend selection. Flat discriminated-union widget state. Designed for future lfortran/WASM compatibility.

```
fortui.f90           -> public API re-export
fortui_core.f90      -> lifecycle, backend detection/dispatch
fortui_context.f90   -> widget state map, context types
fortui_render.f90    -> color constants, backend dispatch flag
fortui_input.f90     -> input state, focus tracking
fortui_layout.f90    -> layout stack, node type, constructors
fortui_tui.f90       -> TUI backend (termbox2 C bindings)
fortui_gui.f90       -> GUI backend (raylib C bindings)
fortui_widgets.f90   -> button, text, slider, checkbox, viewport
fortui_error.f90     -> error reporting
```

## lfortran Status

9 of 10 modules compile with lfortran 0.61.0. Blocker: lfortran/lfortran#10902 (compiler crash on fortui_core.f90).

## Prerequisites

- gfortran 9+ (or lfortran for experimental WASM builds)
- fpm (Fortran Package Manager)
- termbox2 (embedded)
- raylib (optional, for GUI backend)

## License

MIT
