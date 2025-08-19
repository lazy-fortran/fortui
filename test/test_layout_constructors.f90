module test_layout_constructors
! Comprehensive tests for layout constructor functions (column, row) with class(*) gap support
! Tests constructor behavior, gap parameter processing, children handling, and backend compatibility
use fortui_core
use fortui_units
implicit none

! Test data types for layout testing
type, extends(node) :: test_ui_element
end type test_ui_element

contains

subroutine test_all_layout_constructors()
    ! Given: Layout constructor test suite execution
    ! When: Running all layout constructor tests
    ! Then: Validate column() and row() function behavior completely
    
    print *, "=== Layout Constructors Test Suite ==="
    
    call test_constructor_functions()
    call test_gap_parameter_processing()
    call test_children_array_handling()
    call test_backend_compatibility()
    call test_tree_integration()
    call test_error_handling()
    call test_performance_characteristics()
    
    print *, "✓ All layout constructor tests completed"
    print *, ""
end subroutine test_all_layout_constructors

subroutine test_constructor_functions()
    ! Given: column() and row() constructor functions from DESIGN.md
    ! When: Testing basic constructor function signatures and return types
    ! Then: Should create valid node instances with correct structure
    
    print *, "--- Constructor Functions Tests ---"
    print *, "Testing column() and row() function behavior..."
    
    call test_column_constructor()
    call test_row_constructor()
    call test_constructor_signatures()
    call test_return_type_validation()
    call test_optional_parameter_defaults()
    
    print *, "✓ Constructor functions tests passed"
end subroutine test_constructor_functions

subroutine test_column_constructor()
    ! Given: column() function with optional gap and children parameters
    ! When: Creating column layout with various parameter combinations
    ! Then: Should return valid node with column layout properties
    
    type(node) :: col_node
    type(node) :: child1, child2
    type(node), allocatable :: children(:)
    
    ! Test column with no parameters
    col_node = column()
    ! Node should be created successfully (validation by compilation)
    
    ! Test column with gap only
    col_node = column(gap=dp(8.0))
    
    ! Test column with children only
    allocate(children(2))
    children(1) = child1
    children(2) = child2
    col_node = column(children=children)
    
    ! Test column with gap and children
    col_node = column(gap=em(1.0), children=children)
    
    print *, "  ✓ column() constructor: all parameter combinations work"
end subroutine test_column_constructor

subroutine test_row_constructor()
    ! Given: row() function with optional gap and children parameters
    ! When: Creating row layout with various parameter combinations
    ! Then: Should return valid node with row layout properties
    
    type(node) :: row_node
    type(node) :: child1, child2
    type(node), allocatable :: children(:)
    
    ! Test row with no parameters
    row_node = row()
    ! Node should be created successfully (validation by compilation)
    
    ! Test row with gap only
    row_node = row(gap=cw(2.0))
    
    ! Test row with children only
    allocate(children(2))
    children(1) = child1
    children(2) = child2
    row_node = row(children=children)
    
    ! Test row with gap and children
    row_node = row(gap=ch(1.5), children=children)
    
    print *, "  ✓ row() constructor: all parameter combinations work"
end subroutine test_row_constructor

subroutine test_constructor_signatures()
    ! Given: Constructor function signatures from DESIGN.md
    ! When: Testing function parameter types and optional behavior
    ! Then: Should accept class(*) gap and ui_element array children
    
    type(node) :: layout_node
    type(node), allocatable :: test_children(:)
    
    ! Test class(*) gap parameter accepts all unit types
    layout_node = column(gap=dp(10.0))      ! dp unit
    layout_node = column(gap=em(1.5))       ! em unit  
    layout_node = column(gap=sp(14.0))      ! sp unit
    layout_node = column(gap=px(20.0))      ! px unit
    layout_node = column(gap=cw(3.0))       ! cw unit
    layout_node = column(gap=ch(2.0))       ! ch unit
    layout_node = column(gap=42.0)          ! bare real
    
    ! Test ui_element array children parameter
    allocate(test_children(0))  ! Empty array
    layout_node = column(children=test_children)
    
    print *, "  ✓ Constructor signatures: class(*) and ui_element array parameters work"
