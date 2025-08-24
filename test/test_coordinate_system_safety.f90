program test_coordinate_system_safety
! Test suite for Issue #62: Missing coordinate system abstraction causing conversion errors
! Validates that coordinate conversions are safe from division-by-zero and overflow
use fortui_coordinates
use iso_fortran_env, only: real32
implicit none

! Test results tracking
integer :: total_tests = 0
integer :: passed_tests = 0

! Run all tests
call test_coordinate_types()
call test_safe_conversions()
call test_transformer_validation()
call test_coordinate_transformations()
call test_error_handling()
call test_edge_cases()

! Report results
call print_test_summary()

contains

subroutine test_coordinate_types()
    print *, "=== Testing Coordinate Type Safety ==="
    
    call test_coordinate_abstraction()
    call test_coordinate_string_representations()
    
    print *, ""
end subroutine test_coordinate_types

subroutine test_coordinate_abstraction()
    ! Test that coordinate types enforce explicit space representation via discriminated union
    type(coordinate_t) :: screen_coord, viewport_coord, logical_coord
    
    ! Initialize coordinates using constructors
    screen_coord = create_screen_coord(100.0, 200.0)
    viewport_coord = create_viewport_coord(0.5, 0.75)
    logical_coord = create_logical_coord(42.7, 33.3)
    
    call assert_real_equal(screen_coord%x, 100.0, "Screen coordinate X assignment")
    call assert_real_equal(screen_coord%y, 200.0, "Screen coordinate Y assignment")
    call assert_true(screen_coord%space_type == SCREEN_SPACE, "Screen coordinate type tag")
    call assert_real_equal(viewport_coord%x, 0.5, "Viewport coordinate X assignment")
    call assert_real_equal(viewport_coord%y, 0.75, "Viewport coordinate Y assignment")
    call assert_true(viewport_coord%space_type == VIEWPORT_SPACE, "Viewport coordinate type tag")
    call assert_real_equal(logical_coord%x, 42.7, "Logical coordinate X assignment")
    call assert_real_equal(logical_coord%y, 33.3, "Logical coordinate Y assignment")
    call assert_true(logical_coord%space_type == LOGICAL_SPACE, "Logical coordinate type tag")
end subroutine test_coordinate_abstraction

subroutine test_coordinate_string_representations()
    ! Test coordinate to string conversion for debugging
    type(coordinate_t) :: screen_coord, viewport_coord, logical_coord
    character(64) :: str
    
    screen_coord = create_screen_coord(150.0, 250.0)
    str = coordinate_to_string(screen_coord)
    call assert_true(len_trim(str) > 0, "Screen coordinate string representation")
    
    viewport_coord = create_viewport_coord(0.25, 0.80)
    str = coordinate_to_string(viewport_coord)
    call assert_true(len_trim(str) > 0, "Viewport coordinate string representation")
    
    logical_coord = create_logical_coord(64.0, 48.0)
    str = coordinate_to_string(logical_coord)
    call assert_true(len_trim(str) > 0, "Logical coordinate string representation")
end subroutine test_coordinate_string_representations

subroutine test_safe_conversions()
    print *, "=== Testing Safe Conversion Functions ==="
    
    call test_safe_px_to_dp()
    call test_safe_dp_to_px()
    call test_safe_scale_coordinate()
    call test_division_by_zero_protection()
    
    print *, ""
end subroutine test_safe_conversions

