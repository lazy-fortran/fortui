# Demo Application Guide

Complete guide to the fortui demo application showcasing all widget types.

## Running the Demo

```bash
# Build and run the comprehensive demo
fpm build
./build/gfortran_*/app/fortui
```

**Demo Output:**
```
fortui - Comprehensive Widget Demo
====================================
Demonstrating button, slider, checkbox, text, and viewport widgets
Press ESC to exit

Frame 1: Gain changed to: 1.00000000
...
Demo Statistics:
  Total frames processed: 5
  Final state:
    - Gain: 1.00000000
    - Grid enabled: F
    - Zoom scale: (1.00000000, 1.00000000)
    - Pan offset: (0.00000000, 0.00000000)

✓ Multi-widget integration demonstrated
✓ Immediate-mode interaction pattern working
✓ State management across all widget types
✓ Cross-backend compatibility validated
```

## Demo Features

### Multi-Widget Integration
- **Button widgets**: Zoom in/out with immediate feedback
- **Slider widget**: Gain control (0.1-5.0 range, 0.1 step)
- **Checkbox widget**: Grid toggle state management
- **Text widget**: Dynamic status display
- **Viewport widget**: Pan/zoom state management

### Immediate-Mode Patterns
All widgets follow the immediate-mode pattern from `app/main.f90`:

```fortran
! Button - returns true when clicked
if (button("zoom_in", "Zoom In")) then
    call zoom(v, 1.2)
    print *, "Zoom in clicked! Scale:", v%scale_x
end if

! Slider - returns true when value changes
if (slider("gain", 0.1, 5.0, 0.1, gain)) then
    print *, "Gain changed to:", gain
end if

! Checkbox - toggles state when clicked
call checkbox("grid", grid, "Show Grid")

! Text - displays content with auto-sizing
call text("status", status_line(gain, v, grid))

! Viewport - manages pan/zoom state
call viewport("plot", dp(80.0), dp(24.0), v)
```

### State Management
Demo shows persistent state across frames:
- `real :: gain = 1.0` - slider value
- `logical :: grid = .false.` - checkbox state
- `type(view) :: v` - viewport pan/zoom state

### Layout Structure
Demo uses nested layout system:
```fortran
ui_root = build_demo_layout()  ! Placeholder nodes
call ui_present(ui_root)
```

## Source Code

**Main file:** `app/main.f90` - Complete working example
**Test validation:** `test/test_demo_application.f90` - Comprehensive test suite

## Performance
- Frame-limited to 200 for demo purposes
- Status output every 50 frames
- Event-driven with 200ms timeout
- Automatic backend selection (TUI/GUI)

## Integration Testing

The demo validates:
1. **Widget composition** - All widget types working together
2. **State persistence** - Values maintained across frames  
3. **Backend compatibility** - Same code works TUI/GUI
4. **Performance targets** - Responsive interaction
5. **Build system** - fpm integration working