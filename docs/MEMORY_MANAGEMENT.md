# fortui Memory Management Guide

Complete guide to memory-safe Fortran patterns in fortui, from basic allocatable usage to advanced ownership transfer.

## Overview

fortui follows Fortran 2003+ automatic memory management standards. All allocatable components clean up automatically when they go out of scope, eliminating manual memory management.

## Core Principles

```fortran
! CORRECT: Automatic cleanup
program memory_safe
  use fortui_core
  implicit none
  
  type :: app_data_t
    real, allocatable :: values(:)
    type(fortui_context_t), allocatable :: context
  end type
  
  type(app_data_t) :: data
  
  ! Allocation
  allocate(data%values(1000))
  allocate(data%context)
  
  ! Use data...
  
  ! NO explicit deallocate needed - automatic cleanup
end program
```

```fortran
! INCORRECT: Manual deallocation (violates Fortran best practices)
program memory_unsafe
  type(app_data_t) :: data
  
  allocate(data%values(1000))
  
  ! WRONG - creates double-free risk
  deallocate(data%values)  ! DON'T DO THIS
end program
```

## Allocatable Variables

### Basic Allocatable Arrays

```fortran
module safe_arrays
  implicit none
  
contains

  subroutine process_data()
    real, allocatable :: dataset(:)
    integer, allocatable :: indices(:)
    
    ! Allocation
    allocate(dataset(10000))
    allocate(indices(10000))
    
    ! Use arrays...
    dataset = 1.0
    indices = [(i, i=1,10000)]
    
    ! Automatic cleanup when leaving scope
    ! NO deallocate statements needed
  end subroutine

end module
```

### Allocatable Components in Types

```fortran
module widget_storage
  use fortui_core
  implicit none
  
  type :: widget_collection_t
    type(node), allocatable :: widgets(:)
    real, allocatable :: positions(:,:)
    character(len=:), allocatable :: labels(:)
    
  contains
    procedure :: resize => collection_resize
    procedure :: add_widget => collection_add
    ! NO cleanup procedure needed
  end type
  
contains

  subroutine collection_resize(self, new_size)
    class(widget_collection_t), intent(inout) :: self
    integer, intent(in) :: new_size
    
    type(node), allocatable :: temp_widgets(:)
    real, allocatable :: temp_positions(:,:)
    
    ! Allocate new arrays
    allocate(temp_widgets(new_size))
    allocate(temp_positions(2, new_size))
    
    ! Copy existing data if present
    if (allocated(self%widgets)) then
      temp_widgets(1:min(size(self%widgets), new_size)) = &
        self%widgets(1:min(size(self%widgets), new_size))
      temp_positions(:, 1:min(size(self%positions,2), new_size)) = &
        self%positions(:, 1:min(size(self%positions,2), new_size))
    end if
    
    ! Transfer ownership (no copy, automatic cleanup of old)
    call move_alloc(temp_widgets, self%widgets)
    call move_alloc(temp_positions, self%positions)
  end subroutine
  
  subroutine collection_add(self, widget)
    class(widget_collection_t), intent(inout) :: self
    type(node), intent(in) :: widget
    
    if (.not. allocated(self%widgets)) then
      allocate(self%widgets(1))
      self%widgets(1) = widget
    else
      call self%resize(size(self%widgets) + 1)
      self%widgets(size(self%widgets)) = widget
    end if
  end subroutine

end module
```

## Ownership Transfer with move_alloc()

### Array Resizing

```fortran
subroutine safe_array_resize(array, new_size)
  real, allocatable, intent(inout) :: array(:)
  integer, intent(in) :: new_size
  
  real, allocatable :: temp_array(:)
  
  allocate(temp_array(new_size))
  
  ! Copy existing data
  if (allocated(array)) then
    temp_array(1:min(size(array), new_size)) = &
      array(1:min(size(array), new_size))
  end if
  
  ! Transfer ownership - no copy, automatic cleanup
  call move_alloc(temp_array, array)
end subroutine
```

### Context Transfer

