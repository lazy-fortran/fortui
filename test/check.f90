program check
use test_abstract_unit_types
use test_conditional_compilation
use test_core_types
use test_layout_constructors
use test_lifecycle_functions
use test_platform_measurement
use test_termbox2_interface
use test_tui_backend
use test_ui_context_integration
use test_units_operators
use test_units_simple
use test_viewport_widget
implicit none

call run_fortran_tests()

print *, "All test suites completed!"

contains

subroutine run_fortran_tests()
    print *, "=== Fortran Unit Tests ==="

    call test_all_core_types()
    call test_all_conditional_compilation()
    call test_all_lifecycle_functions()
    call test_all_unit_operators()
    call test_all_units_simple()
    call test_all_layout_constructors()
    call test_all_tui_backend()
    call test_all_termbox2_interface()
    call test_all_ui_context_integration()
    call test_all_abstract_unit_types()
    call test_all_platform_measurement()
    call test_all_viewport_widget()

    print *, "✓ All Fortran unit tests completed"
    print *, ""
end subroutine run_fortran_tests

end program check
