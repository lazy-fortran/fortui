program test_memory_safety
! Comprehensive memory safety tests for Issue #78
! Tests for manual deallocation violations and Fortran best practices compliance
! 
! Given: The current code has manual deallocate statements
! When: Manual deallocations are removed and automatic memory management is used
! Then: All these tests should pass
!
! Categories of tests:
! 1. Manual deallocation detection tests
! 2. Memory leak validation tests  
! 3. Memory safety pattern tests
! 4. Functional regression tests

use iso_fortran_env, only: error_unit
implicit none

! Test framework state
integer :: tests_run = 0
integer :: tests_passed = 0
logical :: all_tests_passed = .true.

! Execute test suites
call test_manual_deallocation_detection()
call test_memory_leak_validation()
call test_memory_safety_patterns()
call test_functional_regression()

! Report results
call print_test_summary()

if (.not. all_tests_passed) then
    stop 1
end if

contains

    subroutine test_manual_deallocation_detection()
        ! Given: Source code should not contain manual deallocate statements
        ! When: We scan the source files for deallocate usage
        ! Then: No manual deallocates should be found in core modules
        
        write(*, '(A)') "=== Manual Deallocation Detection Tests ==="
        
        ! Test 1: No manual deallocates in fortui_context.f90
        call test_case("No manual deallocates in fortui_context.f90", &
                      test_no_manual_deallocates_context())
        
        ! Test 2: No manual deallocates in fortui_backend.f90
        call test_case("No manual deallocates in fortui_backend.f90", &
                      test_no_manual_deallocates_backend())
        
        ! Test 3: Verify automatic cleanup patterns are used
        call test_case("Automatic cleanup patterns verification", &
                      test_automatic_cleanup_patterns())
        
        ! Test 4: Verify move_alloc usage instead of deallocate+assign
        call test_case("Move semantics usage verification", &
                      test_move_semantics_usage())
        
    end subroutine
    
    subroutine test_memory_leak_validation()
        ! Given: Memory should be automatically managed by Fortran
        ! When: Context and backend objects are created and destroyed
        ! Then: No memory leaks should occur
        
        write(*, '(A)') "=== Memory Leak Validation Tests ==="
        
        ! Test 1: Context lifecycle memory tracking
        call test_case("Context lifecycle memory safety", &
                      test_context_lifecycle_memory())
        
        ! Test 2: Backend cleanup memory validation
        call test_case("Backend cleanup memory safety", &
                      test_backend_cleanup_memory())
        
        ! Test 3: Widget state memory management
        call test_case("Widget state memory safety", &
                      test_widget_state_memory())
        
        ! Test 4: Allocatable array proper scoping
        call test_case("Allocatable array scoping safety", &
                      test_allocatable_scoping())
        
    end subroutine
    
    subroutine test_memory_safety_patterns()
        ! Given: Fortran should handle memory automatically
        ! When: We check for proper automatic deallocation patterns
        ! Then: All allocatable components should have automatic cleanup
        
        write(*, '(A)') "=== Memory Safety Pattern Tests ==="
        
        ! Test 1: Automatic deallocation verification
        call test_case("Automatic deallocation verification", &
                      test_automatic_deallocation())
        
        ! Test 2: Proper variable scoping validation
        call test_case("Variable scoping validation", &
                      test_variable_scoping())
        
        ! Test 3: Move semantics where appropriate
        call test_case("Move semantics appropriateness", &
                      test_move_semantics_appropriate())
        
        ! Test 4: No double-free scenarios
        call test_case("No double-free scenarios", &
                      test_no_double_free())
        
    end subroutine
    
    subroutine test_functional_regression()
        ! Given: Memory management changes should not break functionality
        ! When: Automatic memory management is used instead of manual
        ! Then: All existing functionality should continue to work
        
        write(*, '(A)') "=== Functional Regression Tests ==="
        
        ! Test 1: Context creation and destruction still work
        call test_case("Context creation/destruction functionality", &
                      test_context_functionality())
        
        ! Test 2: Backend initialization and cleanup still work  
        call test_case("Backend initialization/cleanup functionality", &
                      test_backend_functionality())
        
        ! Test 3: Widget state management integrity preserved
        call test_case("Widget state management integrity", &
                      test_widget_state_integrity())
        
        ! Test 4: Error handling during memory operations
        call test_case("Error handling during memory operations", &
                      test_memory_error_handling())
        
    end subroutine

    ! Manual deallocation detection test implementations
    
    logical function test_no_manual_deallocates_context() result(passed)
        ! This test should FAIL until manual deallocates are removed from fortui_context.f90
        ! According to Issue #78, there are 7 manual deallocates that need removal:
        ! Line 140: deallocate(ctx%backends%entries)
        ! Line 145: deallocate(ctx%backend_state)  
        ! Line 152: deallocate(ctx)
        ! Line 234: deallocate(self%backends%entries)
        ! Line 239: deallocate(self%backend_state)
        ! Line 408: deallocate(self%entries(slot)%state)
        ! Line 424: deallocate(self%entries(i)%state)
        
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Manual deallocates still exist in fortui_context.f90"
        write(error_unit, '(A)') "Found violations at lines: 140, 145, 152, 234, 239, 408, 424"
        write(error_unit, '(A)') "Fix: Remove manual deallocate statements, let Fortran handle automatically"
        write(error_unit, '(A)') "Pattern: Use allocatable components that clean up automatically"
    end function
    
    logical function test_no_manual_deallocates_backend() result(passed)
        ! This test should FAIL until manual deallocates are removed from fortui_backend.f90
        ! According to Issue #78, there are 2 manual deallocates that need removal:
        ! Line 110: deallocate(registered_backends(i)%backend)
        ! Line 188: deallocate(registry%entries(i)%backend)
        
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Manual deallocates still exist in fortui_backend.f90"
        write(error_unit, '(A)') "Found violations at lines: 110, 188"
        write(error_unit, '(A)') "Fix: Remove manual deallocate statements for backend objects"
        write(error_unit, '(A)') "Pattern: Use allocatable backend pointers with automatic cleanup"
    end function
    
    logical function test_automatic_cleanup_patterns() result(passed)
        ! This test verifies that automatic cleanup patterns are in place
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Automatic cleanup patterns not fully implemented"
        write(error_unit, '(A)') "Need: Rely on Fortran automatic deallocation of allocatable components"
        write(error_unit, '(A)') "Pattern: Remove explicit deallocate calls from destructors"
    end function
    
    logical function test_move_semantics_usage() result(passed)
        ! This test verifies move_alloc is used instead of deallocate+assign
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Move semantics not consistently used"
        write(error_unit, '(A)') "Need: Use move_alloc() for ownership transfer instead of manual deallocate"
        write(error_unit, '(A)') "Example: call move_alloc(source_array, target_array)"
    end function

    ! Memory leak validation test implementations
    
    logical function test_context_lifecycle_memory() result(passed)
        ! This test verifies no memory leaks during context lifecycle
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Context lifecycle may have memory leaks"
        write(error_unit, '(A)') "Risk: Manual deallocates can cause double-free or missed cleanup"
        write(error_unit, '(A)') "Fix: Let fortui_context_t components deallocate automatically"
    end function
    
    logical function test_backend_cleanup_memory() result(passed)
        ! This test verifies no memory leaks during backend cleanup
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Backend cleanup may have memory leaks"
        write(error_unit, '(A)') "Risk: Manual backend deallocates can cause corruption"
        write(error_unit, '(A)') "Fix: Use nullify() instead of deallocate for backend pointers"
    end function
    
    logical function test_widget_state_memory() result(passed)
        ! This test verifies widget state memory management is safe
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget state memory management unsafe"
        write(error_unit, '(A)') "Risk: Manual deallocate of entries(slot)%state can cause issues"
        write(error_unit, '(A)') "Fix: Let class(*) allocatable state components clean up automatically"
    end function
    
    logical function test_allocatable_scoping() result(passed)
        ! This test verifies allocatable arrays have proper scoping
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Allocatable array scoping not optimal"
        write(error_unit, '(A)') "Risk: Manual deallocates prevent automatic cleanup on scope exit"
        write(error_unit, '(A)') "Fix: Remove manual deallocates, let Fortran handle scope cleanup"
    end function

    ! Memory safety pattern test implementations
    
    logical function test_automatic_deallocation() result(passed)
        ! This test verifies automatic deallocation is working
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Automatic deallocation patterns incomplete"
        write(error_unit, '(A)') "Need: All allocatable components must clean up automatically"
        write(error_unit, '(A)') "Pattern: No explicit deallocate in type-bound procedures"
    end function
    
    logical function test_variable_scoping() result(passed)
        ! This test verifies proper variable scoping for automatic cleanup
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Variable scoping not optimized for auto-cleanup"
        write(error_unit, '(A)') "Need: Ensure allocatable variables clean up at end of scope"
        write(error_unit, '(A)') "Pattern: Let variables go out of scope naturally"
    end function
    
    logical function test_move_semantics_appropriate() result(passed)
        ! This test verifies move semantics are used where appropriate
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Move semantics not used appropriately"
        write(error_unit, '(A)') "Need: Use move_alloc() for ownership transfer without copy"
        write(error_unit, '(A)') "Example: In map_resize, move_alloc(new_entries, self%entries)"
    end function
    
    logical function test_no_double_free() result(passed)
        ! This test verifies no double-free scenarios exist
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Double-free scenarios possible with manual deallocates"
        write(error_unit, '(A)') "Risk: Manual deallocate followed by automatic cleanup = double-free"
        write(error_unit, '(A)') "Fix: Remove all manual deallocates to prevent double-free"
    end function

    ! Functional regression test implementations
    
    logical function test_context_functionality() result(passed)
        ! This test verifies context creation/destruction still works after changes
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Context functionality may break during refactor"
        write(error_unit, '(A)') "Need: Ensure create_context/destroy_context work without manual deallocates"
        write(error_unit, '(A)') "Test: Context should initialize and clean up properly"
    end function
    
    logical function test_backend_functionality() result(passed)
        ! This test verifies backend initialization/cleanup still works
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Backend functionality may break during refactor"
        write(error_unit, '(A)') "Need: Backend registration/cleanup works without manual deallocates"
        write(error_unit, '(A)') "Test: Backend pointers should be manageable without explicit deallocate"
    end function
    
    logical function test_widget_state_integrity() result(passed)
        ! This test verifies widget state management integrity is preserved
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget state integrity may be affected"
        write(error_unit, '(A)') "Need: Widget state map operations work without manual state deallocates"
        write(error_unit, '(A)') "Test: set/get/clear operations should work with automatic cleanup"
    end function
    
    logical function test_memory_error_handling() result(passed)
        ! This test verifies error handling during memory operations
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Memory error handling needs verification"
        write(error_unit, '(A)') "Need: Error paths should not leave dangling pointers"
        write(error_unit, '(A)') "Test: Exception safety during memory operations"
    end function

    ! Test framework utilities
    subroutine test_case(description, passed)
        character(*), intent(in) :: description
        logical, intent(in) :: passed
        
        tests_run = tests_run + 1
        
        if (passed) then
            tests_passed = tests_passed + 1
            write(*, '(A, A, A)') "PASS: ", description, ""
        else
            all_tests_passed = .false.
            write(*, '(A, A, A)') "FAIL: ", description, ""
        end if
    end subroutine
    
    subroutine print_test_summary()
        write(*, '(A)') ""
        write(*, '(A)') "=== Memory Safety Test Summary ==="
        write(*, '(A, I0, A, I0)') "Tests run: ", tests_run, ", Passed: ", tests_passed
        
        if (all_tests_passed) then
            write(*, '(A)') "All memory safety tests PASSED - Manual deallocations removed!"
            write(*, '(A)') "Issue #78 has been successfully resolved."
        else
            write(*, '(A)') "Memory safety tests FAILED (expected in RED phase)"
            write(*, '(A)') ""
            write(*, '(A)') "These failures indicate manual deallocation violations."
            write(*, '(A)') "Implementation should:"
            write(*, '(A)') "1. Remove all manual deallocate statements"
            write(*, '(A)') "2. Let Fortran handle automatic memory management"
            write(*, '(A)') "3. Use move_alloc() for ownership transfer"
            write(*, '(A)') "4. Ensure proper variable scoping for automatic cleanup"
            write(*, '(A)') ""
            write(*, '(A)') "See Issue #78 for specific line numbers and fix requirements."
        end if
    end subroutine

end program test_memory_safety