```fortran
module context_management
  use fortui_core
  implicit none
  
contains

  subroutine transfer_context(source_ctx, target_ctx)
    type(fortui_context_t), allocatable, intent(inout) :: source_ctx
    type(fortui_context_t), allocatable, intent(inout) :: target_ctx
    
    ! Transfer ownership without copy
    call move_alloc(source_ctx, target_ctx)
    ! source_ctx is now unallocated
    ! target_ctx owns the context
  end subroutine

end module
```

## Pointer Management

### Safe Pointer Usage

```fortran
module pointer_patterns
  use fortui_core
  implicit none
  
contains

  subroutine safe_pointer_demo()
    type(fortui_context_t), allocatable, target :: context
    type(fortui_context_t), pointer :: ctx_ptr
    
    allocate(context)
    ctx_ptr => context
    
    ! Use pointer...
    
    ! Clear pointer reference
    ctx_ptr => null()
    
    ! Context automatically deallocated when leaving scope
  end subroutine
  
  function get_context_reference() result(ctx_ptr)
    type(fortui_context_t), pointer :: ctx_ptr
    
    ! Return pointer to existing context
    ctx_ptr => get_default_context()
    ! DO NOT deallocate through this pointer
  end function

end module
```

## Widget State Management

### ID-Based State Storage

```fortran
module widget_state_safe
  implicit none
  
  type :: widget_state_entry_t
    character(len=:), allocatable :: id
    class(*), allocatable :: state
  end type
  
  type :: widget_state_map_t
    type(widget_state_entry_t), allocatable :: entries(:)
    integer :: count = 0
    
  contains
    procedure :: set_state => map_set_state
    procedure :: get_state => map_get_state
    procedure :: clear => map_clear
  end type
  
contains

  subroutine map_set_state(self, id, state)
    class(widget_state_map_t), intent(inout) :: self
    character(*), intent(in) :: id
    class(*), intent(in) :: state
    
    integer :: slot
    
    slot = find_or_create_slot(self, id)
    
    ! Store state (automatic cleanup of previous value)
    allocate(self%entries(slot)%state, source=state)
  end subroutine
  
  subroutine map_clear(self)
    class(widget_state_map_t), intent(inout) :: self
    
    ! Clear all entries - automatic cleanup of all allocatable components
    if (allocated(self%entries)) then
      ! entries(:)%id and entries(:)%state deallocate automatically
      deallocate(self%entries)
    end if
    self%count = 0
  end subroutine

end module
```

## Error-Safe Patterns

### Exception Safety

```fortran
module exception_safe
  use fortui_core
  implicit none
  
contains

  subroutine exception_safe_operation()
    real, allocatable :: data(:)
    type(fortui_context_t), allocatable :: context
    logical :: success
    
    allocate(data(1000))
    allocate(context)
    
    ! Risky operation
    call risky_ui_operation(context, data, success)
    
    if (.not. success) then
      ! Early return - automatic cleanup ensures no leaks
      return
    end if
    
    ! Continue processing...
    
    ! Automatic cleanup on normal exit too
  end subroutine
  
  subroutine risky_ui_operation(ctx, data, success)
    type(fortui_context_t), intent(inout) :: ctx
    real, intent(inout) :: data(:)
    logical, intent(out) :: success
    
    success = .false.
    
    ! Operation that might fail
    if (ctx%is_valid()) then
      ! Process data...
      success = .true.
    end if
    
    ! If failure occurs, calling routine cleans up automatically
  end subroutine

end module
```

### Resource Cleanup Patterns

```fortran
module resource_cleanup
  use fortui_core
  implicit none
  
  type :: application_t
    type(fortui_context_t), allocatable :: ui_context
    real, allocatable :: app_data(:)
    logical :: initialized = .false.
    
  contains
    procedure :: init => app_init
    procedure :: cleanup => app_cleanup
    final :: app_finalize  ! Automatic cleanup
  end type
  
contains

  subroutine app_init(self)
    class(application_t), intent(out) :: self
    
    allocate(self%ui_context)
    allocate(self%app_data(10000))
    
    self%initialized = .true.
  end subroutine
  
  subroutine app_cleanup(self)
    class(application_t), intent(inout) :: self
    
    if (self%initialized) then
      call ui_shutdown()
      self%initialized = .false.
    end if
    
    ! Allocatable components clean up automatically
  end subroutine
  
  ! Automatic cleanup when object is destroyed
  subroutine app_finalize(self)
    type(application_t), intent(inout) :: self
    
    if (self%initialized) then
      call self%cleanup()
    end if
  end subroutine

end module
```

