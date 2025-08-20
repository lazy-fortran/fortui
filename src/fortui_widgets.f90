module fortui_widgets
! Simplified widgets module to test compilation
use fortui_widgets_button, only: button_node_t, button
implicit none
private

! Re-export button widget
public :: button_node_t, button

! Placeholder types for other widgets
public :: text_node_t, slider_node_t, checkbox_node_t, viewport_node_t
public :: text, slider, checkbox, viewport

! Widget node types (simplified placeholders)
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
    ! Store view state for tracking changes
    real :: current_scale_x = 1.0
    real :: current_scale_y = 1.0
    real :: current_off_x = 0.0
    real :: current_off_y = 0.0
end type viewport_node_t

contains

! Placeholder implementations returning widget nodes
function text(id, value, text_size, width, height) result(widget_node)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: value
    real, intent(in), optional :: text_size, width, height
    type(text_node_t) :: widget_node
    
    widget_node%id = id
    if (present(value)) widget_node%value = value
    if (present(width)) widget_node%width_dp = width
    if (present(height)) widget_node%height_dp = height
end function text

logical function slider(id, min_val, max_val, step_val, value, width, height) &
    result(value_changed)
    character(*), intent(in) :: id
    real, intent(in), optional :: min_val, max_val, step_val
    real, intent(inout), optional :: value
    real, intent(in), optional :: width, height
    
    ! Placeholder - no value change
    value_changed = .false.
end function slider

logical function checkbox(id, checked, label, width, height) result(toggled)
    character(*), intent(in) :: id
    logical, intent(inout), optional :: checked
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height
    
    ! Placeholder - no toggle
    toggled = .false.
end function checkbox

