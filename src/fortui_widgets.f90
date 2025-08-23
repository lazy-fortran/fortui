module fortui_widgets
! Context-aware widgets module implementing Context Object Pattern
use iso_c_binding
use fortui_context, only: fortui_context_t, get_default_context
use fortui_core, only: view, ui_element
use fortui_core, only: view
use fortui_units, only: ui_context, ui_get_context, convert_to_dp
implicit none
private

! Widget functions (immediate-mode only)
public :: button, text, slider, checkbox, viewport

! Widget state types for context storage
public :: button_state, text_state, slider_state, checkbox_state, viewport_state

! Button widget state for context storage
type :: button_state
    logical :: pressed = .false.
    logical :: hover = .false.
    logical :: clicked_this_frame = .false.
    integer :: last_frame_clicked = -1
end type button_state

! Widget state types for context storage
type :: text_state
    character(len=1024) :: value = ""
    logical :: focused = .false.
    integer :: cursor_pos = 1
end type text_state

type :: slider_state
    real :: current_value = 0.0
    logical :: dragging = .false.
    real :: last_mouse_x = 0.0
end type slider_state

type :: checkbox_state
    logical :: checked = .false.
    logical :: hover = .false.
end type checkbox_state

type :: viewport_state
    logical :: dragging = .false.
    real :: last_mouse_x = 0.0
    real :: last_mouse_y = 0.0
    real :: viewport_x = 0.0
    real :: viewport_y = 0.0
    real :: viewport_w = 0.0
    real :: viewport_h = 0.0
    real :: prev_scale_x = 1.0
    real :: prev_scale_y = 1.0
    real :: prev_off_x = 0.0
    real :: prev_off_y = 0.0
end type viewport_state

! Widget node types
type, extends(ui_element) :: button_node_t
    character(len=256) :: id = ""
    character(len=256) :: label = ""
    real :: width_dp = 0.0
    real :: height_dp = 0.0
    logical :: clicked = .false.
end type button_node_t

type :: text_node_t
    character(len=256) :: id = ""
    character(len=1024) :: value = ""
    real :: width_dp = 0.0
    real :: height_dp = 0.0
end type text_node_t

type :: slider_node_t
    character(len=256) :: id = ""
    real :: min_val = 0.0
    real :: max_val = 100.0
    real :: width_dp = 0.0
    real :: height_dp = 0.0
end type slider_node_t

type :: checkbox_node_t
    character(len=256) :: id = ""
    character(len=256) :: label = ""
    logical :: checked = .false.
    real :: width_dp = 0.0
    real :: height_dp = 0.0
end type checkbox_node_t

type :: viewport_node_t
    character(len=256) :: id = ""
    real :: width_dp = 0.0
    real :: height_dp = 0.0
    logical :: view_changed = .false.
    real :: current_scale_x = 1.0
    real :: current_scale_y = 1.0
    real :: current_off_x = 0.0
    real :: current_off_y = 0.0
end type viewport_node_t

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

! Context-aware text widget implementation
subroutine text(id, value, text_size, width, height)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: value
    real, intent(in), optional :: text_size, width, height
    
    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(text_state) :: new_state
    
    ! Immediate-mode text rendering - no node objects exposed
    ! Get context for state management
    ctx => get_default_context()
    if (associated(ctx)) then
        ! Get or create text state
        state_index = ctx%widget_states%get(id, "text")
        if (state_index == 0) then
            ! Create new text state
            new_state = text_state()
            if (present(value)) new_state%value = value
            call ctx%widget_states%set(id, "text", new_state)
        else
            ! Update value if provided
            select type(state_obj => ctx%widget_states%entries(state_index)%state)
            type is (text_state)
                if (present(value)) state_obj%value = value
            end select
        end if
    end if
    
    ! TODO: Immediate rendering should happen here
    ! In proper immediate-mode, this would render directly to current UI frame
    ! For now, text rendering is deferred to present cycle
end subroutine text

logical function slider(id, min_val, max_val, step_val, value, width, height) &
    result(value_changed)
    character(*), intent(in) :: id
    real, intent(in), optional :: min_val, max_val, step_val
    real, intent(inout), optional :: value
    real, intent(in), optional :: width, height
    
    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(slider_state) :: new_state
    real :: min_v, max_v
    
    value_changed = .false.
    
    ! Set defaults
    min_v = 0.0
    max_v = 100.0
    if (present(min_val)) min_v = min_val
    if (present(max_val)) max_v = max_val
    
    ! Get context for state management
    ctx => get_default_context()
    if (associated(ctx)) then
        ! Get or create slider state
        state_index = ctx%widget_states%get(id, "slider")
        if (state_index == 0) then
            ! Create new slider state
            new_state = slider_state()
            if (present(value)) then
                new_state%current_value = max(min_v, min(max_v, value))
            else
                new_state%current_value = min_v
            end if
            call ctx%widget_states%set(id, "slider", new_state)
        else
            ! Update and return current value
            select type(state_obj => ctx%widget_states%entries(state_index)%state)
            type is (slider_state)
                if (present(value)) then
                    ! Check if value changed
                    if (abs(state_obj%current_value - value) > 1e-6) then
                        state_obj%current_value = max(min_v, min(max_v, value))
                        value_changed = .true.
                    end if
                    value = state_obj%current_value
                end if
            end select
        end if
    else
        ! Fallback without context - just clamp value
        if (present(value)) then
            value = max(min_v, min(max_v, value))
        end if
    end if
