# Button Widget API

Interactive button widget with click detection and auto-sizing.

## Basic Usage

```fortran
use fortui_widgets

! Simple button - returns true when clicked
if (button("my_button")) then
    print *, "Button was clicked!"
end if

! Custom label
if (button("save_btn", label="Save File")) then
    ! Handle save action
end if

! Explicit size with units
if (button("big_btn", width=dp(100.0), height=dp(40.0))) then
    ! Handle click
end if
```

## Function Signature

```fortran
logical function button(id, label, width, height)
    character(*), intent(in)           :: id      ! Stable identifier for state
    character(*), intent(in), optional :: label   ! Display text (default: id)
    class(*),     intent(in), optional :: width   ! Button width (auto-sized if not specified)
    class(*),     intent(in), optional :: height  ! Button height (auto-sized if not specified)
end function
```

## Parameters

- **id**: Required string identifier for state management. Must be unique per button.
- **label**: Optional display text. Defaults to `id` if not provided.
- **width**: Optional width using any unit type. Auto-calculates based on label if omitted.
- **height**: Optional height using any unit type. Auto-calculates based on context if omitted.

## Unit Support

```fortran
! All unit types supported
button("btn", width=dp(80.0))    ! density-independent pixels
button("btn", width=em(5.0))     ! relative to font size
button("btn", width=cw(10.0))    ! cell widths (TUI-friendly)
button("btn", width=40.0)        ! bare real (treated as dp)
```

## Auto-Sizing

When width/height not specified:
- **Width**: Calculated from label length + padding (minimum 40dp)
- **Height**: Based on font size with 1.8x ratio (minimum 20dp)

## Click Detection

- **Mouse**: Click within button bounds
- **Keyboard**: Enter/Space when button has focus
- **Returns**: `true` only on the frame when clicked, `false` otherwise
- **State**: Automatically managed by ID, persists across frames

## Complete Example

```fortran
program button_demo
use fortui_widgets
use fortui_units
implicit none

logical :: save_clicked, load_clicked, quit_clicked
logical :: running = .true.
integer :: click_count = 0

do while (running)
    ! Auto-sized buttons
    save_clicked = button("save")
    load_clicked = button("load", label="Load File")
    
    ! Custom-sized button
    quit_clicked = button("quit", label="Exit", width=dp(60.0))
    
    if (save_clicked) then
        click_count = click_count + 1
        print *, "Save clicked! Count:", click_count
    end if
    
    if (load_clicked) then
        print *, "Loading file..."
    end if
    
    if (quit_clicked) then
        running = .false.
        print *, "Exiting..."
    end if
    
    ! Simulate frame cycle (in real app, use ui_frame_begin/ui_present)
    if (click_count >= 3) running = .false.
end do
end program
```