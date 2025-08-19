module fortui_widgets
! Widget system for fortui - immediate-mode UI with ID-based state management
! Implements button widget with unified class(*) interface and cross-backend support
use iso_c_binding
use fortui_core, only: ui_element, node, view
use fortui_units, only: ui_context, convert_to_dp, ui_get_context
implicit none
private

! Public widget functions
public :: button

! Testing helper functions (for test suite only)
public :: simulate_button_click, simulate_key_press, set_button_focus
public :: get_button_debug_info, reset_button_system

! Internal state management types
type :: button_state_t
    logical :: clicked = .false.
    logical :: hovered = .false.
    logical :: active = .false.
    logical :: focused = .false.
    real :: width_dp = 0.0
    real :: height_dp = 0.0
    real :: x_dp = 0.0
    real :: y_dp = 0.0
    integer :: click_count = 0
    integer :: last_frame = 0
    character(len=256) :: id = ""
end type button_state_t

! Global state storage for all buttons
integer, parameter :: MAX_BUTTONS = 1000
type(button_state_t), save :: button_states(MAX_BUTTONS)
integer, save :: button_count = 0
integer, save :: current_frame = 0

! Mouse and keyboard state tracking
type :: input_state_t
    real :: mouse_x = 0.0
    real :: mouse_y = 0.0
    logical :: mouse_clicked = .false.
    logical :: enter_pressed = .false.
    logical :: space_pressed = .false.
    character(len=256) :: focused_button_id = ""
end type input_state_t

type(input_state_t), save :: input_state

contains

logical function button(id, label, width, height) result(clicked)
    ! Immediate-mode button widget with unified class(*) interface
    ! Returns true only on the frame when button is clicked
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    class(*), intent(in), optional :: width
    class(*), intent(in), optional :: height
    
    integer :: state_index
    character(len=256) :: display_label
    real :: button_width_dp, button_height_dp
    type(ui_context) :: ctx
    
    ! Increment frame counter for immediate-mode behavior
    current_frame = current_frame + 1
    
    ! Validate ID parameter
    if (len_trim(id) == 0) then
        print *, "button: Warning - Empty button ID provided, using fallback"
        clicked = .false.
        return
    end if
    
    ! Get or create button state
    state_index = find_or_create_button_state(id)
    if (state_index <= 0) then
        clicked = .false.
        return
    end if
    
    ! Process label parameter (use id as default)
    if (present(label)) then
        display_label = label
    else
        display_label = id
    end if
    
    ! Get current UI context
    call ui_get_context(ctx)
    
    ! Calculate dimensions - either explicit or auto-sized
    if (present(width)) then
        button_width_dp = convert_to_dp(width, ctx)
        ! Apply minimum width constraint for clickability
        button_width_dp = max(button_width_dp, 20.0)
    else
        ! Auto-size width based on label content
        button_width_dp = calculate_auto_width(display_label, ctx)
    end if
    
    if (present(height)) then
        button_height_dp = convert_to_dp(height, ctx)
        ! Apply minimum height constraint for clickability
        button_height_dp = max(button_height_dp, 16.0)
    else
        ! Auto-size height based on context
        button_height_dp = calculate_auto_height(display_label, ctx)
    end if
    
    ! Update button state with current dimensions
    button_states(state_index)%width_dp = button_width_dp
    button_states(state_index)%height_dp = button_height_dp
    button_states(state_index)%last_frame = current_frame
    
    ! Process input and determine click state
    clicked = process_button_interaction(state_index, display_label)
    
    ! Render button (would be handled by presentation system in full implementation)
    call render_button_placeholder(state_index, display_label)
end function button

integer function find_or_create_button_state(id) result(index)
    ! Find existing button state or create new one
    character(*), intent(in) :: id
    integer :: i
    
    ! Search for existing state
    do i = 1, button_count
        if (trim(button_states(i)%id) == trim(id)) then
            index = i
            return
        end if
    end do
    
    ! Create new state if space available
    if (button_count < MAX_BUTTONS) then
        button_count = button_count + 1
        index = button_count
        
        ! Initialize new button state
        button_states(index) = button_state_t()
        button_states(index)%id = id
        button_states(index)%last_frame = current_frame
    else
        ! Handle overflow - reuse oldest slot
        print *, "button: Warning - Maximum button limit reached, reusing slot"
        index = MAX_BUTTONS
        button_states(index) = button_state_t()
        button_states(index)%id = id
        button_states(index)%last_frame = current_frame
    end if
