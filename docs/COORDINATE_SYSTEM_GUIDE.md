# Coordinate System Guide

Complete guide to fortui's coordinate conversion system for seamless TUI/GUI compatibility.

## Overview

fortui uses a unified coordinate system that automatically converts between density-independent pixels (dp) and terminal cells. This ensures perfect visual parity between TUI and GUI backends while maintaining cell-aligned rendering in terminals.

## Quick Start

```fortran
program coordinate_demo
  use fortui_core
  use fortui_units
  implicit none

  type(node) :: ui
  
  ! Initialize TUI backend (coordinates work identically in GUI)
  call ui_init("tui", 80, 25, "Coordinate Demo")
  
  ! All coordinates automatically convert to terminal cells
  ui = column(gap=dp(16.0), children=[ &    ! 16dp gap → ~1 cell
    row(gap=cw(2.0), children=[ &          ! 2 cell widths gap
      node(), node() ]), &
    column(gap=ch(1.0), children=[ &       ! 1 cell height gap
      node(), node() ]) ])
  
  call ui_present(ui)  ! Perfect cell alignment
  call ui_shutdown()
end program
```

## Coordinate Systems

### Density-Independent Pixels (dp)

The base unit for cross-backend compatibility:

```fortran
use fortui_units, only: dp

! Density-independent pixels are the foundation
real :: width_dp = 40.0        ! 40 density-independent pixels
width_dp = dp(40.0)            ! Explicit dp constructor

! Benefits:
! - Consistent sizing across backends
! - Automatic scaling for different displays
! - Backend-agnostic measurements
! - Foundation for all other units
```

**Default Context Values:**
```fortran
! TUI backend cell dimensions (configurable)
type(ui_context) :: ctx
ctx%cell_w_dp = 8.0      ! Terminal cell width in dp
ctx%cell_h_dp = 16.0     ! Terminal cell height in dp
ctx%dpi_scale = 1.0      ! TUI always uses 1.0 scale

! GUI backend adapts to actual display DPI
! ctx%dpi_scale = 1.5   ! High-DPI display example
```

### Cell Units (TUI-Optimized)

Direct cell measurements for perfect terminal alignment:

```fortran
use fortui_units, only: cw, ch

! Cell width units - perfect for terminal columns
layout = row(gap=cw(2.0))      ! 2 terminal columns gap
width = cw(10.0)               ! 10 terminal columns wide

! Cell height units - perfect for terminal rows  
layout = column(gap=ch(1.0))   ! 1 terminal row gap
height = ch(3.0)               ! 3 terminal rows tall

! Conversion to dp:
! cw(2.0) = 2.0 * 8.0 = 16.0 dp
! ch(1.0) = 1.0 * 16.0 = 16.0 dp
```

### All Unit Types

Complete unit type support:

```fortran
use fortui_units, only: dp, em, sp, px, cw, ch

! Different unit types for different purposes
layout = column(gap=dp(12.0))   ! Device-independent pixels
layout = column(gap=em(1.0))    ! Relative to font size (16dp)
layout = column(gap=sp(14.0))   ! Scaled pixels (accessibility)
layout = column(gap=px(10.0))   ! Physical pixels
layout = column(gap=cw(2.0))    ! Cell widths (TUI-friendly)
layout = column(gap=ch(1.0))    ! Cell heights (TUI-friendly)
layout = column(gap=16.0)       ! Bare real (treated as dp)
```

## Automatic Conversion

### Cell Snapping

Coordinates automatically snap to cell boundaries in TUI backend:

```fortran
! Internal conversion process (automatic and transparent)
real :: dp_x = 12.5, dp_y = 25.3
integer :: cell_x, cell_y

! Automatic conversion with snapping
call dp_to_cell_coords(dp_x, dp_y, cell_x, cell_y)
! dp_x = 12.5 → cell_x = 2 (12.5 / 8.0 = 1.56 → rounded to 2)
! dp_y = 25.3 → cell_y = 2 (25.3 / 16.0 = 1.58 → rounded to 2)

! Result: Perfect cell alignment, no sub-pixel positioning
```

### Context-Aware Conversion

Conversion uses current UI context:

```fortran
use fortui_units, only: convert_to_dp, ui_get_context, ui_set_context

! Get current context
type(ui_context) :: ctx
call ui_get_context(ctx)

! Convert units using context
real :: result_dp = convert_to_dp(cw(2.0), ctx)
! result_dp = 2.0 * ctx%cell_w_dp = 2.0 * 8.0 = 16.0

! Customize context for different terminals
ctx%cell_w_dp = 10.0   ! Wider cells
ctx%cell_h_dp = 20.0   ! Taller cells
call ui_set_context(ctx)

! All subsequent conversions use new context
result_dp = convert_to_dp(cw(2.0), ctx)
! result_dp = 2.0 * 10.0 = 20.0
```

## Layout Coordinate Integration

### Column Layouts

Vertical layouts use height-based coordinates:

```fortran
use fortui_core, only: column
use fortui_units, only: dp, ch

! Column layout with various gap units
type(node) :: vertical_ui

vertical_ui = column(gap=dp(16.0), children=[ &
  node(), &  ! Child 1 at (0, 0)
  node(), &  ! Child 2 at (0, 16dp) → cell (0, 1)
  node() ])  ! Child 3 at (0, 32dp) → cell (0, 2)

! Cell-optimized version
vertical_ui = column(gap=ch(1.0), children=[ &
  node(), &  ! Child 1 at (0, 0)
  node(), &  ! Child 2 at (0, 16dp) → cell (0, 1)
  node() ])  ! Child 3 at (0, 32dp) → cell (0, 2)

! Both produce identical cell positions
```

### Row Layouts

Horizontal layouts use width-based coordinates:

```fortran
use fortui_core, only: row
use fortui_units, only: dp, cw

! Row layout with various gap units  
type(node) :: horizontal_ui

horizontal_ui = row(gap=dp(16.0), children=[ &
  node(), &  ! Child 1 at (0, 0)
  node(), &  ! Child 2 at (64dp, 0) → cell (8, 0)
  node() ])  ! Child 3 at (128dp, 0) → cell (16, 0)

! Cell-optimized version
horizontal_ui = row(gap=cw(2.0), children=[ &
  node(), &  ! Child 1 at (0, 0)
  node(), &  ! Child 2 at (16dp, 0) → cell (2, 0)
  node() ])  ! Child 3 at (32dp, 0) → cell (4, 0)

! More compact cell positioning
```

### Nested Layouts

Complex layouts combine both coordinate systems:

```fortran
! Complex nested layout with mixed units
type(node) :: sidebar, content, app_ui

! Sidebar uses cell units for precise terminal control
sidebar = column(gap=ch(1.0), children=[ &
  node(), &  ! Nav item 1
  node(), &  ! Nav item 2  
  node() ])  ! Nav item 3

! Content uses dp units for cross-backend consistency
content = column(gap=dp(24.0), children=[ &
  node(), &  ! Content section 1
  node() ])  ! Content section 2

! Main layout combines both approaches
app_ui = row(gap=cw(3.0), children=[sidebar, content])
!              ↑ Cell gap for terminal alignment
```

## Performance Optimization

### Cell-Aligned Layouts

Design layouts that align naturally to cell boundaries:

```fortran
! Optimized for terminal rendering
type(node) :: optimized_ui

! Use cell units for gaps - no conversion needed
optimized_ui = column(gap=ch(1.0), children=[ &
  row(gap=cw(2.0), children=[ &
    node(), node() ]), &
  row(gap=cw(1.0), children=[ &
    node(), node(), node() ]) ])

! Benefits:
! - Perfect cell alignment
! - No rounding errors
! - Optimal terminal rendering  
! - Consistent visual spacing
```

### Avoid Sub-Cell Positioning

Prevent unnecessary coordinate calculations:

```fortran
! Inefficient - requires conversion and rounding
layout = column(gap=dp(5.5))    ! 5.5dp → 0.34 cells → rounded
layout = row(gap=dp(3.7))       ! 3.7dp → 0.46 cells → rounded

! Efficient - direct cell alignment
layout = column(gap=ch(1.0))    ! Exactly 1 cell
layout = row(gap=cw(1.0))       ! Exactly 1 cell

! Good compromise - dp values that align to cells
layout = column(gap=dp(16.0))   ! 16dp = 1 cell exactly
layout = row(gap=dp(8.0))       ! 8dp = 1 cell exactly
```

