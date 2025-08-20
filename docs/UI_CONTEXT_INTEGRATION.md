# UI Context Integration Guide

## Overview

fortui's UI context integration provides automatic measurement-based unit conversion through backend-specific detection systems. Context setup is fully automatic during `ui_init()` with no manual configuration required.

## Automatic Context Setup

Context initialization occurs automatically during `ui_init()` based on the selected backend:

```fortran
use fortui_core
use fortui_unit_types

! TUI: Measures terminal cell dimensions
call ui_init("tui", cw_unit(80.0), ch_unit(25.0), "Terminal App")

! GUI: Detects system DPI, font metrics, accessibility scaling  
call ui_init("gui", dp_unit(800.0), em_unit(30.0), "GUI App")

! Auto: Intelligent backend selection with appropriate measurement
call ui_init("auto", inches_unit(8.5), cm_unit(21.0), "Mixed Units")
```

## Context Parameters

The UI context contains backend-specific measurement values used for unit conversion:

| Parameter | TUI Value | GUI Value | Purpose |
|-----------|-----------|-----------|---------|
| `dpi_scale` | Always 1.0 | System DPI factor | Physical pixel scaling |
| `em_dp` | Font height | Measured font size | Font-relative units |
| `text_scale` | Always 1.0 | Accessibility scaling | Text size scaling |
| `cell_w_dp` | Measured width | Equivalent width | Terminal cell width |
| `cell_h_dp` | Measured height | Equivalent height | Terminal cell height |

## Backend-Specific Measurement

### TUI Backend Measurement

```fortran
! Automatic during ui_init("tui", ...)
! - Measures actual terminal cell dimensions
! - Queries terminal font metrics via terminfo/termcap
! - Falls back to conservative defaults (8x16 pixels)
! - No DPI scaling (always 1.0)
```

### GUI Backend Measurement

```fortran
! Automatic during ui_init("gui", ...)
! - Detects system DPI scaling factor
! - Measures font metrics using raylib
! - Queries accessibility text scaling settings
! - Calculates equivalent cell dimensions
```

## Cross-Platform Support

Context measurement adapts to the target platform:

**Linux:**
- X11/Wayland DPI detection
- fontconfig integration  
- gsettings accessibility queries

**Windows:**
- GetDpiForWindow API
- SystemParametersInfo for accessibility
- High-DPI awareness support

**macOS:**
- NSScreen backingScaleFactor
- NSUserDefaults accessibility integration
- Retina display detection

**Fallback:**
- Conservative defaults for unknown platforms
- Graceful degradation when measurement fails

## Unit Conversion Flow

Abstract units convert to display pixels through the context system:

```fortran
! Example conversion flow
call ui_init("gui", inches_unit(8.5), em_unit(30.0), "App")

! inches_unit(8.5) → 8.5 * 96 * dpi_scale → 816 dp (at 1.0 DPI)
! em_unit(30.0) → 30.0 * em_dp → 480 dp (at 16dp font)
! Final window: 816 x 480 dp
```

## Context Validation

The measurement system includes validation and fallback mechanisms:

```fortran
! Validation checks:
! - DPI scale: 0.5 - 4.0 range
! - Font size: 8 - 72 dp range  
! - Cell dimensions: 4 - 50 dp range
! - Text scale: 0.5 - 3.0 range

! Fallback values when measurement fails:
! - dpi_scale = 1.0
! - em_dp = 16.0
! - text_scale = 1.0
! - cell_w_dp = 8.0, cell_h_dp = 16.0
```

## Performance Optimization

Context measurement is optimized for efficiency:

- **Measurement caching**: Results cached to avoid repeated system calls
- **One-time setup**: Context established once during initialization
- **Efficient conversion**: Simple arithmetic for unit-to-dp conversion
- **Minimal overhead**: Fast polymorphic dispatch for abstract units

## Error Handling

Robust error handling ensures graceful operation:

```fortran
! Measurement failures:
! - System API unavailable → Use cached defaults
! - Invalid measurements → Apply validation bounds
! - Platform unsupported → Conservative fallback values

! Context errors are logged but don't prevent initialization
! Applications continue with fallback context values
```

## Advanced Features

### Runtime Context Updates (Future)

```fortran
! Framework exists for runtime context updates
! Triggered by:
! - DPI changes (monitor switching)
! - Accessibility setting changes
! - Font size changes
! - Terminal resize events

! Note: Currently context is established once during ui_init()
```

### Multi-Monitor Support (Future)

```fortran
! Per-monitor DPI awareness framework in place
! Will support:
! - Window movement between displays
! - Different DPI scaling per monitor
! - Dynamic context switching
```

## Implementation Architecture

Context integration uses a layered approach:

1. **Abstract Interface**: `unit_type` with deferred `to_dp(ctx)` method
2. **Platform Measurement**: Cross-platform measurement APIs
3. **Context Management**: Global context storage and lifecycle
4. **Validation System**: Bounds checking and fallback handling
5. **Backend Integration**: TUI/GUI specific measurement routines

## Usage Patterns

### Standard Application

```fortran
program standard_app
  use fortui_core
  use fortui_unit_types

  ! Context setup is automatic - no manual configuration needed
  call ui_init("auto", cw_unit(80.0), ch_unit(25.0), "My App")
  
  ! All units work automatically with established context
  ui = column(gap=ch_unit(1.0), children=[ &
    button("ok", width=dp_unit(120.0), height=em_unit(2.5)) ])
    
  call ui_present(ui)
  call ui_shutdown()
end program
```

### Mixed Unit Application

```fortran
program mixed_units_app
  use fortui_core  
  use fortui_unit_types

  ! Physical units for document layout
  call ui_init("gui", inches_unit(8.5), cm_unit(21.0), "Document")
  
  ! Mix physical and logical units
  ui = column(gap=mm_unit(5.0), children=[ &
    text("title", text_size=points_unit(14.0)), &
    button("print", width=cm_unit(3.0), height=mm_unit(10.0)) ])
    
  call ui_present(ui)
  call ui_shutdown()
end program
```

The UI context integration system provides transparent, automatic measurement-based unit conversion with robust cross-platform support and efficient performance characteristics.