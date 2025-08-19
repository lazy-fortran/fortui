# TUI Backend User Guide

Complete guide to using fortui's terminal user interface backend with termbox2 integration.

## Overview

The TUI backend provides a high-performance terminal-based interface using the termbox2 library. It offers event-driven interaction, cell-based rendering, and efficient screen updates through diff-based optimization.

## Quick Start

```fortran
program tui_app
  use fortui_core
  use fortui_units
  implicit none

  type(node) :: ui
  logical :: running

  ! Initialize TUI backend
  call ui_init(backend="tui", width=80, height=25, title="TUI Demo")
  
  running = .true.
  do while (running)
    ! Event-driven frame with 200ms timeout
    call ui_frame_begin(timeout_ms=200)
    
    ! Build UI tree
    ui = column(gap=ch(1.0), children=[ &
      node(), node() ])  ! Placeholder nodes
    
    ! Render to terminal
    call ui_present(ui)
    
    ! Check for quit conditions (ESC, Ctrl+C, etc.)
    running = .not. ui_should_close()
  end do

  call ui_shutdown()
end program
```

## Core Features

### Event-Driven Model

The TUI backend uses an event-driven architecture with configurable timeouts:

```fortran
! Different timeout strategies for various use cases
call ui_frame_begin(timeout_ms=250)  ! Idle timeout (250-1000ms)
call ui_frame_begin(timeout_ms=16)   ! Fast updates (16-33ms for dragging)
call ui_frame_begin(timeout_ms=10)   ! Event coalescing (10-20ms)
call ui_frame_begin(timeout_ms=0)    ! Immediate return
```

**Timeout Guidelines:**
- **Idle applications**: 250-1000ms for power efficiency
- **Interactive dragging**: 16-33ms for smooth feedback
- **Event coalescing**: 10-20ms to batch rapid events
- **Non-blocking polling**: 0ms for immediate return

### Cell-Based Rendering

The TUI backend renders to a terminal cell grid with automatic coordinate conversion:

```fortran
use fortui_units, only: dp, ch, cw

! Coordinates automatically convert to cell positions
ui = column(gap=dp(16.0))   ! Converts to cell boundaries
ui = row(gap=cw(2.0))       ! Direct cell width units
ui = column(gap=ch(1.0))    ! Direct cell height units
```

**Cell Coordinate System:**
- Terminal cells are the atomic rendering unit
- dp coordinates snap to cell boundaries automatically
- Cell dimensions configurable via `ui_context` (default: 8×16 dp)
- Perfect alignment between TUI and GUI backends

### Diff-Based Updates

Efficient screen updates through front/back buffer comparison:

```fortran
! Automatic diff optimization - no user intervention needed
call ui_present(ui)  ! Only changed cells update on screen

! Benefits:
! - Minimizes terminal writes for better performance
! - Reduces flicker and screen tearing
! - Optimizes bandwidth over SSH connections
! - Per-line hashing for rapid change detection
```

## Terminal Integration

### Termbox2 Library

The TUI backend uses termbox2 for low-level terminal control:

```fortran
! Automatic termbox2 initialization and configuration
call ui_init("tui", 80, 25, "My App")

! Features provided by termbox2:
! - Alternate screen buffer (preserves user's terminal)
! - Raw mode input (no line buffering)
! - Mouse support (clicks, motion, wheel)
! - Signal handling (resize, interrupts)
! - Cross-platform compatibility
```

**Termbox2 Features:**
- **Alternate screen**: User's terminal state preserved
- **Raw mode**: Direct key input without buffering
- **Mouse support**: Full mouse interaction support
- **Signal handling**: Graceful resize and interrupt handling
- **Color support**: 256-color and truecolor capabilities

### Quit Detection

Multiple quit mechanisms for user convenience:

```fortran
! Automatic quit detection
logical :: should_exit = ui_should_close()

! Detects these quit conditions:
! - ESC key press
! - Ctrl+C (SIGINT)
! - Ctrl+D (EOF)
! - Ctrl+Z (with proper handling)
! - Terminal disconnect (SIGHUP)
! - Window close events
! - Application-level quit state
```

## Performance Optimization

### Event Coalescing

Rapid events are automatically coalesced for performance:

```fortran
! Automatic event coalescing (no user configuration needed)
call ui_frame_begin(timeout_ms=10)  ! Enables coalescing

! Coalesced events:
! - Mouse motion events (keeps only latest position)
! - Key repeat events (optimized for continuous input)
! - Resize events (handles rapid terminal resizing)
! - Critical events always preserved (clicks, special keys)
```

### Buffer Management

Front/back buffer system minimizes terminal writes:

```fortran
! Buffer management is automatic and transparent
call ui_present(ui)

! Internal optimization:
! - Front buffer: current terminal state
! - Back buffer: new frame to render  
! - Line hashing: rapid change detection
! - Diff calculation: only update changed regions
! - Write coalescing: batch terminal operations
```

### Memory Management

Efficient memory usage with automatic cleanup:

```fortran
! Automatic memory management - no manual cleanup needed
type(tui_state_t) :: tui_state  ! Internal state management

! Features:
! - Cell buffers allocated on demand
! - Automatic deallocation on resize
! - Line hash caching for diff optimization
! - Safe cleanup on shutdown
! - No memory leaks or corruption
```

## Coordinate System

### Units Conversion

The TUI backend integrates seamlessly with fortui's units system:

```fortran
use fortui_units, only: dp, em, sp, px, cw, ch, ui_context

! All unit types supported
layout = column(gap=dp(12.0))   ! Density-independent pixels
layout = column(gap=em(1.0))    ! Relative to font size
layout = column(gap=cw(2.0))    ! Cell widths (TUI-friendly)
layout = column(gap=ch(1.0))    ! Cell heights (TUI-friendly)

! Context-aware conversion
type(ui_context) :: ctx
call ui_get_context(ctx)
! ctx%cell_w_dp = 8.0   ! Cell width in dp
! ctx%cell_h_dp = 16.0  ! Cell height in dp
! ctx%dpi_scale = 1.0   ! TUI always uses 1.0
```

### Cell Snapping

Coordinates automatically snap to cell boundaries:

```fortran
! Automatic snapping - no manual intervention needed
real :: dp_x = 12.5, dp_y = 25.3
integer :: cell_x, cell_y

! Internal conversion (done automatically by TUI backend)
call dp_to_cell_coords(dp_x, dp_y, cell_x, cell_y)
! cell_x = 2 (12.5 / 8.0 ≈ 1.6, rounded to 2)
! cell_y = 2 (25.3 / 16.0 ≈ 1.6, rounded to 2)

! Result: Perfect cell alignment for crisp rendering
```

## Widget Rendering

### Layout Integration

Layouts render perfectly to the terminal grid:

```fortran
use fortui_core, only: column, row, node

! Nested layouts work seamlessly
type(node) :: sidebar, content, app_ui

! Create sidebar with cell-friendly spacing
sidebar = column(gap=ch(1.0), children=[ &
  node(), node(), node() ])  ! Navigation items

! Create main content with dp spacing
content = column(gap=dp(16.0), children=[ &
  node(), node() ])  ! Content sections

! Combine horizontally
app_ui = row(gap=cw(3.0), children=[sidebar, content])

! Render to terminal
call ui_present(app_ui)
```

### Text Rendering

Text content maps directly to terminal cells:

```fortran
! Text rendering features (when widgets module available):
! - Character-perfect positioning
! - Multi-line text flow
! - Text wrapping at cell boundaries
! - Unicode character support
! - Color and style attributes
! - Text alignment options
```

### Color and Styling

Terminal color capabilities are fully utilized:

```fortran
! Color support features:
! - Foreground/background colors
! - 256-color palette support
! - Truecolor support (when available)
! - Text attributes (bold, italic, underline)
! - Automatic capability detection
! - Graceful degradation for limited terminals
```

## Error Handling

### Graceful Degradation

The TUI backend handles errors gracefully:

```fortran
! Automatic error handling
call ui_init("tui", 80, 25, "My App")

! Error conditions handled:
! - Terminal initialization failure
! - Invalid terminal dimensions
! - Signal handling setup failure
! - Memory allocation failure
! - Network disconnection (SSH)
```

### Mock Terminal Support

Testing support without actual terminal:

```fortran
! Automatic mock terminal for testing
! - Simulates terminal capabilities
! - Provides event generation
! - Validates rendering output
! - Enables automated testing
! - No actual termbox2 dependency needed for tests
```

## Build Integration

### Dependencies

The TUI backend requires termbox2:

```bash
# Install termbox2 system-wide
sudo apt-get install libterm*  # Ubuntu/Debian
brew install termbox2          # macOS

# Or let build script handle it automatically
./tools/build_fortui.sh build
fpm build  # TUI backend ready
```

### Compilation

TUI backend is always available:

```bash
# TUI backend included by default
fmp build
fpm run
fpm test

# Explicit TUI-only build (even if GUI available)
DISABLE_GUI=1 fpm build
```

## Best Practices

### Responsive Design

Design for various terminal sizes:

```fortran
! Responsive layout strategies
program responsive_app
  use fortui_core
  implicit none
  
  integer :: term_width, term_height
  type(node) :: ui
  
  ! Initialize with reasonable defaults
  call ui_init("tui", 80, 25, "Responsive App")
  
  ! TODO: Get actual terminal dimensions when available
  ! call get_terminal_size(term_width, term_height)
  
  ! Adapt layout to terminal size
  if (term_width >= 120) then
    ! Wide terminal - use three columns
    ui = row(gap=cw(2.0), children=[ &
      node(), node(), node() ])
  else if (term_width >= 80) then
    ! Standard terminal - use two columns
    ui = row(gap=cw(1.0), children=[ &
      node(), node() ])
  else
    ! Narrow terminal - single column
    ui = column(gap=ch(1.0), children=[ &
      node(), node() ])
  end if
  
  call ui_present(ui)
  call ui_shutdown()
end program
```

### Performance Tips

Optimize for terminal performance:

```fortran
! Performance optimization strategies

! 1. Use appropriate timeouts
call ui_frame_begin(250)  ! Idle apps - longer timeout
call ui_frame_begin(16)   ! Interactive apps - shorter timeout

! 2. Minimize unnecessary redraws
logical :: needs_redraw = .false.
if (data_changed .or. user_input) needs_redraw = .true.
if (needs_redraw) call ui_present(ui)

! 3. Use cell-friendly units
layout = row(gap=cw(2.0))  ! Aligns perfectly to cell grid
layout = column(gap=ch(1.0))  ! No sub-cell calculations

! 4. Batch updates when possible
! Let event coalescing handle rapid events automatically
```

### Accessibility

Ensure terminal compatibility:

```fortran
! Accessibility considerations

! 1. Support limited color terminals
! Colors automatically degrade gracefully

! 2. Provide keyboard-only navigation
! Mouse support is optional enhancement

! 3. Handle various terminal sizes
! Design responsive layouts

! 4. Clear visual hierarchy
! Use whitespace and consistent spacing

! 5. Reasonable default dimensions
call ui_init("tui", 80, 25, "App")  ! Works on most terminals
```

## Troubleshooting

### Common Issues

**Terminal size detection:**
```fortran
! If terminal size detection fails
call ui_init("tui", 80, 25, "App")  ! Use safe defaults
! Terminal will be resized to fit if smaller
```

**Event handling problems:**
```fortran
! If events not detected properly
call ui_frame_begin(0)  ! Try immediate polling
! Or increase timeout for better event capture
call ui_frame_begin(500)  ! Longer timeout
```

**Rendering issues:**
```fortran
! If screen updates don't appear
call ui_shutdown()
call ui_init("tui", 80, 25, "App")  ! Reinitialize
! This resets terminal state
```

### Environment Issues

**SSH connections:**
```bash
# Ensure proper terminal type
export TERM=xterm-256color

# Test termbox2 compatibility
echo $TERM  # Should be recognized terminal type
```

**Color support:**
```bash
# Test color capabilities
tput colors  # Should return 256 or more

# Force color mode if needed
export COLORTERM=truecolor
```

## Testing

### Unit Testing

Comprehensive test coverage:

```fortran
! Tests included in test suite
call test_tui_initialization()      ! Terminal setup
call test_tui_event_polling()       ! Event handling
call test_tui_quit_detection()      ! Quit conditions
call test_tui_coordinate_conversion() ! Units system
call test_tui_cell_rendering()      ! Widget rendering  
call test_tui_diff_updates()        ! Performance optimization
call test_termbox2_integration()    ! C library interface
call test_mock_terminal_capabilities() ! Testing infrastructure
```

### Manual Testing

Interactive testing approaches:

```bash
# Run example applications
fpm run --example layout_demo    # Test layout system
fpm run --example tui_test      # Test TUI features

# Test quit conditions
# - Press ESC to quit
# - Press Ctrl+C to quit
# - Press Ctrl+D to quit
# - Resize terminal window

# Test performance
# - Monitor CPU usage during idle
# - Test responsive behavior during interaction
# - Verify smooth updates during rapid input
```

## Next Steps

- **Layout System**: Learn layout basics in [LAYOUT_API.md](LAYOUT_API.md)
- **Units System**: Understand coordinate system in [UNITS_GUIDE.md](UNITS_GUIDE.md)
- **Backend Selection**: Compare TUI vs GUI in [BACKEND_SELECTION.md](BACKEND_SELECTION.md)
- **Core Types**: Explore fundamental types in [CORE_TYPES_API.md](CORE_TYPES_API.md)
- **Build Setup**: Configure dependencies in [BUILD_GUIDE.md](../BUILD_GUIDE.md)