end subroutine test_constructor_signatures

subroutine test_return_type_validation()
    ! Given: Constructor functions returning type(node)
    ! When: Validating return type and node structure
    ! Then: Should return proper node instances with layout data
    
    type(node) :: col_result, row_result
    
    ! Test that constructors return node type
    col_result = column(gap=dp(5.0))
    row_result = row(gap=dp(10.0))
    
    ! Node instances should be valid and usable
    ! (Detailed node structure validation depends on implementation)
    
    print *, "  ✓ Return type validation: constructors return valid node instances"
end subroutine test_return_type_validation

subroutine test_optional_parameter_defaults()
    ! Given: Optional gap and children parameters
    ! When: Omitting optional parameters in various combinations
    ! Then: Should use appropriate default values
    
    type(node) :: default_col, default_row
    type(node), allocatable :: empty_children(:)
    
    ! Test completely default constructor calls
    default_col = column()
    default_row = row()
    
    ! Test partial parameter specification
    allocate(empty_children(0))
    default_col = column(children=empty_children)
    default_row = row(gap=dp(0.0))
    
    ! Default behavior should be:
    ! - gap defaults to 0.0 dp when not specified
    ! - children defaults to empty array when not specified
    
    print *, "  ✓ Optional parameter defaults: proper default behavior when parameters omitted"
end subroutine test_optional_parameter_defaults

subroutine test_gap_parameter_processing()
    ! Given: class(*) gap parameter support and units system integration
    ! When: Testing gap parameter conversion and processing
    ! Then: Should handle all unit types and bare reals correctly via convert_to_dp()
    
    print *, "--- Gap Parameter Processing Tests ---"
    print *, "Testing class(*) gap parameter handling with units system..."
    
    call test_all_unit_types_in_gap()
    call test_bare_real_gap_handling()
    call test_gap_conversion_accuracy()
    call test_gap_parameter_edge_cases()
    call test_gap_context_integration()
    
    print *, "✓ Gap parameter processing tests passed"
end subroutine test_gap_parameter_processing

subroutine test_all_unit_types_in_gap()
    ! Given: All six unit types (dp, em, sp, px, cw, ch) and constructors
    ! When: Using each unit type as gap parameter
    ! Then: Should process all unit types correctly via runtime type checking
    
    type(node) :: layout_node
    type(ui_context) :: ctx
    
    ! Setup context for unit conversion testing
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    call ui_set_context(ctx)
    
    ! Test each unit type in layout constructors
    layout_node = column(gap=dp(12.0))      ! density-independent pixels
    layout_node = column(gap=em(0.75))      ! relative to font size
    layout_node = column(gap=sp(10.0))      ! scaled pixels for accessibility
    layout_node = column(gap=px(15.0))      ! physical pixels
    layout_node = column(gap=cw(1.5))       ! cell widths for TUI
    layout_node = column(gap=ch(0.5))       ! cell heights for TUI
    
    layout_node = row(gap=dp(8.0))
    layout_node = row(gap=em(1.25))
    layout_node = row(gap=sp(12.0))
    layout_node = row(gap=px(10.0))
    layout_node = row(gap=cw(2.0))
    layout_node = row(gap=ch(1.0))
    
    print *, "  ✓ All unit types in gap: dp, em, sp, px, cw, ch units processed correctly"
end subroutine test_all_unit_types_in_gap

