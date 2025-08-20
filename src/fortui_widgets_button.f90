module fortui_widgets_button
! Button widget implementation split from main widgets module
use iso_c_binding
use fortui_core, only: ui_element
use fortui_units, only: ui_context, ui_get_context
implicit none
private

public :: button_node_t, button

! Button widget node type
type, extends(ui_element) :: button_node_t
    character(len=256) :: id = ""
    character(len=256) :: label = ""
    real :: width_dp = 0.0
    real :: height_dp = 0.0
    logical :: clicked = .false.
end type button_node_t

contains

logical function button(id, label, width, height) result(clicked)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height
    ! type(button_node_t) :: widget_node  ! Would be used in full implementation
    
    type(ui_context) :: ctx
    real :: button_width_dp, button_height_dp
    character(len=256) :: display_label
    
    ! Get current UI context
    call ui_get_context(ctx)
    
    ! Process label
    if (present(label)) then
        display_label = label
    else
        display_label = id
    end if
    
    ! Calculate dimensions
    if (present(width)) then
        button_width_dp = max(width, 20.0)
    else
        button_width_dp = max(real(len_trim(display_label)) * 8.0 + 16.0, 40.0)
    end if
    
    if (present(height)) then
        button_height_dp = max(height, 16.0)
    else
        button_height_dp = max(ctx%em_dp * 1.8, 20.0)
    end if
    
    ! In full implementation, would create widget node and check interaction
    ! For now, return false (no click)
    clicked = .false.
end function button

end module fortui_widgets_button