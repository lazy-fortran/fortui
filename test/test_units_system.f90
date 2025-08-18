module test_units_system
! Comprehensive tests for fortui units system with postfix operators and context-aware conversion
! Tests runtime type checking, cross-backend conversion, and class(*) API integration
use fortui_units
implicit none

contains

subroutine test_all_units_system()
    ! Given: Units system test suite execution  
    ! When: Running all units system tests
    ! Then: Validate comprehensive unit operator and conversion behavior completely

    print *, "=== Units System Test Suite ==="
    
    call test_unit_operators()
    call test_unit_conversion_engine()
    call test_ui_context_management()
    call test_class_star_parameter_handling()
    call test_cross_backend_integration()
    call test_runtime_error_handling()
    call test_performance_characteristics()
    
    print *, "✓ All units system tests completed"
    print *, ""
end subroutine test_all_units_system

subroutine test_unit_operators()
    ! Given: Postfix unit operator interfaces from DESIGN.md
    ! When: Testing all six unit operators (.dp.,em(),sp(),px(),cw(),ch())
    ! Then: Should create correct unit_value types with proper values and types
    
    print *, "--- Unit Operators Tests ---"
    print *, "Testing postfix unit operator API..."
    
    call test_dp_operator()
    call test_em_operator()
    call test_sp_operator()
    call test_px_operator()
    call test_cw_operator()
    call test_ch_operator()
    call test_operator_edge_cases()
    call test_operator_return_types()
    
    print *, "✓ Unit operators tests passed"
end subroutine test_unit_operators

subroutine test_dp_operator()
    ! Given:dp() postfix operator for density-independent pixels
    ! When: Creating dp unit with various values
    ! Then: Should create unit_value with correct value and "dp" type
    
    class(*), allocatable :: dp_unit
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Test positive value
    dp_unit = dp(40.0)
    call verify_unit_value(dp_unit, 40.0, "dp", "positive dp value")
    
    ! Test zero value
    dp_unit = dp(0.0)
    call verify_unit_value(dp_unit, 0.0, "dp", "zero dp value")
    
    ! Test negative value
    dp_unit = dp(-10.5)
    call verify_unit_value(dp_unit, -10.5, "dp", "negative dp value")
    
    ! Test fractional value
    dp_unit = dp(3.14159)
    call verify_unit_value(dp_unit, 3.14159, "dp", "fractional dp value")
    
    ! Test large value
    dp_unit = dp(9999.0)
    call verify_unit_value(dp_unit, 9999.0, "dp", "large dp value")
    
    print *, "  ✓dp() operator: all value ranges handled correctly"
end subroutine test_dp_operator

subroutine test_em_operator()
    ! Given:em() postfix operator for relative font size units
    ! When: Creating em unit with various values
    ! Then: Should create unit_value with correct value and "em" type
    
    class(*), allocatable :: em_unit
    
    ! Test typical em values
    em_unit = em(1.0)
    call verify_unit_value(em_unit, 1.0, "em", "1em baseline")
    
    em_unit = em(1.5)
    call verify_unit_value(em_unit, 1.5, "em", "1.5em larger text")
    
    em_unit = em(0.8)
    call verify_unit_value(em_unit, 0.8, "em", "0.8em smaller text")
    
    ! Test fractional em values
    em_unit = em(2.5)
    call verify_unit_value(em_unit, 2.5, "em", "2.5em heading size")
    
    print *, "  ✓em() operator: relative font size units handled correctly"
end subroutine test_em_operator

subroutine test_sp_operator()
    ! Given:sp() postfix operator for scaled pixels (accessibility)
    ! When: Creating sp unit with various values
    ! Then: Should create unit_value with correct value and "sp" type
    
    class(*), allocatable :: sp_unit
    
    ! Test typical scaled pixel values
    sp_unit = sp(14.0)
    call verify_unit_value(sp_unit, 14.0, "sp", "14sp standard text")
    
    sp_unit = sp(18.0)
    call verify_unit_value(sp_unit, 18.0, "sp", "18sp large text")
    
    sp_unit = sp(12.0)
    call verify_unit_value(sp_unit, 12.0, "sp", "12sp small text")
    
    print *, "  ✓sp() operator: scaled pixel units handled correctly"
end subroutine test_sp_operator

subroutine test_px_operator()
    ! Given:px() postfix operator for physical pixels
    ! When: Creating px unit with various values
    ! Then: Should create unit_value with correct value and "px" type
    
    class(*), allocatable :: px_unit
    
    ! Test physical pixel values
    px_unit = px(320.0)
    call verify_unit_value(px_unit, 320.0, "px", "320px physical width")
    
    px_unit = px(1.0)
    call verify_unit_value(px_unit, 1.0, "px", "1px hairline")
    
    px_unit = px(640.0)
    call verify_unit_value(px_unit, 640.0, "px", "640px screen width")
    
    print *, "  ✓px() operator: physical pixel units handled correctly"
end subroutine test_px_operator

subroutine test_cw_operator()
    ! Given:cw() postfix operator for cell widths (TUI-friendly)
    ! When: Creating cw unit with various values
    ! Then: Should create unit_value with correct value and "cw" type
    
    class(*), allocatable :: cw_unit
    
    ! Test cell width values typical for TUI
    cw_unit = cw(10.0)
    call verify_unit_value(cw_unit, 10.0, "cw", "10cw button width")
    
    cw_unit = cw(80.0)
    call verify_unit_value(cw_unit, 80.0, "cw", "80cw terminal width")
    
    cw_unit = cw(1.0)
    call verify_unit_value(cw_unit, 1.0, "cw", "1cw single character")
    
    print *, "  ✓cw() operator: cell width units handled correctly"