function viewport(id, width, height, view_state) result(viewport_node)
    use fortui_core, only: view, ui_element, node
    use fortui_units, only: ui_context, ui_get_context, convert_to_dp
    character(*), intent(in) :: id
    class(*), intent(in) :: width, height
    type(view), intent(inout) :: view_state
    type(node) :: viewport_node
    
    type(ui_context) :: ctx
    real :: width_dp, height_dp
    real :: mouse_x, mouse_y, scroll_x, scroll_y
    logical :: mouse_left, mouse_right, mouse_middle
    logical :: view_changed
    
    ! Internal viewport state tracking with per-ID state management
    type :: viewport_state_t
        logical :: dragging = .false.
        real :: last_mouse_x = 0.0
        real :: last_mouse_y = 0.0
        real :: viewport_x = 0.0
        real :: viewport_y = 0.0
        real :: viewport_w = 0.0
        real :: viewport_h = 0.0
        ! Previous view state for change detection
        real :: prev_scale_x = 1.0
        real :: prev_scale_y = 1.0
        real :: prev_off_x = 0.0
        real :: prev_off_y = 0.0
    end type
    
    type(viewport_state_t), save :: state
    character(len=256), save :: last_id = ""
    
    view_changed = .false.
    
    ! Get UI context for conversions
    call ui_get_context(ctx)
    
    ! Convert dimensions to dp using class(*) interface
    call process_viewport_size(width, height, ctx, width_dp, height_dp)
    
    ! Reset state if ID changed, preserving view state for change detection
    if (trim(id) /= trim(last_id)) then
        state%dragging = .false.
        ! Store current view state as "previous" for change detection
        state%prev_scale_x = view_state%scale_x
        state%prev_scale_y = view_state%scale_y
        state%prev_off_x = view_state%off_x
        state%prev_off_y = view_state%off_y
        last_id = id
    end if
    
    ! Check if view has changed since last frame
    view_changed = (abs(view_state%scale_x - state%prev_scale_x) > 1e-6) .or. &
                   (abs(view_state%scale_y - state%prev_scale_y) > 1e-6) .or. &
                   (abs(view_state%off_x - state%prev_off_x) > 1e-6) .or. &
                   (abs(view_state%off_y - state%prev_off_y) > 1e-6)
    
    ! Store viewport dimensions for this frame
    state%viewport_w = width_dp
    state%viewport_h = height_dp
    
    ! Get input state (placeholder implementation - will be replaced with actual input system)
    call get_input_state(mouse_x, mouse_y, mouse_left, mouse_right, mouse_middle, &
                         scroll_x, scroll_y)
    
    ! Check if mouse is within viewport bounds
    ! (For now, assume viewport starts at current layout position)
    ! TODO: Get actual viewport position from layout system
    
    ! Handle mouse scroll for zoom
    if (abs(scroll_y) > 1e-6) then
        call update_zoom(view_state, 1.0 + scroll_y * 0.1, &
                        mouse_x - state%viewport_x, mouse_y - state%viewport_y, &
                        state%viewport_w, state%viewport_h)
        view_changed = .true.
    end if
    
    ! Handle mouse drag for pan
    if (mouse_left) then
        if (.not. state%dragging) then
            ! Start dragging
            state%dragging = .true.
            state%last_mouse_x = mouse_x
            state%last_mouse_y = mouse_y
        else
            ! Continue dragging - update pan
            call update_pan(view_state, &
                           mouse_x - state%last_mouse_x, &
                           mouse_y - state%last_mouse_y, &
                           state%viewport_w, state%viewport_h)
            state%last_mouse_x = mouse_x
            state%last_mouse_y = mouse_y
            view_changed = .true.
        end if
    else
        state%dragging = .false.
    end if
    
    ! Store current view state for next frame's change detection
    state%prev_scale_x = view_state%scale_x
    state%prev_scale_y = view_state%scale_y
    state%prev_off_x = view_state%off_x
    state%prev_off_y = view_state%off_y
    
    ! Create viewport node with updated state
    ! For now, create a basic node - full implementation will include viewport-specific properties
    viewport_node = node()
    
    ! TODO: Store viewport-specific state and view changes in node metadata
    ! TODO: Use viewport_node_t type with proper id, dimensions, and view state
    ! Note: view_changed status available for immediate-mode pattern integration

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
        w_dp = max(w_dp, ctx%em_dp * 2.0)  ! Minimum 2em width
        h_dp = max(h_dp, ctx%em_dp * 1.5)  ! Minimum 1.5em height
    end subroutine process_viewport_size

    subroutine update_pan(view_state, mouse_delta_x, mouse_delta_y, viewport_width, viewport_height)
        use fortui_core, only: view
        ! Update pan offsets based on mouse movement
        type(view), intent(inout) :: view_state
        real, intent(in) :: mouse_delta_x, mouse_delta_y
        real, intent(in) :: viewport_width, viewport_height
        
        ! Convert pixel delta to view coordinates
        if (viewport_width > 0.0 .and. viewport_height > 0.0) then
            view_state%off_x = view_state%off_x - mouse_delta_x / (viewport_width * view_state%scale_x)
            view_state%off_y = view_state%off_y - mouse_delta_y / (viewport_height * view_state%scale_y)
        end if
    end subroutine update_pan

    subroutine update_zoom(view_state, zoom_factor, mouse_x, mouse_y, viewport_width, viewport_height)
        use fortui_core, only: view
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
        if (abs(new_scale_x - old_scale_x) > 1e-6 .or. abs(new_scale_y - old_scale_y) > 1e-6) then
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
                    ! Adjust pan to maintain mouse position in view
                    view_state%off_x = view_state%off_x + view_x * (1.0/old_scale_x - 1.0/view_state%scale_x)
                    view_state%off_y = view_state%off_y + view_y * (1.0/old_scale_y - 1.0/view_state%scale_y)
                end if
            end if
        end if
    end subroutine update_zoom

    subroutine get_input_state(mouse_x, mouse_y, mouse_left, mouse_right, mouse_middle, &
                              scroll_x, scroll_y)
        ! Placeholder input function - returns safe defaults
        ! TODO: Replace with actual input system integration
        real, intent(out) :: mouse_x, mouse_y, scroll_x, scroll_y
        logical, intent(out) :: mouse_left, mouse_right, mouse_middle
        
        ! Safe defaults - no input
        mouse_x = 0.0
        mouse_y = 0.0
        scroll_x = 0.0
        scroll_y = 0.0
        mouse_left = .false.
        mouse_right = .false.
        mouse_middle = .false.
    end subroutine get_input_state

end function viewport

end module fortui_widgets