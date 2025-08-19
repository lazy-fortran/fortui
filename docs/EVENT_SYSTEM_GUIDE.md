# Event System Guide

Complete guide to fortui's event-driven model for responsive TUI applications.

## Overview

fortui's TUI backend uses an event-driven architecture that provides responsive user interaction while maintaining efficient CPU usage. The event system integrates seamlessly with the lifecycle API for optimal performance.

## Quick Start

```fortran
program event_driven_app
  use fortui_core
  implicit none

  type(node) :: ui
  logical :: running

  call ui_init("tui", 80, 25, "Event Demo")
  
  running = .true.
  do while (running)
    ! Event-driven frame with timeout
    call ui_frame_begin(timeout_ms=200)
    
    ! Build UI (only rebuilt when needed)
    ui = column(children=[node(), node()])
    call ui_present(ui)
    
    ! Check for quit events
    running = .not. ui_should_close()
  end do

  call ui_shutdown()
end program
```

## Event-Driven Architecture

### Frame Lifecycle Integration

The event system integrates with fortui's frame lifecycle:

```fortran
! Event-driven frame cycle
call ui_frame_begin(timeout_ms)  ! 1. Poll events with timeout
call ui_present(ui)              ! 2. Render UI tree
logical :: quit = ui_should_close()  ! 3. Check quit conditions

! Benefits:
! - Responsive user interaction
! - Efficient CPU usage during idle periods
! - Automatic event coalescing for performance
! - Integrated quit detection
```

### Timeout Strategies

Different timeout values optimize for different use cases:

```fortran
! Idle applications - power efficient
call ui_frame_begin(timeout_ms=250)   ! Wait 250ms for events
! Use case: Dashboard apps, monitoring tools, status displays

! Interactive applications - responsive
call ui_frame_begin(timeout_ms=50)    ! Wait 50ms for events  
! Use case: Text editors, file browsers, games

! Real-time applications - very responsive
call ui_frame_begin(timeout_ms=16)    ! Wait 16ms for events (~60 FPS)
! Use case: Animations, dragging operations, real-time data

! Event coalescing - batch rapid events
call ui_frame_begin(timeout_ms=10)    ! Wait 10ms for events
! Use case: Mouse tracking, rapid key repeat

! Non-blocking poll - immediate return
call ui_frame_begin(timeout_ms=0)     ! Return immediately
! Use case: Busy applications, background processing
```

## Event Types

### Keyboard Events

All keyboard input is automatically handled:

```fortran
! Automatic keyboard event processing
call ui_frame_begin(timeout_ms=200)

! Events detected automatically:
! - Regular key presses (a-z, 0-9, symbols)
! - Special keys (ESC, Enter, Tab, Backspace)
! - Function keys (F1-F12)
! - Arrow keys (Up, Down, Left, Right)
! - Modifier combinations (Ctrl+Key, Alt+Key)
! - Quit sequences (ESC, Ctrl+C, Ctrl+D)
```

**Quit Key Detection:**
```fortran
! Automatic quit detection via ui_should_close()
logical :: should_exit = ui_should_close()

! Quit conditions detected:
! - ESC key press
! - Ctrl+C (SIGINT)
! - Ctrl+D (EOF)
! - Ctrl+Z (handled appropriately)
! - Application quit state
```

### Mouse Events

Complete mouse support for interactive applications:

```fortran
! Automatic mouse event processing
call ui_frame_begin(timeout_ms=50)   ! Responsive for mouse

! Mouse events handled automatically:
! - Click events (left, right, middle buttons)
! - Mouse motion tracking
! - Mouse wheel scrolling
! - Drag and drop operations
! - Coordinate mapping to UI elements
```

### Terminal Events

System-level terminal events are handled gracefully:

```fortran
! Automatic terminal event handling
call ui_frame_begin(timeout_ms=200)

! Terminal events processed:
! - Window resize (SIGWINCH)
! - Terminal disconnect (SIGHUP)
! - Signal interrupts (SIGINT, SIGTERM)
! - Focus change events
! - Terminal capability changes
```

## Performance Optimization

### Event Coalescing

Rapid events are automatically coalesced for optimal performance:

```fortran
! Automatic event coalescing (no configuration needed)
call ui_frame_begin(timeout_ms=10)   ! Enable coalescing

! Coalesced event types:
! - Mouse motion: Only latest position kept
! - Key repeat: Optimized for continuous input
! - Resize events: Batch rapid terminal resizing
! - Scroll events: Combine multiple wheel events

! Critical events never coalesced:
! - Mouse clicks
! - Special key presses (ESC, Enter)
! - Quit signals
```

### Adaptive Timeouts

Optimize timeouts based on application activity:

```fortran
program adaptive_timeouts
  use fortui_core
  implicit none
  
  logical :: user_active = .false.
  integer :: idle_timeout = 250
  integer :: active_timeout = 50
  integer :: current_timeout
  
  call ui_init("tui", 80, 25, "Adaptive App")
  
  do
    ! Adapt timeout based on activity
    if (user_active) then
      current_timeout = active_timeout    ! Responsive when active
    else
      current_timeout = idle_timeout      ! Power-efficient when idle
    end if
    
    call ui_frame_begin(current_timeout)
    
    ! TODO: Detect user activity when widget system available
    ! user_active = has_user_input() .or. animation_running()
    
    call ui_present(ui)
    if (ui_should_close()) exit
  end do
  
  call ui_shutdown()
end program
```

### Background Processing

Handle background tasks efficiently:

```fortran
program background_processing
  use fortui_core
  implicit none
  
  logical :: background_work_pending = .true.
  
  call ui_init("tui", 80, 25, "Background App")
  
  do
    if (background_work_pending) then
      ! Non-blocking event poll for background work
      call ui_frame_begin(timeout_ms=0)
      
      ! Do background processing
      call process_background_tasks()
      
    else
      ! Longer timeout when idle
      call ui_frame_begin(timeout_ms=200)
    end if
    
    call ui_present(ui)
    if (ui_should_close()) exit
  end do
  
  call ui_shutdown()

contains
  subroutine process_background_tasks()
    ! Placeholder for background work
    ! In real app: file operations, network requests, calculations
    background_work_pending = .false.  ! Mark work complete
  end subroutine
end program
```

## Integration Patterns

### State-Driven Updates

Only rebuild UI when state changes:

```fortran
program efficient_updates
  use fortui_core
  implicit none
  
  type(node) :: ui
  logical :: ui_needs_rebuild = .true.
  integer :: counter = 0
  integer :: last_counter = -1
  
  call ui_init("tui", 80, 25, "Efficient App")
  
  do
    call ui_frame_begin(timeout_ms=100)
    
    ! TODO: Update counter based on events when widget system available
    ! if (button_clicked()) counter = counter + 1
    
    ! Only rebuild UI when state changes
    if (counter /= last_counter) then
      ui_needs_rebuild = .true.
      last_counter = counter
    end if
    
    ! Rebuild UI only when necessary
    if (ui_needs_rebuild) then
      ! TODO: Build UI with actual counter display
      ui = column(children=[node(), node()])  ! Placeholder
      ui_needs_rebuild = .false.
    end if
    
    call ui_present(ui)
    if (ui_should_close()) exit
  end do
  
  call ui_shutdown()
end program
```

### Event-Triggered Actions

Respond to specific events efficiently:

```fortran
program event_triggered
  use fortui_core
  implicit none
  
  type(node) :: ui
  logical :: save_requested = .false.
  logical :: refresh_requested = .false.
  
  call ui_init("tui", 80, 25, "Event Triggered App")
  
  do
    call ui_frame_begin(timeout_ms=200)
    
    ! TODO: Detect specific events when widget system available
    ! save_requested = key_pressed(KEY_CTRL_S)
    ! refresh_requested = key_pressed(KEY_F5)
    
    ! Handle triggered actions
    if (save_requested) then
      call handle_save_action()
      save_requested = .false.
    end if
    
    if (refresh_requested) then
      call handle_refresh_action()
      refresh_requested = .false.
    end if
    
    call ui_present(ui)
    if (ui_should_close()) exit
  end do
  
  call ui_shutdown()

contains
  subroutine handle_save_action()
    ! Placeholder for save logic
    print *, "Save action triggered"
  end subroutine
  
  subroutine handle_refresh_action()
    ! Placeholder for refresh logic
    print *, "Refresh action triggered"
  end subroutine
end program
```

## Testing Event Systems

### Mock Event Generation

Test event handling without user interaction:

```fortran
! Mock event testing (framework provided)
program test_events
  use fortui_core
  implicit none
  
  ! Initialize with mock terminal for testing
  call ui_init("tui", 80, 25, "Test Events")
  
  ! TODO: Mock event generation when available
  ! call mock_generate_key_event(KEY_ESC)
  ! call mock_generate_mouse_event(10, 5, MOUSE_LEFT)
  ! call mock_generate_resize_event(100, 30)
  
  ! Test event processing
  call ui_frame_begin(timeout_ms=0)  ! Non-blocking for testing
  
  ! Verify event handling
  if (ui_should_close()) then
    print *, "Quit event detected correctly"
  end if
  
  call ui_shutdown()
end program
```

### Performance Testing

Measure event processing performance:

```fortran
program performance_test
  use fortui_core
  implicit none
  
  integer :: frame_count = 0
  integer :: start_time, end_time
  real :: fps
  
  call ui_init("tui", 80, 25, "Performance Test")
  
  ! TODO: Get system time when available
  ! call system_clock(start_time)
  
  ! Process events for performance measurement
  do while (frame_count < 1000)
    call ui_frame_begin(timeout_ms=0)  ! Non-blocking for max speed
    call ui_present(ui)
    
    frame_count = frame_count + 1
    if (ui_should_close()) exit
  end do
  
  ! TODO: Calculate FPS when timing available
  ! call system_clock(end_time)
  ! fps = real(frame_count) / real(end_time - start_time) * 1000
  ! print *, "Event processing FPS:", fps
  
  call ui_shutdown()
end program
```

## Best Practices

### Responsive Design

Design for optimal user experience:

```fortran
! 1. Use appropriate timeouts
call ui_frame_begin(50)    ! Responsive for interactive apps
call ui_frame_begin(200)   ! Efficient for display apps

! 2. Minimize UI rebuilding
logical :: needs_update = data_changed .or. user_input
if (needs_update) then
  ! Rebuild UI only when necessary
  ui = build_ui_tree()
end if

! 3. Handle quit gracefully
if (ui_should_close()) then
  call cleanup_application_state()
  exit
end if

! 4. Provide visual feedback
! Update UI to show processing state
! Show progress for long operations
! Indicate when events are being handled
```

### Power Efficiency

Optimize for battery life and system resources:

```fortran
! 1. Longer timeouts when idle
integer :: timeout = 200   ! Default idle timeout
if (background_activity) timeout = 50  ! Faster when active

! 2. Avoid unnecessary redraws
if (.not. ui_changed) then
  ! Skip ui_present() call when nothing changed
  cycle
end if

! 3. Use event coalescing
call ui_frame_begin(10)    ! Enable automatic coalescing

! 4. Background processing integration
if (has_background_work()) then
  call ui_frame_begin(0)   ! Non-blocking poll
  call do_background_work()
else
  call ui_frame_begin(250) ! Longer idle timeout
end if
```

### Error Handling

Handle event system errors gracefully:

```fortran
program robust_events
  use fortui_core
  implicit none
  
  logical :: terminal_ok = .true.
  integer :: retry_count = 0
  
  call ui_init("tui", 80, 25, "Robust App")
  
  do
    ! TODO: Add error detection when available
    ! terminal_ok = check_terminal_status()
    
    if (.not. terminal_ok .and. retry_count < 3) then
      ! Attempt recovery
      call ui_shutdown()
      call ui_init("tui", 80, 25, "Robust App")
      retry_count = retry_count + 1
      terminal_ok = .true.
    else if (.not. terminal_ok) then
      ! Give up after 3 retries
      print *, "Terminal connection lost, exiting"
      exit
    end if
    
    call ui_frame_begin(timeout_ms=200)
    call ui_present(ui)
    
    if (ui_should_close()) exit
  end do
  
  call ui_shutdown()
end program
```

## Troubleshooting

### Event Not Detected

```fortran
! If events seem unresponsive:

! 1. Check timeout value
call ui_frame_begin(0)     ! Try immediate polling
call ui_frame_begin(50)    ! Try shorter timeout

! 2. Verify initialization
call ui_shutdown()
call ui_init("tui", 80, 25, "Debug App")

! 3. Test with different event types
! Try ESC key (always works)
! Try mouse clicks
! Try window resize
```

### High CPU Usage

```fortran
! If CPU usage is too high:

! 1. Increase timeout
call ui_frame_begin(200)   ! Longer idle timeout

! 2. Avoid unnecessary updates
if (.not. needs_redraw) cycle  ! Skip frame processing

! 3. Use adaptive timeouts
integer :: timeout = user_active ? 50 : 200
call ui_frame_begin(timeout)

! 4. Check for infinite loops
! Ensure ui_should_close() is checked
! Verify loop exit conditions
```

### Events Lost

```fortran
! If events seem to be lost:

! 1. Reduce timeout for better capture
call ui_frame_begin(10)    ! Enable event coalescing

! 2. Check event coalescing
! Some events are intentionally coalesced
! Critical events are never lost

! 3. Verify terminal mode
! Ensure termbox2 initialized properly
! Check for terminal compatibility issues
```

## Next Steps

- **TUI Backend**: Complete TUI documentation in [TUI_BACKEND_GUIDE.md](TUI_BACKEND_GUIDE.md)
- **Lifecycle API**: Frame management details in [LIFECYCLE_API.md](LIFECYCLE_API.md)
- **Backend Selection**: Choose optimal backend in [BACKEND_SELECTION.md](BACKEND_SELECTION.md)
- **Performance**: Optimization tips in [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)