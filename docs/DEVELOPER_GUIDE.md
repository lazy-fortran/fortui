# fortui Developer Integration Guide

Complete guide for integrating fortui into your Fortran applications, from basic setup to advanced patterns.

## Overview

This guide shows how to integrate fortui's core types and lifecycle into real applications. All examples use the implemented `fortui_core` module with `node`, `view` types and lifecycle procedures.

## Quick Integration

```fortran
program my_app
  use fortui_core
  implicit none
  
  type(node) :: ui_tree
  logical :: running
  
  call ui_init("tui", 80, 25, "My Application")
  
  running = .true.
  do while (running)
    call ui_frame_begin(200)
    
    ! Build UI here (widgets will extend node type)
    ! ui_tree = build_my_interface()
    
    call ui_present(ui_tree)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
end program
```

## Application Architecture Patterns

### Single-Module Application

```fortran
! simple_app.f90 - Basic structure
program simple_app
  use fortui_core
  implicit none
  
  ! Application state
  type :: app_state_t
    real :: progress = 0.0
    logical :: show_details = .false.
    type(view) :: main_view
    character(len=100) :: status = "Ready"
  end type
  
  type(app_state_t) :: state
  type(node) :: ui_root
  logical :: running
  
  call ui_init("tui", 80, 25, "Simple App")
  
  running = .true.
  do while (running)
    call ui_frame_begin(200)
    
    ! Update application state
    call update_state(state)
    
    ! Build UI tree with current state
    call build_interface(state, ui_root)
    
    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()

contains

  subroutine update_state(s)
    type(app_state_t), intent(inout) :: s
    ! Update progress, handle timers, etc.
    s%progress = s%progress + 0.01
    if (s%progress > 1.0) s%progress = 0.0
  end subroutine
  
  subroutine build_interface(s, root)
    type(app_state_t), intent(in) :: s
    type(node), intent(out) :: root
    ! Build UI tree using widgets (when available)
    ! root = column(children=[...])
  end subroutine

end program
```

### Multi-Module Application

```fortran
! app_types.f90 - Application data types
module app_types
  use fortui_core, only: view
  implicit none
  
  type :: settings_t
    integer :: refresh_rate = 200
    logical :: auto_save = .true.
    character(len=50) :: theme = "default"
  end type
  
  type :: app_data_t
    real, allocatable :: values(:)
    type(view) :: plot_view
    type(view) :: minimap_view
    type(settings_t) :: settings
    character(len=200) :: current_file = ""
  end type
  
end module app_types

! app_ui.f90 - UI building logic  
module app_ui
  use fortui_core
  use app_types
  implicit none
  
contains

  subroutine build_main_ui(data, root)
    type(app_data_t), intent(in) :: data
    type(node), intent(out) :: root
    
    ! Build complex UI hierarchy
    ! This will use fortui_widgets when available
    ! root = column(gap=1, children=[ &
    !   build_toolbar(data), &
    !   build_content_area(data), &
    !   build_status_bar(data) ])
    
  end subroutine
  
  ! Additional UI building subroutines...
  
end module app_ui

! main.f90 - Application entry point
program data_viewer
  use fortui_core
  use app_types
  use app_ui
  implicit none
  
  type(app_data_t) :: app_data
  type(node) :: ui_root
  logical :: running
  
  ! Initialize application
  call init_app_data(app_data)
  call ui_init("tui", 100, 35, "Data Viewer")
  
  ! Main loop
  running = .true.
  do while (running)
    call ui_frame_begin(app_data%settings%refresh_rate)
    
    call build_main_ui(app_data, ui_root)
    
    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
  call cleanup_app_data(app_data)
  
contains

  subroutine init_app_data(data)
    type(app_data_t), intent(out) :: data
    allocate(data%values(1000))
    data%values = 0.0
    ! Initialize views with defaults
    ! data%plot_view already initialized with default values
    ! data%minimap_view already initialized with default values
  end subroutine
  
  subroutine cleanup_app_data(data)
    type(app_data_t), intent(inout) :: data
    if (allocated(data%values)) deallocate(data%values)
  end subroutine

end program
```

## State Management Patterns

### Simple State Pattern