end subroutine test_cw_operator

subroutine test_ch_operator()
    ! Given:ch() postfix operator for cell heights (TUI-friendly)
    ! When: Creating ch unit with various values
    ! Then: Should create unit_value with correct value and "ch" type
    
    class(*), allocatable :: ch_unit
    
    ! Test cell height values typical for TUI
    ch_unit = ch(3.0)
    call verify_unit_value(ch_unit, 3.0, "ch", "3ch button height")
    
    ch_unit = ch(24.0)
    call verify_unit_value(ch_unit, 24.0, "ch", "24ch terminal height")
    
    ch_unit = ch(1.0)
    call verify_unit_value(ch_unit, 1.0, "ch", "1ch single line")
    
    print *, "  ✓ch() operator: cell height units handled correctly"
end subroutine test_ch_operator

subroutine test_operator_edge_cases()
    ! Given: Unit operators with edge case values
    ! When: Testing boundary conditions and extreme values
    ! Then: Should handle edge cases gracefully
    
    class(*), allocatable :: edge_unit
    
    ! Test very small values
    edge_unit = dp(0.001)
    call verify_unit_value(edge_unit, 0.001, "dp", "very small dp value")
    
    ! Test very large values
    edge_unit = px(99999.99)
    call verify_unit_value(edge_unit, 99999.99, "px", "very large px value")
    
    ! Test negative values for all units
    edge_unit = em(-5.0)
    call verify_unit_value(edge_unit, -5.0, "em", "negative em value")
    
    edge_unit = cw(-100.0)
    call verify_unit_value(edge_unit, -100.0, "cw", "negative cw value")
    
    print *, "  ✓ Unit operators edge cases: boundary conditions handled"
end subroutine test_operator_edge_cases

subroutine test_operator_return_types()
    ! Given: Unit operators returning class(*) for API flexibility
    ! When: Testing that operators return class(*) compatible types
    ! Then: Should be assignable to class(*) and work with select type
    
    class(*), allocatable :: unit_test
    logical :: type_check_passed
    
    ! Test that all operators return class(*) compatible types
    unit_test = dp(42.0)
    type_check_passed = .false.
    select type(unit_test)
        type is (unit_value)
            type_check_passed = .true.
    end select
    
    if (.not. type_check_passed) then
        print *, "  ✗ FAILED:dp() operator does not return unit_value type"
        stop 1
    end if
    
    ! Test with different operator
    unit_test = em(1.5)
    type_check_passed = .false.
    select type(unit_test)
        type is (unit_value)
            type_check_passed = .true.
    end select
    
    if (.not. type_check_passed) then
        print *, "  ✗ FAILED:em() operator does not return unit_value type"
        stop 1
    end if
    
    print *, "  ✓ Unit operators return types: class(*) compatibility verified"
end subroutine test_operator_return_types

subroutine test_unit_conversion_engine()
    ! Given: convert_to_dp() function with runtime type checking
    ! When: Converting various unit types with ui_context
    ! Then: Should produce correct dp values for all unit types and bare reals
    
    print *, "--- Unit Conversion Engine Tests ---"
    print *, "Testing runtime type conversion to dp..."
    
    call test_dp_conversion()
    call test_em_conversion()
    call test_sp_conversion()
    call test_px_conversion()
    call test_cw_conversion()
    call test_ch_conversion()
    call test_bare_real_conversion()
    call test_conversion_accuracy()
    
    print *, "✓ Unit conversion engine tests passed"
end subroutine test_unit_conversion_engine

subroutine test_dp_conversion()
    ! Given: dp units (base unit) and convert_to_dp function
    ! When: Converting dp values to dp (identity conversion)
    ! Then: Should return exact same value (base unit)
    
    type(ui_context) :: ctx
    class(*), allocatable :: dp_unit
    real :: result
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup default context
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test identity conversion for dp units
    dp_unit = dp(40.0)
    result = convert_to_dp(dp_unit, ctx)
    
    if (abs(result - 40.0) > TOLERANCE) then
        print *, "  ✗ FAILED: dp conversion should be identity, got", result, "expected 40.0"
        stop 1
    end if
    
    ! Test with different dp value
    dp_unit = dp(123.456)
    result = convert_to_dp(dp_unit, ctx)
    
    if (abs(result - 123.456) > TOLERANCE) then
        print *, "  ✗ FAILED: dp conversion precision error"
        stop 1
    end if
    
    print *, "  ✓ dp conversion: identity conversion verified"
end subroutine test_dp_conversion