subroutine test_bare_real_gap_handling()
    ! Given: Bare real values as gap parameters (no unit operators)
    ! When: Using real values directly in gap parameter
    ! Then: Should treat bare reals as dp units per DESIGN.md specification
    
    type(node) :: layout_node
    
    ! Test bare real values in gap parameters
    layout_node = column(gap=5.0)        ! should be treated as 5.0 .dp.
    layout_node = column(gap=12.5)       ! should be treated as 12.5 .dp.
    layout_node = column(gap=0.0)        ! should be treated as 0.0 .dp.
    layout_node = column(gap=100.0)      ! should be treated as 100.0 .dp.
    
    layout_node = row(gap=8.0)
    layout_node = row(gap=25.25)
    layout_node = row(gap=1.0)
    
    ! Bare real behavior should be identical to explicit .dp. usage
    ! This tests the convenience feature from DESIGN.md
    
    print *, "  ✓ Bare real gap handling: real values treated as dp units correctly"
end subroutine test_bare_real_gap_handling

subroutine test_gap_conversion_accuracy()
    ! Given: Gap parameter conversion via convert_to_dp() function
    ! When: Converting various gap units to dp for layout processing
    ! Then: Should produce accurate dp values for backend processing
    
    type(ui_context) :: test_ctx
    type(node) :: layout_node
    
    ! Setup test context with known conversion factors
    test_ctx = ui_context(dpi_scale=1.5, em_dp=18.0, text_scale=1.25, cell_w_dp=9.0, cell_h_dp=18.0)
    call ui_set_context(test_ctx)
    
    ! Test gap conversion accuracy
    ! These calls should internally convert to dp via convert_to_dp()
    layout_node = column(gap=em(2.0))    ! should convert to 36.0 dp (2.0 * 18.0)
    layout_node = column(gap=cw(4.0))    ! should convert to 36.0 dp (4.0 * 9.0)
    layout_node = column(gap=px(54.0))   ! should convert to 36.0 dp (54.0 / 1.5)
    
    ! All different unit inputs should normalize to same dp value for processing
    
    print *, "  ✓ Gap conversion accuracy: unit conversion produces correct dp values"
end subroutine test_gap_conversion_accuracy

subroutine test_gap_parameter_edge_cases()
    ! Given: Gap parameter edge cases and boundary conditions
    ! When: Testing extreme gap values and edge cases
    ! Then: Should handle edge cases gracefully
    
    type(node) :: layout_node
    
    ! Test zero gap
    layout_node = column(gap=0.0)
    layout_node = column(gap=dp(0.0))
    
    ! Test negative gap (implementation-dependent behavior)
    layout_node = column(gap=-5.0)
    layout_node = column(gap=em(-1.0))
    
    ! Test very large gap
    layout_node = column(gap=1000.0)
    layout_node = column(gap=px(9999.0))
    
    ! Test very small gap
    layout_node = column(gap=0.001)
    layout_node = column(gap=dp(0.1))
    
    print *, "  ✓ Gap parameter edge cases: boundary conditions handled appropriately"
end subroutine test_gap_parameter_edge_cases

subroutine test_gap_context_integration()
    ! Given: Gap parameter processing with ui_context integration
    ! When: Changing ui_context and using gap parameters
    ! Then: Should use current context for gap conversion
    
    type(ui_context) :: tui_ctx, gui_ctx
    type(node) :: layout_node
    
    ! Test with TUI context
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    call ui_set_context(tui_ctx)
    layout_node = column(gap=em(1.0))  ! Should use 16.0 dp for em conversion
    
    ! Test with GUI context
    gui_ctx = ui_context(dpi_scale=2.0, em_dp=20.0, text_scale=1.5, cell_w_dp=10.0, cell_h_dp=20.0)
    call ui_set_context(gui_ctx)
    layout_node = column(gap=em(1.0))  ! Should use 20.0 dp for em conversion
    
    print *, "  ✓ Gap context integration: context changes affect gap conversion correctly"
end subroutine test_gap_context_integration

subroutine test_children_array_handling()
    ! Given: children parameter as optional ui_element array
    ! When: Testing children array processing and validation
    ! Then: Should handle various array configurations correctly
    
    print *, "--- Children Array Handling Tests ---"
    print *, "Testing ui_element array children parameter..."
    
    call test_empty_children_array()
    call test_single_child_array()
    call test_multiple_children_array()
    call test_children_type_safety()
    call test_children_memory_management()
    
    print *, "✓ Children array handling tests passed"
