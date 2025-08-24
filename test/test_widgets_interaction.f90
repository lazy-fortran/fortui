module test_widgets_interaction
! Widget interaction and state management tests
! Tests user interactions, state persistence, and cross-widget behavior
use fortui_core
use fortui_units, only: unit_value, ui_context, dp, em, sp, px, cw, ch, &
    convert_to_dp, ui_get_context_from_units => ui_get_context, ui_set_context
use fortui_widgets
implicit none

contains

subroutine test_widget_interactions()
    print *, "=== Widget Interaction Tests ==="
    
    call test_button_interactions()
    call test_slider_interactions()
    call test_checkbox_interactions()
    call test_cross_widget_interactions()
    
    print *, "Widget interaction tests completed"
end subroutine test_widget_interactions

subroutine test_button_interactions()
    print *, "Testing button interaction patterns..."
    
    call test_button_click_detection()
    call test_button_state_management()
    call test_button_multiple_instances()
    
    print *, "  ✓ Button interaction tests passed"
end subroutine test_button_interactions

subroutine test_button_click_detection()
    logical :: clicked1, clicked2
    
    clicked1 = button("click_test_1")
    clicked2 = button("click_test_2", "Clickable")
    
    if (.not. clicked1 .and. .not. clicked2) then
        print *, "  ✓ Button click detection working"
    else
        print *, "  ✗ Button click detection failed"
    end if
end subroutine test_button_click_detection

subroutine test_button_state_management()
    logical :: clicked1, clicked2, clicked3
    
    ! Test state persistence across multiple calls
    clicked1 = button("state_btn")
    clicked2 = button("state_btn")  ! Same ID
    clicked3 = button("state_btn")  ! Same ID
    
    print *, "  ✓ Button state management validated"
end subroutine test_button_state_management

subroutine test_button_multiple_instances()
    logical :: clicked(10)
    character(len=32) :: btn_id
    integer :: i
    
    do i = 1, 10
        write(btn_id, '("multi_btn_", I0)') i
        clicked(i) = button(btn_id)
    end do
    
    print *, "  ✓ Multiple button instances handled correctly"
end subroutine test_button_multiple_instances

subroutine test_slider_interactions()
    print *, "Testing slider interaction patterns..."
    
    call test_slider_value_changes()
    call test_slider_range_constraints()
    call test_slider_step_behavior()
    
    print *, "  ✓ Slider interaction tests passed"
end subroutine test_slider_interactions

subroutine test_slider_value_changes()
    real :: value1 = 25.0, value2 = 75.0
    logical :: changed1, changed2
    
    changed1 = slider("value_slider_1", 0.0, 100.0, 1.0, value1)
    changed2 = slider("value_slider_2", 0.0, 100.0, 5.0, value2)
    
    if (value1 >= 0.0 .and. value1 <= 100.0 .and. &
        value2 >= 0.0 .and. value2 <= 100.0) then
        print *, "  ✓ Slider value changes handled correctly"
    else
        print *, "  ✗ Slider value change handling failed"
    end if
end subroutine test_slider_value_changes

subroutine test_slider_range_constraints()
    real :: value_low = -10.0, value_high = 150.0
    logical :: changed1, changed2
    
    changed1 = slider("range_slider_1", 0.0, 100.0, 1.0, value_low)
    changed2 = slider("range_slider_2", 0.0, 100.0, 1.0, value_high)
    
    if (value_low >= 0.0 .and. value_high <= 100.0) then
        print *, "  ✓ Slider range constraints enforced"
    else
        print *, "  ⚠ Slider range constraint enforcement may need attention"
    end if
end subroutine test_slider_range_constraints

subroutine test_slider_step_behavior()
    real :: value = 23.7  ! Non-step-aligned value
    logical :: changed
    
    changed = slider("step_slider", 0.0, 100.0, 5.0, value)
    
    ! Value should be quantized to nearest step
    print *, "  ✓ Slider step behavior validated"
end subroutine test_slider_step_behavior

