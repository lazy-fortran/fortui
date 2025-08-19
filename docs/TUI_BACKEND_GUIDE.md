# TUI Backend Guide

Terminal UI backend with termbox2 integration, visual widget rendering, and production-ready cell-based display.

## Quick Setup

```bash
# Build termbox2 dependency
./tools/build_fortui.sh build

# Compile with TUI backend
fpm build
fpm run --example tui_rendering_demo
```

## Basic Usage

```fortran
program tui_app
  use fortui
  implicit none
  type(node) :: ui
  logical :: running

  call ui_init(backend="tui", width=80, height=25, title="Demo")
  
  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)
    ui = column(gap=ch(1.0), children=[node(), node()])
    call ui_present(ui)
    running = .not. ui_should_close()
  end do

  call ui_shutdown()
end program
```

## Visual Rendering System

The TUI backend renders widgets as visual characters:

```fortran
! Layout visualization
ui = column(gap=dp(2.0))  ! Renders as '|' characters
ui = row(gap=dp(4.0))     ! Renders as '-' characters
! Content placeholders render as '*' characters
```

**Layout Characters:**
- Column layouts: `|` (vertical bars)
- Row layouts: `-` (horizontal bars)  
- Content markers: `*` (asterisks)

**Timeout Configuration:**
- Idle: 250-1000ms
- Interactive: 16-33ms
- Event coalescing: 10-20ms

## Cell-Based Display

Terminal rendering using cell grid with coordinate snapping:

```fortran
! All coordinates snap to cell boundaries
ui = column(gap=dp(16.0))  ! Auto-snaps to cells
ui = row(gap=cw(2.0))      ! Direct cell units
```

**Cell Properties:**
- Default size: 8×16 dp per cell
- Automatic coordinate snapping
- Perfect TUI/GUI alignment

## Performance Features

```fortran
call ui_present(ui)  ! Only changed cells update
```

**Optimizations:**
- Front/back buffer diffing
- Line-level hashing
- Minimal terminal writes
- SSH-optimized updates

## Termbox2 Integration

```fortran
call ui_init("tui", 80, 25, "App")  ! Automatic setup
```

**Features:**
- Alternate screen buffer
- Raw input mode
- Mouse support (clicks, wheel, motion)
- Resize handling
- 256-color support

## Quit Detection

```fortran
running = .not. ui_should_close()  ! Automatic quit detection
```

**Quit Triggers:**
- ESC key
- Ctrl+C, Ctrl+D
- Terminal disconnect
- Window close

## Build Requirements

```bash
# Install termbox2 dependency
./tools/build_fortui.sh build

# Compile TUI-only version
DISABLE_GUI=1 fpm build

# Test functionality
fpm run --example tui_rendering_demo
```

**Dependencies:**
- termbox2 library (auto-built)
- Mock termbox2 for testing
- No external GUI dependencies

## Units & Coordinates

```fortran
use fortui_units

! All unit types supported
layout = column(gap=dp(12.0))  ! Density pixels
layout = column(gap=cw(2.0))   ! Cell widths
layout = column(gap=ch(1.0))   ! Cell heights
```

**Cell Conversion:**
- Auto-snapping to cell boundaries
- Default: 8×16 dp per cell
- Perfect alignment guaranteed

## Widget System

```fortran
! Nested layouts with visual rendering
sidebar = column(gap=ch(1.0), children=[node(), node()])
content = column(gap=dp(16.0), children=[node(), node()])
app_ui = row(gap=cw(3.0), children=[sidebar, content])
call ui_present(app_ui)
```

**Rendering:**
- Layout containers: `|` and `-` characters
- Content placeholders: `*` characters
- Perfect cell positioning
- Color/style support

## Testing & Validation

```bash
# Run visual rendering test
fpm run --example tui_rendering_demo

# Expected output: Layout visualization with |, -, * characters
# Automatic quit after 5 frames
```

**Mock Terminal:**
- No termbox2 dependency for tests
- Simulated events and rendering
- Automatic validation

## Implementation Status

✅ **Complete TUI Backend:**
- Real termbox2 C library bindings
- Visual widget rendering system
- Event-driven architecture (keyboard, mouse, resize)
- Cell-based coordinate system
- Front/back buffer optimization
- Production-ready build integration

**Current Build Mode:**
- Uses mock termbox2 for FPM compatibility
- Real termbox2 available via build script
- Visual rendering fully functional

## Best Practices

```fortran
! Responsive terminal design
if (term_width >= 120) then
  ui = row(gap=cw(2.0), children=[node(), node(), node()])
else
  ui = column(gap=ch(1.0), children=[node(), node()])
end if

! Performance optimization
call ui_frame_begin(250)   ! Idle: longer timeout
call ui_frame_begin(16)    ! Interactive: shorter timeout

! Cell-friendly units
layout = row(gap=cw(2.0))     ! Perfect cell alignment
layout = column(gap=ch(1.0))  ! No sub-cell calculations
```

## Troubleshooting

**Size Issues:**
```fortran
call ui_init("tui", 80, 25, "App")  ! Safe defaults
```

**Event Problems:**
```fortran
call ui_frame_begin(0)    ! Immediate polling
call ui_frame_begin(500)  ! Longer timeout
```

**SSH/Environment:**
```bash
export TERM=xterm-256color
export COLORTERM=truecolor
```

## Next Steps

- [Layout System](LAYOUT_API.md) - Layout basics
- [Units System](UNITS_GUIDE.md) - Coordinate system  
- [Backend Selection](BACKEND_SELECTION.md) - TUI vs GUI
- [Build Setup](../BUILD_GUIDE.md) - Dependencies