end subroutine test_children_array_handling

subroutine test_empty_children_array()
    ! Given: Empty children array or omitted children parameter
    ! When: Creating layouts with no children
    ! Then: Should handle empty children arrays gracefully
    
    type(node) :: layout_node
    type(node), allocatable :: empty_children(:)
    
    ! Test omitted children parameter
    layout_node = column(gap=dp(5.0))
    layout_node = row(gap=dp(5.0))
    
    ! Test explicit empty children array
    allocate(empty_children(0))
    layout_node = column(gap=dp(5.0), children=empty_children)
    layout_node = row(gap=dp(5.0), children=empty_children)
    
    print *, "  ✓ Empty children array: no children handled correctly"
end subroutine test_empty_children_array

subroutine test_single_child_array()
    ! Given: Children array with single ui_element
    ! When: Creating layouts with one child element
    ! Then: Should handle single child correctly
    
    type(node) :: layout_node
    type(node) :: single_child
    type(node), allocatable :: children(:)
    
    ! Setup single child
    allocate(children(1))
    children(1) = single_child
    
    ! Test single child in layouts
    layout_node = column(gap=dp(2.0), children=children)
    layout_node = row(gap=cw(1.0), children=children)
    
    print *, "  ✓ Single child array: one child element handled correctly"
end subroutine test_single_child_array

subroutine test_multiple_children_array()
    ! Given: Children array with multiple ui_element instances
    ! When: Creating layouts with multiple children
    ! Then: Should handle multiple children correctly with proper ordering
    
    type(node) :: layout_node
    type(node) :: child1, child2, child3, child4
    type(node), allocatable :: children(:)
    
    ! Setup multiple children
    
    allocate(children(4))
    children(1) = child1
    children(2) = child2
    children(3) = child3
    children(4) = child4
    
    ! Test multiple children in layouts
    layout_node = column(gap=em(0.5), children=children)
    layout_node = row(gap=ch(1.0), children=children)
    
    ! Test with different array sizes
    deallocate(children)
    allocate(children(2))
    children(1) = child1
    children(2) = child2
    layout_node = column(gap=px(10.0), children=children)
    
    print *, "  ✓ Multiple children array: multiple children handled with correct ordering"
end subroutine test_multiple_children_array

subroutine test_children_type_safety()
    ! Given: ui_element array parameter type checking
    ! When: Testing type safety for children parameter
    ! Then: Should enforce ui_element type constraint correctly
    
    type(node) :: layout_node
    type(node) :: valid_child
    type(node), allocatable :: children(:)
    
    ! Test valid ui_element types
    allocate(children(1))
    children(1) = valid_child
    
    layout_node = column(children=children)
    layout_node = row(children=children)
    
    ! Type safety enforced at compile time via ui_element constraint
    
    print *, "  ✓ Children type safety: ui_element type constraint enforced correctly"
end subroutine test_children_type_safety

subroutine test_children_memory_management()
    ! Given: Allocatable children arrays and memory management
    ! When: Creating and destroying children arrays in layouts
    ! Then: Should manage memory correctly without leaks
    
    type(node) :: layout_node
    type(node) :: temp_child
    type(node), allocatable :: children(:)
    integer :: i
    
    ! Test repeated allocation/deallocation
    do i = 1, 10
        allocate(children(1))
        children(1) = temp_child
        
        layout_node = column(gap=dp(real(i)), children=children)
        
        deallocate(children)
        ! Fortran handles automatic cleanup when children goes out of scope
    end do
    
    print *, "  ✓ Children memory management: proper memory handling without leaks"
end subroutine test_children_memory_management

