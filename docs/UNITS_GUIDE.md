# fortui Units System Guide

## Quick Start

The fortui units system provides consistent cross-backend sizing with ergonomic function syntax:

```fortran
use fortui_units

! Create units using constructor functions
width = dp(40.0)      ! density-independent pixels
gap = em(2.5)         ! relative to font size  
text_size = sp(14.0)  ! scaled pixels (accessibility)
border = px(2.0)      ! physical pixels
cols = cw(10.0)       ! cell widths (TUI-friendly)
rows = ch(3.0)        ! cell heights (TUI-friendly)

! Bare real values default to dp automatically
width = 40.0          ! equivalent to dp(40.0)
```

## Unit Types

### dp(value) - Density-Independent Pixels
**Base unit for all calculations**
```fortran
button_width = dp(120.0)  ! 120 dp wide button
margin = dp(8.0)          ! 8 dp margin
```
- **TUI**: Converts to cells via `cell_w_dp` and `cell_h_dp`
- **GUI**: Scales with system DPI via `dpi_scale`
- **Default**: Bare `real` values automatically treated as dp

### em(value) - Font-Relative Size
**Relative to base font size**
```fortran
heading_size = em(2.0)    ! 2x base font size
small_text = em(0.8)      ! 0.8x base font size
line_height = em(1.5)     ! 1.5x font height
```
- Converts to dp: `value * em_dp`
- Default `em_dp = 16.0` (adjustable via context)

### sp(value) - Scaled Pixels
**Accessibility-aware text sizing**
```fortran
body_text = sp(14.0)      ! 14sp body text
large_text = sp(18.0)     ! 18sp large text
```
- Converts to dp: `value * text_scale`
- Respects system accessibility text scaling
- Default `text_scale = 1.0` (user can increase for larger text)

### px(value) - Physical Pixels
**Exact pixel control**
```fortran
hairline = px(1.0)        ! 1 physical pixel border
icon_size = px(32.0)      ! 32 pixel icon
```
- Converts to dp: `value / dpi_scale`
- **TUI**: Usually same as dp (dpi_scale = 1.0)
- **GUI**: Accounts for HiDPI displays

### cw(value) - Cell Widths
**TUI-optimized horizontal sizing**
```fortran
button_width = cw(12.0)   ! 12 character widths
terminal_width = cw(80.0) ! 80 character terminal
```
- Converts to dp: `value * cell_w_dp`
- Perfect for TUI layouts that align to text grid
- Default `cell_w_dp = 8.0`

### ch(value) - Cell Heights
**TUI-optimized vertical sizing**
```fortran
button_height = ch(2.0)   ! 2 character heights
text_area = ch(10.0)      ! 10 line text area
```
- Converts to dp: `value * cell_h_dp`
- Perfect for TUI layouts that align to text grid
- Default `cell_h_dp = 16.0`

## Mixed Unit Usage

All fortui widgets accept mixed unit types seamlessly:

```fortran
ui = column(gap=ch(1.0), children=[ &
       row(gap=cw(2.0), children=[ &
         button("ok", width=120.0, height=em(2.5)), &      ! mixed: dp + em
         slider("gain", width=px(200.0), height=sp(24.0)) & ! mixed: px + sp
       ]), &
       text("status", text_size=sp(12.0)) ])
```

## UI Context Management

### Default Context
```fortran
type(ui_context) :: ctx = ui_context( &
  dpi_scale = 1.0,     ! GUI: system DPI; TUI: always 1.0
  em_dp = 16.0,        ! base font size in dp
  text_scale = 1.0,    ! accessibility scaling
  cell_w_dp = 8.0,     ! TUI cell width in dp
  cell_h_dp = 16.0 )   ! TUI cell height in dp
```

### Getting Current Context
```fortran
type(ui_context) :: current_ctx
call ui_get_context(current_ctx)
print *, "Current font size:", current_ctx%em_dp, "dp"
```

### Setting Custom Context
```fortran
type(ui_context) :: custom_ctx

! Configure for high-DPI GUI environment
custom_ctx = ui_context( &
  dpi_scale = 2.0,     ! 2x HiDPI display
  em_dp = 18.0,        ! larger base font
  text_scale = 1.25,   ! 125% accessibility scaling
  cell_w_dp = 9.0,     ! wider characters
  cell_h_dp = 18.0 )   ! taller lines

call ui_set_context(custom_ctx)
```

