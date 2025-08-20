# fortui Lifecycle API

Complete documentation for fortui's UI lifecycle management procedures from the `fortui_core` module.

## Overview

The lifecycle API manages initialization, frame rendering, and cleanup for fortui applications. All procedures are backend-agnostic and handle both TUI and GUI modes automatically.

## Quick Reference

```fortran
! 1. Initialize
call ui_init(backend, width, height, title [, target_fps, vsync])

! 2. Optional: Configure GUI idle policy  
call ui_set_idle_policy(mode [, idle_fps])  ! GUI only

! 3. Main loop
do while (running)
  call ui_frame_begin(timeout_ms)           ! Begin frame
  ! ... build UI tree ...
  call ui_present(tree)                     ! Render UI
  running = .not. ui_should_close()         ! Check for exit
end do

! 4. Cleanup
call ui_shutdown()
```

## Initialization

### ui_init

Initialize the UI system with backend selection and window parameters. Supports both integer dimensions (backward compatible) and abstract unit types.

```fortran
! Integer dimensions (backward compatible)
subroutine ui_init(backend, width, height, title, target_fps, vsync)
  character(*), intent(in) :: backend        ! "tui" | "gui" | "auto"
  integer,      intent(in) :: width, height  ! grid units (gu)  
  character(*), intent(in) :: title
  integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
  logical,      intent(in), optional :: vsync        ! gui: default .true.; tui: ignored

! Abstract unit types (NEW)
subroutine ui_init(backend, width_unit, height_unit, title, target_fps, vsync)
  character(*),         intent(in) :: backend            ! "tui" | "gui" | "auto"
  class(unit_type),     intent(in) :: width_unit, height_unit  ! any abstract unit type
  character(*),         intent(in) :: title
  integer,      intent(in), optional :: target_fps       ! gui: default 60; tui: ignored
  logical,      intent(in), optional :: vsync            ! gui: default .true.; tui: ignored
```

**Parameters:**
- `backend`: Backend selection with automatic detection support
  - `"tui"`: Force terminal UI backend
  - `"gui"`: Force graphical window backend (falls back to TUI if not available)
  - `"auto"`: Automatically select best available backend based on environment
- `width`, `height` (integer version): Window dimensions in grid units (gu)
- `width_unit`, `height_unit` (abstract version): Window dimensions as abstract unit types
  - **Any unit type**: `dp_unit()`, `em_unit()`, `cw_unit()`, `inches_unit()`, etc.
  - **Context conversion**: Units converted using backend measurement system
- `title`: Window title displayed in terminal title bar or GUI window
- `target_fps` (optional): Target frame rate for GUI mode (default: 60, ignored in TUI)
- `vsync` (optional): Enable VSync for GUI mode (default: true, ignored in TUI)

**Usage Examples:**

```fortran
use fortui_unit_types

! Automatic backend selection (recommended)
call ui_init("auto", cw_unit(80.0), ch_unit(25.0), "Smart App")

! Abstract units with mixed types
call ui_init("auto", dp_unit(800.0), em_unit(30.0), "Mixed Units")

! Physical units for print layouts
call ui_init("gui", inches_unit(8.5), cm_unit(21.0), "Paper Size")

! Legacy integer syntax (backward compatible)
call ui_init("tui", 80, 25, "Terminal App")

! GUI with abstract units and options
call ui_init("gui", dp_unit(1200.0), dp_unit(800.0), "High FPS App", &
             target_fps=120, vsync=.false.)
```

**Backend Selection Logic:**
```fortran
use fortui_unit_types

! Automatic selection with abstract units
call ui_init("auto", cw_unit(80.0), ch_unit(25.0), "Smart App")

! TUI mode with terminal-friendly units
call ui_init("tui", cw_unit(80.0), ch_unit(25.0), "Terminal")

! GUI mode with mixed units
call ui_init("gui", dp_unit(800.0), em_unit(30.0), "GUI Window")
```

**Environment Variable Overrides:**
```bash
# Force specific backend regardless of code
export FORTUI_BACKEND=tui
./my_app  # Uses TUI even if code specifies "auto" or "gui"

export FORTUI_BACKEND=gui  
./my_app  # Uses GUI if available, TUI fallback otherwise

# Force headless mode (useful for CI/testing)
export FORTUI_HEADLESS=1
./my_app  # Forces TUI backend

# Disable GUI completely
export DISABLE_GUI=1
./my_app  # Forces TUI backend even if GUI compiled in
```

