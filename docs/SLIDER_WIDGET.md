# Slider Widget API

Interactive slider for numeric input with value updates and cross-backend rendering.

## Basic Usage

```fortran
use fortui_widgets
use fortui_units

real :: value = 50.0

! Returns true when value changes from user interaction
if (slider("volume", 0.0, 100.0, 1.0, value)) then
    print *, "Volume changed to:", value
end if
```

## Function Signature

```fortran
logical function slider(id, min_val, max_val, step_val, value, width, height)
    character(*), intent(in)    :: id       ! Stable identifier for state
    real,         intent(in)    :: min_val  ! Minimum value
    real,         intent(in)    :: max_val  ! Maximum value  
    real,         intent(in)    :: step_val ! Step size (0 for continuous)
    real,         intent(inout) :: value    ! Current value (modified directly)
    class(*),     intent(in), optional :: width  ! Slider width
    class(*),     intent(in), optional :: height ! Slider height
end function
```

## Parameters

- **id**: Required string identifier. Must be unique per slider.
- **min_val**: Minimum allowed value
- **max_val**: Maximum allowed value  
- **step_val**: Step increment. Use 0.0 for continuous/smooth values.
- **value**: Current value, modified directly by user interaction
- **width**: Optional width using any unit type (default: 8em minimum)
- **height**: Optional height using any unit type (default: 1.5em)

## Examples

```fortran
real :: volume = 50.0
real :: temperature = 22.5
real :: brightness = 75.0

! Volume slider with discrete steps
if (slider("volume", 0.0, 100.0, 5.0, volume, width=dp(120.0))) then
    print *, "Volume:", volume, "%"
end if

! Temperature slider with continuous values
if (slider("temp", 15.0, 30.0, 0.0, temperature)) then
    print *, "Temperature:", temperature, "°C"  
end if

! Brightness with TUI-friendly width
if (slider("brightness", 0.0, 100.0, 1.0, brightness, width=cw(20.0))) then
    print *, "Brightness:", brightness
end if
```

## Value Management

- **Direct modification**: `value` parameter modified in-place
- **Range clamping**: Values automatically clamped to [min_val, max_val]
- **Step quantization**: When step_val > 0, values snap to nearest step
- **Continuous mode**: step_val = 0.0 allows smooth floating-point values
- **Change detection**: Returns true only when value actually changes

## Unit Support

```fortran
! All unit types supported
slider("id", 0.0, 100.0, 1.0, val, width=dp(100.0))  ! density-independent pixels
slider("id", 0.0, 100.0, 1.0, val, width=em(8.0))    ! relative to font size  
slider("id", 0.0, 100.0, 1.0, val, width=cw(15.0))   ! cell widths (TUI-friendly)
slider("id", 0.0, 100.0, 1.0, val, width=120.0)      ! bare real (treated as dp)
```

## Auto-Sizing

When dimensions not specified:
- **Width**: 8em minimum, scales with context font size
- **Height**: 1.5em for compact but usable slider track

## Complete Example

```fortran
program slider_example
use fortui_widgets
use fortui_units
implicit none

real :: volume = 50.0
real :: brightness = 75.0
real :: temperature = 22.5
logical :: running = .true.

do while (running)
    ! Volume control with steps
    if (slider("volume", 0.0, 100.0, 5.0, volume, width=dp(150.0))) then
        print *, "Volume:", volume, "%"
    end if
    
    ! Brightness control
    if (slider("brightness", 0.0, 100.0, 1.0, brightness)) then
        print *, "Brightness:", brightness
    end if
    
    ! Temperature with continuous adjustment
    if (slider("temp", 15.0, 30.0, 0.0, temperature, width=cw(20.0))) then
        print *, "Temperature:", temperature, "°C"
    end if
    
    ! Exit control
    if (volume >= 95.0) running = .false.
end do
end program
```