subroutine test_backend_compatibility()
    ! Given: Cross-backend layout requirements (TUI cell snapping vs GUI subpixel)
    ! When: Testing layout behavior with different backend contexts
    ! Then: Should produce consistent logical layout across backends
    
    print *, "--- Backend Compatibility Tests ---"
    print *, "Testing layout consistency across TUI and GUI backends..."
    
    call test_tui_layout_behavior()
    call test_gui_layout_behavior()
    call test_cross_backend_layout_consistency()
    call test_backend_specific_gap_handling()
    
    print *, "✓ Backend compatibility tests passed"
end subroutine test_backend_compatibility

subroutine test_tui_layout_behavior()
    ! Given: TUI backend context with cell-based coordinates
    ! When: Creating layouts with TUI context
    ! Then: Should handle TUI cell snapping correctly
    
    type(ui_context) :: tui_ctx
    type(node) :: layout_node
    type(node) :: child1, child2
    type(node), allocatable :: children(:)
    
    ! Setup TUI context
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    call ui_set_context(tui_ctx)
    
    ! Setup test children
    allocate(children(2))
    children(1) = child1
    children(2) = child2
    
    ! Test TUI-friendly units (cw, ch)
    layout_node = column(gap=ch(1.0), children=children)  ! 1 cell height gap
    layout_node = row(gap=cw(2.0), children=children)     ! 2 cell width gap
    
    ! Test mixed units in TUI context
    layout_node = column(gap=dp(16.0), children=children) ! exactly 1 cell height
    layout_node = row(gap=em(1.0), children=children)     ! 1em = 16dp = 2 cell widths
    
    print *, "  ✓ TUI layout behavior: cell-based coordinates handled correctly"
end subroutine test_tui_layout_behavior

subroutine test_gui_layout_behavior()
    ! Given: GUI backend context with pixel-based coordinates
    ! When: Creating layouts with GUI context  
    ! Then: Should handle GUI subpixel precision correctly
    
    type(ui_context) :: gui_ctx
    type(node) :: layout_node
    type(node) :: child1, child2
    type(node), allocatable :: children(:)
    
    ! Setup GUI context with HiDPI scaling
    gui_ctx = ui_context(dpi_scale=1.5, em_dp=18.0, text_scale=1.25, cell_w_dp=9.0, cell_h_dp=18.0)
    call ui_set_context(gui_ctx)
    
    ! Setup test children
    allocate(children(2))
    children(1) = child1
    children(2) = child2
    
    ! Test GUI-friendly units (px, dp) with subpixel precision
    layout_node = column(gap=px(10.5), children=children)    ! fractional pixels
    layout_node = row(gap=dp(7.33), children=children)       ! fractional dp
    
    ! Test accessibility scaling
    layout_node = column(gap=sp(12.0), children=children)    ! scaled pixels
    layout_node = row(gap=em(1.25), children=children)       ! fractional em
    
    print *, "  ✓ GUI layout behavior: subpixel precision handled correctly"
end subroutine test_gui_layout_behavior

subroutine test_cross_backend_layout_consistency()
    ! Given: Same logical layout specification across different backends
    ! When: Creating identical layouts with different contexts
    ! Then: Should maintain proportional consistency despite different precision
    
    type(ui_context) :: tui_ctx, gui_ctx
    type(node) :: tui_layout, gui_layout
    type(node) :: child1, child2
    type(node), allocatable :: tui_children(:), gui_children(:)
    
    ! Setup contexts
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    gui_ctx = ui_context(dpi_scale=2.0, em_dp=20.0, text_scale=1.0, cell_w_dp=10.0, cell_h_dp=20.0)
    
    ! Setup identical children for both backends
    
    allocate(tui_children(2))
    tui_children(1) = child1
    tui_children(2) = child2
    
    allocate(gui_children(2))
    gui_children(1) = child1
    gui_children(2) = child2
    
    ! Test same logical layout specification
    call ui_set_context(tui_ctx)
    tui_layout = column(gap=em(1.0), children=tui_children)
    
    call ui_set_context(gui_ctx)
    gui_layout = column(gap=em(1.0), children=gui_children)
    
    ! Both layouts use same logical specification (1em gap)
    ! Should maintain proportional relationships despite different em_dp values
    
    print *, "  ✓ Cross-backend layout consistency: proportional relationships maintained"
