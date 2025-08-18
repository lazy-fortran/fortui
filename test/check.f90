program check
! Test runner for fortui build system and core functionality
implicit none

! Given: Test suite execution
! When: Running all available tests
! Then: Execute both Fortran unit tests and shell script tests

call run_fortran_tests()
call run_build_script_tests()

print *, "All test suites completed!"

contains

subroutine run_fortran_tests()
    ! Given: Core Fortran functionality tests needed
    ! When: Testing fortui modules (when implemented)
    ! Then: Validate core library functionality
    
    print *, "=== Fortran Unit Tests ==="
    print *, "Core fortui tests will be added as modules are implemented"
    print *, "Current status: Awaiting fortui_core and fortui_widgets implementation"
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
    
    print *, ""
end subroutine run_build_script_tests

end program check