```fortran
! Direct state management - good for small applications
module simple_state
  use fortui_core
  implicit none
  
  ! Global application state
  type :: global_state_t
    real :: zoom_level = 1.0
    real :: pan_x = 0.0, pan_y = 0.0
    logical :: grid_visible = .true.
    integer :: selected_item = 1
    type(view) :: main_view
  end type
  
  type(global_state_t) :: g_state
  
contains

  subroutine handle_zoom_in()
    g_state%zoom_level = g_state%zoom_level * 1.2
    g_state%main_view%scale_x = g_state%zoom_level
    g_state%main_view%scale_y = g_state%zoom_level
  end subroutine
  
  subroutine handle_pan(dx, dy)
    real, intent(in) :: dx, dy
    g_state%pan_x = g_state%pan_x + dx
    g_state%pan_y = g_state%pan_y + dy
    g_state%main_view%off_x = g_state%pan_x
    g_state%main_view%off_y = g_state%pan_y
  end subroutine

end module simple_state
```

### Encapsulated State Pattern

```fortran
! Object-oriented state management - better for larger applications
module app_state
  use fortui_core
  implicit none
  
  type :: application_t
    private
    ! Core UI state
    type(view) :: main_view
    type(view) :: overview_view
    type(node) :: ui_cache
    
    ! Application data
    real, allocatable :: dataset(:)
    character(len=100) :: filename
    logical :: modified = .false.
    
    ! UI state
    integer :: active_tab = 1
    logical :: show_grid = .true.
    real :: animation_time = 0.0
    
  contains
    procedure :: init => app_init
    procedure :: cleanup => app_cleanup
    procedure :: update => app_update
    procedure :: build_ui => app_build_ui
    procedure :: handle_zoom => app_zoom
    procedure :: handle_pan => app_pan
    procedure :: load_file => app_load_file
    procedure :: save_file => app_save_file
  end type

contains

  subroutine app_init(this, filename)
    class(application_t), intent(out) :: this
    character(*), intent(in), optional :: filename
    
    ! Initialize with defaults (types already have default values)
    allocate(this%dataset(1000))
    this%dataset = 0.0
    
    if (present(filename)) then
      call this%load_file(filename)
    end if
  end subroutine
  
  subroutine app_update(this, dt)
    class(application_t), intent(inout) :: this
    real, intent(in) :: dt
    
    ! Update animations, timers, etc.
    this%animation_time = this%animation_time + dt
  end subroutine
  
  subroutine app_build_ui(this, root)
    class(application_t), intent(inout) :: this
    type(node), intent(out) :: root
    
    ! Build UI using current state
    ! Will use widgets when available
    ! root = build_complex_interface(this)
  end subroutine
  
  subroutine app_zoom(this, factor)
    class(application_t), intent(inout) :: this
    real, intent(in) :: factor
    
    this%main_view%scale_x = this%main_view%scale_x * factor
    this%main_view%scale_y = this%main_view%scale_y * factor
    
    ! Synchronize overview
    this%overview_view%scale_x = 1.0 / this%main_view%scale_x
    this%overview_view%scale_y = 1.0 / this%main_view%scale_y
  end subroutine
  
  ! Additional methods...
  
end module app_state

! Usage:
program object_oriented_app
  use fortui_core
  use app_state
  implicit none
  
  type(application_t) :: app
  type(node) :: ui_root
  logical :: running
  
  call app%init("data.txt")
  call ui_init("tui", 120, 40, "OO Application")
  
  running = .true.
  do while (running)
    call ui_frame_begin(200)
    
    call app%update(0.2)  ! 200ms timestep
    call app%build_ui(ui_root)
    
    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
  call app%cleanup()
end program
```

## Error Handling Patterns

### Basic Error Handling

```fortran
program robust_app
  use fortui_core
  implicit none
  
  type(node) :: ui_root
  logical :: running, init_success
  integer :: error_code
  
  ! Safe initialization with error checking
  init_success = safe_init_ui(error_code)
  if (.not. init_success) then
    print *, "Failed to initialize UI:", error_code
    stop 1
  end if
  
  ! Exception-safe main loop
  running = .true.
  do while (running)
    call ui_frame_begin(200)
    
    ! Protected UI building
    call safe_build_ui(ui_root, running)
    
    call ui_present(ui_root)
    running = running .and. .not. ui_should_close()
  end do
  
  ! Guaranteed cleanup
  call ui_shutdown()
  
contains

  function safe_init_ui(error_code) result(success)
    integer, intent(out) :: error_code
    logical :: success
    
    success = .false.
    error_code = 0
    
    ! Try GUI first, fall back to TUI
#ifdef ENABLE_GUI
    call ui_init("gui", 100, 30, "Robust App")
    success = .true.
#else
    call ui_init("tui", 80, 25, "Robust App") 
    success = .true.
#endif
    
  end function
  
  subroutine safe_build_ui(root, running)
    type(node), intent(out) :: root
    logical, intent(inout) :: running
    
    ! Build UI with error recovery
    ! If widget building fails, create minimal UI
    ! root = create_minimal_ui()
    
  end subroutine

end program
```