end function slider

logical function checkbox(id, checked, label, width, height) result(toggled)
    character(*), intent(in) :: id
    logical, intent(inout), optional :: checked
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height
    
    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(checkbox_state) :: new_state
    
    toggled = .false.
    
    ! Get context for state management
    ctx => get_default_context()
    if (associated(ctx)) then
        ! Get or create checkbox state
        state_index = ctx%widget_states%get(id, "checkbox")
        if (state_index == 0) then
            ! Create new checkbox state
            new_state = checkbox_state()
            if (present(checked)) new_state%checked = checked
            call ctx%widget_states%set(id, "checkbox", new_state)
        else
            ! Update and return current state
            select type(state_obj => ctx%widget_states%entries(state_index)%state)
            type is (checkbox_state)
                if (present(checked)) then
                    ! Check if state changed
                    if (state_obj%checked .neqv. checked) then
                        state_obj%checked = checked
                        toggled = .true.
                    end if
                    checked = state_obj%checked
                end if
            end select
        end if
    else
        ! Fallback without context - no state persistence
        if (present(checked)) then
            ! Just return current value, no change detection
        end if
    end if
end function checkbox

logical function viewport(id, width, height, view_state) result(view_changed)
    character(*), intent(in) :: id
    class(*), intent(in) :: width, height
    type(view), intent(inout) :: view_state
    
    type(fortui_context_t), pointer :: ctx
    type(ui_context) :: ui_ctx
    integer :: state_index
    type(viewport_state) :: new_state
    real :: width_dp, height_dp
    real :: mouse_x, mouse_y, scroll_x, scroll_y
    logical :: mouse_left, mouse_right, mouse_middle
    
    view_changed = .false.
    
    ! Get context for state management
    ctx => get_default_context()
    if (.not. associated(ctx)) then
        ! Fallback without context
        return
    end if
    
    ! Get UI context for conversions
    call ui_get_context(ui_ctx)
    
    ! Convert dimensions to dp using class(*) interface
    call process_viewport_size(width, height, ui_ctx, width_dp, height_dp)
    
    ! Get or create viewport state
    state_index = ctx%widget_states%get(id, "viewport")
    if (state_index == 0) then
        ! Create new viewport state
        new_state = viewport_state()
        new_state%prev_scale_x = view_state%scale_x
        new_state%prev_scale_y = view_state%scale_y
        new_state%prev_off_x = view_state%off_x
        new_state%prev_off_y = view_state%off_y
        new_state%viewport_w = width_dp
        new_state%viewport_h = height_dp
        call ctx%widget_states%set(id, "viewport", new_state)
        state_index = ctx%widget_states%get(id, "viewport")
    end if
    
    if (state_index == 0) return
    
    ! Process viewport interaction
    select type(state_obj => ctx%widget_states%entries(state_index)%state)
    type is (viewport_state)
        ! Check if view has changed since last frame
        view_changed = (abs(view_state%scale_x - state_obj%prev_scale_x) > 1e-6) &
                       .or. (abs(view_state%scale_y - state_obj%prev_scale_y) > 1e-6) &
                       .or. (abs(view_state%off_x - state_obj%prev_off_x) > 1e-6) &
                       .or. (abs(view_state%off_y - state_obj%prev_off_y) > 1e-6)
        
        ! Store viewport dimensions for this frame
        state_obj%viewport_w = width_dp
        state_obj%viewport_h = height_dp
        
        ! Get input state
        call get_input_state(mouse_x, mouse_y, mouse_left, mouse_right, mouse_middle, &
                             scroll_x, scroll_y)
        
        ! Handle mouse scroll for zoom
        if (abs(scroll_y) > 1e-6) then
            call update_zoom(view_state, 1.0 + scroll_y * 0.1, &
                            mouse_x - state_obj%viewport_x, &
                            mouse_y - state_obj%viewport_y, &
                            state_obj%viewport_w, state_obj%viewport_h)
            view_changed = .true.
        end if
        
        ! Handle mouse drag for pan
        if (mouse_left) then
            if (.not. state_obj%dragging) then
                ! Start dragging
                state_obj%dragging = .true.
                state_obj%last_mouse_x = mouse_x
                state_obj%last_mouse_y = mouse_y
            else
                ! Continue dragging - update pan
                call update_pan(view_state, &
                               mouse_x - state_obj%last_mouse_x, &
                               mouse_y - state_obj%last_mouse_y, &
                               state_obj%viewport_w, &
                               state_obj%viewport_h)
                state_obj%last_mouse_x = mouse_x
                state_obj%last_mouse_y = mouse_y
                view_changed = .true.
            end if
        else
            state_obj%dragging = .false.
        end if
        
        ! Store current view state for next frame's change detection
        state_obj%prev_scale_x = view_state%scale_x
        state_obj%prev_scale_y = view_state%scale_y
        state_obj%prev_off_x = view_state%off_x
        state_obj%prev_off_y = view_state%off_y
    end select

