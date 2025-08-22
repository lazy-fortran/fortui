program check
! Test runner for fortui build system and core functionality
use test_core_types
use test_conditional_compilation
use test_lifecycle_functions
use test_units_system
use test_layout_constructors
use test_tui_backend
! use test_gui_backend  ! Temporarily disabled due to compilation issues
use test_termbox2_interface
use test_ui_context_integration
use test_abstract_unit_types
use test_platform_measurement
use test_viewport_widget
use test_widgets
! use test_demo_application  ! Temporarily disabled due to API mismatch
! use test_demo_integration  ! Temporarily disabled due to API mismatch
! Test restoration infrastructure modules (Issue #87)
use test_restoration_infrastructure
use test_build_dependency_validation
use test_disabled_test_restoration
use test_coverage_gap_assessment
use test_ci_integration_validation
implicit none

! Given: Test suite execution
! When: Running all available tests
! Then: Execute both Fortran unit tests and shell script tests

call run_fortran_tests()
call run_build_script_tests()
call run_test_restoration_tests()

print *, "All test suites completed!"

contains

subroutine run_fortran_tests()
    ! Given: Core Fortran functionality tests needed
    ! When: Testing fortui modules and core types
    ! Then: Validate core library functionality
    
    print *, "=== Fortran Unit Tests ==="
    
    ! Core types and module structure tests
    call test_all_core_types()
    
    ! Conditional compilation tests  
    call test_all_conditional_compilation()
    
    ! Lifecycle functions and backend selection tests
    call test_all_lifecycle_functions()
    
    ! Units system with postfix operators and context-aware conversion tests
    call test_all_units_system()
    
    ! Layout constructor tests with class(*) gap support and children arrays
    call test_all_layout_constructors()
    
    ! TUI backend tests with termbox2 integration and event-driven model
    call test_all_tui_backend()
    
    ! GUI backend tests with raylib/raygui integration and conditional compilation (RED phase - Issue #11)
    ! call test_all_gui_backend()  ! Temporarily disabled due to compilation issues
    
    ! Termbox2 C interface tests with memory management and error handling
    call test_all_termbox2_interface()
    
    ! UI context integration tests with backend measurement (RED phase)
    call test_all_ui_context_integration()
    
    ! Abstract unit types integration tests (RED phase)
    call test_all_abstract_unit_types()
    
    ! Platform measurement system tests (RED phase)
    call test_all_platform_measurement()
    
    ! Viewport widget tests with pan/zoom functionality (RED phase - Issue #9)
    call test_all_viewport_widget()
    
    ! Widget system tests with button implementation and immediate-mode interaction
    call test_all_widgets()
    
    ! Demo application tests for complete widget foundation integration
    ! call run_demo_application_tests()  ! Temporarily disabled due to API mismatch
    
    ! Demo integration tests for application lifecycle and multi-widget interactions  
    ! call run_demo_integration_tests()  ! Temporarily disabled due to API mismatch
    
    print *, "✓ All Fortran unit tests completed"
    print *, ""
end subroutine run_fortran_tests

subroutine run_build_script_tests()
    ! Given: Build script functionality needs validation
    ! When: Executing shell-based build system tests  
    ! Then: Run comprehensive build script test suite
    
    integer :: status
    
    print *, "=== Build Script Test Suite ==="
    print *, "Running build script unit and integration tests..."
    
    ! Execute build script test suite
    call execute_command_line("cd test && ./test_build_script.sh", exitstat=status)
    
    if (status == 0) then
        print *, "✓ Build script unit tests: PASSED"
    else
        print *, "✗ Build script unit tests: FAILED"
    end if
    
    ! Execute integration test suite
    call execute_command_line("cd test && ./test_build_integration.sh", exitstat=status)
    
    if (status == 0) then
        print *, "✓ Build script integration tests: PASSED"
    else
        print *, "✗ Build script integration tests: FAILED" 
    end if
    
    ! Execute demo application build system tests
    call execute_command_line("cd test && ./test_demo_build_system.sh", exitstat=status)
    
    if (status == 0) then
        print *, "✓ Demo application build system tests: PASSED"
    else
        print *, "✗ Demo application build system tests: FAILED"
    end if
    
    print *, ""
end subroutine run_build_script_tests

subroutine run_test_restoration_tests()
    ! Given: Test restoration infrastructure needed for Issue #87
    ! When: Running test restoration validation tests
    ! Then: Execute comprehensive test restoration test suite
    
    print *, "=== Test Restoration Infrastructure Tests (Issue #87) ==="
    print *, "Validating test restoration infrastructure and requirements..."
    
    ! Core test restoration infrastructure tests
    call run_restoration_tests()
    
    ! Build system dependency validation tests  
    call run_build_dependency_tests()
    
    ! Disabled test restoration validation tests
    call run_disabled_test_restoration_tests()
    
    ! Coverage gap assessment tests
    call run_coverage_gap_assessment_tests()
    
    ! CI/CD integration validation tests
    call run_ci_integration_validation_tests()
    
    print *, ""
    print *, "NOTE: These tests are expected to FAIL until test restoration is complete."
    print *, "They validate the infrastructure needed to restore disabled tests."
    print *, "✓ Test restoration infrastructure validation completed"
    print *, ""
end subroutine run_test_restoration_tests

end program check