subroutine test_safe_px_to_dp()
    ! Test safe pixel to DP conversion (Issue #62 core fix)
    type(coordinate_error_t) :: error
    real(real32) :: result
    
    ! Normal conversion
    result = safe_px_to_dp(100.0_real32, 2.0_real32, error)
    call assert_error_success(error, "Normal px to dp conversion")
    call assert_real_equal(result, 50.0, "px to dp calculation: 100/2 = 50")
    
    ! High DPI conversion
    result = safe_px_to_dp(150.0_real32, 1.5_real32, error)
    call assert_error_success(error, "High DPI px to dp conversion")
    call assert_real_equal(result, 100.0, "High DPI calculation: 150/1.5 = 100")
    
    ! Zero DPI scale (should return fallback)
    result = safe_px_to_dp(200.0_real32, 0.0_real32, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Zero DPI scale error")
    call assert_real_equal(result, 200.0, "Zero DPI fallback: return px as dp")
    
    ! Negative DPI scale (should return fallback)
    result = safe_px_to_dp(100.0_real32, -1.0_real32, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Negative DPI scale error")
end subroutine test_safe_px_to_dp

subroutine test_safe_dp_to_px()
    ! Test safe DP to pixel conversion
    type(coordinate_error_t) :: error
    real(real32) :: result
    
    ! Normal conversion
    result = safe_dp_to_px(50.0_real32, 2.0_real32, error)
    call assert_error_success(error, "Normal dp to px conversion")
    call assert_real_equal(result, 100.0, "dp to px calculation: 50*2 = 100")
    
    ! Zero scale factor
    result = safe_dp_to_px(50.0_real32, 0.0_real32, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Zero scale factor error")
end subroutine test_safe_dp_to_px

subroutine test_safe_scale_coordinate()
    ! Test safe coordinate scaling with overflow protection
    type(coordinate_error_t) :: error
    real(real32) :: result
    
    ! Normal scaling
    result = safe_scale_coordinate(100.0_real32, 1.5_real32, error)
    call assert_error_success(error, "Normal coordinate scaling")
    call assert_real_equal(result, 150.0, "Scale calculation: 100*1.5 = 150")
    
    ! Zero scale factor
    result = safe_scale_coordinate(100.0_real32, 0.0_real32, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Zero scale factor error")
    call assert_real_equal(result, 100.0, "Zero scale fallback: return original")
    
    ! Very small scale factor
    result = safe_scale_coordinate(100.0_real32, 1e-20_real32, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Very small scale factor error")
end subroutine test_safe_scale_coordinate

subroutine test_division_by_zero_protection()
    ! Test the core division by zero protection (Issue #62 vulnerability)
    type(coordinate_error_t) :: error
    real(real32) :: result
    real(real32) :: tiny_scale
    
    ! Test with epsilon-level scale
    tiny_scale = epsilon(1.0_real32) / 2.0
    result = safe_px_to_dp(100.0_real32, tiny_scale, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Epsilon-level scale protection")
    
    ! Test with exactly zero
    result = safe_px_to_dp(100.0_real32, 0.0_real32, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Exact zero scale protection")
    
    ! Test with negative near-zero
    result = safe_px_to_dp(100.0_real32, -1e-10_real32, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Negative near-zero protection")
end subroutine test_division_by_zero_protection

subroutine test_transformer_validation()
    print *, "=== Testing Transformer Validation ==="
    
    call test_valid_transformer_creation()
    call test_invalid_transformer_handling()
    
    print *, ""
end subroutine test_transformer_validation

subroutine test_valid_transformer_creation()
    ! Test creation of valid coordinate transformer
    type(coordinate_transformer_t) :: transformer
    type(coordinate_error_t) :: error
    
    transformer = create_transformer(1.5_real32, 800.0_real32, 600.0_real32)
    call transformer%validate(error)
    
    call assert_error_success(error, "Valid transformer creation")
    call assert_true(transformer%initialized, "Transformer initialized")
    call assert_real_equal(transformer%dpi_scale, 1.5, "DPI scale preserved")
    call assert_real_equal(transformer%viewport_width, 800.0, "Viewport width preserved")
    call assert_real_equal(transformer%viewport_height, 600.0, "Viewport height preserved")
end subroutine test_valid_transformer_creation

subroutine test_invalid_transformer_handling()
    ! Test handling of invalid transformer parameters
    type(coordinate_transformer_t) :: transformer
    type(coordinate_error_t) :: error
    
    ! Invalid DPI scale
    transformer = create_transformer(0.0_real32, 800.0_real32, 600.0_real32)
    call assert_true(transformer%initialized, "Invalid transformer auto-corrected")
    call assert_real_equal(transformer%dpi_scale, 1.0, "DPI scale corrected to safe default")
    
    ! Invalid viewport dimensions
    transformer = create_transformer(1.0_real32, -800.0_real32, 600.0_real32)
    call assert_real_equal(transformer%viewport_width, 1.0, "Viewport width corrected")
end subroutine test_invalid_transformer_handling

subroutine test_coordinate_transformations()
    print *, "=== Testing Coordinate Transformations ==="
    
    call test_screen_to_logical_transform()
    call test_logical_to_screen_transform()
    call test_viewport_transforms()
    
    print *, ""
end subroutine test_coordinate_transformations

subroutine test_screen_to_logical_transform()
    ! Test screen to logical space transformation
    type(coordinate_transformer_t) :: transformer
    type(coordinate_t) :: screen_coord, logical_coord
    type(coordinate_error_t) :: error
    
    transformer = create_transformer(2.0_real32, 800.0_real32, 600.0_real32)
    
    screen_coord = create_screen_coord(200.0, 150.0)
    
    logical_coord = transformer%transform_screen_to_logical(screen_coord, error)
    
    call assert_error_success(error, "Screen to logical transformation")
    call assert_real_equal(logical_coord%x, 100.0, "Screen to logical X: 200/2 = 100")
    call assert_real_equal(logical_coord%y, 75.0, "Screen to logical Y: 150/2 = 75")
    call assert_true(logical_coord%space_type == LOGICAL_SPACE, "Output coordinate has logical space type")
end subroutine test_screen_to_logical_transform

subroutine test_logical_to_screen_transform()
    ! Test logical to screen space transformation
    type(coordinate_transformer_t) :: transformer
    type(coordinate_t) :: logical_coord, screen_coord
    type(coordinate_error_t) :: error
    
    transformer = create_transformer(1.5_real32, 800.0_real32, 600.0_real32)
    
    logical_coord = create_logical_coord(100.0, 80.0)
    
    screen_coord = transformer%transform_logical_to_screen(logical_coord, error)
    
    call assert_error_success(error, "Logical to screen transformation")
    call assert_real_equal(screen_coord%x, 150.0, "Logical to screen X: 100*1.5 = 150")
    call assert_real_equal(screen_coord%y, 120.0, "Logical to screen Y: 80*1.5 = 120")
    call assert_true(screen_coord%space_type == SCREEN_SPACE, "Output coordinate has screen space type")
end subroutine test_logical_to_screen_transform

subroutine test_viewport_transforms()
    ! Test viewport coordinate transformations
    type(coordinate_transformer_t) :: transformer
    type(coordinate_t) :: viewport_coord, screen_coord
    type(coordinate_error_t) :: error
    
    transformer = create_transformer(1.0_real32, 800.0_real32, 600.0_real32)
    
    ! Viewport to screen
    viewport_coord = create_viewport_coord(0.5, 0.25)  ! Center X, Quarter Y
    
    screen_coord = transformer%transform_viewport_to_screen(viewport_coord, error)
    
    call assert_error_success(error, "Viewport to screen transformation")
    call assert_real_equal(screen_coord%x, 400.0, "Viewport to screen X: 0.5*800 = 400")
    call assert_real_equal(screen_coord%y, 150.0, "Viewport to screen Y: 0.25*600 = 150")
    call assert_true(screen_coord%space_type == SCREEN_SPACE, "V2S output has screen space type")
    
    ! Screen to viewport
    screen_coord = create_screen_coord(200.0, 300.0)
    
    viewport_coord = transformer%transform_screen_to_viewport(screen_coord, error)
    
    call assert_error_success(error, "Screen to viewport transformation")
    call assert_real_equal(viewport_coord%x, 0.25, "Screen to viewport X: 200/800 = 0.25")
    call assert_real_equal(viewport_coord%y, 0.5, "Screen to viewport Y: 300/600 = 0.5")
    call assert_true(viewport_coord%space_type == VIEWPORT_SPACE, "S2V output has viewport space type")
end subroutine test_viewport_transforms

subroutine test_error_handling()
    print *, "=== Testing Error Handling ==="
    
    call test_overflow_protection()
    call test_invalid_viewport_coordinates()
    call test_zero_viewport_dimensions()
    
    print *, ""
end subroutine test_error_handling

subroutine test_overflow_protection()
    ! Test overflow protection in coordinate calculations
    type(coordinate_error_t) :: error
    real(real32) :: result, large_value, small_scale
    
    large_value = huge(1.0_real32) / 2.0
    small_scale = 1e-20_real32
    
    result = safe_scale_coordinate(large_value, small_scale, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Overflow protection via zero scale")
    
    ! Test near-overflow condition
    result = safe_scale_coordinate(huge(1.0_real32) / 10.0, 100.0_real32, error)
    call assert_error_code(error, COORD_ERROR_OVERFLOW, "Overflow protection")
end subroutine test_overflow_protection

subroutine test_invalid_viewport_coordinates()
    ! Test handling of invalid viewport coordinates
    type(coordinate_transformer_t) :: transformer
    type(coordinate_t) :: viewport_coord, screen_coord
    type(coordinate_error_t) :: error
    
    transformer = create_transformer(1.0_real32, 800.0_real32, 600.0_real32)
    
    ! Viewport coordinates out of range
    viewport_coord = create_viewport_coord(1.5, -0.5)  ! > 1.0 and < 0.0
    
    screen_coord = transformer%transform_viewport_to_screen(viewport_coord, error)
    call assert_error_code(error, COORD_ERROR_INVALID_INPUT, "Invalid viewport coordinates")
end subroutine test_invalid_viewport_coordinates

subroutine test_zero_viewport_dimensions()
    ! Test handling of zero viewport dimensions
    type(coordinate_transformer_t) :: transformer
    type(coordinate_t) :: screen_coord, viewport_coord
    type(coordinate_error_t) :: error
    
    transformer = create_transformer(1.0_real32, 0.0_real32, 600.0_real32)
    
    screen_coord = create_screen_coord(100.0, 100.0)
    
    viewport_coord = transformer%transform_screen_to_viewport(screen_coord, error)
    call assert_error_code(error, COORD_ERROR_ZERO_SCALE, "Zero viewport width error")
end subroutine test_zero_viewport_dimensions

subroutine test_edge_cases()
    print *, "=== Testing Edge Cases ==="
    
    call test_minimum_scale_values()
    call test_maximum_scale_values()
    call test_precision_edge_cases()
    
    print *, ""
end subroutine test_edge_cases

subroutine test_minimum_scale_values()
    ! Test minimum valid scale values
    type(coordinate_error_t) :: error
    real(real32) :: result, min_scale
    
    min_scale = epsilon(1.0_real32) * 2.0  ! Just above threshold
    result = safe_px_to_dp(100.0_real32, min_scale, error)
    call assert_error_success(error, "Minimum valid scale value")
end subroutine test_minimum_scale_values

subroutine test_maximum_scale_values()
    ! Test maximum reasonable scale values
    type(coordinate_transformer_t) :: transformer
    type(coordinate_error_t) :: error
    
    transformer = create_transformer(10.0_real32, 8000.0_real32, 6000.0_real32)
    call transformer%validate(error)
    call assert_error_success(error, "Maximum reasonable scale values")
    
    transformer = create_transformer(11.0_real32, 8000.0_real32, 6000.0_real32)
    call transformer%validate(error)
    call assert_error_code(error, COORD_ERROR_INVALID_INPUT, "Excessive scale value rejected")
end subroutine test_maximum_scale_values

subroutine test_precision_edge_cases()
    ! Test precision edge cases
    type(coordinate_error_t) :: error
    real(real32) :: result
    
    ! Very small coordinate values
    result = safe_px_to_dp(1e-10_real32, 1.0_real32, error)
    call assert_error_success(error, "Very small coordinate values")
    
    ! Very large coordinate values
    result = safe_px_to_dp(1e6_real32, 1.0_real32, error)
    call assert_error_success(error, "Very large coordinate values")
end subroutine test_precision_edge_cases

! Test utility functions
subroutine assert_true(condition, message)
    logical, intent(in) :: condition
    character(*), intent(in) :: message
    
    total_tests = total_tests + 1
    if (condition) then
        passed_tests = passed_tests + 1
        print *, "  ✓ ", message
    else
        print *, "  ✗ ", message
    end if
end subroutine assert_true

subroutine assert_real_equal(actual, expected, message)
    real(real32), intent(in) :: actual, expected
    character(*), intent(in) :: message
    real(real32), parameter :: tolerance = 1e-6_real32
    
    call assert_true(abs(actual - expected) < tolerance, message)
end subroutine assert_real_equal

subroutine assert_error_success(error, message)
    type(coordinate_error_t), intent(in) :: error
    character(*), intent(in) :: message
    
    call assert_true(error%code == COORD_SUCCESS, message)
end subroutine assert_error_success

subroutine assert_error_code(error, expected_code, message)
    type(coordinate_error_t), intent(in) :: error
    integer, intent(in) :: expected_code
    character(*), intent(in) :: message
    
    call assert_true(error%code == expected_code, message)
end subroutine assert_error_code

subroutine print_test_summary()
    print *, "================================"
    write(*, '(A, I0, A, I0)') "Tests passed: ", passed_tests, " / ", total_tests
    
    if (passed_tests == total_tests) then
        print *, "✅ All coordinate system safety tests PASSED"
        print *, "Issue #62 resolved: No division-by-zero vulnerabilities"
    else
        print *, "❌ Some tests FAILED"
        print *, "Issue #62 requires additional fixes"
    end if
    print *, "================================"
end subroutine print_test_summary

end program test_coordinate_system_safety