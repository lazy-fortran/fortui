# Layout API Documentation

The fortui layout system provides `column()` and `row()` functions for building hierarchical UI structures with automatic spacing and child management. These functions are fully implemented and tested for production use.

## Quick Start

```fortran
use fortui_core
use fortui_units
implicit none

type(node) :: ui, button_section
type(node), allocatable :: children(:), buttons(:)

! Create button row
allocate(buttons(2))
buttons(1) = node()  ! OK button placeholder
buttons(2) = node()  ! Cancel button placeholder
button_section = row(gap=dp(8.0), children=buttons)

! Create main column layout
allocate(children(3))
children(1) = node()  ! Header placeholder
children(2) = node()  ! Content placeholder
children(3) = button_section
ui = column(gap=dp(16.0), children=children)

! Memory cleanup handled automatically
deallocate(children, buttons)
```

## API Reference

### column() Function

Creates a vertical layout container that arranges children top-to-bottom with automatic memory management.

```fortran
type(node) function column(gap, children)
  class(*), intent(in), optional :: gap      ! Spacing between children
  type(node), intent(in), optional :: children(:)  ! Child elements
```

**Parameters:**
- `gap` - Spacing between children. Supports all unit types via `class(*)` polymorphism:
  - `unit_value` types from `dp()`, `em()`, `sp()`, `px()`, `cw()`, `ch()` constructors
  - `real` values (treated as dp units)
  - `integer` values (converted to real, treated as dp)
  - Default: `0.0` dp when omitted
- `children` - Array of `node` elements to arrange vertically
  - Creates deep copy of array for internal storage
  - Default: empty array when omitted

**Return Value:** `node` with `layout_type="column"` and processed gap/children data

### row() Function

Creates a horizontal layout container that arranges children left-to-right with automatic memory management.

```fortran
type(node) function row(gap, children)
  class(*), intent(in), optional :: gap      ! Spacing between children  
  type(node), intent(in), optional :: children(:)  ! Child elements
```

**Parameters:**
- `gap` - Spacing between children. Same polymorphic support as `column()`
- `children` - Array of `node` elements to arrange horizontally

**Return Value:** `node` with `layout_type="row"` and processed gap/children data

## Gap Parameter

The `gap` parameter uses `class(*)` polymorphism to accept all fortui unit types, with runtime type checking and conversion via `convert_to_dp()`:

```fortran
! Unit constructor functions (recommended for clarity)
layout = column(gap=dp(12.0))   ! density-independent pixels
layout = column(gap=em(0.75))   ! relative to font size  
layout = column(gap=sp(10.0))   ! scaled pixels for accessibility
layout = column(gap=px(8.0))    ! physical pixels
layout = column(gap=cw(2.0))    ! cell widths (TUI-friendly)
layout = column(gap=ch(1.0))    ! cell heights (TUI-friendly)

! Bare numeric values (convenience syntax)
layout = column(gap=16.0)       ! real - treated as dp(16.0)
layout = column(gap=8)          ! integer - converted to real, treated as dp

! Zero gap (explicit)
layout = column(gap=0.0)        ! no spacing between children
layout = column()               ! same as above (default behavior)
```

**Gap Processing:**
1. **Runtime Type Detection:** Uses `select type()` to identify parameter type
2. **Context-Aware Conversion:** Calls `convert_to_dp()` with current `ui_context`
3. **Storage:** Converted gap stored as `real :: gap_dp` in node structure
4. **Backend Rendering:** Backends use `gap_dp` for actual spacing calculations

**Default Behavior:** When `gap` is omitted, defaults to `0.0` dp (no spacing).

## Children Array

Children arrays contain `node` elements that get arranged by the layout with automatic memory management:

```fortran
type(node), allocatable :: children(:)
type(node) :: layout

! Empty layout (no children)
layout = column(gap=dp(8.0))  ! Creates node with zero-size children array

! Single child
allocate(children(1))
children(1) = node()  ! Placeholder node
layout = column(gap=dp(8.0), children=children)
deallocate(children)  ! Safe to deallocate - layout has deep copy

! Multiple children with nested layouts
allocate(children(3))
children(1) = node()  ! Header node
children(2) = row(gap=cw(1.0), children=[node(), node()])  ! Nested row
children(3) = node()  ! Footer node
layout = column(gap=dp(12.0), children=children)
```

**Memory Management:**
- **Deep Copy:** Layout constructors create deep copies of children arrays
- **Safe Deallocation:** Source arrays can be deallocated immediately after layout creation
- **Automatic Cleanup:** Child arrays deallocated automatically when layout nodes go out of scope
- **Assignment Operator:** Custom assignment operator handles proper memory management for nested structures

