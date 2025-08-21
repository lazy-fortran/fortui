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

logical function viewport(id, width, height, view_state) result(view_changed)
    use fortui_core, only: view
    use fortui_units, only: ui_context, ui_get_context, convert_to_dp
    character(*), intent(in) :: id
    class(*), intent(in) :: width, height
    type(view), intent(inout) :: view_state
    
    type(ui_context) :: ctx
    real :: width_dp, height_dp
    real :: mouse_x, mouse_y, scroll_x, scroll_y
    logical :: mouse_left, mouse_right, mouse_middle
    
    ! Internal viewport state tracking with per-ID state management
    type :: viewport_state_t
        character(len=256) :: id = ""
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
    end type
    
    type(viewport_state_t), allocatable :: states(:)
    integer :: state_count
    integer :: state_idx
    
    view_changed = .false.
    
    ! Initialize state storage if needed
    if (.not. allocated(states)) then
        allocate(states(10))
        state_count = 0
    end if
    
    ! Get UI context for conversions
    call ui_get_context(ctx)
    
    ! Convert dimensions to dp using class(*) interface
    call process_viewport_size(width, height, ctx, width_dp, height_dp)
    
    ! Find or create state for this ID
    state_idx = find_or_create_state(id)
    
    ! Initialize state if this is the first time
    if (trim(states(state_idx)%id) /= trim(id)) then
        states(state_idx)%id = id
        states(state_idx)%dragging = .false.
        states(state_idx)%prev_scale_x = view_state%scale_x
        states(state_idx)%prev_scale_y = view_state%scale_y
        states(state_idx)%prev_off_x = view_state%off_x
        states(state_idx)%prev_off_y = view_state%off_y
    end if
    
    ! Check if view has changed since last frame
    view_changed = (abs(view_state%scale_x - states(state_idx)%prev_scale_x) > 1e-6) &
                   .or. (abs(view_state%scale_y - states(state_idx)%prev_scale_y) > 1e-6) &
                   .or. (abs(view_state%off_x - states(state_idx)%prev_off_x) > 1e-6) &
                   .or. (abs(view_state%off_y - states(state_idx)%prev_off_y) > 1e-6)
    
    ! Store viewport dimensions for this frame
    states(state_idx)%viewport_w = width_dp
    states(state_idx)%viewport_h = height_dp
    
    ! Get input state
    call get_input_state(mouse_x, mouse_y, mouse_left, mouse_right, mouse_middle, &
                         scroll_x, scroll_y)
    
    ! Handle mouse scroll for zoom
    if (abs(scroll_y) > 1e-6) then
        call update_zoom(view_state, 1.0 + scroll_y * 0.1, &
                        mouse_x - states(state_idx)%viewport_x, &
                        mouse_y - states(state_idx)%viewport_y, &
                        states(state_idx)%viewport_w, states(state_idx)%viewport_h)
        view_changed = .true.
    end if
    
    ! Handle mouse drag for pan
    if (mouse_left) then
        if (.not. states(state_idx)%dragging) then
            ! Start dragging
            states(state_idx)%dragging = .true.
            states(state_idx)%last_mouse_x = mouse_x
            states(state_idx)%last_mouse_y = mouse_y
        else
            ! Continue dragging - update pan
            call update_pan(view_state, &
                           mouse_x - states(state_idx)%last_mouse_x, &
                           mouse_y - states(state_idx)%last_mouse_y, &
                           states(state_idx)%viewport_w, &
                           states(state_idx)%viewport_h)
            states(state_idx)%last_mouse_x = mouse_x
            states(state_idx)%last_mouse_y = mouse_y
            view_changed = .true.
        end if
    else
        states(state_idx)%dragging = .false.
    end if
    
    ! Store current view state for next frame's change detection
    states(state_idx)%prev_scale_x = view_state%scale_x
    states(state_idx)%prev_scale_y = view_state%scale_y
    states(state_idx)%prev_off_x = view_state%off_x
    states(state_idx)%prev_off_y = view_state%off_y

contains
    
    integer function find_or_create_state(viewport_id) result(idx)
        character(*), intent(in) :: viewport_id
        integer :: i
        
        ! First try to find existing state
        do i = 1, state_count
            if (trim(states(i)%id) == trim(viewport_id)) then
                idx = i
                return
            end if
        end do
        
        ! Create new state if not found and space available
        if (state_count < size(states)) then
            state_count = state_count + 1
            idx = state_count
        else
            ! Reuse oldest state (simple LRU)
            idx = 1
        end if
    end function find_or_create_state

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
        use fortui_core, only: view
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
                    ! Adjust pan to maintain mouse position in view
                    view_state%off_x = view_state%off_x + &
                                       view_x * (1.0/old_scale_x - 1.0/view_state%scale_x)
                    view_state%off_y = view_state%off_y + &
                                       view_y * (1.0/old_scale_y - 1.0/view_state%scale_y)
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