### TUI vs GUI Context Setup
```fortran
! TUI context (terminal environment)
tui_ctx = ui_context( &
  dpi_scale = 1.0,     ! no DPI scaling in terminal
  em_dp = 16.0,        ! standard terminal font
  text_scale = 1.0,    ! no accessibility scaling
  cell_w_dp = 8.0,     ! standard character width
  cell_h_dp = 16.0 )   ! standard line height

! GUI context (high-DPI desktop)
gui_ctx = ui_context( &
  dpi_scale = 1.5,     ! 150% display scaling
  em_dp = 18.0,        ! larger desktop font
  text_scale = 1.25,   ! user accessibility preference
  cell_w_dp = 10.8,    ! scaled character width (18 * 0.6)
  cell_h_dp = 18.0 )   ! scaled line height
```

## Cross-Backend Behavior

### TUI Backend
Units convert to terminal cells with automatic snapping:

```fortran
! Example: 42.7 dp with cell_w_dp=8.0
dp_value = convert_to_dp(dp(42.7), ctx)    ! 42.7 dp
cell_x = nint(dp_value / ctx%cell_w_dp)    ! 42.7/8.0 = 5.34 → 5 cells
```

**TUI Characteristics:**
- Integer cell coordinates only
- Automatic snapping to grid boundaries
- Perfect alignment with terminal text

### GUI Backend
Units convert to pixels with subpixel precision:

```fortran
! Example: 42.7 dp with dpi_scale=1.5  
dp_value = convert_to_dp(dp(42.7), ctx)    ! 42.7 dp
pixel_x = dp_value * ctx%dpi_scale         ! 42.7 * 1.5 = 64.05 pixels
```

**GUI Characteristics:**
- Subpixel positioning maintained
- Smooth scaling and animations
- HiDPI display support

## Complete Examples

### Basic Widget Sizing
```fortran
use fortui_units

! Simple button with default dp units
if (button("ok", width=100.0, height=32.0)) then
  print *, "OK clicked"
end if

! Mixed units for responsive design
if (button("save", width=cw(12.0), height=em(2.5))) then
  print *, "Save clicked"
end if
```

### Layout with Consistent Spacing
```fortran
use fortui_units

ui = column(gap=ch(1.0), children=[ &
  text("title", "Settings", text_size=em(1.5)), &
  row(gap=cw(2.0), children=[ &
    text("volume", "Volume:", text_size=sp(14.0)), &
    slider("vol", 0.0, 1.0, 0.1, volume, width=cw(20.0)) &
  ]), &
  row(gap=cw(2.0), children=[ &
    button("ok", width=cw(8.0), height=ch(2.0)), &
    button("cancel", width=cw(8.0), height=ch(2.0)) &
  ]) &
])
```

### Context-Aware Multi-Backend App
```fortran
program responsive_app
  use fortui_core
  use fortui_widgets  
  use fortui_units
  
  type(ui_context) :: ctx
  class(ui_element), allocatable :: ui
  real :: volume = 0.5
  
  ! Initialize with auto backend detection
  call ui_init(backend="auto", width=cw(50.0), height=ch(20.0), &
               title="Responsive Demo")
  
  ! Get initial context (set by backend)
  call ui_get_context(ctx)
  
  ! Adjust context for better appearance
  if (ctx%dpi_scale > 1.0) then
    ! High-DPI GUI detected
    ctx%em_dp = 18.0      ! larger fonts
    ctx%text_scale = 1.1  ! slight accessibility boost
  else
    ! Standard DPI or TUI
    ctx%em_dp = 16.0      ! standard fonts
  end if
  call ui_set_context(ctx)
  
  do while (.not. ui_should_close())
    call ui_frame_begin(timeout_ms=200)
    
    ui = column(gap=ch(1.0), children=[ &
      text("title", "Volume Control", text_size=em(1.5)), &
      slider("volume", 0.0, 1.0, 0.1, volume, width=cw(30.0)), &
      text("value", volume_text(volume), text_size=sp(12.0)), &
      button("reset", "Reset", width=cw(10.0), height=ch(2.0)) &
    ])
    
    if (button("reset", "Reset")) volume = 0.5
    
    call ui_present(ui)
  end do
  
  call ui_shutdown()

contains
  function volume_text(vol) result(text)
    real, intent(in) :: vol
    character(len=20) :: text
    write(text, '("Volume: ", I0, "%")') nint(vol * 100.0)
  end function
end program
```