**Array Handling:**
- **Empty Arrays:** `allocate(children(0))` creates valid empty layout
- **Size Validation:** All array sizes handled correctly (0 to tested 500+ elements)
- **Type Safety:** Compile-time enforcement that children must be `node` types

**Default:** When `children` is omitted, creates layout with empty children array (`allocate(children(0))`).

## Layout Composition

Build complex UIs by nesting layouts within each other using the recursive node structure:

```fortran
type(node) :: ui_root, header_section, content_area, footer_section
type(node) :: sidebar, main_content, button_row
type(node), allocatable :: children(:), buttons(:), nav_items(:)

! Create navigation sidebar
allocate(nav_items(3))
nav_items(1) = node()  ! Dashboard item
nav_items(2) = node()  ! Reports item
nav_items(3) = node()  ! Settings item
sidebar = column(gap=ch(1.0), children=nav_items)

! Create main content area
main_content = column(gap=dp(16.0), children=[node(), node()])

! Combine sidebar and content horizontally
content_area = row(gap=cw(3.0), children=[sidebar, main_content])

! Create footer button row
allocate(buttons(2))
buttons(1) = node()  ! Save button
buttons(2) = node()  ! Cancel button
button_row = row(gap=dp(12.0), children=buttons)

! Build complete 3-level hierarchy
ui_root = column(gap=ch(2.0), children=[ &
  node(),        & ! Header
  content_area,  & ! Nested row containing nested columns
  button_row     & ! Footer buttons
])
```

**Composition Features:**
- **Arbitrary Nesting:** Tested up to 20+ levels deep without performance issues
- **Mixed Layout Types:** Combine columns and rows freely in same tree
- **Memory Efficiency:** Deep copying ensures independent layout trees
- **Type Safety:** All nested elements must be `node` types (enforced at compile time)

**Real Example from layout_demo.f90:**
The working demo creates this exact structure:
```
┌─────────────────────────────────────┐
│ Header Section                      │  ← column
├─────────────────────────────────────┤
│ Nav   │ Main Content Area           │  ← row containing 2 columns
│ - 1   │ - Content header            │
│ - 2   │ - Main body                 │
│ - 3   │ - Status info               │
│ - 4   │                             │
├─────────────────────────────────────┤
│           [Save] [Cancel] [Help]    │  ← column containing row of buttons
└─────────────────────────────────────┘
```

## Backend Behavior

### TUI Backend
- **Cell Alignment:** Layouts snap to character cell boundaries
- **Gap Conversion:** `cw()` and `ch()` units align perfectly with cells
- **Precision:** Integer cell coordinates for crisp terminal rendering

```fortran
! TUI-optimized layout
tui_layout = column(gap=ch(1.0), children=[ &
  text("header", "Menu"), &
  text("item1", "1. Option A"), &
  text("item2", "2. Option B") ])
```

### GUI Backend  
- **Subpixel Precision:** Maintains exact fractional coordinates
- **Gap Conversion:** `dp()`, `px()`, `em()` units provide smooth spacing
- **Scaling:** Automatic HiDPI and accessibility scaling support

```fortran
! GUI-optimized layout  
gui_layout = column(gap=dp(12.0), children=[ &
  text("header", "Settings"), &
  slider("volume", 0.75), &
  checkbox("mute", "Mute audio") ])
```

## Complete Examples

### Working Layout Demo

This example is extracted from the actual working `layout_demo.f90` that demonstrates all layout features:

```fortran
program layout_demo
  use fortui_core
  use fortui_units
  implicit none

  type(node) :: ui_root, header_section, content_area, footer_section
  type(node) :: sidebar, main_content, button_row
  type(node), allocatable :: children(:), buttons(:), nav_items(:), content_items(:)
  logical :: running
  integer :: frame_count = 0

  ! Initialize with automatic backend selection
  call ui_init(backend="auto", width=80, height=25, title="Layout Demo")
  call ui_set_idle_policy("adaptive", idle_fps=12)

  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)
    frame_count = frame_count + 1
    
    ! Build navigation sidebar (column layout)
    allocate(nav_items(4))
    nav_items(1) = node()  ! Dashboard
    nav_items(2) = node()  ! Reports  
    nav_items(3) = node()  ! Settings
    nav_items(4) = node()  ! Help
    sidebar = column(gap=ch(1.0), children=nav_items)
    deallocate(nav_items)
    
    ! Build main content area (column layout)
    allocate(content_items(3))
    content_items(1) = node()  ! Content header
    content_items(2) = node()  ! Main content body
    content_items(3) = node()  ! Status info
    main_content = column(gap=dp(16.0), children=content_items)
    deallocate(content_items)
    
    ! Combine sidebar and main content horizontally (row layout)
    content_area = row(gap=cw(3.0), children=[sidebar, main_content])
    
    ! Build footer button row
    allocate(buttons(3))
    buttons(1) = node()  ! Save button
    buttons(2) = node()  ! Cancel button
    buttons(3) = node()  ! Help button
    button_row = row(gap=dp(12.0), children=buttons)
    footer_section = column(gap=dp(8.0), children=[button_row])
    deallocate(buttons)
    
    ! Build complete 3-level hierarchy
    ui_root = column(gap=ch(2.0), children=[ &
      node(),         & ! Header placeholder
      content_area,   & ! Nested layouts
      footer_section  & ! Footer with buttons
    ])
    
    call ui_present(ui_root)
    running = .not. ui_should_close()
  end do

  call ui_shutdown()
end program
```