end function find_or_create_button_state

real function calculate_auto_width(label, ctx) result(width_dp)
    ! Calculate automatic button width based on label content
    character(*), intent(in) :: label
    type(ui_context), intent(in) :: ctx
    
    real, parameter :: CHAR_WIDTH_RATIO = 0.6  ! Typical character width to font size ratio
    real, parameter :: PADDING_DP = 16.0       ! Horizontal padding
    real, parameter :: MIN_WIDTH_DP = 40.0     ! Minimum button width
    
    integer :: label_length
    real :: text_width_dp
    
    ! Calculate text width based on font metrics
    label_length = len_trim(label)
    text_width_dp = real(label_length) * ctx%em_dp * CHAR_WIDTH_RATIO
    
    ! Add padding and enforce minimum size
    width_dp = max(text_width_dp + PADDING_DP, MIN_WIDTH_DP)
end function calculate_auto_width

real function calculate_auto_height(label, ctx) result(height_dp)
    ! Calculate automatic button height based on context
    character(*), intent(in) :: label
    type(ui_context), intent(in) :: ctx
    
    real, parameter :: HEIGHT_RATIO = 1.8      ! Button height to font size ratio
    real, parameter :: MIN_HEIGHT_DP = 20.0    ! Minimum button height
    
    ! Calculate height based on font size with standard ratio
    ! Ensure context em_dp is positive to avoid negative heights
    if (ctx%em_dp > 0.0) then
        height_dp = max(ctx%em_dp * HEIGHT_RATIO, MIN_HEIGHT_DP)
    else
        ! Fallback to minimum height if context is invalid
        height_dp = MIN_HEIGHT_DP
    end if
end function calculate_auto_height

logical function process_button_interaction(state_index, label) result(clicked)
    ! Process mouse and keyboard interaction for button
    integer, intent(in) :: state_index
    character(*), intent(in) :: label
    
    logical :: mouse_hit, keyboard_activated
    
    ! Update input state (would be updated from actual events in full implementation)
    call update_input_state()
    
    ! Check for mouse interaction
    mouse_hit = check_mouse_interaction(state_index)
    
    ! Check for keyboard activation
    keyboard_activated = check_keyboard_activation(state_index)
    
    ! Determine if button was clicked this frame
    clicked = mouse_hit .or. keyboard_activated
    
    ! Update button state
    if (clicked) then
        button_states(state_index)%clicked = .true.
        button_states(state_index)%click_count = button_states(state_index)%click_count + 1
    else
        ! Reset click state immediately after reading (immediate-mode behavior)
        button_states(state_index)%clicked = .false.
    end if
    
    ! Update hover state
    button_states(state_index)%hovered = check_mouse_hover(state_index)
end function process_button_interaction

subroutine update_input_state()
    ! Update global input state from system events
    ! This is a simplified version - full implementation would integrate with event system
    
    ! Mock input simulation for testing
    ! In real implementation, this would read from actual mouse/keyboard events
    
    ! Reset per-frame input states (keep previous values for testing)
    ! input_state%mouse_clicked = .false.
    ! input_state%enter_pressed = .false.
    ! input_state%space_pressed = .false.
    
    ! Simple test behavior - simulate click every 100 frames for testing
    if (mod(current_frame, 100) == 0) then
        input_state%mouse_clicked = .true.
        input_state%mouse_x = 50.0
        input_state%mouse_y = 25.0
    end if
end subroutine update_input_state

logical function check_mouse_interaction(state_index) result(clicked)
    ! Check if mouse click occurred within button bounds
    integer, intent(in) :: state_index
    
    clicked = .false.
    
    ! Only check if mouse was clicked this frame
    if (.not. input_state%mouse_clicked) return
    
    ! Check if mouse position is within button bounds
    if (input_state%mouse_x >= button_states(state_index)%x_dp .and. &
        input_state%mouse_x <= button_states(state_index)%x_dp + button_states(state_index)%width_dp .and. &
        input_state%mouse_y >= button_states(state_index)%y_dp .and. &
        input_state%mouse_y <= button_states(state_index)%y_dp + button_states(state_index)%height_dp) then
        clicked = .true.
    end if
end function check_mouse_interaction

logical function check_mouse_hover(state_index) result(hovered)
    ! Check if mouse is hovering over button
    integer, intent(in) :: state_index
    
    hovered = .false.
    
    ! Check if mouse position is within button bounds
    if (input_state%mouse_x >= button_states(state_index)%x_dp .and. &
        input_state%mouse_x <= button_states(state_index)%x_dp + button_states(state_index)%width_dp .and. &
        input_state%mouse_y >= button_states(state_index)%y_dp .and. &
        input_state%mouse_y <= button_states(state_index)%y_dp + button_states(state_index)%height_dp) then
        hovered = .true.
    end if