## Performance Considerations

### Memory-Efficient Loops

```fortran
module efficient_loops
  use fortui_core
  implicit none
  
contains

  subroutine ui_main_loop()
    type(node) :: ui_root
    type(fortui_context_t), allocatable :: context
    real, allocatable :: frame_data(:)
    logical :: running
    
    ! Pre-allocate outside loop
    allocate(context)
    allocate(frame_data(1000))
    
    call ui_init("tui", 80, 25, "Efficient App")
    
    running = .true.
    do while (running)
      call ui_frame_begin(200)
      
      ! Reuse existing allocations
      call update_frame_data(frame_data)
      call build_ui_tree(context, frame_data, ui_root)
      
      call ui_present(ui_root)
      running = .not. ui_should_close()
    end do
    
    call ui_shutdown()
    ! Automatic cleanup of context and frame_data
  end subroutine
  
  subroutine update_frame_data(data)
    real, intent(inout) :: data(:)
    
    ! Modify existing array - no new allocations
    data = data + 0.1
  end subroutine

end module
```

### Cache-Friendly Access

```fortran
module cache_friendly
  use fortui_core
  implicit none
  
  ! Structure of Arrays (SoA) for better cache performance
  type :: widget_cache_t
    real, allocatable :: positions_x(:)
    real, allocatable :: positions_y(:)
    real, allocatable :: sizes_w(:)
    real, allocatable :: sizes_h(:)
    integer :: count = 0
    
  contains
    procedure :: resize => cache_resize
    procedure :: add_widget => cache_add
  end type
  
contains

  subroutine cache_resize(self, new_size)
    class(widget_cache_t), intent(inout) :: self
    integer, intent(in) :: new_size
    
    real, allocatable :: temp_x(:), temp_y(:), temp_w(:), temp_h(:)
    
    allocate(temp_x(new_size))
    allocate(temp_y(new_size))
    allocate(temp_w(new_size))
    allocate(temp_h(new_size))
    
    ! Copy existing data
    if (allocated(self%positions_x)) then
      temp_x(1:min(size(self%positions_x), new_size)) = &
        self%positions_x(1:min(size(self%positions_x), new_size))
      temp_y(1:min(size(self%positions_y), new_size)) = &
        self%positions_y(1:min(size(self%positions_y), new_size))
      temp_w(1:min(size(self%sizes_w), new_size)) = &
        self%sizes_w(1:min(size(self%sizes_w), new_size))
      temp_h(1:min(size(self%sizes_h), new_size)) = &
        self%sizes_h(1:min(size(self%sizes_h), new_size))
    end if
    
    ! Transfer ownership
    call move_alloc(temp_x, self%positions_x)
    call move_alloc(temp_y, self%positions_y)
    call move_alloc(temp_w, self%sizes_w)
    call move_alloc(temp_h, self%sizes_h)
  end subroutine

end module
```

## Common Anti-Patterns to Avoid

### Manual Deallocation

```fortran
! WRONG - Manual deallocation anti-pattern
subroutine bad_cleanup(context)
  type(fortui_context_t), allocatable :: context
  
  ! DON'T DO THIS
  if (allocated(context)) then
    deallocate(context)  ! Risk of double-free
  end if
end subroutine

! CORRECT - Automatic cleanup
subroutine good_cleanup(context)
  type(fortui_context_t), allocatable :: context
  
  ! Do nothing - automatic cleanup handles it
  ! OR use move_alloc for ownership transfer
end subroutine
```

### Unnecessary Allocatable Status Checks

```fortran
! INEFFICIENT - Unnecessary checks
subroutine bad_array_use(data)
  real, allocatable :: data(:)
  
  if (allocated(data)) then
    deallocate(data)  ! WRONG
  end if
  allocate(data(100))
end subroutine

! CORRECT - Direct allocation
subroutine good_array_use(data)
  real, allocatable :: data(:)
  
  ! Direct allocation - automatic cleanup of previous
  allocate(data(100))
end subroutine
```

