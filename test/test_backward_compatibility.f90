program test_backward_compatibility
! Backward compatibility tests for Context Object Pattern (Issue #64)
! These tests verify that existing code continues to work unchanged
!
! Given: Existing code uses current API without contexts
! When: Context Object Pattern is implemented
! Then: All existing code should continue to work unchanged

use iso_fortran_env, only: error_unit
implicit none

! Test framework state
integer :: tests_run = 0
integer :: tests_passed = 0
logical :: all_tests_passed = .true.

! Backward compatibility test functions
call test_existing_api_unchanged()
call test_default_context_behavior()
call test_existing_examples_work()
call test_thread_local_default_context()
call test_migration_path_available()

! Report results
call print_test_summary()

if (.not. all_tests_passed) then
    stop 1
end if

contains

    subroutine test_existing_api_unchanged()
        ! Given: Existing public API functions
        ! When: Context pattern is implemented
        ! Then: All existing functions should work unchanged
        
        write(*, '(A)') "=== Existing API Unchanged Tests ==="
        
        call test_case("ui_init signature unchanged", &
                      test_ui_init_signature_unchanged())
        
        call test_case("ui_shutdown signature unchanged", &
                      test_ui_shutdown_signature_unchanged())
        
        call test_case("ui_frame_begin signature unchanged", &
                      test_ui_frame_begin_signature_unchanged())
        
        call test_case("ui_present signature unchanged", &
                      test_ui_present_signature_unchanged())
        
        call test_case("Widget function signatures unchanged", &
                      test_widget_signatures_unchanged())
        
    end subroutine
    
    subroutine test_default_context_behavior()
        ! Given: Code not using explicit contexts
        ! When: Default context is used
        ! Then: Behavior should be identical to current implementation
        
        write(*, '(A)') "=== Default Context Behavior Tests ==="
        
        call test_case("Default context auto-creation", &
                      test_default_context_auto_creation())
        
        call test_case("Default context state management", &
                      test_default_context_state_management())
        
        call test_case("Default context cleanup", &
                      test_default_context_cleanup())
        
        call test_case("Default context thread safety", &
                      test_default_context_thread_safety())
        
    end subroutine
    
    subroutine test_existing_examples_work()
        ! Given: Existing example programs
        ! When: Context pattern is implemented
        ! Then: All examples should compile and run unchanged
        
        write(*, '(A)') "=== Existing Examples Work Tests ==="
        
        call test_case("Simple test example works", &
                      test_simple_test_example())
        
        call test_case("Button test example works", &
                      test_button_test_example())
        
        call test_case("Widget examples work", &
                      test_widget_examples())
        
        call test_case("Demo application works", &
                      test_demo_application())
        
    end subroutine
    
    subroutine test_thread_local_default_context()
        ! Given: Thread-local default context implementation
        ! When: Multiple threads use default context
        ! Then: Each thread should have independent default context
        
        write(*, '(A)') "=== Thread-Local Default Context Tests ==="
        
        call test_case("Thread-local default context isolation", &
                      test_thread_local_isolation())
        
        call test_case("Thread-local context initialization", &
                      test_thread_local_initialization())
        
        call test_case("Thread-local context cleanup", &
                      test_thread_local_cleanup())
        
    end subroutine
    
    subroutine test_migration_path_available()
        ! Given: Need for gradual migration to explicit contexts
        ! When: Migration path is provided
        ! Then: Code can be gradually migrated without breaking changes
        
        write(*, '(A)') "=== Migration Path Available Tests ==="
        
        call test_case("Context-aware function overloads available", &
                      test_context_aware_overloads())
        
        call test_case("Gradual migration possible", &
                      test_gradual_migration_possible())
        
        call test_case("Mixed API usage works", &
                      test_mixed_api_usage())
        
        call test_case("Deprecation warnings for future removal", &
                      test_deprecation_warnings())
        
    end subroutine

    ! Individual test implementations (will fail until backward compatibility implemented)
    
    logical function test_ui_init_signature_unchanged() result(passed)
        ! Test that ui_init signature remains unchanged
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: ui_init signature backward compatibility not implemented"
        write(error_unit, '(A)') "Need: call ui_init('tui', 80.0, 24.0, 'Title') still works"
        write(error_unit, '(A)') "Implementation: ui_init should use default context internally"
    end function
    
    logical function test_ui_shutdown_signature_unchanged() result(passed)
        ! Test that ui_shutdown signature remains unchanged
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: ui_shutdown signature backward compatibility not implemented"
        write(error_unit, '(A)') "Need: call ui_shutdown() still works"
        write(error_unit, '(A)') "Implementation: ui_shutdown should operate on default context"
    end function
    
    logical function test_ui_frame_begin_signature_unchanged() result(passed)
        ! Test that ui_frame_begin signature remains unchanged
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: ui_frame_begin signature backward compatibility not implemented"
        write(error_unit, '(A)') "Need: call ui_frame_begin() still works"
        write(error_unit, '(A)') "Implementation: ui_frame_begin should operate on default context"
    end function
    
    logical function test_ui_present_signature_unchanged() result(passed)
        ! Test that ui_present signature remains unchanged
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: ui_present signature backward compatibility not implemented"
        write(error_unit, '(A)') "Need: call ui_present() still works"
        write(error_unit, '(A)') "Implementation: ui_present should operate on default context"
    end function
    
    logical function test_widget_signatures_unchanged() result(passed)
        ! Test that widget function signatures remain unchanged
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget signatures backward compatibility not implemented"
        write(error_unit, '(A)') "Need: button('id', 'label'), slider('id', val, min, max) still work"
        write(error_unit, '(A)') "Implementation: Widget functions should use default context"
    end function
    
    logical function test_default_context_auto_creation() result(passed)
        ! Test default context auto-creation
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Default context auto-creation not implemented"
        write(error_unit, '(A)') "Need: Default context automatically created on first use"
        write(error_unit, '(A)') "Implementation: get_default_context() creates if null"
    end function
    
    logical function test_default_context_state_management() result(passed)
        ! Test default context state management
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Default context state management not implemented"
        write(error_unit, '(A)') "Need: Default context manages state same as current global state"
        write(error_unit, '(A)') "Implementation: Default context stores what used to be global"
    end function
    
    logical function test_default_context_cleanup() result(passed)
        ! Test default context cleanup
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Default context cleanup not implemented"
        write(error_unit, '(A)') "Need: Default context cleaned up on program termination"
        write(error_unit, '(A)') "Implementation: Automatic cleanup or explicit cleanup call"
    end function
    
    logical function test_default_context_thread_safety() result(passed)
        ! Test default context thread safety
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Default context thread safety not implemented"
        write(error_unit, '(A)') "Need: Thread-local default context for thread safety"
        write(error_unit, '(A)') "Implementation: !$OMP THREADPRIVATE(default_context)"
    end function
    
    logical function test_simple_test_example() result(passed)
        ! Test that simple test example still works
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Simple test example compatibility not verified"
        write(error_unit, '(A)') "Need: example/simple_test.f90 compiles and runs unchanged"
        write(error_unit, '(A)') "Verification: Compile and run existing example"
    end function
    
    logical function test_button_test_example() result(passed)
        ! Test that button test example still works
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Button test example compatibility not verified"
        write(error_unit, '(A)') "Need: example/button_test.f90 compiles and runs unchanged"
        write(error_unit, '(A)') "Verification: Compile and run existing button example"
    end function
    
    logical function test_widget_examples() result(passed)
        ! Test that widget examples still work
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget examples compatibility not verified"
        write(error_unit, '(A)') "Need: All example/*.f90 files compile and run unchanged"
        write(error_unit, '(A)') "Verification: Compile and run all existing widget examples"
    end function
    
    logical function test_demo_application() result(passed)
        ! Test that demo application still works
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Demo application compatibility not verified"
        write(error_unit, '(A)') "Need: Main demo application compiles and runs unchanged"
        write(error_unit, '(A)') "Verification: Full demo functionality preserved"
    end function
    
    logical function test_thread_local_isolation() result(passed)
        ! Test thread-local default context isolation
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Thread-local isolation not implemented"
        write(error_unit, '(A)') "Need: Each thread has independent default context"
        write(error_unit, '(A)') "Implementation: THREADPRIVATE default context pointer"
    end function
    
    logical function test_thread_local_initialization() result(passed)
        ! Test thread-local context initialization
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Thread-local initialization not implemented"
        write(error_unit, '(A)') "Need: Each thread can initialize independent default context"
        write(error_unit, '(A)') "Implementation: Per-thread context creation"
    end function
    
    logical function test_thread_local_cleanup() result(passed)
        ! Test thread-local context cleanup
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Thread-local cleanup not implemented"
        write(error_unit, '(A)') "Need: Thread-local contexts cleaned up on thread exit"
        write(error_unit, '(A)') "Implementation: Thread cleanup handlers"
    end function
    
    logical function test_context_aware_overloads() result(passed)
        ! Test context-aware function overloads
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Context-aware overloads not implemented"
        write(error_unit, '(A)') "Need: ui_init_with_context(), button_with_context() available"
        write(error_unit, '(A)') "Implementation: Function overloads with optional context parameter"
    end function
    
    logical function test_gradual_migration_possible() result(passed)
        ! Test gradual migration possibility
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Gradual migration not supported"
        write(error_unit, '(A)') "Need: Can migrate function by function to explicit context"
        write(error_unit, '(A)') "Implementation: Mixed API usage supported"
    end function
    
    logical function test_mixed_api_usage() result(passed)
        ! Test mixed API usage
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Mixed API usage not supported"
        write(error_unit, '(A)') "Need: Can use both old and new API in same program"
        write(error_unit, '(A)') "Implementation: Compatible function signatures"
    end function
    
    logical function test_deprecation_warnings() result(passed)
        ! Test deprecation warnings
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Deprecation warnings not implemented"
        write(error_unit, '(A)') "Need: Warnings for future removal of implicit context functions"
        write(error_unit, '(A)') "Implementation: Compiler warnings or runtime messages"
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
        write(*, '(A)') "=== Backward Compatibility Test Summary ==="
        write(*, '(A, I0, A, I0)') "Tests run: ", tests_run, ", Passed: ", tests_passed
        
        if (all_tests_passed) then
            write(*, '(A)') "All backward compatibility tests PASSED"
        else
            write(*, '(A)') "Backward compatibility tests FAILED (expected in RED phase)"
            write(*, '(A)') ""
            write(*, '(A)') "These failures define backward compatibility requirements."
            write(*, '(A)') "Context Object Pattern must preserve existing API behavior."
        end if
    end subroutine

end program test_backward_compatibility