### ui_set_idle_policy (GUI Only)

Configure power-saving behavior for GUI applications when no user input occurs.

```fortran
subroutine ui_set_idle_policy(mode, idle_fps)
  character(*), intent(in) :: mode                   ! "steady" | "adaptive"
  integer,      intent(in), optional :: idle_fps     ! e.g., 12
```

**Parameters:**
- `mode`: Idle behavior mode
  - `"steady"`: Maintain constant frame rate regardless of activity
  - `"adaptive"`: Reduce frame rate when idle to save power
- `idle_fps` (optional): Frame rate when idle in adaptive mode (default varies)

**Usage Examples:**
```fortran
! Power-saving mode - drop to 12 FPS when idle
call ui_set_idle_policy("adaptive", idle_fps=12)

! Maintain steady 60 FPS always
call ui_set_idle_policy("steady")

! Only works in GUI mode - automatically ignored in TUI
#ifdef ENABLE_GUI
call ui_set_idle_policy("adaptive", idle_fps=8)
#endif
```

## Frame Management

### ui_frame_begin

Begin a new frame and handle timing/events.

```fortran
subroutine ui_frame_begin(timeout_ms)
  integer, intent(in) :: timeout_ms  ! tui uses; gui ignores
```

**Parameters:**
- `timeout_ms`: Event timeout in milliseconds
  - **TUI**: Maximum time to wait for keyboard/mouse events
  - **GUI**: Ignored (GUI uses vsync/target_fps for timing)

**Usage Examples:**
```fortran
! TUI: Wait up to 200ms for events, then continue
call ui_frame_begin(timeout_ms=200)

! TUI: Responsive input (50ms timeout)
call ui_frame_begin(timeout_ms=50)

! TUI: Patient input (1 second timeout)  
call ui_frame_begin(timeout_ms=1000)

! TUI: Non-blocking (immediate return)
call ui_frame_begin(timeout_ms=0)

! GUI: Value ignored, but call still required
call ui_frame_begin(timeout_ms=16)  ! Any value works for GUI
```

**Timing Strategy:**
```fortran
! Game-like responsiveness
do while (running)
  call ui_frame_begin(timeout_ms=16)   ! ~60 Hz polling
  ! ... UI updates ...
end do

! Dashboard-like efficiency  
do while (running)
  call ui_frame_begin(timeout_ms=500)  ! 2 Hz polling
  ! ... UI updates ...
end do
```

### ui_present

Present the UI tree to the backend for rendering.

```fortran
subroutine ui_present(tree)
  class(node), intent(in) :: tree
```

**Parameters:**
- `tree`: Root node of the UI tree to render

**Usage Examples:**
```fortran
type(node) :: root_ui

! Build UI tree (using fortui_widgets)
! root_ui = column(children=[...])

! Present for rendering
call ui_present(root_ui)
```

**Integration Pattern:**
```fortran
do while (running)
  call ui_frame_begin(timeout_ms=200)
  
  ! Build complete UI tree
  root_ui = build_interface()
  
  ! Single present call renders everything
  call ui_present(root_ui)
  
  running = .not. ui_should_close()
end do
```

### ui_should_close

Check if the application should terminate due to user action.

```fortran
logical function ui_should_close()
```

**Returns:**
- `true`: User requested application exit (ESC key, window close, etc.)
- `false`: Application should continue running

**Usage Examples:**
```fortran
! Basic exit checking
do while (.not. ui_should_close())
  ! ... frame logic ...
end do

! Combined with other exit conditions
logical :: running = .true.
do while (running)
  ! ... frame logic ...
  
  ! Multiple exit conditions
  running = running .and. .not. ui_should_close()  ! User didn't quit
  running = running .and. .not. error_occurred     ! No errors
  running = running .and. work_remaining           ! Still have work
end do

! Store result for complex logic
logical :: user_quit
user_quit = ui_should_close()
if (user_quit) then
  call save_application_state()
end if
```

## Cleanup

### ui_shutdown

Clean up all backend resources and restore terminal state.

```fortran
subroutine ui_shutdown()
```

