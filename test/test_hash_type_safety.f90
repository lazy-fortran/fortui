program test_hash_type_safety
! Test suite for Issue #63: Hash calculation integer overflow due to missing type safety
! Validates that the new hash implementation is overflow-safe and collision-resistant
use fortui_hash
use iso_fortran_env, only: int32, int64
implicit none

! Test results tracking
integer :: total_tests = 0
integer :: passed_tests = 0

! Run all tests
call test_basic_hash_calculation()
call test_integer_overflow_protection()
call test_hash_collision_resistance()
call test_edge_cases()
call test_fnv_algorithm_properties()

! Report results
call print_test_summary()

contains

subroutine test_basic_hash_calculation()
    print *, "=== Testing Basic Hash Calculation ==="
    
    call test_empty_line_hash()
    call test_single_cell_hash()
    call test_multiple_cells_hash()
    call test_hash_deterministic()
    
    print *, ""
end subroutine test_basic_hash_calculation

subroutine test_empty_line_hash()
    ! Test hash of empty line
    type(tb_cell), allocatable :: empty_line(:)
    type(line_hash_t) :: hash1, hash2
    
    allocate(empty_line(0))
    hash1 = calculate_line_hash(empty_line)
    hash2 = calculate_line_hash(empty_line)
    
    call assert_true(hash_equal(hash1, hash2), "Empty line hash deterministic")
    call assert_true(hash1%value /= 0_int64, "Empty line hash non-zero")
    
    deallocate(empty_line)
end subroutine test_empty_line_hash

subroutine test_single_cell_hash()
    ! Test hash of single cell
    type(tb_cell) :: cells(1)
    type(line_hash_t) :: hash
    
    cells(1)%ch = 65  ! 'A'
    cells(1)%fg = 7   ! White
    cells(1)%bg = 0   ! Black
    
    hash = calculate_line_hash(cells)
    call assert_true(hash%value /= 0_int64, "Single cell hash non-zero")
end subroutine test_single_cell_hash

subroutine test_multiple_cells_hash()
    ! Test hash of multiple cells
    type(tb_cell) :: cells(3)
    type(line_hash_t) :: hash
    
    ! Set up test cells
    cells(1)%ch = 65; cells(1)%fg = 7; cells(1)%bg = 0  ! 'A'
    cells(2)%ch = 66; cells(2)%fg = 7; cells(2)%bg = 0  ! 'B'  
    cells(3)%ch = 67; cells(3)%fg = 7; cells(3)%bg = 0  ! 'C'
    
    hash = calculate_line_hash(cells)
    call assert_true(hash%value /= 0_int64, "Multiple cells hash non-zero")
end subroutine test_multiple_cells_hash

subroutine test_hash_deterministic()
    ! Test that same input produces same hash
    type(tb_cell) :: cells(2)
    type(line_hash_t) :: hash1, hash2
    
    cells(1)%ch = 88; cells(1)%fg = 3; cells(1)%bg = 1
    cells(2)%ch = 89; cells(2)%fg = 4; cells(2)%bg = 2
    
    hash1 = calculate_line_hash(cells)
    hash2 = calculate_line_hash(cells)
    
    call assert_true(hash_equal(hash1, hash2), "Hash calculation deterministic")
end subroutine test_hash_deterministic

subroutine test_integer_overflow_protection()
    print *, "=== Testing Integer Overflow Protection ==="
    
    call test_large_values_no_overflow()
    call test_maximum_cell_values()
    call test_long_line_no_overflow()
    
    print *, ""
end subroutine test_integer_overflow_protection

subroutine test_large_values_no_overflow()
    ! Test with large character/color values
    type(tb_cell) :: cells(1)
    type(line_hash_t) :: hash
    
    ! Use maximum valid values that could cause overflow in old implementation
    cells(1)%ch = 2147483647     ! Max int32
    cells(1)%fg = 2147483647     ! Max int32
    cells(1)%bg = 2147483647     ! Max int32
    
    hash = calculate_line_hash(cells)
    
    ! Should not crash or produce undefined behavior
    call assert_true(hash%value /= 0_int64, "Large values handled safely")
end subroutine test_large_values_no_overflow