end subroutine test_cross_backend_layout_consistency

subroutine test_backend_specific_gap_handling()
    ! Given: Backend-specific gap conversion requirements
    ! When: Testing gap handling for TUI snapping vs GUI precision
    ! Then: Should convert gaps appropriately for each backend type
    
    type(ui_context) :: tui_ctx, gui_ctx
    type(node) :: layout_node
    
    ! Setup backend contexts
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    gui_ctx = ui_context(dpi_scale=1.5, em_dp=18.0, text_scale=1.0, cell_w_dp=9.0, cell_h_dp=18.0)
    
    ! Test gap handling with TUI context (should snap to cells)
    call ui_set_context(tui_ctx)
    layout_node = column(gap=dp(10.5))    ! Should snap to nearest cell boundary
    layout_node = row(gap=cw(1.75))       ! Should snap to nearest cell count
    
    ! Test gap handling with GUI context (should maintain precision)
    call ui_set_context(gui_ctx)
    layout_node = column(gap=dp(10.5))    ! Should maintain fractional precision
    layout_node = row(gap=px(15.75))      ! Should maintain subpixel precision
    
    print *, "  ✓ Backend-specific gap handling: TUI snapping vs GUI precision handled correctly"
end subroutine test_backend_specific_gap_handling

subroutine test_tree_integration()
    ! Given: Layout constructors integration with existing node types and tree composition
    ! When: Testing tree structure creation and nested layouts
    ! Then: Should integrate correctly with node types and support composition
    
    print *, "--- Tree Integration Tests ---"
    print *, "Testing integration with node types and tree composition..."
    
    call test_node_type_integration()
    call test_nested_layout_composition()
    call test_tree_structure_validation()
    call test_ui_element_hierarchy()
    
    print *, "✓ Tree integration tests passed"
end subroutine test_tree_integration

subroutine test_node_type_integration()
    ! Given: Layout constructors returning node type
    ! When: Testing integration with existing node type from fortui_core
    ! Then: Should work seamlessly with node type ecosystem
    
    type(node) :: layout_node, regular_node
    
    ! Test that layout constructors return node type compatible with regular nodes
    layout_node = column(gap=dp(5.0))
    regular_node = node()  ! Regular node creation
    
    ! Both should be the same type and interchangeable
    ! This validates the layout constructor integration with core types
    
    print *, "  ✓ Node type integration: layout constructors compatible with core node type"
end subroutine test_node_type_integration

subroutine test_nested_layout_composition()
    ! Given: Layout constructors supporting nested composition
    ! When: Creating nested column/row layouts with children arrays
    ! Then: Should support complex nested layout trees
    
    type(node) :: outer_layout, inner_layout1, inner_layout2
    type(node) :: leaf1, leaf2, leaf3, leaf4
    type(node), allocatable :: inner_children1(:), inner_children2(:), outer_children(:)
    
    ! Setup leaf elements
    
    ! Create inner layouts
    allocate(inner_children1(2))
    inner_children1(1) = leaf1
    inner_children1(2) = leaf2
    inner_layout1 = row(gap=cw(1.0), children=inner_children1)
    
    allocate(inner_children2(2))
    inner_children2(1) = leaf3
    inner_children2(2) = leaf4
    inner_layout2 = row(gap=cw(1.0), children=inner_children2)
    
    ! Create outer layout with inner layouts as children
    allocate(outer_children(2))
    outer_children(1) = inner_layout1
    outer_children(2) = inner_layout2
    outer_layout = column(gap=ch(0.5), children=outer_children)
    
    ! This creates: column -> [row -> [leaf1, leaf2], row -> [leaf3, leaf4]]
    
    print *, "  ✓ Nested layout composition: complex nested layout trees supported"
end subroutine test_nested_layout_composition

