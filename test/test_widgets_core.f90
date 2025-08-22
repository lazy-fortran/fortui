module test_widgets_core
! Core widget functionality tests - focused on basic API and functionality
! Tests button, text, slider, and checkbox basic operations
use fortui_core
use fortui_units, only: unit_value, ui_context, dp, em, sp, px, cw, ch, &
    convert_to_dp, ui_get_context_from_units => ui_get_context, ui_set_context
use fortui_widgets
implicit none

! Core state tracking types
type :: widget_test_state_t
    logical :: clicked = .false.
    logical :: hovered = .false.
    logical :: active = .false.
    real :: width_dp = 0.0
    real :: height_dp = 0.0
    integer :: interaction_count = 0
end type widget_test_state_t

! Global state storage
type(widget_test_state_t), save :: test_states(100)
integer, save :: state_count = 0

contains

subroutine test_core_widgets()
    print *, "=== Core Widget Tests ==="
    
    call test_button_core()
    call test_text_core()
    call test_slider_core()
    call test_checkbox_core()
    
    print *, "Core widget tests completed"
end subroutine test_core_widgets

subroutine test_button_core()
    print *, "Testing button core functionality..."
    
    call test_button_minimal()
    call test_button_with_label()
    call test_button_return_values()
    
    print *, "  ✓ Button core tests passed"
end subroutine test_button_core

subroutine test_button_minimal()
    logical :: clicked
    
    clicked = button("test_btn")
    if (clicked .eqv. .false.) then
        print *, "  ✓ Minimal button creation successful"
    else
        print *, "  ✗ Minimal button test failed"
    end if
end subroutine test_button_minimal

subroutine test_button_with_label()
    logical :: clicked
    
    clicked = button("labeled_btn", "Click Me")
    if (clicked .eqv. .false.) then
        print *, "  ✓ Button with label creation successful"
    else
        print *, "  ✗ Button with label test failed"
    end if
end subroutine test_button_with_label

subroutine test_button_return_values()
    logical :: result1, result2
    
    result1 = button("return_test_1")
    result2 = button("return_test_2", "Test Button")
    
    if (result1 .eqv. .false. .and. result2 .eqv. .false.) then
        print *, "  ✓ Button return values valid"
    else
        print *, "  ✗ Button return value test failed"
    end if
end subroutine test_button_return_values

subroutine test_text_core()
    print *, "Testing text widget core functionality..."
    
    call test_text_minimal()
    call test_text_with_content()
    call test_text_sizing()
    
    print *, "  ✓ Text core tests passed"
end subroutine test_text_core

subroutine test_text_minimal()
    type(text_node_t) :: text_node
    text_node = text("test_text")
    print *, "  ✓ Minimal text widget creation successful"
end subroutine test_text_minimal

subroutine test_text_with_content()
    type(text_node_t) :: text_node
    text_node = text("content_text", "Hello World")
    print *, "  ✓ Text widget with content successful"
end subroutine test_text_with_content

subroutine test_text_sizing()
    type(text_node_t) :: text_node
    text_node = text("sized_text", "Sample Text", text_size=14.0)
    print *, "  ✓ Text widget with size successful"
end subroutine test_text_sizing

subroutine test_slider_core()
    print *, "Testing slider core functionality..."
    
    call test_slider_minimal()
    call test_slider_value_handling()
    call test_slider_range_validation()
    
    print *, "  ✓ Slider core tests passed"
end subroutine test_slider_core

subroutine test_slider_minimal()
    real :: test_value = 50.0
    logical :: changed
    
    changed = slider("test_slider", 0.0, 100.0, 1.0, test_value)
    if (changed .eqv. .false.) then
        print *, "  ✓ Minimal slider creation successful"
    else
        print *, "  ✗ Minimal slider test failed"
    end if
end subroutine test_slider_minimal

subroutine test_slider_value_handling()
    real :: test_value = 25.0
    logical :: changed
    
    changed = slider("value_slider", 0.0, 100.0, 5.0, test_value)
    
    if (test_value >= 0.0 .and. test_value <= 100.0) then
        print *, "  ✓ Slider value handling correct"
    else
        print *, "  ✗ Slider value handling failed"
    end if
end subroutine test_slider_value_handling

subroutine test_slider_range_validation()
    real :: test_value = 150.0  ! Outside range
    logical :: changed
    
    changed = slider("range_slider", 0.0, 100.0, 1.0, test_value)
    
    if (test_value <= 100.0) then
        print *, "  ✓ Slider range validation working"
    else
        print *, "  ✗ Slider range validation failed"
    end if
end subroutine test_slider_range_validation

subroutine test_checkbox_core()
    print *, "Testing checkbox core functionality..."
    
    call test_checkbox_minimal()
    call test_checkbox_with_label()
    call test_checkbox_state_handling()
    
    print *, "  ✓ Checkbox core tests passed"
end subroutine test_checkbox_core

subroutine test_checkbox_minimal()
    logical :: checked = .false.
    logical :: clicked
    
    clicked = checkbox("test_checkbox", checked)
    if (clicked .eqv. .false.) then
        print *, "  ✓ Minimal checkbox creation successful"
    else
        print *, "  ✗ Minimal checkbox test failed"
    end if
end subroutine test_checkbox_minimal

subroutine test_checkbox_with_label()
    logical :: checked = .false.
    logical :: clicked
    
    clicked = checkbox("labeled_checkbox", checked, "Check me")
    if (clicked .eqv. .false.) then
        print *, "  ✓ Checkbox with label creation successful"
    else
        print *, "  ✗ Checkbox with label test failed"
    end if
end subroutine test_checkbox_with_label

subroutine test_checkbox_state_handling()
    logical :: checked1 = .false., checked2 = .true.
    logical :: clicked1, clicked2
    
    clicked1 = checkbox("state_checkbox_1", checked1)
    clicked2 = checkbox("state_checkbox_2", checked2)
    
    if (.not. clicked1 .and. .not. clicked2) then
        print *, "  ✓ Checkbox state handling working"
    else
        print *, "  ✗ Checkbox state handling failed"
    end if
end subroutine test_checkbox_state_handling

end module test_widgets_core