contains
    
    subroutine process_viewport_size(width_arg, height_arg, ctx, w_dp, h_dp)
        ! Convert class(*) dimensions to dp with minimum size enforcement
        class(*), intent(in) :: width_arg, height_arg
        type(ui_context), intent(in) :: ctx
        real, intent(out) :: w_dp, h_dp
        
        ! Convert width (required parameter)
        w_dp = convert_to_dp(width_arg, ctx)
        
        ! Convert height (required parameter)
        h_dp = convert_to_dp(height_arg, ctx)
        
        ! Ensure minimum usable size
        w_dp = max(w_dp, ctx%em_dp * 2.0)
        h_dp = max(h_dp, ctx%em_dp * 1.5)
    end subroutine process_viewport_size

    subroutine update_pan(view_state, mouse_delta_x, mouse_delta_y, &
                          viewport_width, viewport_height)
        ! Update pan offsets based on mouse movement
        type(view), intent(inout) :: view_state
        real, intent(in) :: mouse_delta_x, mouse_delta_y
        real, intent(in) :: viewport_width, viewport_height
        
        ! Convert pixel delta to view coordinates
        if (viewport_width > 0.0 .and. viewport_height > 0.0) then
            view_state%off_x = view_state%off_x - &
                               mouse_delta_x / (viewport_width * view_state%scale_x)
            view_state%off_y = view_state%off_y - &
                               mouse_delta_y / (viewport_height * view_state%scale_y)
        end if
    end subroutine update_pan

    subroutine update_zoom(view_state, zoom_factor, mouse_x, mouse_y, &
                           viewport_width, viewport_height)
        ! Update zoom scaling around mouse position with enhanced precision
        type(view), intent(inout) :: view_state
        real, intent(in) :: zoom_factor, mouse_x, mouse_y
        real, intent(in) :: viewport_width, viewport_height
        
        real :: old_scale_x, old_scale_y
        real :: view_x, view_y
        real :: new_scale_x, new_scale_y
        
        ! Store old scale values
        old_scale_x = view_state%scale_x
        old_scale_y = view_state%scale_y
        
        ! Calculate new scale values with enhanced limits
        new_scale_x = old_scale_x * zoom_factor
        new_scale_y = old_scale_y * zoom_factor
        
        ! Apply zoom limits with smooth clamping
        ! Min zoom: 0.01 (1%), Max zoom: 100x
        new_scale_x = max(0.01, min(100.0, new_scale_x))
        new_scale_y = max(0.01, min(100.0, new_scale_y))
        
        ! Only update if scale actually changed (avoid floating point drift)
        if (abs(new_scale_x - old_scale_x) > 1e-6 .or. &
            abs(new_scale_y - old_scale_y) > 1e-6) then
            view_state%scale_x = new_scale_x
            view_state%scale_y = new_scale_y
            
            ! Adjust offset to zoom around mouse position
            if (viewport_width > 0.0 .and. viewport_height > 0.0) then
                ! Normalized mouse position (0-1)
                view_x = mouse_x / viewport_width
                view_y = mouse_y / viewport_height
                
                ! Clamp to viewport bounds
                view_x = max(0.0, min(1.0, view_x))
                view_y = max(0.0, min(1.0, view_y))
                
                if (old_scale_x > 0.0 .and. old_scale_y > 0.0) then
                    ! Adjust pan to maintain mouse position in view (Issue #62 fix)
                    if (abs(old_scale_x) > epsilon(1.0) .and. abs(view_state%scale_x) > epsilon(1.0)) then
                        view_state%off_x = view_state%off_x + &
                                           view_x * (1.0/old_scale_x - 1.0/view_state%scale_x)
                    end if
                    if (abs(old_scale_y) > epsilon(1.0) .and. abs(view_state%scale_y) > epsilon(1.0)) then
                        view_state%off_y = view_state%off_y + &
                                           view_y * (1.0/old_scale_y - 1.0/view_state%scale_y)
                    end if
                end if
            end if
        end if
    end subroutine update_zoom

    subroutine get_input_state(mouse_x, mouse_y, mouse_left, mouse_right, &
                              mouse_middle, scroll_x, scroll_y)
        real, intent(out) :: mouse_x, mouse_y, scroll_x, scroll_y
        logical, intent(out) :: mouse_left, mouse_right, mouse_middle
        
        ! Initialize with safe defaults
        mouse_x = 0.0
        mouse_y = 0.0
        scroll_x = 0.0
        scroll_y = 0.0
        mouse_left = .false.
        mouse_right = .false.
        mouse_middle = .false.
        
        ! Input system integration would go here
        ! For now, return safe defaults to prevent crashes
    end subroutine get_input_state

end function viewport

end module fortui_widgets