## Implementation Details

### Runtime Type Checking
The units system uses `class(*)` polymorphism with runtime type checking:

```fortran
real function convert_to_dp(unit_arg, ctx) result(dp_val)
  class(*), intent(in) :: unit_arg
  type(ui_context), intent(in) :: ctx
  
  select type(unit_arg)
    type is (unit_value)
      ! Handle unit types (dp, em, sp, px, cw, ch)
      select case (trim(unit_arg%unit_type))
        case ("dp"); dp_val = unit_arg%value
        case ("em"); dp_val = unit_arg%value * ctx%em_dp
        case ("sp"); dp_val = unit_arg%value * ctx%text_scale
        case ("px"); dp_val = unit_arg%value / ctx%dpi_scale
        case ("cw"); dp_val = unit_arg%value * ctx%cell_w_dp
        case ("ch"); dp_val = unit_arg%value * ctx%cell_h_dp
      end select
    type is (real)
      ! Bare real values treated as dp
      dp_val = unit_arg
    type is (integer)
      ! Integer values converted to dp
      dp_val = real(unit_arg)
  end select
end function
```

### Unit Constructor Functions
Each unit type has a corresponding constructor function:

```fortran
function dp(value) result(unit)
  real, intent(in) :: value
  type(unit_value) :: unit
  unit%value = value
  unit%unit_type = "dp"
end function

! Similar for em(), sp(), px(), cw(), ch()
```

### Integration with Widgets
All fortui widgets accept `class(*)` parameters for unit values:

```fortran
logical function button(id, label, width, height)
  character(*), intent(in) :: id
  character(*), intent(in), optional :: label
  class(*), intent(in), optional :: width, height  ! accepts any unit type
  
  ! Internal conversion to dp for rendering
  type(ui_context) :: ctx
  real :: w_dp, h_dp
  
  call ui_get_context(ctx)
  if (present(width)) w_dp = convert_to_dp(width, ctx)
  if (present(height)) h_dp = convert_to_dp(height, ctx)
  
  ! Use w_dp, h_dp for actual rendering...
end function
```

## Migration from DESIGN.md

The implementation uses **function syntax** instead of postfix operators:

**DESIGN.md (postfix operators):**
```fortran
width = 40.0 .dp.      ! postfix operator syntax
gap = 2.5 .em.         ! postfix operator syntax
```

**Actual Implementation (function syntax):**
```fortran
width = dp(40.0)       ! function call syntax
gap = em(2.5)          ! function call syntax
```

**Reason**: Fortran limitations with postfix operators and `class(*)` return types required switching to function syntax for a clean, working implementation.

## Error Handling

The units system provides graceful error handling:

```fortran
! Unsupported types default to 0.0 with error message
result = convert_to_dp("invalid", ctx)  ! prints error, returns 0.0

! Unknown unit types fall back to raw value
bad_unit%unit_type = "xx"
result = convert_to_dp(bad_unit, ctx)   ! prints error, uses raw value
```

## Performance Considerations

- Unit conversion is fast (simple arithmetic)
- `class(*)` has minimal runtime overhead
- Context lookups are efficient (global storage)
- Memory allocation is automatic and efficient

## Best Practices

1. **Use dp() for absolute sizes**: `width = dp(100.0)`
2. **Use em() for text-relative sizes**: `font_size = em(1.2)`  
3. **Use sp() for accessibility text**: `body_text = sp(14.0)`
4. **Use cw()/ch() for TUI layouts**: `button_width = cw(10.0)`
5. **Use bare reals for simple cases**: `margin = 8.0` (auto-dp)
6. **Set context early**: Configure once during initialization
7. **Mix units freely**: Different units in same widget work perfectly

The fortui units system makes cross-backend UI development straightforward while maintaining precise control over sizing and layout behavior.