# TUI Backend Quick Start

Get the TUI backend running in 3 steps with visual widget rendering.

## Setup

```bash
# Build termbox2 dependency
./tools/build_fortui.sh build

# Compile with TUI support
fmp build
```

## Basic Example

```fortran
program tui_demo
  use fortui
  implicit none
  
  type(node) :: ui
  logical :: running
  integer :: frame = 0

  call ui_init("tui", 80, 25, "TUI Demo")
  
  running = .true.
  do while (running .and. frame < 10)
    call ui_frame_begin(timeout_ms=200)
    
    ! Create visual layout
    ui = column(gap=ch(1.0), children=[ &
      row(gap=cw(2.0), children=[node(), node()]), &
      node() ])
    
    call ui_present(ui)
    running = .not. ui_should_close()
    frame = frame + 1
  end do

  call ui_shutdown()
end program
```

## Visual Output

**Layout rendering:**
- `|` = Column layouts (vertical)
- `-` = Row layouts (horizontal) 
- `*` = Content placeholders

**Event handling:**
- ESC, Ctrl+C, Ctrl+D = Quit
- Mouse clicks and motion supported
- Automatic resize handling

## Test

```bash
# Run visual rendering demo
fpm run --example tui_rendering_demo

# Expected: 5 frames with layout visualization
# Auto-quit with character rendering feedback
```

**Next:** [Complete TUI Guide](TUI_BACKEND_GUIDE.md)