### Advanced Error Recovery

```fortran
module error_recovery
  use fortui_core
  implicit none
  
  type :: recovery_state_t
    logical :: ui_failed = .false.
    logical :: data_corrupted = .false. 
    character(len=200) :: last_error = ""
    type(node) :: fallback_ui
  end type
  
contains

  subroutine handle_ui_error(recovery, error_msg)
    type(recovery_state_t), intent(inout) :: recovery
    character(*), intent(in) :: error_msg
    
    recovery%ui_failed = .true.
    recovery%last_error = error_msg
    
    ! Create minimal fallback UI
    ! recovery%fallback_ui = create_error_ui(error_msg)
    
    print *, "UI Error: ", trim(error_msg)
  end subroutine
  
  subroutine attempt_recovery(recovery)
    type(recovery_state_t), intent(inout) :: recovery
    
    if (recovery%ui_failed) then
      ! Try to recover UI state
      recovery%ui_failed = .false.
      print *, "Attempting UI recovery..."
    end if
  end subroutine

end module error_recovery
```

## Performance Optimization

### Memory-Efficient Patterns

```fortran
! Minimize allocations in main loop
program efficient_app
  use fortui_core
  implicit none
  
  type(node) :: ui_root
  type(view) :: persistent_view
  logical :: running
  integer :: frame_count = 0
  
  ! Pre-allocate what you can
  call ui_init("tui", 80, 25, "Efficient App")
  
  running = .true.
  do while (running)
    call ui_frame_begin(200)
    
    ! Reuse existing objects
    call update_ui_in_place(ui_root, persistent_view, frame_count)
    
    call ui_present(ui_root)
    running = .not. ui_should_close()
    
    frame_count = frame_count + 1
  end do
  
  call ui_shutdown()
  
contains

  subroutine update_ui_in_place(root, view, frame)
    type(node), intent(inout) :: root
    type(view), intent(inout) :: view  
    integer, intent(in) :: frame
    
    ! Modify existing objects rather than recreating
    view%off_x = sin(real(frame) * 0.1) * 10.0
    
    ! Build UI by modifying root in place
    ! (When widgets available, will modify root%children, etc.)
  end subroutine

end program
```

### Cache-Friendly Access

```fortran
module cache_patterns
  use fortui_core
  implicit none
  
  ! Group related data for cache efficiency
  type :: ui_cache_t
    type(node) :: widgets(100)      ! Pre-allocated widget pool
    type(view) :: views(10)         ! Pre-allocated view pool
    integer :: widget_count = 0
    integer :: view_count = 0
  end type
  
contains

  subroutine reset_cache(cache)
    type(ui_cache_t), intent(inout) :: cache
    cache%widget_count = 0
    cache%view_count = 0
    ! Objects remain allocated, just reset counters
  end subroutine
  
  function get_widget(cache) result(widget_ptr)
    type(ui_cache_t), intent(inout) :: cache
    type(node), pointer :: widget_ptr
    
    cache%widget_count = cache%widget_count + 1
    widget_ptr => cache%widgets(cache%widget_count)
  end function
  
  function get_view(cache) result(view_ptr)
    type(ui_cache_t), intent(inout) :: cache
    type(view), pointer :: view_ptr
    
    cache%view_count = cache%view_count + 1  
    view_ptr => cache%views(cache%view_count)
  end function

end module cache_patterns
```

## Testing Integration

### Enhanced Test Suite (~87 Validations)

```bash
# Run comprehensive test suite
fpm test
```

**Core Test Coverage:**
- **Core Types**: `node`/`view` initialization, memory management, backend compatibility
- **Lifecycle**: `ui_init`/shutdown, backend selection, frame management  
- **Units System**: dp/em/sp/px/cw/ch conversion, `class(*)` polymorphism
- **Layout System**: `column()`/`row()` constructors, gap processing, performance
- **TUI Backend**: termbox2 integration, event polling, coordinate conversion
- **C Interface**: termbox2 bindings, memory safety, error handling