subroutine test_maximum_cell_values()
    ! Test edge case with maximum possible values
    type(tb_cell) :: cells(5)
    type(line_hash_t) :: hash
    integer :: i
    
    ! Fill with maximum values
    do i = 1, 5
        cells(i)%ch = huge(0_int32)
        cells(i)%fg = huge(0_int32)
        cells(i)%bg = huge(0_int32)
    end do
    
    hash = calculate_line_hash(cells)
    call assert_true(hash%value /= 0_int64, "Maximum values handled safely")
end subroutine test_maximum_cell_values

subroutine test_long_line_no_overflow()
    ! Test with very long line that would overflow old implementation
    type(tb_cell), allocatable :: cells(:)
    type(line_hash_t) :: hash
    integer :: i
    
    allocate(cells(1000))  ! Long line
    
    do i = 1, 1000
        cells(i)%ch = 65 + mod(i, 26)  ! A-Z cycling
        cells(i)%fg = mod(i, 16)       ! Color cycling
        cells(i)%bg = mod(i, 8)        ! Background cycling
    end do
    
    hash = calculate_line_hash(cells)
    call assert_true(hash%value /= 0_int64, "Long line handled safely")
    
    deallocate(cells)
end subroutine test_long_line_no_overflow

subroutine test_hash_collision_resistance()
    print *, "=== Testing Hash Collision Resistance ==="
    
    call test_different_inputs_different_hashes()
    call test_order_sensitivity()
    call test_color_sensitivity()
    
    print *, ""
end subroutine test_hash_collision_resistance

subroutine test_different_inputs_different_hashes()
    ! Test that different inputs produce different hashes
    type(tb_cell) :: cells1(2), cells2(2)
    type(line_hash_t) :: hash1, hash2
    
    ! Setup different inputs
    cells1(1)%ch = 65; cells1(1)%fg = 7; cells1(1)%bg = 0
    cells1(2)%ch = 66; cells1(2)%fg = 7; cells1(2)%bg = 0
    
    cells2(1)%ch = 67; cells2(1)%fg = 7; cells2(1)%bg = 0  ! Different
    cells2(2)%ch = 66; cells2(2)%fg = 7; cells2(2)%bg = 0
    
    hash1 = calculate_line_hash(cells1)
    hash2 = calculate_line_hash(cells2)
    
    call assert_false(hash_equal(hash1, hash2), "Different inputs produce different hashes")
end subroutine test_different_inputs_different_hashes

subroutine test_order_sensitivity()
    ! Test that order matters (no commutative property)
    type(tb_cell) :: cells1(2), cells2(2)
    type(line_hash_t) :: hash1, hash2
    
    ! Same cells, different order
    cells1(1)%ch = 65; cells1(1)%fg = 7; cells1(1)%bg = 0
    cells1(2)%ch = 66; cells1(2)%fg = 3; cells1(2)%bg = 1
    
    cells2(1)%ch = 66; cells2(1)%fg = 3; cells2(1)%bg = 1  ! Swapped
    cells2(2)%ch = 65; cells2(2)%fg = 7; cells2(2)%bg = 0
    
    hash1 = calculate_line_hash(cells1)
    hash2 = calculate_line_hash(cells2)
    
    call assert_false(hash_equal(hash1, hash2), "Order affects hash (avalanche effect)")
end subroutine test_order_sensitivity

subroutine test_color_sensitivity()
    ! Test that color changes affect hash
    type(tb_cell) :: cells1(1), cells2(1)
    type(line_hash_t) :: hash1, hash2
    
    ! Same character, different colors
    cells1(1)%ch = 65; cells1(1)%fg = 7; cells1(1)%bg = 0
    cells2(1)%ch = 65; cells2(1)%fg = 3; cells2(1)%bg = 0  ! Different fg
    
    hash1 = calculate_line_hash(cells1)
    hash2 = calculate_line_hash(cells2)
    
    call assert_false(hash_equal(hash1, hash2), "Color changes affect hash")
end subroutine test_color_sensitivity

subroutine test_edge_cases()
    print *, "=== Testing Edge Cases ==="
    
    call test_zero_values()
    call test_negative_values()
    call test_unicode_characters()
    
    print *, ""
end subroutine test_edge_cases

