module fortui_widgets_button
! Button widget implementation split from main widgets module
use iso_c_binding
use fortui_core, only: ui_element
use fortui_context, only: fortui_context_t, get_default_context
use fortui_units, only: ui_context, ui_get_context
implicit none
private

public :: button_node_t, button, button_with_context, button_state

! Button widget state for context storage
type :: button_state
    logical :: pressed = .false.
    logical :: hover = .false.
    logical :: clicked_this_frame = .false.
    integer :: last_frame_clicked = -1
end type button_state

! Button widget node type
type, extends(ui_element) :: button_node_t
    character(len=256) :: id = ""
    character(len=256) :: label = ""
    real :: width_dp = 0.0
    real :: height_dp = 0.0
    logical :: clicked = .false.
end type button_node_t

! Interface for button overloading
interface button
    module procedure button_default
    module procedure button_with_context
end interface

contains

! Context-aware button implementation (new API)
logical function button_with_context(ctx, id, label, width, height) result(clicked)
    type(fortui_context_t), intent(inout) :: ctx
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height
    
    real :: button_width_dp, button_height_dp
    character(len=256) :: display_label
    integer :: state_index
    type(button_state) :: new_state
    
    ! Validate context
    if (.not. ctx%is_valid()) then
        clicked = .false.
        return
    end if
    
    ! Get or create button state
    state_index = ctx%widget_states%get(id, "button")
    if (state_index == 0) then
        ! Create new button state
        new_state = button_state()  ! Initialize with defaults
        call ctx%widget_states%set(id, "button", new_state)
        state_index = ctx%widget_states%get(id, "button")
    end if
    
    if (state_index == 0) then
        clicked = .false.
        return
    end if
    
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
        button_height_dp = max(ctx%units%em_dp * 1.8, 20.0)
    end if
    
    ! Update state for this frame
    ! Access state through the entries array
    select type(state_obj => ctx%widget_states%entries(state_index)%state)
    type is (button_state)
        if (state_obj%last_frame_clicked == ctx%frame_count) then
            clicked = state_obj%clicked_this_frame
        else
            ! Simulate button interaction for demonstration
            ! In real implementation, would check mouse/keyboard input
            clicked = .false.
            state_obj%clicked_this_frame = clicked
            state_obj%last_frame_clicked = ctx%frame_count
        end if
    class default
        ! Invalid state type
        clicked = .false.
    end select
end function button_with_context

logical function button_default(id, label, width, height) result(clicked)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height
    
    type(fortui_context_t), pointer :: ctx
    
    ! Get default context
    ctx => get_default_context()
    if (associated(ctx)) then
        clicked = button_with_context(ctx, id, label, width, height)
    else
        ! No context available - fall back to simple implementation
        clicked = .false.
    end if
end function button_default

end module fortui_widgets_button