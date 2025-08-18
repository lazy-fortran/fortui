# fortui Core Types API

This document provides complete API documentation for fortui's core types: `node` and `view`.

## Overview

The `fortui_core` module provides the foundational types and lifecycle management for building UIs. These types are backend-agnostic and work identically whether compiled for TUI or GUI backends.

## Quick Example

```fortran
program demo_core_types
  use fortui_core
  implicit none
  
  type(node) :: ui_root
  type(view) :: plot_view
  logical :: running
  
  call ui_init(backend="tui", width=80, height=25, title="Core Types Demo")
  
  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)
    
    ! Use core types here - ui_root and plot_view
    ! (widget operations will be added via fortui_widgets module)
    
    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
end program
```

## Core Types

### node Type

The `node` type is the building block for all UI elements. It serves as the base type that will be extended by specific widget types.

```fortran
type :: node
    ! Minimal structure - extensible for widgets
    ! Backend-agnostic design
end type node
```

**Usage:**
```fortran
type(node) :: my_node        ! Stack allocation
type(node), allocatable :: dynamic_node  ! Dynamic allocation

! Fortran automatically handles memory management
allocate(dynamic_node)
! Automatically deallocated when out of scope
```

**Key Properties:**
- **Extensible**: Designed to be extended by widget-specific types
- **Backend-agnostic**: Identical behavior in TUI and GUI modes
- **Memory-safe**: Automatic Fortran memory management
- **Minimal**: Contains only essential structure for UI tree building

### view Type

The `view` type manages pan and zoom state for plot areas and viewports.

```fortran
type :: view
    real :: scale_x = 1.0  ! Zoom factor X-axis (default: no zoom)
    real :: scale_y = 1.0  ! Zoom factor Y-axis (default: no zoom)
    real :: off_x = 0.0    ! Pan offset X-axis (default: no pan)
    real :: off_y = 0.0    ! Pan offset Y-axis (default: no pan)
end type view
```

**Usage Examples:**

```fortran
! Default initialization - no zoom, no pan
type(view) :: my_view  ! scale_x=1.0, scale_y=1.0, off_x=0.0, off_y=0.0

! Zoom operations
my_view%scale_x = my_view%scale_x * 1.5  ! Zoom in X by 1.5x
my_view%scale_y = my_view%scale_y * 1.5  ! Zoom in Y by 1.5x

! Pan operations  
my_view%off_x = 100.0   ! Pan right by 100 units
my_view%off_y = -50.0   ! Pan up by 50 units

! Reset to defaults
my_view = view()  ! Back to scale=1.0, offset=0.0
```

**Practical Zoom/Pan Example:**
```fortran
subroutine handle_zoom_in(v)
  type(view), intent(inout) :: v
  real, parameter :: ZOOM_FACTOR = 1.2
  v%scale_x = v%scale_x * ZOOM_FACTOR
  v%scale_y = v%scale_y * ZOOM_FACTOR
end subroutine

subroutine handle_zoom_out(v)
  type(view), intent(inout) :: v
  real, parameter :: ZOOM_FACTOR = 1.0/1.2
  v%scale_x = v%scale_x * ZOOM_FACTOR
  v%scale_y = v%scale_y * ZOOM_FACTOR
end subroutine

subroutine handle_pan(v, dx, dy)
  type(view), intent(inout) :: v
  real, intent(in) :: dx, dy
  v%off_x = v%off_x + dx
  v%off_y = v%off_y + dy
end subroutine
```

## Memory Management

Both core types follow Fortran's automatic memory management:

```fortran
! Stack allocation - automatic cleanup
type(node) :: stack_node
type(view) :: stack_view

! Dynamic allocation - automatic cleanup when out of scope
type(node), allocatable :: heap_node
allocate(heap_node)
! No manual deallocation needed

! Array allocation
type(view), allocatable :: view_array(:)
allocate(view_array(10))
! Automatically deallocated when out of scope
```

**Critical Rule**: Never manually deallocate these types. Fortran handles all memory management automatically.

## Backend Compatibility

Both types are completely backend-agnostic:

```fortran
! Identical behavior regardless of compilation mode
#ifdef ENABLE_GUI
  ! Same type definitions and behavior
#else  
  ! Exact same type definitions and behavior
#endif

! Your code works identically:
type(node) :: ui_element   ! Works in TUI and GUI
type(view) :: plot_state   ! Works in TUI and GUI
```

**Compilation Modes:**
- **TUI-only**: `fpm build` (default)
- **GUI-enabled**: `fpm build --flag "-DENABLE_GUI"` (when raylib available)

## Integration Patterns

### Basic Application Structure

```fortran
program my_app
  use fortui_core
  implicit none
  
  type(node) :: root_ui
  type(view) :: main_view
  logical :: running
  
  ! 1. Initialize
  call ui_init(backend="tui", width=80, height=25, title="My App")
  
  ! 2. Main loop
  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)
    
    ! 3. Build UI (using widgets from fortui_widgets)
    ! root_ui = build_my_interface(main_view)
    
    ! 4. Present and check exit
    call ui_present(root_ui)
    running = .not. ui_should_close()
  end do
  
  ! 5. Cleanup
  call ui_shutdown()
end program
```

### Multiple Views Pattern

```fortran
type :: app_state
  type(view) :: plot_view
  type(view) :: minimap_view
  type(node) :: ui_tree
end type

subroutine update_views(state, zoom_factor)
  type(app_state), intent(inout) :: state
  real, intent(in) :: zoom_factor
  
  ! Synchronize main plot and minimap
  state%plot_view%scale_x = state%plot_view%scale_x * zoom_factor
  state%plot_view%scale_y = state%plot_view%scale_y * zoom_factor
  
  ! Minimap shows inverse zoom
  state%minimap_view%scale_x = 1.0 / state%plot_view%scale_x
  state%minimap_view%scale_y = 1.0 / state%plot_view%scale_y
end subroutine
```

## Error Handling

Core types are designed for robust usage:

```fortran
! Types have safe defaults
type(view) :: safe_view  ! Always initialized to sensible values

! No invalid states possible
safe_view%scale_x = 0.0  ! Warning: zero scale, but not an error
safe_view%off_x = 1.0e10 ! Large offset, but still valid

! Memory allocation is safe
type(node), allocatable :: safe_node
if (.not. allocated(safe_node)) then
  allocate(safe_node)  ! Safe allocation
end if
```

## Performance Notes

- **Stack allocation preferred**: Use `type(node) :: my_node` for better performance
- **View updates are cheap**: Simple real number assignments
- **No hidden allocations**: Core types contain no pointers or allocatable components
- **Backend-agnostic overhead**: Zero - same performance in TUI and GUI modes

## Next Steps

After mastering core types:

1. **Widget Usage**: Learn `fortui_widgets` module for interactive elements
2. **Layout Management**: Understand container widgets (`column`, `row`)  
3. **Event Handling**: React to user interactions in your main loop
4. **Backend Selection**: Choose TUI vs GUI at runtime

See [WIDGET_API.md](WIDGET_API.md) for widget documentation.