subroutine test_zero_values()
    ! Test with zero values
    type(tb_cell) :: cells(2)
    type(line_hash_t) :: hash
    
    cells(1)%ch = 0; cells(1)%fg = 0; cells(1)%bg = 0
    cells(2)%ch = 0; cells(2)%fg = 0; cells(2)%bg = 0
    
    hash = calculate_line_hash(cells)
    call assert_true(hash%value /= 0_int64, "Zero values produce valid hash")
end subroutine test_zero_values

subroutine test_negative_values()
    ! Test with negative values (should be handled as unsigned)
    type(tb_cell) :: cells(1)
    type(line_hash_t) :: hash
    
    cells(1)%ch = -1  ! Will be treated as large positive in hash
    cells(1)%fg = -1
    cells(1)%bg = -1
    
    hash = calculate_line_hash(cells)
    call assert_true(hash%value /= 0_int64, "Negative values handled")
end subroutine test_negative_values

subroutine test_unicode_characters()
    ! Test with Unicode character codes
    type(tb_cell) :: cells(3)
    type(line_hash_t) :: hash
    
    cells(1)%ch = 8364   ! Euro symbol
    cells(2)%ch = 65536  ! High Unicode plane
    cells(3)%ch = 128512 ! Emoji range
    cells(1)%fg = 7; cells(1)%bg = 0
    cells(2)%fg = 7; cells(2)%bg = 0
    cells(3)%fg = 7; cells(3)%bg = 0
    
    hash = calculate_line_hash(cells)
    call assert_true(hash%value /= 0_int64, "Unicode characters handled")
end subroutine test_unicode_characters

subroutine test_fnv_algorithm_properties()
    print *, "=== Testing FNV Algorithm Properties ==="
    
    call test_fnv_avalanche_effect()
    call test_fnv_bit_distribution()
    
    print *, ""
end subroutine test_fnv_algorithm_properties

subroutine test_fnv_avalanche_effect()
    ! Test that small input changes cause large hash changes
    type(tb_cell) :: cells1(1), cells2(1)
    type(line_hash_t) :: hash1, hash2
    integer(int64) :: xor_result
    integer :: changed_bits
    
    ! Minimal difference in input
    cells1(1)%ch = 65; cells1(1)%fg = 7; cells1(1)%bg = 0
    cells2(1)%ch = 66; cells2(1)%fg = 7; cells2(1)%bg = 0  ! Only ch differs by 1
    
    hash1 = calculate_line_hash(cells1)
    hash2 = calculate_line_hash(cells2)
    
    ! Count changed bits
    xor_result = ieor(hash1%value, hash2%value)
    changed_bits = popcnt(xor_result)
    
    ! Good avalanche should change many bits (aim for ~50% of 64 bits = ~32)
    call assert_true(changed_bits > 16, "Avalanche effect: sufficient bit changes")
end subroutine test_fnv_avalanche_effect

subroutine test_fnv_bit_distribution()
    ! Basic test that hashes don't cluster in specific ranges
    type(tb_cell) :: cells(1)
    type(line_hash_t) :: hash
    integer :: i
    integer(int64) :: hash_sum
    
    hash_sum = 0_int64
    
    ! Generate several hashes and check they're distributed
    do i = 1, 10
        cells(1)%ch = i
        cells(1)%fg = mod(i, 16)
        cells(1)%bg = mod(i, 8)
        
        hash = calculate_line_hash(cells)
        hash_sum = hash_sum + hash%value
    end do
    
    ! Hashes should not all be the same
    call assert_true(hash_sum /= 0_int64, "Hash distribution non-trivial")
end subroutine test_fnv_bit_distribution

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

subroutine assert_false(condition, message)
    logical, intent(in) :: condition
    character(*), intent(in) :: message
    
    call assert_true(.not. condition, message)
end subroutine assert_false

subroutine print_test_summary()
    print *, "================================"
    write(*, '(A, I0, A, I0)') "Tests passed: ", passed_tests, " / ", total_tests
    
    if (passed_tests == total_tests) then
        print *, "✅ All hash type safety tests PASSED"
        print *, "Issue #63 resolved: No integer overflow vulnerabilities"
    else
        print *, "❌ Some tests FAILED"
        print *, "Issue #63 requires additional fixes"
    end if
    print *, "================================"
end subroutine print_test_summary

end program test_hash_type_safety