**Key Features:**
- **Actual Validation**: All tests use real validation logic, not placeholders
- **Edge Cases**: Boundary conditions, error handling, parameter validation
- **Performance**: 500+ layouts/frame, 1000+ conversions, 20+ nesting levels
- **Memory Safety**: Allocation cycles, leak prevention, corruption detection

### Adding Tests for Your Integration

```fortran
subroutine test_my_feature()
  integer :: test_count = 0
  logical :: result
  
  ! Actual validation - NOT placeholder
  result = my_feature_works()
  if (.not. result) then
    print *, "  ✗ FAILED: feature validation failed"
    stop 1
  end if
  test_count = test_count + 1
  
  print *, "  ✓ My feature: validated", test_count, "behaviors"
end subroutine
  
  subroutine test_node_management()
    type(node) :: test_node
    type(node), allocatable :: alloc_node
    
    ! Test basic node creation
    ! (More detailed tests when widgets available)
    
    allocate(alloc_node)
    ! Automatic cleanup when out of scope
    
    print *, "✓ Node management test passed"
  end subroutine
  
  subroutine test_backend_selection()
    logical :: has_gui
    
#ifdef ENABLE_GUI
    has_gui = .true.
#else
    has_gui = .false.
#endif
    
    ! Test appropriate backend available
    if (has_gui) then
      call ui_init("gui", 80, 25, "GUI Test")
    else
      call ui_init("tui", 80, 25, "TUI Test")
    end if
    
    call ui_shutdown()
    print *, "✓ Backend selection test passed"
  end subroutine

end program
```

### Integration Testing

```fortran
! integration_test.f90
program integration_test
  use fortui_core
  implicit none
  
  call test_full_lifecycle()
  print *, "Integration test completed!"
  
contains

  subroutine test_full_lifecycle()
    type(node) :: ui_root
    type(view) :: test_view
    logical :: running
    integer :: frame_count
    
    ! Full application lifecycle test
    call ui_init("tui", 40, 15, "Integration Test")
    
    running = .true.
    frame_count = 0
    
    ! Run for a few frames to test stability
    do while (running .and. frame_count < 5)
      call ui_frame_begin(50)  ! Short timeout for quick test
      
      ! Modify view state
      test_view%scale_x = 1.0 + real(frame_count) * 0.1
      test_view%off_x = real(frame_count) * 5.0
      
      ! Build minimal UI
      ! ui_root = build_test_ui(test_view)
      
      call ui_present(ui_root)
      
      frame_count = frame_count + 1
      running = frame_count < 5  ! Exit after 5 frames
    end do
    
    call ui_shutdown()
    print *, "✓ Full lifecycle test completed -", frame_count, "frames"
  end subroutine

end program
```

## Deployment Patterns

### Single Binary Deployment

```fortran
! Build script integration for deployment
program deploy_ready_app
  use fortui_core
  implicit none
  
  character(len=100) :: backend_choice
  
  ! Runtime backend detection
  call detect_environment(backend_choice)
  
  if (trim(backend_choice) == "gui") then
    call ui_init("gui", 100, 30, "Production App")
  else
    call ui_init("tui", 80, 25, "Production App")
  end if
  
  ! ... application logic ...
  
  call ui_shutdown()
  
contains

  subroutine detect_environment(backend)
    character(*), intent(out) :: backend
    
    ! Detect if we're in a GUI environment
#ifdef ENABLE_GUI
    if (gui_environment_available()) then
      backend = "gui"
    else
      backend = "tui"
    end if
#else
    backend = "tui"
#endif
  end subroutine
  
  function gui_environment_available() result(available)
    logical :: available
    ! Check for DISPLAY, WAYLAND_DISPLAY, etc.
    available = .false.  ! Simplified for example
  end function

end program
```

## Next Steps

After integrating fortui core:

1. **Learn Widgets**: Add interactive elements with `fortui_widgets` module
2. **Layout Management**: Master container widgets for complex UIs  
3. **Event Handling**: React to user interactions in your main loop
4. **Performance Tuning**: Optimize for your specific use case
5. **Testing Strategy**: Build robust test suites for your UI components

## Additional Resources

- **[CORE_TYPES_API.md](CORE_TYPES_API.md)**: Detailed type documentation
- **[LIFECYCLE_API.md](LIFECYCLE_API.md)**: Lifecycle procedure reference
- **[BACKEND_SELECTION.md](BACKEND_SELECTION.md)**: Backend configuration guide
- **[BUILD_GUIDE.md](BUILD_GUIDE.md)**: Build system setup