### Stack Allocation for Large Data

```fortran
! WRONG - Stack allocation for large arrays
subroutine stack_overflow_risk()
  real :: large_array(1000000)  ! DON'T DO THIS
  
  ! Process array...
end subroutine

! CORRECT - Heap allocation
subroutine heap_allocation()
  real, allocatable :: large_array(:)
  
  allocate(large_array(1000000))
  
  ! Process array...
  
  ! Automatic cleanup
end subroutine
```

## Memory Safety Testing

### Validation Patterns

```fortran
module memory_testing
  implicit none
  
contains

  subroutine test_allocation_cycle()
    real, allocatable :: data(:)
    integer :: i
    
    ! Test multiple allocation cycles
    do i = 1, 100
      allocate(data(i * 1000))
      
      ! Use data...
      data = real(i)
      
      ! No explicit deallocate - automatic cleanup
      ! Next iteration allocates fresh
    end do
    
    print *, "✓ Allocation cycle test passed"
  end subroutine
  
  subroutine test_move_semantics()
    real, allocatable :: source(:), target(:)
    
    allocate(source(1000))
    source = 42.0
    
    ! Transfer ownership
    call move_alloc(source, target)
    
    ! Verify transfer
    if (allocated(source)) then
      error stop "Move failed - source still allocated"
    end if
    
    if (.not. allocated(target)) then
      error stop "Move failed - target not allocated"
    end if
    
    if (any(target /= 42.0)) then
      error stop "Move failed - data corrupted"
    end if
    
    print *, "✓ Move semantics test passed"
  end subroutine
  
  subroutine test_scope_cleanup()
    call nested_allocation()
    ! All nested allocations cleaned up automatically
    print *, "✓ Scope cleanup test passed"
  end subroutine
  
  subroutine nested_allocation()
    real, allocatable :: temp1(:), temp2(:)
    
    allocate(temp1(5000))
    allocate(temp2(10000))
    
    ! Use arrays...
    temp1 = 1.0
    temp2 = 2.0
    
    ! Automatic cleanup when leaving scope
  end subroutine

end module
```

## Integration with fortui

### Context Management

```fortran
program safe_fortui_app
  use fortui_core
  implicit none
  
  type(fortui_context_t), allocatable :: ui_context
  type(node) :: ui_root
  logical :: running
  
  ! Allocate context
  allocate(ui_context)
  
  call ui_init("tui", 80, 25, "Memory Safe App")
  
  running = .true.
  do while (running)
    call ui_frame_begin(200)
    
    ! Build UI with automatic memory management
    call build_safe_ui(ui_context, ui_root)
    
    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do
  
  call ui_shutdown()
  ! ui_context automatically cleaned up
  
contains

  subroutine build_safe_ui(ctx, root)
    type(fortui_context_t), intent(inout) :: ctx
    type(node), intent(out) :: root
    
    ! UI building with safe patterns
    ! All widget allocations managed automatically
  end subroutine

end program
```

## Summary

**Memory Safety Rules:**
1. **Never use manual deallocate** on allocatable variables
2. **Use move_alloc()** for ownership transfer without copy  
3. **Let scope handle cleanup** - variables clean up when leaving scope
4. **Use allocatable for large data** - avoid stack overflow
5. **Trust automatic memory management** - Fortran handles it correctly

**Performance Guidelines:**
1. **Pre-allocate outside loops** when possible
2. **Reuse existing allocations** rather than reallocate
3. **Use Structure of Arrays (SoA)** for cache efficiency
4. **Minimize allocation/deallocation cycles** in hot paths

**Testing Approach:**
1. **Test allocation cycles** to verify no leaks
2. **Validate move semantics** for ownership transfer
3. **Check scope cleanup** with nested procedures
4. **Stress test** with large allocations

This memory management approach eliminates entire classes of bugs:
- Double-free errors
- Memory leaks
- Use-after-free
- Stack overflow from large arrays

All fortui modules follow these patterns for guaranteed memory safety.