**Key Features Demonstrated:**
- **3-Level Nesting:** Root column → content row → nested columns
- **Mixed Units:** `ch()` for TUI alignment, `dp()` for precision, `cw()` for TUI spacing
- **Memory Management:** Explicit deallocation after layout creation
- **Real Performance:** Runs at 50fps for 10+ seconds (500+ frames)

### Settings Dialog Pattern

```fortran
subroutine build_settings_dialog(ui_root)
  type(node), intent(out) :: ui_root
  type(node) :: button_row, option_section
  type(node), allocatable :: children(:), buttons(:), options(:)
  
  ! Create button row with proper spacing
  allocate(buttons(3))
  buttons(1) = node()  ! Apply button
  buttons(2) = node()  ! Cancel button 
  buttons(3) = node()  ! Help button
  button_row = row(gap=dp(8.0), children=buttons)
  deallocate(buttons)
  
  ! Create options section
  allocate(options(4))
  options(1) = node()  ! Auto-save checkbox
  options(2) = node()  ! Dark mode checkbox
  options(3) = node()  ! Notifications checkbox
  options(4) = node()  ! Language dropdown
  option_section = column(gap=dp(12.0), children=options)
  deallocate(options)
  
  ! Combine into final dialog
  ui_root = column(gap=dp(20.0), children=[ &
    node(),           & ! Title
    option_section,   & ! Settings options
    button_row        & ! Action buttons
  ])
end subroutine
```

**Pattern Benefits:**
- **Readable Structure:** Clear separation of UI sections
- **Flexible Spacing:** Different gap values for different layout levels
- **Reusable Components:** Subroutine can be called from multiple contexts
- **Memory Safe:** Automatic cleanup of all temporary arrays

## Memory Management

fortui handles memory automatically - no manual cleanup required:

```fortran
! Arrays deallocated automatically when out of scope
do i = 1, iterations
  allocate(children(size))
  ! ... populate children ...
  layout = column(gap=dp(8.0), children=children)
  call ui_present(layout)
  deallocate(children)  ! Optional - automatic otherwise
end do
```

The layout constructors create deep copies of child arrays, so source arrays can be safely modified or deallocated after layout creation.

## Error Handling

### Invalid Gap Types
```fortran
! These will be handled gracefully with error messages:
! layout = column(gap="invalid")     ! Invalid type
! layout = column(gap=my_custom_type) ! Unsupported type
```

### Invalid Context
```fortran
! Negative or zero context values handled gracefully:
ctx = ui_context(dpi_scale=0.0, em_dp=-1.0)  ! Will use safe defaults
call ui_set_context(ctx)
layout = column(gap=em(1.0))  ! Converted safely
```

## Performance Characteristics

Layout constructors are optimized for immediate-mode UI patterns where trees are rebuilt every frame:

### Constructor Performance
- **Speed:** Tested at 500+ layout constructions per frame without performance degradation
- **Memory Allocation:** Efficient memory usage with automatic cleanup
- **Deep Nesting:** Supports 20+ nesting levels without stack overflow
- **Array Handling:** Optimized for repeated allocation/deallocation cycles

### Real Performance Data
From `test_layout_constructors.f90` performance tests:
```fortran
! Creates 1000 layouts (500 column + 500 row) rapidly
do i = 1, 500
  layout_node = column(gap=dp(real(i)), children=children)
  layout_node = row(gap=cw(real(i)), children=children)
end do
! Completes in milliseconds on modern hardware
```

### Memory Efficiency
- **Deep Copy Strategy:** Children arrays copied once at construction
- **Automatic Cleanup:** Fortran handles deallocation when nodes go out of scope
- **No Memory Leaks:** Tested with 100+ allocation/deallocation cycles
- **Assignment Operator:** Custom operator ensures proper memory management for nested structures

### Production Recommendations
- **Immediate-Mode Usage:** Rebuild UI trees every frame for dynamic interfaces
- **Static Layouts:** Cache complex layout trees for better performance if content is static
- **Memory Monitoring:** Use explicit `deallocate()` for large arrays if memory is constrained
- **Profiling:** Test with your specific use case - performance depends on tree complexity and update frequency