**Usage:**
```fortran
! Always call at program end
call ui_shutdown()

! Exception-safe cleanup pattern
block
  call ui_init("tui", 80, 25, "My App")
  
  ! ... application logic ...
  
  call ui_shutdown()  ! Guaranteed cleanup
end block

! Multiple exit points
subroutine run_application()
  call ui_init("tui", 80, 25, "App")
  
  ! ... main logic ...
  
  if (error_condition) then
    call ui_shutdown()
    return
  end if
  
  ! ... more logic ...
  
  call ui_shutdown()  ! Normal exit
end subroutine
```

## Complete Application Template

```fortran
program complete_lifecycle_example
  use fortui_core
  use fortui_unit_types
  implicit none
  
  type(node) :: ui_root
  logical :: running
  integer :: frame_count = 0
  
  ! 1. Initialize with automatic backend selection and abstract units
  call ui_init("auto", cw_unit(80.0), ch_unit(25.0), "Lifecycle Demo")
  
  ! 2. Optional: Configure for GUI efficiency (ignored in TUI mode)
  call ui_set_idle_policy("adaptive", idle_fps=12)
  
  ! 3. Main application loop
  running = .true.
  do while (running)
    ! Begin frame with appropriate timeout
    call ui_frame_begin(timeout_ms=200)
    
    ! Build UI tree here (using fortui_widgets when available)
    ! ui_root = column(children=[ &
    !   text("counter", "Frame: " // int_to_string(frame_count)), &
    !   button("quit", "Exit") ])
    frame_count = frame_count + 1
    
    ! Present to backend
    call ui_present(ui_root)
    
    ! Check for exit conditions
    running = .not. ui_should_close()
  end do
  
  ! 4. Clean shutdown
  call ui_shutdown()
  
  print *, "Application completed after", frame_count, "frames"
end program
```

## Backend-Specific Behavior

### Auto Mode Behavior
```fortran
call ui_init("auto", 80, 25, "Smart App")
! - Detects best available backend automatically
! - GUI preferred if available and not in headless environment
! - Falls back to TUI in headless environments (SSH, CI, no display)
! - Respects FORTUI_BACKEND environment variable override
```

### TUI Mode Behavior
```fortran
call ui_init("tui", 80, 25, "TUI App")
! - target_fps and vsync parameters ignored
! - ui_set_idle_policy() calls ignored  
! - ui_frame_begin(timeout_ms) controls event polling
! - Efficient terminal output via diffing
```

### GUI Mode Behavior
```fortran
call ui_init("gui", 100, 30, "GUI App", target_fps=60, vsync=.true.)
! - target_fps controls rendering rate
! - vsync enables smooth display synchronization
! - ui_set_idle_policy() enables power saving
! - ui_frame_begin(timeout_ms) ignored (uses target_fps instead)
! - Falls back to TUI if GUI not available
```

## Error Handling

Lifecycle procedures are designed for robust operation:

```fortran
! Safe to call multiple times - automatic cleanup and reinit
call ui_init("tui", 80, 25, "App")
call ui_init("gui", 100, 30, "App")  ! Automatically shuts down TUI, starts GUI

! Safe to call without initialization
call ui_shutdown()  ! No-op if not initialized

! Safe backend selection with automatic fallbacks
call ui_init("invalid", 80, 25, "App")    ! Falls back to TUI with warning
call ui_init("gui", 80, 25, "App")        ! Falls back to TUI if GUI unavailable
call ui_init("auto", 80, 25, "App")       ! Intelligent selection based on environment

! Parameter validation with sensible defaults
call ui_init("tui", 0, 0, "App")          ! Uses minimum 1x1 with warning
call ui_init("tui", -10, -5, "App")       ! Converts to positive values
```

## Performance Guidelines

**TUI Applications:**
- Use longer timeouts (200-500ms) for efficient terminal applications
- Use shorter timeouts (16-50ms) for responsive interactive applications
- Consider user workflow - dashboards vs games have different timing needs

**GUI Applications:**
- Default 60 FPS works well for most applications
- Use adaptive idle policy for power efficiency
- Higher FPS (120+) only needed for demanding real-time applications
- Lower FPS (30) sufficient for data visualization applications

## Next Steps

- **Core Types**: Understand `node` and `view` types in [CORE_TYPES_API.md](CORE_TYPES_API.md)
- **Widgets**: Learn interactive UI elements in [WIDGET_API.md](WIDGET_API.md)  
- **Backend Selection**: Choose compilation mode in [BUILD_GUIDE.md](BUILD_GUIDE.md)