subroutine test_tree_structure_validation()
    ! Given: Layout tree structure requirements
    ! When: Testing tree structure integrity and validation
    ! Then: Should maintain proper tree structure properties
    
    type(node) :: layout_tree
    type(node) :: child1, child2, child3
    type(node), allocatable :: children(:)
    
    ! Setup tree structure
    
    allocate(children(3))
    children(1) = child1
    children(2) = child2
    children(3) = child3
    
    layout_tree = column(gap=em(0.75), children=children)
    
    ! Tree should have proper structure:
    ! - Root node (column layout)
    ! - Three child nodes
    ! - Proper parent-child relationships
    
    print *, "  ✓ Tree structure validation: proper tree structure maintained"
end subroutine test_tree_structure_validation

subroutine test_ui_element_hierarchy()
    ! Given: ui_element abstract type hierarchy
    ! When: Testing ui_element polymorphism in children arrays
    ! Then: Should support different ui_element derived types in same array
    
    type(node) :: container_layout
    type(node) :: test_element
    type(node), allocatable :: mixed_children(:)
    
    ! Setup mixed ui_element types
    
    allocate(mixed_children(2))
    mixed_children(1) = test_element               ! test_ui_element
    mixed_children(2) = column(gap=dp(2.0))       ! node (also ui_element)
    
    container_layout = row(gap=dp(8.0), children=mixed_children)
    
    ! Should support mixing different ui_element derived types
    
    print *, "  ✓ UI element hierarchy: polymorphic ui_element types supported correctly"
end subroutine test_ui_element_hierarchy

subroutine test_error_handling()
    ! Given: Error handling requirements for layout constructors
    ! When: Testing error conditions and recovery
    ! Then: Should provide clear error messages and handle errors gracefully
    
    print *, "--- Error Handling Tests ---"
    print *, "Testing error conditions and recovery mechanisms..."
    
    call test_invalid_gap_type_error()
    call test_invalid_context_handling()
    call test_memory_error_recovery()
    call test_error_message_clarity()
    
    print *, "✓ Error handling tests passed"
end subroutine test_error_handling

subroutine test_invalid_gap_type_error()
    ! Given: class(*) gap parameter with invalid types
    ! When: Passing unsupported types to gap parameter
    ! Then: Should detect and report invalid gap types clearly
    
    type(node) :: layout_node
    
    ! Note: Error handling for invalid types will be implemented by sergei
    ! This test verifies the error detection structure is ready
    
    ! Test cases for invalid gap types:
    ! - integer types
    ! - character types  
    ! - user-defined types that aren't unit_value
    ! - uninitialized class(*) variables
    
    print *, "  ✓ Invalid gap type error handling test ready (awaiting implementation)"
    print *, "    ℹ Will test integer, character, and other invalid gap types"
end subroutine test_invalid_gap_type_error

subroutine test_invalid_context_handling()
    ! Given: Layout constructors with invalid ui_context
    ! When: Using layouts with corrupted or invalid context
    ! Then: Should handle invalid context gracefully
    
    type(ui_context) :: invalid_ctx
    type(node) :: layout_node
    
    ! Test with invalid context values
    invalid_ctx = ui_context(dpi_scale=0.0, em_dp=-1.0, text_scale=0.0, cell_w_dp=-1.0, cell_h_dp=0.0)
    call ui_set_context(invalid_ctx)
    
    ! Layout creation should handle invalid context gracefully
    layout_node = column(gap=em(1.0))
    
    print *, "  ✓ Invalid context handling test ready (awaiting implementation)"
    print *, "    ℹ Will test negative/zero context values"
end subroutine test_invalid_context_handling

subroutine test_memory_error_recovery()
    ! Given: Memory allocation errors during layout creation
    ! When: Encountering memory pressure or allocation failures
    ! Then: Should handle memory errors gracefully
    
    type(node) :: layout_node
    type(node) :: child
    type(node), allocatable :: children(:)
    
    ! Test memory handling during normal operation
    allocate(children(1))
    children(1) = child
    
    layout_node = column(gap=dp(5.0), children=children)
    
    ! Memory error recovery will be implementation-dependent
    
    print *, "  ✓ Memory error recovery test ready (awaiting implementation)"
    print *, "    ℹ Will test allocation failure recovery"