### Context Optimization

Customize context for specific terminal configurations:

```fortran
program context_optimization
  use fortui_core
  use fortui_units
  implicit none
  
  type(ui_context) :: ctx
  type(node) :: ui
  
  call ui_init("tui", 80, 25, "Optimized App")
  
  ! Get current context
  call ui_get_context(ctx)
  
  ! Optimize for specific terminal
  ! Example: Terminal with different font metrics
  ctx%cell_w_dp = 9.0    ! Slightly wider cells
  ctx%cell_h_dp = 18.0   ! Slightly taller cells
  call ui_set_context(ctx)
  
  ! All layouts now use optimized context
  ui = column(gap=cw(1.0))  ! Uses 9.0dp per cell width
  
  call ui_present(ui)
  call ui_shutdown()
end program
```

## Cross-Backend Compatibility

### Identical Visual Results

Same layout produces identical appearance:

```fortran
! This layout looks identical in TUI and GUI
type(node) :: cross_backend_ui

cross_backend_ui = column(gap=dp(16.0), children=[ &
  row(gap=dp(8.0), children=[ &
    node(), node() ]), &
  node() ])

! TUI rendering:
! - dp(16.0) → 1 cell height gap
! - dp(8.0) → 1 cell width gap
! - Perfect cell alignment

! GUI rendering:
! - dp(16.0) → 16 pixels gap  
! - dp(8.0) → 8 pixels gap
! - Subpixel precision maintained
```

### Unit Selection Guidelines

Choose appropriate units for different scenarios:

```fortran
! Cross-backend layouts - use dp units
layout = column(gap=dp(16.0))   ! Consistent across backends

! TUI-optimized layouts - use cell units  
layout = column(gap=ch(1.0))    ! Perfect for terminals

! Font-relative layouts - use em units
layout = column(gap=em(1.0))    ! Scales with font size

! Accessibility layouts - use sp units
layout = column(gap=sp(12.0))   ! Scales with user preferences

! Pixel-perfect layouts - use px units
layout = column(gap=px(10.0))   ! Exact pixel control (GUI only)

! Default layouts - use bare reals
layout = column(gap=16.0)       ! Treated as dp, most common
```

## Testing Coordinates

### Visual Verification

Verify coordinate calculations visually:

```fortran
program coordinate_test
  use fortui_core
  use fortui_units
  implicit none
  
  type(node) :: test_ui
  integer :: i
  
  call ui_init("tui", 80, 25, "Coordinate Test")
  
  ! Create test pattern for visual verification
  allocate(children(5))
  do i = 1, 5
    children(i) = node()  ! Will show as markers when widgets available
  end do
  
  ! Test different gap sizes
  test_ui = column(gap=ch(1.0), children=children)  ! 1 cell gaps
  call ui_present(test_ui)
  
  ! TODO: Add visual markers when widget system available
  ! Each child should appear exactly 1 cell apart
  
  call ui_shutdown()
end program
```

### Measurement Validation

Validate coordinate calculations programmatically:

```fortran
program measurement_test
  use fortui_units
  implicit none
  
  type(ui_context) :: ctx
  real :: result_dp
  
  ! Get standard context
  call ui_get_context(ctx)
  
  ! Test cell unit conversions
  result_dp = convert_to_dp(cw(1.0), ctx)
  if (abs(result_dp - 8.0) < 0.001) then
    print *, "✓ Cell width conversion correct"
  else
    print *, "✗ Cell width conversion error:", result_dp
  end if
  
  result_dp = convert_to_dp(ch(1.0), ctx)
  if (abs(result_dp - 16.0) < 0.001) then
    print *, "✓ Cell height conversion correct"
  else
    print *, "✗ Cell height conversion error:", result_dp
  end if
  
  ! Test dp passthrough
  result_dp = convert_to_dp(dp(10.0), ctx)
  if (abs(result_dp - 10.0) < 0.001) then
    print *, "✓ DP passthrough correct"
  else
    print *, "✗ DP passthrough error:", result_dp
  end if
  
  print *, "Coordinate system validation complete"
end program
```

## Best Practices

### Layout Design

Design for optimal coordinate usage:

```fortran
! 1. Use cell units for TUI-optimized layouts
ui = column(gap=ch(1.0))    ! Perfect terminal spacing
ui = row(gap=cw(2.0))       ! Clean column separation

! 2. Use dp units for cross-backend layouts
ui = column(gap=dp(16.0))   ! Consistent across TUI/GUI

! 3. Combine units strategically
main_layout = row(gap=cw(3.0), children=[ &  ! Cell gap for separation
  column(gap=dp(12.0), children=[...]), &    ! DP gaps for content
  column(gap=ch(1.0), children=[...]) ])     ! Cell gaps for navigation

! 4. Avoid fractional cell positions
gap = dp(4.0)    ! 0.5 cells - will round
gap = dp(8.0)    ! 1.0 cells - perfect alignment
gap = dp(16.0)   ! 2.0 cells - perfect alignment
```

### Performance Tips

Optimize coordinate calculations:

```fortran
! 1. Cache frequently used layouts
type(node), save :: cached_sidebar
logical, save :: sidebar_built = .false.

if (.not. sidebar_built) then
  cached_sidebar = column(gap=ch(1.0), children=[...])
  sidebar_built = .true.
end if

! 2. Use direct cell units when possible
layout = row(gap=cw(2.0))   ! No conversion needed
layout = column(gap=ch(1.0)) ! Direct cell positioning

! 3. Minimize context changes
! Set context once at startup, avoid frequent updates

! 4. Pre-calculate complex layouts
! Build complex layouts once, reuse when possible
```

### Debugging Coordinates

Debug coordinate issues effectively:

```fortran
program debug_coordinates
  use fortui_units
  implicit none
  
  type(ui_context) :: ctx
  real :: dp_value
  integer :: cell_x, cell_y
  
  ! Print current context
  call ui_get_context(ctx)
  print *, "Cell dimensions:", ctx%cell_w_dp, "x", ctx%cell_h_dp
  print *, "DPI scale:", ctx%dpi_scale
  
  ! Test coordinate conversion
  dp_value = convert_to_dp(cw(5.0), ctx)
  print *, "cw(5.0) =", dp_value, "dp"
  
  dp_value = convert_to_dp(ch(3.0), ctx)
  print *, "ch(3.0) =", dp_value, "dp"
  
  ! Test cell snapping
  call dp_to_cell_coords(12.5, 25.3, cell_x, cell_y)
  print *, "dp(12.5, 25.3) → cell(", cell_x, ",", cell_y, ")"
  
  ! Verify round-trip conversion
  dp_value = real(cell_x) * ctx%cell_w_dp
  print *, "Back to dp:", dp_value
end program
```

## Troubleshooting

### Alignment Issues

Fix visual alignment problems:

```fortran
! Problem: Elements don't align to cell boundaries
layout = column(gap=dp(5.0))    ! 5dp = 0.625 cells

! Solution: Use cell-aligned values
layout = column(gap=dp(8.0))    ! 8dp = 1 cell exactly
layout = column(gap=ch(1.0))    ! Direct cell reference
```

### Size Inconsistencies

Resolve size differences between backends:

```fortran
! Problem: Different sizes in TUI vs GUI
layout = column(gap=px(10.0))   ! Pixel units don't scale

! Solution: Use density-independent units
layout = column(gap=dp(10.0))   ! Scales appropriately
layout = column(gap=em(0.8))    ! Relative to font size
```

### Context Problems

Fix context-related issues:

```fortran
! Problem: Unexpected coordinate behavior
! Check context settings
type(ui_context) :: ctx
call ui_get_context(ctx)
print *, "Context:", ctx%cell_w_dp, ctx%cell_h_dp, ctx%dpi_scale

! Reset to defaults if needed
ctx = ui_context()  ! Default values
call ui_set_context(ctx)
```

## Next Steps

- **TUI Backend**: Complete TUI documentation in [TUI_BACKEND_GUIDE.md](TUI_BACKEND_GUIDE.md)
- **Units System**: Detailed units reference in [UNITS_GUIDE.md](UNITS_GUIDE.md)
- **Layout System**: Layout fundamentals in [LAYOUT_API.md](LAYOUT_API.md)
- **Backend Selection**: Choose optimal backend in [BACKEND_SELECTION.md](BACKEND_SELECTION.md)