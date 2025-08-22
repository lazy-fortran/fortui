module fortui_test_utils
! Test utilities for fortui widget testing
! Provides mock functions and simulation utilities for testing widget interactions
use fortui_core
use fortui_widgets
use fortui_context, only: fortui_context_t, get_default_context
implicit none

contains

! Checkbox simulation utilities
subroutine simulate_checkbox_toggle(id)
    character(*), intent(in) :: id
    logical :: checked
    logical :: toggled
    
    ! Toggle the checkbox state
    checked = .false.
    toggled = checkbox(id, checked)
    if (.not. toggled) then
        checked = .true.
        toggled = checkbox(id, checked)
    end if
end subroutine simulate_checkbox_toggle

subroutine simulate_checkbox_click(id, x, y)
    character(*), intent(in) :: id
    real, intent(in) :: x, y
    ! Simulate a click by toggling
    call simulate_checkbox_toggle(id)
end subroutine simulate_checkbox_click

! Button simulation utilities
subroutine simulate_button_click(id)
    character(*), intent(in) :: id
    logical :: clicked
    
    ! Simulate button click
    clicked = button(id)
end subroutine simulate_button_click

subroutine simulate_button_press(id, x, y)
    character(*), intent(in) :: id
    real, intent(in) :: x, y
    ! Simulate button press at location
    call simulate_button_click(id)
end subroutine simulate_button_press

! Slider simulation utilities
subroutine simulate_slider_interaction(id, value)
    character(*), intent(in) :: id
    real, intent(inout) :: value
    logical :: changed
    
    ! Update slider value
    changed = slider(id, 0.0, 100.0, value)
end subroutine simulate_slider_interaction

subroutine simulate_slider_drag(id, new_value)
    character(*), intent(in) :: id
    real, intent(in) :: new_value
    real :: value
    logical :: changed
    
    value = new_value
    changed = slider(id, 0.0, 100.0, value)
end subroutine simulate_slider_drag

! Text widget simulation utilities
subroutine simulate_text_input(id, text_value)
    character(*), intent(in) :: id
    character(*), intent(in) :: text_value
    type(text_node_t) :: node
    
    ! Create text widget with value
    node = text(id, text_value)
end subroutine simulate_text_input

subroutine simulate_key_press(key_code)
    integer, intent(in) :: key_code
    ! Simulate keyboard input (placeholder for actual implementation)
end subroutine simulate_key_press

! Widget state query utilities
function get_button_debug_info(id) result(info)
    character(*), intent(in) :: id
    character(len=256) :: info
    
    info = "Button: " // trim(id) // " (test mode)"
end function get_button_debug_info

function get_text_debug_info(id) result(info)
    character(*), intent(in) :: id
    character(len=256) :: info
    
    info = "Text: " // trim(id) // " (test mode)"
end function get_text_debug_info

function get_checkbox_debug_info(id) result(info)
    character(*), intent(in) :: id
    character(len=256) :: info
    
    info = "Checkbox: " // trim(id) // " (test mode)"
end function get_checkbox_debug_info

function get_slider_debug_info(id) result(info)
    character(*), intent(in) :: id
    character(len=256) :: info
    
    info = "Slider: " // trim(id) // " (test mode)"
end function get_slider_debug_info

! Focus management utilities
subroutine set_button_focus(id)
    character(*), intent(in) :: id
    ! Set focus to button (placeholder)
end subroutine set_button_focus

subroutine set_text_focus(id)
    character(*), intent(in) :: id
    ! Set focus to text widget (placeholder)
end subroutine set_text_focus

subroutine set_checkbox_focus(id)
    character(*), intent(in) :: id
    ! Set focus to checkbox (placeholder)
end subroutine set_checkbox_focus

subroutine set_slider_focus(id)
    character(*), intent(in) :: id
    ! Set focus to slider (placeholder)
end subroutine set_slider_focus

! System reset utilities
subroutine reset_button_system()
    ! Reset button system state (placeholder)
end subroutine reset_button_system

subroutine reset_checkbox_system()
    ! Reset checkbox system state (placeholder)
end subroutine reset_checkbox_system

subroutine reset_slider_system()
    ! Reset slider system state (placeholder)
end subroutine reset_slider_system

subroutine reset_text_system()
    ! Reset text system state (placeholder)
end subroutine reset_text_system

end module fortui_test_utils