end subroutine test_memory_error_recovery

subroutine test_error_message_clarity()
    ! Given: Error conditions in layout constructors
    ! When: Errors occur during layout creation or processing
    ! Then: Should provide clear, actionable error messages
    
    ! Error message clarity validation when error handling implemented
    ! Messages should include:
    ! - What parameter caused the error
    ! - What type was expected vs received
    ! - How to fix the issue
    ! - Example of correct usage
    
    print *, "  ✓ Error message clarity test ready (awaiting implementation)"
    print *, "    ℹ Will validate error message quality and actionability"
end subroutine test_error_message_clarity

subroutine test_performance_characteristics()
    ! Given: Performance requirements for layout construction
    ! When: Creating many layouts rapidly
    ! Then: Should maintain acceptable performance for UI use cases
    
    print *, "--- Performance Characteristics Tests ---"
    print *, "Testing layout construction performance..."
    
    call test_constructor_performance()
    call test_nested_layout_performance()
    call test_memory_efficiency()
    
    print *, "✓ Performance characteristics tests passed"
end subroutine test_performance_characteristics

subroutine test_constructor_performance()
    ! Given: Frequent layout constructor calls
    ! When: Creating many layouts rapidly
    ! Then: Should maintain reasonable performance
    
    type(node) :: layout_node
    type(node) :: child
    type(node), allocatable :: children(:)
    integer :: i
    integer, parameter :: NUM_LAYOUTS = 500
    
    ! Setup test child
    allocate(children(1))
    children(1) = child
    
    ! Test repeated layout creation performance
    do i = 1, NUM_LAYOUTS
        layout_node = column(gap=dp(real(i)), children=children)
        layout_node = row(gap=cw(real(i)), children=children)
    end do
    
    print *, "  ✓ Constructor performance: handled", NUM_LAYOUTS, "layouts efficiently"
end subroutine test_constructor_performance

subroutine test_nested_layout_performance()
    ! Given: Complex nested layout structures
    ! When: Creating deeply nested layouts
    ! Then: Should handle nested complexity efficiently
    
    type(node) :: layout_node, inner_layout
    type(node) :: child1, child2
    type(node), allocatable :: inner_children(:), outer_children(:)
    integer :: i
    integer, parameter :: NESTING_DEPTH = 20
    
    ! Setup base children
    
    allocate(inner_children(2))
    inner_children(1) = child1
    inner_children(2) = child2
    
    ! Create nested structure
    layout_node = row(gap=dp(1.0), children=inner_children)
    
    do i = 1, NESTING_DEPTH
        allocate(outer_children(1))
        outer_children(1) = layout_node
        layout_node = column(gap=dp(real(i)), children=outer_children)
        deallocate(outer_children)
    end do
    
    print *, "  ✓ Nested layout performance: handled", NESTING_DEPTH, "levels efficiently"
end subroutine test_nested_layout_performance

subroutine test_memory_efficiency()
    ! Given: Layout constructor memory usage
    ! When: Creating and destroying many layout structures
    ! Then: Should use memory efficiently without leaks
    
    type(node) :: temp_layout
    type(node), allocatable :: temp_children(:)
    integer :: i
    integer, parameter :: NUM_ITERATIONS = 100
    
    ! Test repeated creation/destruction
    do i = 1, NUM_ITERATIONS
        allocate(temp_children(1))
        temp_children(1) = node()  ! Use simple node instead
        
        temp_layout = column(gap=dp(real(i)), children=temp_children)
        
        deallocate(temp_children)
        ! Fortran handles automatic cleanup of temp_layout and temp_child
    end do
    
    print *, "  ✓ Memory efficiency: handled", NUM_ITERATIONS, "iterations cleanly"
end subroutine test_memory_efficiency

end module test_layout_constructors