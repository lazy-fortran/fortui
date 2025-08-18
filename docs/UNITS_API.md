# fortui_units API Reference

## Module Overview

```fortran
use fortui_units
```

The `fortui_units` module provides a comprehensive cross-backend units system for consistent UI sizing.

## Public Types

### unit_value
```fortran
type :: unit_value
    real :: value                          ! Numeric value
    character(len=2) :: unit_type         ! Unit identifier: "dp", "em", "sp", "px", "cw", "ch"
end type unit_value
```
Internal type for runtime unit identification. Users typically don't interact with this directly.

### ui_context
```fortran
type :: ui_context
    real :: dpi_scale = 1.0     ! GUI: system DPI scale; TUI: 1.0
    real :: em_dp = 16.0        ! Base font size in dp
    real :: text_scale = 1.0    ! Accessibility text scaling
    real :: cell_w_dp = 8.0     ! TUI: cell width in dp
    real :: cell_h_dp = 16.0    ! TUI: cell height in dp
end type ui_context
```
Context for cross-backend unit conversion.

## Unit Constructor Functions

### dp(value) → unit_value
```fortran
function dp(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
```
Create density-independent pixel unit (base unit).

### em(value) → unit_value  
```fortran
function em(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
```
Create em unit (relative to font size).

### sp(value) → unit_value
```fortran
function sp(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
```
Create scaled pixel unit (accessibility).

### px(value) → unit_value
```fortran
function px(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
```
Create physical pixel unit.

### cw(value) → unit_value
```fortran
function cw(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
```
Create cell width unit (TUI-friendly).

### ch(value) → unit_value
```fortran
function ch(value) result(unit)
    real, intent(in) :: value
    type(unit_value) :: unit
```
Create cell height unit (TUI-friendly).

## Conversion Functions

### convert_to_dp(unit_arg, ctx) → real
```fortran
real function convert_to_dp(unit_arg, ctx) result(dp_val)
    class(*), intent(in) :: unit_arg
    type(ui_context), intent(in) :: ctx
```
Convert any unit type or bare real to density-independent pixels using runtime type checking.

**Parameters:**
- `unit_arg`: Unit value (unit_value type), bare real, or integer
- `ctx`: UI context for conversion parameters

**Returns:** Value in density-independent pixels

**Conversion Rules:**
- `dp`: Direct assignment (base unit)
- `em`: `value * ctx%em_dp`
- `sp`: `value * ctx%text_scale`  
- `px`: `value / ctx%dpi_scale`
- `cw`: `value * ctx%cell_w_dp`
- `ch`: `value * ctx%cell_h_dp`
- `real`: Treated as dp value
- `integer`: Converted to real, treated as dp

## Context Management

### ui_get_context(ctx)
```fortran
subroutine ui_get_context(ctx)
    type(ui_context), intent(out) :: ctx
```
Retrieve current UI context.

### ui_set_context(ctx)
```fortran
subroutine ui_set_context(ctx)
    type(ui_context), intent(in) :: ctx
```
Set new UI context values.

## Usage Patterns

### Basic Unit Creation
```fortran
width = dp(100.0)     ! 100 density-independent pixels
height = em(3.0)      ! 3x base font size
spacing = cw(2.0)     ! 2 character widths
```

### Mixed Unit Function Calls
```fortran
! All fortui widgets accept class(*) for unit parameters
button("ok", width=dp(120.0), height=em(2.5))
slider("volume", width=cw(20.0), height=sp(24.0))
```

### Context Configuration
```fortran
type(ui_context) :: ctx

! Get current context
call ui_get_context(ctx)

! Modify for high-DPI display
ctx%dpi_scale = 2.0
ctx%em_dp = 18.0
ctx%text_scale = 1.25

! Apply changes
call ui_set_context(ctx)
```

### Manual Conversion
```fortran
type(ui_context) :: ctx
real :: dp_value

call ui_get_context(ctx)
dp_value = convert_to_dp(em(2.5), ctx)  ! Convert 2.5em to dp
```

## Error Handling

The units system provides graceful error handling:

- **Unsupported types**: Default to 0.0 with error message
- **Unknown unit types**: Fall back to raw value with error message
- **Invalid contexts**: Functions continue with available values

## Performance Notes

- Unit conversion is fast (simple arithmetic operations)
- `class(*)` runtime overhead is minimal
- Context storage is global and efficient
- Memory allocation is automatic and optimized

## See Also

- [Units Guide](UNITS_GUIDE.md) - Complete user guide with examples
- [Core Types API](CORE_TYPES_API.md) - fortui_core types documentation