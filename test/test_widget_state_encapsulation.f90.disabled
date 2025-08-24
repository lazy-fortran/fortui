program test_widget_state_encapsulation
! Widget state encapsulation tests for Context Object Pattern (Issue #64)
! These tests verify that all widget state is properly encapsulated in contexts
!
! Given: Current widgets use global SAVE variables for state
! When: Context Object Pattern is implemented
! Then: All widget state should be stored in context objects

use iso_fortran_env, only: error_unit
implicit none

! Test framework state
integer :: tests_run = 0
integer :: tests_passed = 0
logical :: all_tests_passed = .true.

! Widget state encapsulation test functions
call test_global_save_variable_elimination()
call test_widget_state_context_storage()
call test_widget_state_isolation_by_context()
call test_widget_state_persistence_in_context()
call test_widget_state_memory_management()

! Report results
call print_test_summary()

if (.not. all_tests_passed) then
    stop 1
end if

contains

    subroutine test_global_save_variable_elimination()
        ! Given: Current code uses global SAVE variables
        ! When: Context pattern is implemented
        ! Then: No global SAVE variables should remain
        
        write(*, '(A)') "=== Global SAVE Variable Elimination Tests ==="
        
        call test_case("fortui_core.f90 ui_state SAVE removed", &
                      test_ui_state_save_removed())
        
        call test_case("fortui_core.f90 tui_state SAVE removed", &
                      test_tui_state_save_removed())
        
        call test_case("fortui_gui.f90 gui_state SAVE removed", &
                      test_gui_state_save_removed())
        
        call test_case("fortui_widgets.f90 viewport states SAVE removed", &
                      test_viewport_states_save_removed())
        
        call test_case("fortui_units.f90 global_context SAVE removed", &
                      test_global_context_save_removed())
        
        call test_case("fortui_platform_measurement.f90 cache SAVE removed", &
                      test_measurement_cache_save_removed())
        
    end subroutine
    
    subroutine test_widget_state_context_storage()
        ! Given: Widget state needs storage
        ! When: Context objects are used
        ! Then: Widget state should be stored in context
        
        write(*, '(A)') "=== Widget State Context Storage Tests ==="
        
        call test_case("Button state stored in context", &
                      test_button_state_in_context())
        
        call test_case("Slider state stored in context", &
                      test_slider_state_in_context())
        
        call test_case("Checkbox state stored in context", &
                      test_checkbox_state_in_context())
        
        call test_case("Viewport state stored in context", &
                      test_viewport_state_in_context())
        
        call test_case("Text widget state stored in context", &
                      test_text_state_in_context())
        
    end subroutine
    
    subroutine test_widget_state_isolation_by_context()
        ! Given: Multiple contexts with same widget IDs
        ! When: Widgets are used in different contexts
        ! Then: Widget state should be isolated per context
        
        write(*, '(A)') "=== Widget State Isolation by Context Tests ==="
        
        call test_case("Button state isolation", &
                      test_button_state_isolation())
        
        call test_case("Slider state isolation", &
                      test_slider_state_isolation())
        
        call test_case("Checkbox state isolation", &
                      test_checkbox_state_isolation())
        
        call test_case("Viewport state isolation", &
                      test_viewport_state_isolation())
        
        call test_case("Cross-widget state isolation", &
                      test_cross_widget_state_isolation())
        
    end subroutine
    
    subroutine test_widget_state_persistence_in_context()
        ! Given: Widget state within a context
        ! When: Multiple frames are processed
        ! Then: Widget state should persist within context lifecycle
        
        write(*, '(A)') "=== Widget State Persistence in Context Tests ==="
        
        call test_case("Button state persistence", &
                      test_button_state_persistence())
        
        call test_case("Slider value persistence", &
                      test_slider_value_persistence())
        
        call test_case("Checkbox state persistence", &
                      test_checkbox_state_persistence())
        
        call test_case("Viewport state persistence", &
                      test_viewport_state_persistence())
        
        call test_case("Widget state cleanup on context destruction", &
                      test_widget_state_cleanup())
        
    end subroutine
    
    subroutine test_widget_state_memory_management()
        ! Given: Widget state stored in context
        ! When: Context manages widget state lifecycle
        ! Then: Memory should be properly managed
        
        write(*, '(A)') "=== Widget State Memory Management Tests ==="
        
        call test_case("Widget state map allocation", &
                      test_widget_state_map_allocation())
        
        call test_case("Widget state entry cleanup", &
                      test_widget_state_entry_cleanup())
        
        call test_case("Memory leak prevention", &
                      test_widget_memory_leak_prevention())
        
        call test_case("Widget state map resizing", &
                      test_widget_state_map_resizing())
        
    end subroutine

    ! Individual test implementations (will fail until state encapsulation implemented)
    
    logical function test_ui_state_save_removed() result(passed)
        ! Test that ui_state SAVE variable is removed from fortui_core.f90
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: ui_state SAVE variable still exists"
        write(error_unit, '(A)') "Current: type(ui_state_t), save :: ui_state (line 43)"
        write(error_unit, '(A)') "Need: Move ui_state to context object"
    end function
    
    logical function test_tui_state_save_removed() result(passed)
        ! Test that tui_state SAVE variable is removed from fortui_core.f90
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: tui_state SAVE variable still exists"
        write(error_unit, '(A)') "Current: type(tui_state_t), save :: tui_state (line 148)"
        write(error_unit, '(A)') "Need: Move tui_state to backend_state in context"
    end function
    
    logical function test_gui_state_save_removed() result(passed)
        ! Test that gui_state SAVE variable is removed from fortui_gui.f90
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: gui_state SAVE variable still exists"
        write(error_unit, '(A)') "Current: type(gui_backend_t), save :: gui_state (line 44)"
        write(error_unit, '(A)') "Need: Move gui_state to backend_state in context"
    end function
    
    logical function test_viewport_states_save_removed() result(passed)
        ! Test that viewport states SAVE array is removed from fortui_widgets.f90
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: viewport states SAVE array still exists"
        write(error_unit, '(A)') "Current: type(viewport_state_t), save :: states(10) (line 114)"
        write(error_unit, '(A)') "Need: Move viewport states to context widget_states map"
    end function
    
    logical function test_global_context_save_removed() result(passed)
        ! Test that global_context SAVE variable is removed from fortui_units.f90
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: global_context SAVE variable still exists"
        write(error_unit, '(A)') "Current: type(ui_context), save :: global_context (line 34)"
        write(error_unit, '(A)') "Need: Move ui_context to context object units field"
    end function
    
    logical function test_measurement_cache_save_removed() result(passed)
        ! Test that measurement cache SAVE variable is removed
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: measurement cache SAVE variable still exists"
        write(error_unit, '(A)') "Current: type(measurement_cache_t), save :: cache (line 31)"
        write(error_unit, '(A)') "Need: Move cache to context or make context-aware"
    end function
    
    logical function test_button_state_in_context() result(passed)
        ! Test that button state is stored in context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Button state not stored in context"
        write(error_unit, '(A)') "Need: button() function uses ctx%widget_states%get(id, 'button')"
    end function
    
    logical function test_slider_state_in_context() result(passed)
        ! Test that slider state is stored in context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Slider state not stored in context"
        write(error_unit, '(A)') "Need: slider() function uses ctx%widget_states%get(id, 'slider')"
    end function
    
    logical function test_checkbox_state_in_context() result(passed)
        ! Test that checkbox state is stored in context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Checkbox state not stored in context"
        write(error_unit, '(A)') "Need: checkbox() function uses ctx%widget_states%get(id, 'checkbox')"
    end function
    
    logical function test_viewport_state_in_context() result(passed)
        ! Test that viewport state is stored in context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Viewport state not stored in context"
        write(error_unit, '(A)') "Need: viewport() function uses ctx%widget_states%get(id, 'viewport')"
    end function
    
    logical function test_text_state_in_context() result(passed)
        ! Test that text widget state is stored in context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Text state not stored in context"
        write(error_unit, '(A)') "Need: text() function uses ctx%widget_states%get(id, 'text')"
    end function
    
    logical function test_button_state_isolation() result(passed)
        ! Test button state isolation between contexts
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Button state not isolated by context"
        write(error_unit, '(A)') "Need: Same button ID in different contexts has independent state"
    end function
    
    logical function test_slider_state_isolation() result(passed)
        ! Test slider state isolation between contexts
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Slider state not isolated by context"
        write(error_unit, '(A)') "Need: Same slider ID in different contexts has independent values"
    end function
    
    logical function test_checkbox_state_isolation() result(passed)
        ! Test checkbox state isolation between contexts
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Checkbox state not isolated by context"
        write(error_unit, '(A)') "Need: Same checkbox ID in different contexts has independent state"
    end function
    
    logical function test_viewport_state_isolation() result(passed)
        ! Test viewport state isolation between contexts
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Viewport state not isolated by context"
        write(error_unit, '(A)') "Need: Same viewport ID in different contexts has independent view state"
    end function
    
    logical function test_cross_widget_state_isolation() result(passed)
        ! Test cross-widget state isolation
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Cross-widget state isolation not implemented"
        write(error_unit, '(A)') "Need: Different widget types with same ID should be independent"
    end function
    
    logical function test_button_state_persistence() result(passed)
        ! Test button state persistence within context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Button state persistence not context-based"
        write(error_unit, '(A)') "Need: Button hover/press state persists across frames in context"
    end function
    
    logical function test_slider_value_persistence() result(passed)
        ! Test slider value persistence within context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Slider value persistence not context-based"
        write(error_unit, '(A)') "Need: Slider drag state persists across frames in context"
    end function
    
    logical function test_checkbox_state_persistence() result(passed)
        ! Test checkbox state persistence within context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Checkbox state persistence not context-based"
        write(error_unit, '(A)') "Need: Checkbox checked state persists across frames in context"
    end function
    
    logical function test_viewport_state_persistence() result(passed)
        ! Test viewport state persistence within context
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Viewport state persistence not context-based"
        write(error_unit, '(A)') "Need: Viewport pan/zoom state persists across frames in context"
    end function
    
    logical function test_widget_state_cleanup() result(passed)
        ! Test widget state cleanup on context destruction
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget state cleanup not implemented"
        write(error_unit, '(A)') "Need: All widget state cleaned up when context destroyed"
    end function
    
    logical function test_widget_state_map_allocation() result(passed)
        ! Test widget state map allocation
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget state map allocation not implemented"
        write(error_unit, '(A)') "Need: Dynamic allocation of widget_state_map in context"
    end function
    
    logical function test_widget_state_entry_cleanup() result(passed)
        ! Test widget state entry cleanup
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget state entry cleanup not implemented"
        write(error_unit, '(A)') "Need: Proper cleanup of individual widget state entries"
    end function
    
    logical function test_widget_memory_leak_prevention() result(passed)
        ! Test widget memory leak prevention
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget memory leak prevention not implemented"
        write(error_unit, '(A)') "Need: No memory leaks from widget state management"
    end function
    
    logical function test_widget_state_map_resizing() result(passed)
        ! Test widget state map resizing
        passed = .false.
        
        write(error_unit, '(A)') "EXPECTED FAILURE: Widget state map resizing not implemented"
        write(error_unit, '(A)') "Need: Dynamic resizing of widget state map as needed"
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
        write(*, '(A)') "=== Widget State Encapsulation Test Summary ==="
        write(*, '(A, I0, A, I0)') "Tests run: ", tests_run, ", Passed: ", tests_passed
        
        if (all_tests_passed) then
            write(*, '(A)') "All widget state tests PASSED"
        else
            write(*, '(A)') "Widget state tests FAILED (expected in RED phase)"
            write(*, '(A)') ""
            write(*, '(A)') "These failures define widget state encapsulation requirements."
            write(*, '(A)') "All global SAVE variables must be eliminated."
        end if
    end subroutine

end program test_widget_state_encapsulation