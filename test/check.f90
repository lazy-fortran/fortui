program check
use test_core_types
use test_lifecycle_functions
use test_units_operators
use test_units_simple
use test_widgets_core
use test_layout
implicit none

call run_fortran_tests()

print *, "All test suites completed!"

contains

subroutine run_fortran_tests()
    print *, "=== Fortran Unit Tests ==="

    call test_all_core_types()
    call test_all_lifecycle_functions()
    call test_all_unit_operators()
    call test_all_units_simple()
    call test_core_widgets()
    call test_all_layout()

    print *, "✓ All Fortran unit tests completed"
    print *, ""
end subroutine run_fortran_tests

end program check