end function check_mouse_hover

logical function check_keyboard_activation(state_index) result(activated)
    ! Check for keyboard activation (Enter/Space keys)
    integer, intent(in) :: state_index
    
    activated = .false.
    
    ! Only activate if this button has focus
    if (trim(input_state%focused_button_id) /= trim(button_states(state_index)%id)) return
    
    ! Check for activation keys
    if (input_state%enter_pressed .or. input_state%space_pressed) then
        activated = .true.
    end if
end function check_keyboard_activation

subroutine render_button_placeholder(state_index, label)
    ! Placeholder for button rendering - would integrate with backend rendering system
    integer, intent(in) :: state_index
    character(*), intent(in) :: label
    
    ! This is a placeholder for the actual rendering implementation
    ! In the full system, this would:
    ! 1. Convert dp coordinates to backend-specific coordinates
    ! 2. Render button background and border
    ! 3. Render button text with proper alignment
    ! 4. Apply visual state (normal/hovered/active)
    
    ! For now, just update position for interaction testing
    ! Position buttons in a simple grid layout for testing
    button_states(state_index)%x_dp = 0.0
    button_states(state_index)%y_dp = real((state_index - 1) * 50)  ! Vertical spacing
end subroutine render_button_placeholder

! State management utilities

subroutine cleanup_unused_button_states()
    ! Clean up button states that haven't been accessed recently
    integer :: i, active_count
    integer, parameter :: FRAME_TIMEOUT = 300  ! Remove after 300 frames of inactivity
    
    active_count = 0
    
    do i = 1, button_count
        if (current_frame - button_states(i)%last_frame < FRAME_TIMEOUT) then
            active_count = active_count + 1
            ! Move active state to beginning of array if needed
            if (active_count < i) then
                button_states(active_count) = button_states(i)
            end if
        end if
    end do
    
    ! Update count to reflect active buttons only
    button_count = active_count
end subroutine cleanup_unused_button_states

subroutine reset_button_system()
    ! Reset the entire button system (useful for testing)
    button_count = 0
    current_frame = 0
    button_states = button_state_t()  ! Initialize all to default
    input_state = input_state_t()     ! Reset input state
end subroutine reset_button_system

! Debug and testing utilities

subroutine get_button_debug_info(id, width_dp, height_dp, click_count)
    ! Get debug information for testing
    character(*), intent(in) :: id
    real, intent(out), optional :: width_dp, height_dp
    integer, intent(out), optional :: click_count
    
    integer :: state_index
    
    state_index = find_button_state_by_id(id)
    if (state_index <= 0) return
    
    if (present(width_dp)) width_dp = button_states(state_index)%width_dp
    if (present(height_dp)) height_dp = button_states(state_index)%height_dp
    if (present(click_count)) click_count = button_states(state_index)%click_count
end subroutine get_button_debug_info

integer function find_button_state_by_id(id) result(index)
    ! Find button state by ID (returns 0 if not found)
    character(*), intent(in) :: id
    integer :: i
    
    index = 0
    do i = 1, button_count
        if (trim(button_states(i)%id) == trim(id)) then
            index = i
            return
        end if
    end do
end function find_button_state_by_id

! Testing helper functions for mock behavior

subroutine simulate_button_click(id, x, y)
    ! Simulate mouse click at specific coordinates for testing
    character(*), intent(in) :: id
    real, intent(in), optional :: x, y
    
    input_state%mouse_clicked = .true.
    if (present(x)) input_state%mouse_x = x
    if (present(y)) input_state%mouse_y = y
    
    ! Focus the button for keyboard testing
    input_state%focused_button_id = id
end subroutine simulate_button_click

subroutine simulate_key_press(key)
    ! Simulate key press for testing
    character(*), intent(in) :: key
    
    select case (trim(key))
    case ("ENTER", "enter", "Enter")
        input_state%enter_pressed = .true.
    case ("SPACE", "space", "Space", " ")
        input_state%space_pressed = .true.
    end select
end subroutine simulate_key_press

subroutine set_button_focus(id)
    ! Set keyboard focus to specific button for testing
    character(*), intent(in) :: id
    input_state%focused_button_id = id
end subroutine set_button_focus

end module fortui_widgets