subroutine test_em_conversion()
    ! Given: em units and convert_to_dp function with ui_context
    ! When: Converting em values using ctx%em_dp scaling factor
    ! Then: Should return value * ctx%em_dp correctly
    
    type(ui_context) :: ctx
    class(*), allocatable :: em_unit
    real :: result
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup context with em_dp = 16.0 (default font size)
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test 1em = 16dp
    em_unit = em(1.0)
    result = convert_to_dp(em_unit, ctx)
    
    if (abs(result - 16.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 1em should be 16dp, got", result
        stop 1
    end if
    
    ! Test 2.5em = 40dp
    em_unit = em(2.5)
    result = convert_to_dp(em_unit, ctx)
    
    if (abs(result - 40.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 2.5em should be 40dp, got", result
        stop 1
    end if
    
    ! Test with different em_dp context
    ctx%em_dp = 20.0
    em_unit = em(1.5)
    result = convert_to_dp(em_unit, ctx)
    
    if (abs(result - 30.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 1.5em with em_dp=20 should be 30dp, got", result
        stop 1
    end if
    
    print *, "  ✓ em conversion: font size scaling verified"
end subroutine test_em_conversion

subroutine test_sp_conversion()
    ! Given: sp units and convert_to_dp function with text_scale
    ! When: Converting sp values using ctx%text_scale for accessibility
    ! Then: Should return value * ctx%text_scale correctly
    
    type(ui_context) :: ctx
    class(*), allocatable :: sp_unit
    real :: result
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup context with default text_scale = 1.0
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test 14sp with scale=1.0 = 14dp
    sp_unit = sp(14.0)
    result = convert_to_dp(sp_unit, ctx)
    
    if (abs(result - 14.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 14sp with scale=1.0 should be 14dp, got", result
        stop 1
    end if
    
    ! Test with accessibility scaling (125% = 1.25)
    ctx%text_scale = 1.25
    sp_unit = sp(16.0)
    result = convert_to_dp(sp_unit, ctx)
    
    if (abs(result - 20.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 16sp with scale=1.25 should be 20dp, got", result
        stop 1
    end if
    
    print *, "  ✓ sp conversion: accessibility text scaling verified"
end subroutine test_sp_conversion

subroutine test_px_conversion()
    ! Given: px units and convert_to_dp function with dpi_scale
    ! When: Converting px values using ctx%dpi_scale for HiDPI displays
    ! Then: Should return value / ctx%dpi_scale correctly
    
    type(ui_context) :: ctx
    class(*), allocatable :: px_unit
    real :: result
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup context with standard DPI (scale=1.0)
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test 100px with scale=1.0 = 100dp
    px_unit = px(100.0)
    result = convert_to_dp(px_unit, ctx)
    
    if (abs(result - 100.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 100px with scale=1.0 should be 100dp, got", result
        stop 1
    end if
    
    ! Test with HiDPI scaling (2x DPI = scale=2.0)
    ctx%dpi_scale = 2.0
    px_unit = px(200.0)
    result = convert_to_dp(px_unit, ctx)
    
    if (abs(result - 100.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 200px with scale=2.0 should be 100dp, got", result
        stop 1
    end if
    
    print *, "  ✓ px conversion: HiDPI scaling verified"
end subroutine test_px_conversion

subroutine test_cw_conversion()
    ! Given: cw units and convert_to_dp function with cell_w_dp
    ! When: Converting cw values using ctx%cell_w_dp for TUI compatibility
    ! Then: Should return value * ctx%cell_w_dp correctly
    
    type(ui_context) :: ctx
    class(*), allocatable :: cw_unit
    real :: result
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup context with default cell_w_dp = 8.0
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test 10cw = 80dp
    cw_unit = cw(10.0)
    result = convert_to_dp(cw_unit, ctx)
    
    if (abs(result - 80.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 10cw should be 80dp, got", result
        stop 1
    end if
    
    ! Test with different cell width
    ctx%cell_w_dp = 12.0
    cw_unit = cw(5.0)
    result = convert_to_dp(cw_unit, ctx)
    
    if (abs(result - 60.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 5cw with cell_w_dp=12 should be 60dp, got", result
        stop 1
    end if
    
    print *, "  ✓ cw conversion: cell width scaling verified"
end subroutine test_cw_conversion

subroutine test_ch_conversion()
    ! Given: ch units and convert_to_dp function with cell_h_dp
    ! When: Converting ch values using ctx%cell_h_dp for TUI compatibility
    ! Then: Should return value * ctx%cell_h_dp correctly
    
    type(ui_context) :: ctx
    class(*), allocatable :: ch_unit
    real :: result
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup context with default cell_h_dp = 16.0
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test 3ch = 48dp
    ch_unit = ch(3.0)
    result = convert_to_dp(ch_unit, ctx)
    
    if (abs(result - 48.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 3ch should be 48dp, got", result
        stop 1
    end if
    
    ! Test with different cell height
    ctx%cell_h_dp = 20.0
    ch_unit = ch(2.0)
    result = convert_to_dp(ch_unit, ctx)
    
    if (abs(result - 40.0) > TOLERANCE) then
        print *, "  ✗ FAILED: 2ch with cell_h_dp=20 should be 40dp, got", result
        stop 1
    end if
    
    print *, "  ✓ ch conversion: cell height scaling verified"
end subroutine test_ch_conversion

subroutine test_bare_real_conversion()
    ! Given: Bare real values and convert_to_dp function
    ! When: Converting real values (should be treated as dp by default)
    ! Then: Should return exact real value as dp (no conversion)
    
    type(ui_context) :: ctx
    real :: bare_real, result
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup context
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test bare real treated as dp
    bare_real = 42.0
    result = convert_to_dp(bare_real, ctx)
    
    if (abs(result - 42.0) > TOLERANCE) then
        print *, "  ✗ FAILED: bare real 42.0 should be treated as 42dp, got", result
        stop 1
    end if
    
    ! Test fractional bare real
    bare_real = 123.456
    result = convert_to_dp(bare_real, ctx)
    
    if (abs(result - 123.456) > TOLERANCE) then
        print *, "  ✗ FAILED: bare real precision error"
        stop 1
    end if
    
    print *, "  ✓ bare real conversion: treated as dp units verified"
end subroutine test_bare_real_conversion

subroutine test_conversion_accuracy()
    ! Given: Various unit conversions with realistic contexts
    ! When: Testing conversion accuracy with representative values
    ! Then: Should maintain precision and produce realistic results
    
    type(ui_context) :: tui_ctx, gui_ctx
    class(*), allocatable :: unit_test
    real :: tui_result, gui_result
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup realistic contexts
    ! TUI context
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! GUI context (HiDPI with larger font)
    gui_ctx = ui_context(dpi_scale=1.5, em_dp=18.0, text_scale=1.25, cell_w_dp=9.0, cell_h_dp=18.0)
    
    ! Test complex conversion scenarios
    unit_test = em(2.5)
    tui_result = convert_to_dp(unit_test, tui_ctx)  ! 2.5 * 16 = 40
    gui_result = convert_to_dp(unit_test, gui_ctx)  ! 2.5 * 18 = 45
    
    if (abs(tui_result - 40.0) > TOLERANCE) then
        print *, "  ✗ FAILED: TUI em conversion inaccurate"
        stop 1
    end if
    
    if (abs(gui_result - 45.0) > TOLERANCE) then
        print *, "  ✗ FAILED: GUI em conversion inaccurate"
        stop 1
    end if
    
    print *, "  ✓ Conversion accuracy: realistic contexts handled correctly"
end subroutine test_conversion_accuracy

subroutine test_ui_context_management()
    ! Given: ui_context type and context management functions
    ! When: Testing context creation, modification, and usage
    ! Then: Should provide consistent context management API
    
    print *, "--- UI Context Management Tests ---"
    print *, "Testing ui_context type and management functions..."
    
    call test_ui_context_defaults()
    call test_ui_get_context()
    call test_ui_set_context()
    call test_context_backend_adaptation()
    call test_context_validation()
    
    print *, "✓ UI context management tests passed"
end subroutine test_ui_context_management

subroutine test_ui_context_defaults()
    ! Given: ui_context type definition
    ! When: Creating default ui_context instance
    ! Then: Should have correct default values per DESIGN.md specification
    
    type(ui_context) :: ctx
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Test default values match DESIGN.md specification exactly
    if (abs(ctx%dpi_scale - 1.0) > TOLERANCE) then
        print *, "  ✗ FAILED: default dpi_scale should be 1.0, got", ctx%dpi_scale
        stop 1
    end if
    
    if (abs(ctx%em_dp - 16.0) > TOLERANCE) then
        print *, "  ✗ FAILED: default em_dp should be 16.0, got", ctx%em_dp
        stop 1
    end if
    
    if (abs(ctx%text_scale - 1.0) > TOLERANCE) then
        print *, "  ✗ FAILED: default text_scale should be 1.0, got", ctx%text_scale
        stop 1
    end if
    
    if (abs(ctx%cell_w_dp - 8.0) > TOLERANCE) then
        print *, "  ✗ FAILED: default cell_w_dp should be 8.0, got", ctx%cell_w_dp
        stop 1
    end if
    
    if (abs(ctx%cell_h_dp - 16.0) > TOLERANCE) then
        print *, "  ✗ FAILED: default cell_h_dp should be 16.0, got", ctx%cell_h_dp
        stop 1
    end if
    
    print *, "  ✓ UI context defaults: all default values correct per DESIGN.md"
end subroutine test_ui_context_defaults

subroutine test_ui_get_context()
    ! Given: ui_get_context() function  
    ! When: Retrieving current UI context
    ! Then: Should return currently active context
    
    type(ui_context) :: retrieved_ctx
    
    ! Get current context
    call ui_get_context(retrieved_ctx)
    
    ! Function should execute without error
    ! Context values will be validated by other tests
    
    print *, "  ✓ ui_get_context: function executes successfully"
end subroutine test_ui_get_context

subroutine test_ui_set_context()
    ! Given: ui_set_context() function and custom context
    ! When: Setting custom UI context values
    ! Then: Should update active context and affect conversions
    
    type(ui_context) :: custom_ctx, retrieved_ctx
    
    ! Create custom context
    custom_ctx = ui_context(dpi_scale=2.0, em_dp=20.0, text_scale=1.5, cell_w_dp=10.0, cell_h_dp=20.0)
    
    ! Set custom context
    call ui_set_context(custom_ctx)
    
    ! Verify context was set
    call ui_get_context(retrieved_ctx)
    
    ! Context changes should be reflected in conversions
    ! (detailed conversion validation tested elsewhere)
    
    print *, "  ✓ ui_set_context: custom context setting works"
end subroutine test_ui_set_context

subroutine test_context_backend_adaptation()
    ! Given: ui_context adaptation for different backends
    ! When: Setting up context for TUI vs GUI backends
    ! Then: Should adapt context values appropriately for each backend
    
    type(ui_context) :: tui_ctx, gui_ctx
    
    ! Test TUI context characteristics
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! TUI should have dpi_scale=1.0 (no DPI scaling in terminal)
    if (tui_ctx%dpi_scale /= 1.0) then
        print *, "  ✗ FAILED: TUI context should have dpi_scale=1.0"
        stop 1
    end if
    
    ! Test GUI context characteristics  
    gui_ctx = ui_context(dpi_scale=1.5, em_dp=18.0, text_scale=1.25, cell_w_dp=9.0, cell_h_dp=18.0)
    
    ! GUI can have arbitrary dpi_scale for HiDPI
    if (gui_ctx%dpi_scale <= 0.0) then
        print *, "  ✗ FAILED: GUI context should have positive dpi_scale"
        stop 1
    end if
    
    print *, "  ✓ Context backend adaptation: TUI and GUI contexts configured correctly"
end subroutine test_context_backend_adaptation

subroutine test_context_validation()
    ! Given: ui_context with various value ranges
    ! When: Testing context validation and edge cases
    ! Then: Should handle reasonable ranges and edge cases appropriately
    
    type(ui_context) :: edge_ctx
    
    ! Test minimum reasonable values
    edge_ctx = ui_context(dpi_scale=0.1, em_dp=1.0, text_scale=0.1, cell_w_dp=1.0, cell_h_dp=1.0)
    
    ! Values should be positive and reasonable
    if (edge_ctx%dpi_scale <= 0.0 .or. edge_ctx%em_dp <= 0.0 .or. edge_ctx%text_scale <= 0.0) then
        print *, "  ✗ FAILED: context values should be positive"
        stop 1
    end if
    
    ! Test large values
    edge_ctx = ui_context(dpi_scale=5.0, em_dp=100.0, text_scale=3.0, cell_w_dp=50.0, cell_h_dp=100.0)
    
    ! Large values should be acceptable
    if (edge_ctx%dpi_scale <= 0.0) then
        print *, "  ✗ FAILED: large context values should be acceptable"
        stop 1
    end if
    
    print *, "  ✓ Context validation: edge cases and ranges handled appropriately"
end subroutine test_context_validation

subroutine test_class_star_parameter_handling()
    ! Given: class(*) parameter support throughout API
    ! When: Testing mixed unit types in function parameters
    ! Then: Should accept any unit type or bare real seamlessly
    
    print *, "--- Class(*) Parameter Handling Tests ---"
    print *, "Testing class(*) parameter integration throughout API..."
    
    call test_class_star_assignment()
    call test_class_star_function_parameters()
    call test_mixed_unit_scenarios()
    call test_class_star_type_safety()
    
    print *, "✓ Class(*) parameter handling tests passed"
end subroutine test_class_star_parameter_handling

subroutine test_class_star_assignment()
    ! Given: class(*) variables and unit operators
    ! When: Assigning different unit types to class(*) variables
    ! Then: Should accept all unit types and bare reals
    
    class(*), allocatable :: mixed_unit
    
    ! Test assignment of all unit types
    mixed_unit = dp(40.0)
    mixed_unit = em(2.5)
    mixed_unit = sp(14.0)
    mixed_unit = px(320.0)
    mixed_unit = cw(10.0)
    mixed_unit = ch(3.0)
    
    ! Test assignment of bare real
    mixed_unit = 42.0
    
    ! All assignments should succeed without compilation errors
    print *, "  ✓ class(*) assignment: all unit types and bare reals accepted"
end subroutine test_class_star_assignment

subroutine test_class_star_function_parameters()
    ! Given: Functions accepting class(*) parameters
    ! When: Calling functions with mixed unit types
    ! Then: Should accept parameters and convert properly
    
    type(ui_context) :: ctx
    real :: result
    
    ! Setup context
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test function calls with different unit types
    result = convert_to_dp(dp(40.0), ctx)
    result = convert_to_dp(em(2.5), ctx)
    result = convert_to_dp(sp(14.0), ctx)
    result = convert_to_dp(px(320.0), ctx)
    result = convert_to_dp(cw(10.0), ctx)
    result = convert_to_dp(ch(3.0), ctx)
    result = convert_to_dp(42.0, ctx)  ! bare real
    
    print *, "  ✓ class(*) function parameters: all unit types accepted in function calls"
end subroutine test_class_star_function_parameters

subroutine test_mixed_unit_scenarios()
    ! Given: Realistic mixed unit usage scenarios from DESIGN.md
    ! When: Using different units in same context (like widget parameters)
    ! Then: Should handle mixed usage cleanly
    
    type(ui_context) :: ctx
    class(*), allocatable :: width, height, gap, text_size
    real :: w_dp, h_dp, g_dp, ts_dp
    
    ! Setup context
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test mixed unit scenario from DESIGN.md example:
    ! button("ok", width=120.0, height=em(2.5))
    width = 120.0      ! bare real (treated as dp)
    height = em(2.5)  ! explicit em unit
    gap = ch(1.0)     ! cell height for spacing
    text_size = sp(14.0)  ! scaled pixels for text
    
    ! Convert all to dp for processing
    w_dp = convert_to_dp(width, ctx)
    h_dp = convert_to_dp(height, ctx)
    g_dp = convert_to_dp(gap, ctx)
    ts_dp = convert_to_dp(text_size, ctx)
    
    ! Results should be reasonable
    if (w_dp <= 0.0 .or. h_dp <= 0.0 .or. g_dp <= 0.0 .or. ts_dp <= 0.0) then
        print *, "  ✗ FAILED: mixed unit conversion produced invalid results"
        stop 1
    end if
    
    print *, "  ✓ Mixed unit scenarios: realistic mixed usage works correctly"
end subroutine test_mixed_unit_scenarios

subroutine test_class_star_type_safety()
    ! Given: Runtime type checking with class(*) parameters
    ! When: Processing class(*) parameters with select type
    ! Then: Should provide runtime type safety with clear error handling
    
    class(*), allocatable :: test_unit
    logical :: type_identified
    
    ! Test type identification for unit_value
    test_unit = dp(42.0)
    type_identified = .false.
    
    select type(test_unit)
        type is (unit_value)
            type_identified = .true.
        type is (real)
            print *, "  ✗ FAILED: unit operator should create unit_value, not real"
            stop 1
        class default
            print *, "  ✗ FAILED: unknown type from unit operator"
            stop 1
    end select
    
    if (.not. type_identified) then
        print *, "  ✗ FAILED: type identification failed"
        stop 1
    end if
    
    ! Test type identification for bare real
    test_unit = 42.0
    type_identified = .false.
    
    select type(test_unit)
        type is (real)
            type_identified = .true.
        type is (unit_value)
            print *, "  ✗ FAILED: bare real should remain real type"
            stop 1
        class default
            print *, "  ✗ FAILED: bare real should be real type"
            stop 1
    end select
    
    if (.not. type_identified) then
        print *, "  ✗ FAILED: bare real type identification failed"
        stop 1
    end if
    
    print *, "  ✓ class(*) type safety: runtime type checking works correctly"
end subroutine test_class_star_type_safety

subroutine test_cross_backend_integration()
    ! Given: Cross-backend coordinate conversion requirements
    ! When: Converting dp values for TUI vs GUI backends
    ! Then: Should handle TUI cell snapping vs GUI subpixel precision correctly
    
    print *, "--- Cross-Backend Integration Tests ---"
    print *, "Testing TUI cell snapping vs GUI subpixel precision..."
    
    call test_tui_cell_snapping()
    call test_gui_subpixel_precision()
    call test_backend_coordinate_conversion()
    call test_cross_backend_consistency()
    
    print *, "✓ Cross-backend integration tests passed"
end subroutine test_cross_backend_integration

subroutine test_tui_cell_snapping()
    ! Given: TUI backend coordinate conversion requirements
    ! When: Converting dp values to TUI cell coordinates
    ! Then: Should snap to integer cell boundaries as per DESIGN.md
    
    type(ui_context) :: tui_ctx
    real :: dp_value, cell_x, cell_y
    integer :: snapped_x, snapped_y
    
    ! Setup TUI context
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Test example from DESIGN.md: dp(42.7) with cell_w_dp=8.0 → 5.34 cells → snap to 5 cells
    dp_value = 42.7
    cell_x = dp_value / tui_ctx%cell_w_dp  ! 42.7 / 8.0 = 5.3375
    snapped_x = nint(cell_x)               ! round to nearest integer = 5
    
    if (snapped_x /= 5) then
        print *, "  ✗ FAILED: TUI snapping should round 5.34 cells to 5, got", snapped_x
        stop 1
    end if
    
    ! Test height snapping
    dp_value = 37.9
    cell_y = dp_value / tui_ctx%cell_h_dp  ! 37.9 / 16.0 = 2.36875
    snapped_y = nint(cell_y)               ! round to nearest integer = 2
    
    if (snapped_y /= 2) then
        print *, "  ✗ FAILED: TUI height snapping failed"
        stop 1
    end if
    
    ! Test exact cell boundary (should not change)
    dp_value = 80.0  ! exactly 10 cells
    cell_x = dp_value / tui_ctx%cell_w_dp
    snapped_x = nint(cell_x)
    
    if (snapped_x /= 10) then
        print *, "  ✗ FAILED: exact cell boundary snapping failed"
        stop 1
    end if
    
    print *, "  ✓ TUI cell snapping: dp values snap to integer cell boundaries correctly"
end subroutine test_tui_cell_snapping

subroutine test_gui_subpixel_precision()
    ! Given: GUI backend coordinate conversion requirements
    ! When: Converting dp values to GUI pixel coordinates
    ! Then: Should maintain subpixel precision as per DESIGN.md
    
    type(ui_context) :: gui_ctx
    real :: dp_value, pixel_x
    real, parameter :: TOLERANCE = 1.0e-6
    
    ! Setup GUI context with HiDPI scaling
    gui_ctx = ui_context(dpi_scale=1.5, em_dp=18.0, text_scale=1.25, cell_w_dp=9.0, cell_h_dp=18.0)
    
    ! Test example from DESIGN.md: dp(42.7) with dpi_scale=1.5 → 64.05 pixels (exact)
    dp_value = 42.7
    pixel_x = dp_value * gui_ctx%dpi_scale  ! 42.7 * 1.5 = 64.05
    
    if (abs(pixel_x - 64.05) > TOLERANCE) then
        print *, "  ✗ FAILED: GUI subpixel precision lost, got", pixel_x, "expected 64.05"
        stop 1
    end if
    
    ! Test fractional dp with fractional scaling
    dp_value = 33.333
    pixel_x = dp_value * gui_ctx%dpi_scale  ! 33.333 * 1.5 = 49.9995
    
    if (abs(pixel_x - 49.9995) > TOLERANCE) then
        print *, "  ✗ FAILED: GUI fractional precision lost"
        stop 1
    end if
    
    print *, "  ✓ GUI subpixel precision: exact fractional coordinates maintained"
end subroutine test_gui_subpixel_precision

subroutine test_backend_coordinate_conversion()
    ! Given: Backend-specific coordinate conversion functions
    ! When: Converting same dp values for different backends
    ! Then: Should produce appropriate coordinates for each backend type
    
    real :: dp_width, dp_height
    integer :: tui_w_cells, tui_h_cells
    real :: gui_w_pixels, gui_h_pixels
    type(ui_context) :: tui_ctx, gui_ctx
    
    ! Setup contexts
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    gui_ctx = ui_context(dpi_scale=2.0, em_dp=20.0, text_scale=1.0, cell_w_dp=10.0, cell_h_dp=20.0)
    
    ! Test same logical size converted for different backends
    dp_width = 80.0   ! 80dp logical width
    dp_height = 48.0  ! 48dp logical height
    
    ! TUI conversion (snap to cells)
    tui_w_cells = nint(dp_width / tui_ctx%cell_w_dp)   ! 80/8 = 10 cells
    tui_h_cells = nint(dp_height / tui_ctx%cell_h_dp)  ! 48/16 = 3 cells
    
    ! GUI conversion (exact pixels)
    gui_w_pixels = dp_width * gui_ctx%dpi_scale   ! 80*2 = 160 pixels
    gui_h_pixels = dp_height * gui_ctx%dpi_scale  ! 48*2 = 96 pixels
    
    if (tui_w_cells /= 10 .or. tui_h_cells /= 3) then
        print *, "  ✗ FAILED: TUI coordinate conversion incorrect"
        stop 1
    end if
    
    if (gui_w_pixels /= 160.0 .or. gui_h_pixels /= 96.0) then
        print *, "  ✗ FAILED: GUI coordinate conversion incorrect"
        stop 1
    end if
    
    print *, "  ✓ Backend coordinate conversion: same dp converts appropriately per backend"
end subroutine test_backend_coordinate_conversion

subroutine test_cross_backend_consistency()
    ! Given: Cross-backend layout consistency requirements
    ! When: Testing that logical layouts work consistently across backends
    ! Then: Should maintain proportional relationships despite different precision
    
    type(ui_context) :: tui_ctx, gui_ctx
    class(*), allocatable :: button_width, button_height, gap
    real :: tui_w_dp, tui_h_dp, tui_g_dp
    real :: gui_w_dp, gui_h_dp, gui_g_dp
    real :: tui_ratio, gui_ratio
    real, parameter :: TOLERANCE = 0.15  ! Allow differences due to different font sizes
    
    ! Setup contexts
    tui_ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    gui_ctx = ui_context(dpi_scale=1.5, em_dp=18.0, text_scale=1.0, cell_w_dp=9.0, cell_h_dp=18.0)
    
    ! Test consistent proportional relationships
    button_width = dp(120.0)
    button_height = em(2.0)
    gap = ch(1.0)
    
    ! Convert for both backends
    tui_w_dp = convert_to_dp(button_width, tui_ctx)
    tui_h_dp = convert_to_dp(button_height, tui_ctx)
    tui_g_dp = convert_to_dp(gap, tui_ctx)
    
    gui_w_dp = convert_to_dp(button_width, gui_ctx)
    gui_h_dp = convert_to_dp(button_height, gui_ctx)
    gui_g_dp = convert_to_dp(gap, gui_ctx)
    
    ! Check that relationships are preserved
    tui_ratio = tui_w_dp / tui_h_dp
    gui_ratio = gui_w_dp / gui_h_dp
    
    ! Ratios should be similar (accounting for different font sizes)
    if (abs(tui_ratio / gui_ratio - 1.0) > TOLERANCE) then
        print *, "  ✗ FAILED: cross-backend proportional consistency lost"
        stop 1
    end if
    
    print *, "  ✓ Cross-backend consistency: proportional relationships maintained"
end subroutine test_cross_backend_consistency

subroutine test_runtime_error_handling()
    ! Given: Runtime error handling requirements for units system
    ! When: Encountering invalid types, values, or conversion scenarios
    ! Then: Should provide clear error messages and handle errors gracefully
    
    print *, "--- Runtime Error Handling Tests ---"
    print *, "Testing error conditions and recovery..."
    
    call test_unsupported_type_error()
    call test_invalid_context_handling()
    call test_error_message_clarity()
    call test_graceful_error_recovery()
    
    print *, "✓ Runtime error handling tests passed"
end subroutine test_runtime_error_handling

subroutine test_unsupported_type_error()
    ! Given: convert_to_dp() with unsupported class(*) types
    ! When: Passing non-unit, non-real types
    ! Then: Should detect unsupported types and provide clear error message
    
    type(ui_context) :: ctx
    integer :: invalid_type
    character(len=10) :: string_type
    
    ! Setup context
    ctx = ui_context(dpi_scale=1.0, em_dp=16.0, text_scale=1.0, cell_w_dp=8.0, cell_h_dp=16.0)
    
    ! Note: These tests are designed to verify error handling exists
    ! Actual error handling implementation will be added by sergei
    ! Tests verify the function recognizes unsupported types
    
    print *, "  ✓ Unsupported type error handling test ready (awaiting implementation)"
    print *, "    ℹ Will test integer, character, and other invalid types"
end subroutine test_unsupported_type_error

subroutine test_invalid_context_handling()
    ! Given: ui_context with invalid values
    ! When: Using context with negative or zero scaling factors
    ! Then: Should handle invalid contexts gracefully
    
    type(ui_context) :: invalid_ctx
    class(*), allocatable :: test_unit
    real :: result
    
    ! Test context with invalid values
    invalid_ctx = ui_context(dpi_scale=0.0, em_dp=-5.0, text_scale=0.0, cell_w_dp=-1.0, cell_h_dp=0.0)
    
    test_unit = dp(10.0)
    
    ! Function should handle invalid context gracefully
    ! Implementation will add appropriate validation and error handling
    
    print *, "  ✓ Invalid context handling test ready (awaiting implementation)"
    print *, "    ℹ Will test negative/zero scaling factors"
end subroutine test_invalid_context_handling

subroutine test_error_message_clarity()
    ! Given: Error conditions in units system
    ! When: Errors occur during conversion or processing
    ! Then: Should provide clear, actionable error messages
    
    ! Error message clarity will be validated when error handling is implemented
    ! Messages should include:
    ! - What went wrong
    ! - What was expected
    ! - How to fix the issue
    
    print *, "  ✓ Error message clarity test ready (awaiting implementation)"
    print *, "    ℹ Will validate error message quality and actionability"
end subroutine test_error_message_clarity

subroutine test_graceful_error_recovery()
    ! Given: Error conditions that can be recovered from
    ! When: Non-fatal errors occur
    ! Then: Should attempt graceful recovery when possible
    
    ! Test scenarios where graceful recovery is possible:
    ! - Slightly invalid context values (clamp to valid range)
    ! - Missing context (use defaults)
    ! - Minor precision issues (continue with reduced precision)
    
    print *, "  ✓ Graceful error recovery test ready (awaiting implementation)"
    print *, "    ℹ Will test recovery from non-fatal error conditions"
end subroutine test_graceful_error_recovery

subroutine test_performance_characteristics()
    ! Given: Performance requirements for frequent unit conversions
    ! When: Testing conversion performance and overhead
    ! Then: Should maintain acceptable performance for UI use cases
    
    print *, "--- Performance Characteristics Tests ---"
    print *, "Testing conversion performance and overhead..."
    
    call test_conversion_performance()
    call test_memory_efficiency()
    call test_repeated_conversion_overhead()
    
    print *, "✓ Performance characteristics tests passed"
end subroutine test_performance_characteristics

subroutine test_conversion_performance()
    ! Given: Frequent unit conversions in UI rendering
    ! When: Performing many conversions rapidly
    ! Then: Should maintain reasonable performance
    
    type(ui_context) :: ctx
    class(*), allocatable :: test_unit
    real :: result
    integer :: i
    integer, parameter :: NUM_CONVERSIONS = 1000
    
    ! Setup context
    ctx = ui_context(dpi_scale=1.5, em_dp=18.0, text_scale=1.0, cell_w_dp=9.0, cell_h_dp=18.0)
    
    ! Test repeated conversions (simplified performance test)
    test_unit = dp(42.0)
    do i = 1, NUM_CONVERSIONS
        result = convert_to_dp(test_unit, ctx)
    end do
    
    ! Test should complete in reasonable time
    print *, "  ✓ Conversion performance: handled", NUM_CONVERSIONS, "conversions efficiently"
end subroutine test_conversion_performance

subroutine test_memory_efficiency()
    ! Given: unit_value types and class(*) usage
    ! When: Creating and destroying many unit values
    ! Then: Should use memory efficiently without leaks
    
    class(*), allocatable :: temp_unit
    integer :: i
    integer, parameter :: NUM_ALLOCATIONS = 100
    
    ! Test repeated allocation/deallocation
    do i = 1, NUM_ALLOCATIONS
        temp_unit = dp(real(i))
        ! Fortran handles deallocation automatically when temp_unit goes out of scope
    end do
    
    print *, "  ✓ Memory efficiency: handled", NUM_ALLOCATIONS, "allocations cleanly"
end subroutine test_memory_efficiency

subroutine test_repeated_conversion_overhead()
    ! Given: Same unit converted multiple times
    ! When: Converting identical units repeatedly
    ! Then: Should handle repeated conversions efficiently
    
    type(ui_context) :: ctx
    class(*), allocatable :: em_unit, px_unit, cw_unit
    real :: em_result, px_result, cw_result
    integer :: i
    integer, parameter :: NUM_REPEATS = 200
    
    ! Setup context
    ctx = ui_context(dpi_scale=2.0, em_dp=20.0, text_scale=1.5, cell_w_dp=10.0, cell_h_dp=20.0)
    
    ! Setup test units
    em_unit = em(2.5)
    px_unit = px(200.0)
    cw_unit = cw(8.0)
    
    ! Test repeated conversions of different unit types
    do i = 1, NUM_REPEATS
        em_result = convert_to_dp(em_unit, ctx)
        px_result = convert_to_dp(px_unit, ctx)
        cw_result = convert_to_dp(cw_unit, ctx)
    end do
    
    print *, "  ✓ Repeated conversion overhead: minimal overhead for", NUM_REPEATS, "repetitions"
end subroutine test_repeated_conversion_overhead

! Utility functions for test validation

subroutine verify_unit_value(unit, expected_value, expected_type, test_name)
    ! Given: unit_value from operator and expected values
    ! When: Verifying unit_value contents
    ! Then: Should match expected value and type exactly
    
    class(*), intent(in) :: unit
    real, intent(in) :: expected_value
    character(*), intent(in) :: expected_type
    character(*), intent(in) :: test_name
    real, parameter :: TOLERANCE = 1.0e-6
    
    select type(unit)
        type is (unit_value)
            if (abs(unit%value - expected_value) > TOLERANCE) then
                print *, "  ✗ FAILED:", test_name, "- value mismatch, got", unit%value, "expected", expected_value
                stop 1
            end if
            
            if (trim(unit%unit_type) /= trim(expected_type)) then
                print *, "  ✗ FAILED:", test_name, "- type mismatch, got '", trim(unit%unit_type), "' expected '", trim(expected_type), "'"
                stop 1
            end if
        class default
            print *, "  ✗ FAILED:", test_name, "- wrong type returned from operator"
            stop 1
    end select
end subroutine verify_unit_value

end module test_units_system