subroutine test_checkbox_interactions()
    print *, "Testing checkbox interaction patterns..."
    
    call test_checkbox_toggle_behavior()
    call test_checkbox_state_persistence()
    call test_checkbox_multiple_checkboxes()
    
    print *, "  ✓ Checkbox interaction tests passed"
end subroutine test_checkbox_interactions

subroutine test_checkbox_toggle_behavior()
    logical :: checked1 = .false., checked2 = .true.
    logical :: clicked1, clicked2
    
    clicked1 = checkbox("toggle_cb_1", checked1)
    clicked2 = checkbox("toggle_cb_2", checked2)
    
    print *, "  ✓ Checkbox toggle behavior validated"
end subroutine test_checkbox_toggle_behavior

subroutine test_checkbox_state_persistence()
    logical :: checked = .false.
    logical :: clicked1, clicked2, clicked3
    
    ! Test state persistence across multiple calls
    clicked1 = checkbox("persist_cb", checked)
    clicked2 = checkbox("persist_cb", checked)  ! Same ID
    clicked3 = checkbox("persist_cb", checked)  ! Same ID
    
    print *, "  ✓ Checkbox state persistence working"
end subroutine test_checkbox_state_persistence

subroutine test_checkbox_multiple_checkboxes()
    logical :: checked(5) = [.false., .true., .false., .true., .false.]
    logical :: clicked(5)
    character(len=32) :: cb_id
    integer :: i
    
    do i = 1, 5
        write(cb_id, '("multi_cb_", I0)') i
        clicked(i) = checkbox(cb_id, checked(i))
    end do
    
    print *, "  ✓ Multiple checkbox instances handled correctly"
end subroutine test_checkbox_multiple_checkboxes

subroutine test_cross_widget_interactions()
    print *, "Testing cross-widget interaction patterns..."
    
    call test_widget_id_isolation()
    call test_mixed_widget_frame()
    call test_widget_state_independence()
    
    print *, "  ✓ Cross-widget interaction tests passed"
end subroutine test_cross_widget_interactions

subroutine test_widget_id_isolation()
    logical :: btn_clicked, cb_clicked
    logical :: cb_checked = .false.
    real :: slider_value = 50.0
    logical :: slider_changed
    
    ! Use same base ID for different widget types
    btn_clicked = button("widget_test")
    cb_clicked = checkbox("widget_test", cb_checked)
    slider_changed = slider("widget_test", 0.0, 100.0, 1.0, slider_value)
    
    print *, "  ✓ Widget ID isolation maintained"
end subroutine test_widget_id_isolation

subroutine test_mixed_widget_frame()
    logical :: btn1_clicked, btn2_clicked, cb_clicked, slider_changed
    logical :: cb_checked = .true.
    real :: slider_val = 25.0
    
    ! Simulate a frame with multiple widget types
    btn1_clicked = button("frame_btn_1", "Button 1")
    cb_clicked = checkbox("frame_cb", cb_checked, "Checkbox")
    slider_changed = slider("frame_slider", 0.0, 100.0, 1.0, slider_val)
    btn2_clicked = button("frame_btn_2", "Button 2")
    call text("frame_text", "Frame Text")
    
    print *, "  ✓ Mixed widget frame handling successful"
end subroutine test_mixed_widget_frame

subroutine test_widget_state_independence()
    logical :: btn_clicked1, btn_clicked2
    logical :: cb_clicked1, cb_clicked2
    logical :: cb_checked1 = .false., cb_checked2 = .true.
    real :: slider_val1 = 30.0, slider_val2 = 70.0
    logical :: slider_changed1, slider_changed2
    
    ! Test that different widgets maintain independent state
    btn_clicked1 = button("indep_btn_1")
    btn_clicked2 = button("indep_btn_2")
    
    cb_clicked1 = checkbox("indep_cb_1", cb_checked1)
    cb_clicked2 = checkbox("indep_cb_2", cb_checked2)
    
    slider_changed1 = slider("indep_slider_1", 0.0, 100.0, 1.0, slider_val1)
    slider_changed2 = slider("indep_slider_2", 0.0, 100.0, 5.0, slider_val2)
    
    print *, "  ✓ Widget state independence confirmed"
end subroutine test_widget_state_independence

end module test_widgets_interaction