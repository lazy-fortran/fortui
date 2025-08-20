# Checkbox Widget API

Boolean input widget with toggle functionality and state persistence.

## Basic Usage

```fortran
use fortui_widgets

logical :: is_enabled = .false.

! Toggles boolean state when clicked
call checkbox("enable_sound", is_enabled)
if (is_enabled) then
    print *, "Sound enabled"
end if

! With custom label
call checkbox("notifications", is_enabled, label="Enable Notifications")
```

## Function Signature

```fortran
subroutine checkbox(id, checked, label, width, height)
    character(*), intent(in)           :: id      ! Stable identifier for state
    logical,      intent(inout)        :: checked ! Boolean state (modified directly)
    character(*), intent(in), optional :: label   ! Display text (default: id)
    class(*),     intent(in), optional :: width   ! Checkbox width
    class(*),     intent(in), optional :: height  ! Checkbox height
end subroutine
```

## Parameters

- **id**: Required string identifier. Must be unique per checkbox.
- **checked**: Boolean state modified directly by user interaction
- **label**: Optional display text. Defaults to `id` if not provided.
- **width**: Optional width using any unit type. Auto-calculates if omitted.
- **height**: Optional height using any unit type. Auto-calculates if omitted.

## Examples

```fortran
logical :: sound_enabled = .true.
logical :: notifications = .false.
logical :: debug_mode = .false.

! Simple checkbox
call checkbox("sound", sound_enabled)

! With descriptive label
call checkbox("notify", notifications, label="Email Notifications")

! Custom size with units
call checkbox("debug", debug_mode, label="Debug Mode", &
              width=dp(120.0), height=dp(20.0))

! TUI-friendly sizing
call checkbox("compact", debug_mode, width=cw(15.0), height=ch(1.0))
```

## State Management

- **Direct modification**: `checked` parameter modified in-place when toggled
- **Toggle interaction**: Mouse click or keyboard activation (Space/Enter) when focused
- **State persistence**: Checkbox state maintained by ID across frames
- **Immediate-mode**: No return value - state changes reflected in `checked` parameter

## Unit Support

```fortran
! All unit types supported
call checkbox("id", state, width=dp(24.0))    ! density-independent pixels
call checkbox("id", state, width=em(1.5))     ! relative to font size
call checkbox("id", state, width=cw(3.0))     ! cell widths (TUI-friendly)
call checkbox("id", state, width=24.0)        ! bare real (treated as dp)
```

## Auto-Sizing

When dimensions not specified:
- **Width**: Checkbox square (16dp) + spacing + label width
- **Height**: Square aspect ratio (16dp) with text alignment
- **Minimum**: 16dp for clickability and visual clarity

## Interaction

- **Mouse**: Click within checkbox bounds toggles state
- **Keyboard**: Space/Enter when checkbox has focus
- **Visual feedback**: Hover and focus states supported across backends
- **Cross-backend**: TUI shows `[X]`/`[ ]`, GUI shows graphical checkbox

## Complete Example

```fortran
program checkbox_demo
use fortui_widgets
use fortui_units
implicit none

logical :: sound_enabled = .true.
logical :: notifications = .false.
logical :: auto_save = .true.
logical :: dark_mode = .false.
logical :: running = .true.
integer :: frame = 0

do while (running .and. frame < 10)
    frame = frame + 1
    print *, "=== Settings Panel (Frame", frame, ") ==="
    
    ! Audio settings
    call checkbox("sound", sound_enabled, label="Enable Sound")
    call checkbox("notifications", notifications, label="Notifications")
    
    ! Application settings  
    call checkbox("auto_save", auto_save, label="Auto-save Documents")
    call checkbox("dark_mode", dark_mode, label="Dark Theme", &
                  width=dp(150.0))
    
    ! Display current settings
    print *, "Sound:", sound_enabled, "| Notifications:", notifications
    print *, "Auto-save:", auto_save, "| Dark mode:", dark_mode
    
    ! Exit condition
    if (.not. sound_enabled .and. .not. notifications) then
        print *, "All audio features disabled - exiting"
        running = .false.
    end if
end do
end program
```