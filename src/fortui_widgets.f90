module fortui_widgets
! Context-aware widgets module implementing Context Object Pattern
use iso_c_binding
use fortui_context, only: fortui_context_t, get_default_context, &
                          button_state, text_state, slider_state, &
                          checkbox_state, viewport_state, widget_state_union
use fortui_core, only: view, ui_element
use fortui_core, only: view
use fortui_units, only: ui_context, ui_get_context, convert_to_dp, unit_value
implicit none
private

! Widget functions (immediate-mode only)
public :: button, text, slider, checkbox, viewport

! Widget state types for context storage (re-exported from context)
public :: button_state, text_state, slider_state, checkbox_state, viewport_state

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

! Overloaded interface for viewport to replace class(*) polymorphism
interface viewport
    module procedure viewport_real_real
    module procedure viewport_unit_unit
    module procedure viewport_real_unit
    module procedure viewport_unit_real
end interface viewport

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
    type(widget_state_union) :: new_state_union
    
    ! Validate context
    if (.not. ctx%is_valid()) then
        clicked = .false.
        return
    end if
    
    ! Get or create button state
    state_index = ctx%widget_states%get(id, "button")
    if (state_index == 0) then
        ! Create new button state
        new_state_union%state_type = 1  ! button type
        new_state_union%button = button_state()  ! Initialize with defaults
        call ctx%widget_states%set(id, "button", new_state_union)
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
    ! Access state through the entries array using union
    if (ctx%widget_states%entries(state_index)%state%state_type == 1) then
        ! Button state
        if (ctx%widget_states%entries(state_index)%state%button%last_frame_clicked == ctx%frame_count) then
            clicked = ctx%widget_states%entries(state_index)%state%button%clicked_this_frame
        else
            ! Simulate button interaction for demonstration
            ! In real implementation, would check mouse/keyboard input
            clicked = .false.
            ctx%widget_states%entries(state_index)%state%button%clicked_this_frame = clicked
            ctx%widget_states%entries(state_index)%state%button%last_frame_clicked = ctx%frame_count
        end if
    else
        ! Invalid state type
        clicked = .false.
    end if
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
    type(widget_state_union) :: new_state_union
    
    ! Immediate-mode text rendering - no node objects exposed
    ! Get context for state management
    ctx => get_default_context()
    if (associated(ctx)) then
        ! Get or create text state
        state_index = ctx%widget_states%get(id, "text")
        if (state_index == 0) then
            ! Create new text state
            new_state_union%state_type = 2  ! text type
            new_state_union%text = text_state()
            if (present(value)) new_state_union%text%value = value
            call ctx%widget_states%set(id, "text", new_state_union)
        else
            ! Update value if provided using union access
            if (present(value) .and. &
                ctx%widget_states%entries(state_index)%state%state_type == 2) then
                ctx%widget_states%entries(state_index)%state%text%value = value
            end if
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
    type(widget_state_union) :: new_state_union
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
            new_state_union%state_type = 3  ! slider type
            new_state_union%slider = slider_state()
            if (present(value)) then
                new_state_union%slider%current_value = max(min_v, min(max_v, value))
            else
                new_state_union%slider%current_value = min_v
            end if
            call ctx%widget_states%set(id, "slider", new_state_union)
        else
            ! Update and return current value using union access
            if (ctx%widget_states%entries(state_index)%state%state_type == 3) then
                if (present(value)) then
                    ! Check if value changed
                    if (abs(ctx%widget_states%entries(state_index)%state%slider%current_value - value) > 1e-6) then
                        ctx%widget_states%entries(state_index)%state%slider%current_value = max(min_v, min(max_v, value))
                        value_changed = .true.
                    end if
                    value = ctx%widget_states%entries(state_index)%state%slider%current_value
                end if
            end if
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
    type(widget_state_union) :: new_state_union
    
    toggled = .false.
    
    ! Get context for state management
    ctx => get_default_context()
    if (associated(ctx)) then
        ! Get or create checkbox state
        state_index = ctx%widget_states%get(id, "checkbox")
        if (state_index == 0) then
            ! Create new checkbox state
            new_state_union%state_type = 4  ! checkbox type
            new_state_union%checkbox = checkbox_state()
            if (present(checked)) new_state_union%checkbox%checked = checked
            call ctx%widget_states%set(id, "checkbox", new_state_union)
        else
            ! Update and return current state using union access
            if (ctx%widget_states%entries(state_index)%state%state_type == 4) then
                if (present(checked)) then
                    ! Check if state changed
                    if (ctx%widget_states%entries(state_index)%state%checkbox%checked .neqv. checked) then
                        ctx%widget_states%entries(state_index)%state%checkbox%checked = checked
                        toggled = .true.
                    end if
                    checked = ctx%widget_states%entries(state_index)%state%checkbox%checked
                end if
            end if
        end if
    else
        ! Fallback without context - no state persistence
        if (present(checked)) then
            ! Just return current value, no change detection
        end if
    end if
end function checkbox

logical function viewport_real_real(id, width, height, view_state) result(view_changed)
    character(*), intent(in) :: id
    real, intent(in) :: width, height
    type(view), intent(inout) :: view_state
    
    type(fortui_context_t), pointer :: ctx
    type(ui_context) :: ui_ctx
    integer :: state_index
    type(widget_state_union) :: new_state_union
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
    
    ! Convert dimensions to dp
    call process_viewport_size_real_real(width, height, ui_ctx, width_dp, height_dp)
    
    ! Get or create viewport state
    state_index = ctx%widget_states%get(id, "viewport")
    if (state_index == 0) then
        ! Create new viewport state
        new_state_union%state_type = 5  ! viewport type
        new_state_union%viewport = viewport_state()
        new_state_union%viewport%prev_scale_x = view_state%scale_x
        new_state_union%viewport%prev_scale_y = view_state%scale_y
        new_state_union%viewport%prev_off_x = view_state%off_x
        new_state_union%viewport%prev_off_y = view_state%off_y
        new_state_union%viewport%viewport_w = width_dp
        new_state_union%viewport%viewport_h = height_dp
        call ctx%widget_states%set(id, "viewport", new_state_union)
        state_index = ctx%widget_states%get(id, "viewport")
    end if
    
    if (state_index == 0) return
    
    ! Process viewport interaction using union access
    if (ctx%widget_states%entries(state_index)%state%state_type == 5) then
        ! Viewport state - use short alias for readability
        associate (state_obj => ctx%widget_states%entries(state_index)%state%viewport)
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
        end associate
    end if
end function viewport_real_real

logical function viewport_unit_unit(id, width, height, view_state) result(view_changed)
    character(*), intent(in) :: id
    type(unit_value), intent(in) :: width, height
    type(view), intent(inout) :: view_state
    
    type(fortui_context_t), pointer :: ctx
    type(ui_context) :: ui_ctx
    integer :: state_index
    type(widget_state_union) :: new_state_union
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
    
    ! Convert dimensions to dp
    call process_viewport_size_unit_unit(width, height, ui_ctx, width_dp, height_dp)
    
    ! Get or create viewport state
    state_index = ctx%widget_states%get(id, "viewport")
    if (state_index == 0) then
        ! Create new viewport state
        new_state_union%state_type = 5  ! viewport type
        new_state_union%viewport = viewport_state()
        new_state_union%viewport%prev_scale_x = view_state%scale_x
        new_state_union%viewport%prev_scale_y = view_state%scale_y
        new_state_union%viewport%prev_off_x = view_state%off_x
        new_state_union%viewport%prev_off_y = view_state%off_y
        new_state_union%viewport%viewport_w = width_dp
        new_state_union%viewport%viewport_h = height_dp
        call ctx%widget_states%set(id, "viewport", new_state_union)
        state_index = ctx%widget_states%get(id, "viewport")
    end if
    
    if (state_index == 0) return
    
    ! Get backend input for mouse/keyboard handling
    call get_input_state(mouse_x, mouse_y, mouse_left, mouse_right, &
                          mouse_middle, scroll_x, scroll_y)
    
    ! Check for view changes
    associate(vp => ctx%widget_states%entries(state_index)%state%viewport)
        ! Store current state as previous
        vp%prev_scale_x = view_state%scale_x
        vp%prev_scale_y = view_state%scale_y
        vp%prev_off_x = view_state%off_x
        vp%prev_off_y = view_state%off_y
        
        ! Handle pan/zoom input
        call update_pan(view_state, mouse_x - vp%last_mouse_x, mouse_y - vp%last_mouse_y, &
                        width_dp, height_dp)
        call update_zoom(view_state, 1.0 + scroll_y * 0.1, mouse_x, mouse_y, width_dp, height_dp)
        
        ! Check for changes
        if (abs(vp%prev_scale_x - view_state%scale_x) > 1e-6 .or. &
            abs(vp%prev_scale_y - view_state%scale_y) > 1e-6 .or. &
            abs(vp%prev_off_x - view_state%off_x) > 1e-6 .or. &
            abs(vp%prev_off_y - view_state%off_y) > 1e-6) then
            view_changed = .true.
        end if
        
        ! Update state
        vp%last_mouse_x = mouse_x
        vp%last_mouse_y = mouse_y
        end associate
end function viewport_unit_unit

logical function viewport_real_unit(id, width, height, view_state) result(view_changed)
    character(*), intent(in) :: id
    real, intent(in) :: width
    type(unit_value), intent(in) :: height
    type(view), intent(inout) :: view_state
    
    type(fortui_context_t), pointer :: ctx
    type(ui_context) :: ui_ctx
    integer :: state_index
    type(widget_state_union) :: new_state_union
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
    
    ! Convert dimensions to dp
    call process_viewport_size_real_unit(width, height, ui_ctx, width_dp, height_dp)
    
    ! Get or create viewport state
    state_index = ctx%widget_states%get(id, "viewport")
    if (state_index == 0) then
        ! Create new viewport state
        new_state_union%state_type = 5  ! viewport type
        new_state_union%viewport = viewport_state()
        new_state_union%viewport%prev_scale_x = view_state%scale_x
        new_state_union%viewport%prev_scale_y = view_state%scale_y
        new_state_union%viewport%prev_off_x = view_state%off_x
        new_state_union%viewport%prev_off_y = view_state%off_y
        new_state_union%viewport%viewport_w = width_dp
        new_state_union%viewport%viewport_h = height_dp
        call ctx%widget_states%set(id, "viewport", new_state_union)
        state_index = ctx%widget_states%get(id, "viewport")
    end if
    
    if (state_index == 0) return
    
    ! Get backend input for mouse/keyboard handling
    call get_input_state(mouse_x, mouse_y, mouse_left, mouse_right, &
                          mouse_middle, scroll_x, scroll_y)
    
    ! Check for view changes
    associate(vp => ctx%widget_states%entries(state_index)%state%viewport)
        ! Store current state as previous
        vp%prev_scale_x = view_state%scale_x
        vp%prev_scale_y = view_state%scale_y
        vp%prev_off_x = view_state%off_x
        vp%prev_off_y = view_state%off_y
        
        ! Handle pan/zoom input
        call update_pan(view_state, mouse_x - vp%last_mouse_x, mouse_y - vp%last_mouse_y, &
                        width_dp, height_dp)
        call update_zoom(view_state, 1.0 + scroll_y * 0.1, mouse_x, mouse_y, width_dp, height_dp)
        
        ! Check for changes
        if (abs(vp%prev_scale_x - view_state%scale_x) > 1e-6 .or. &
            abs(vp%prev_scale_y - view_state%scale_y) > 1e-6 .or. &
            abs(vp%prev_off_x - view_state%off_x) > 1e-6 .or. &
            abs(vp%prev_off_y - view_state%off_y) > 1e-6) then
            view_changed = .true.
        end if
        
        ! Update state
        vp%last_mouse_x = mouse_x
        vp%last_mouse_y = mouse_y
        end associate
end function viewport_real_unit

logical function viewport_unit_real(id, width, height, view_state) result(view_changed)
    character(*), intent(in) :: id
    type(unit_value), intent(in) :: width
    real, intent(in) :: height
    type(view), intent(inout) :: view_state
    
    type(fortui_context_t), pointer :: ctx
    type(ui_context) :: ui_ctx
    integer :: state_index
    type(widget_state_union) :: new_state_union
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
    
    ! Convert dimensions to dp
    call process_viewport_size_unit_real(width, height, ui_ctx, width_dp, height_dp)
    
    ! Get or create viewport state
    state_index = ctx%widget_states%get(id, "viewport")
    if (state_index == 0) then
        ! Create new viewport state
        new_state_union%state_type = 5  ! viewport type
        new_state_union%viewport = viewport_state()
        new_state_union%viewport%prev_scale_x = view_state%scale_x
        new_state_union%viewport%prev_scale_y = view_state%scale_y
        new_state_union%viewport%prev_off_x = view_state%off_x
        new_state_union%viewport%prev_off_y = view_state%off_y
        new_state_union%viewport%viewport_w = width_dp
        new_state_union%viewport%viewport_h = height_dp
        call ctx%widget_states%set(id, "viewport", new_state_union)
        state_index = ctx%widget_states%get(id, "viewport")
    end if
    
    if (state_index == 0) return
    
    ! Get backend input for mouse/keyboard handling
    call get_input_state(mouse_x, mouse_y, mouse_left, mouse_right, &
                          mouse_middle, scroll_x, scroll_y)
    
    ! Check for view changes
    associate(vp => ctx%widget_states%entries(state_index)%state%viewport)
        ! Store current state as previous
        vp%prev_scale_x = view_state%scale_x
        vp%prev_scale_y = view_state%scale_y
        vp%prev_off_x = view_state%off_x
        vp%prev_off_y = view_state%off_y
        
        ! Handle pan/zoom input
        call update_pan(view_state, mouse_x - vp%last_mouse_x, mouse_y - vp%last_mouse_y, &
                        width_dp, height_dp)
        call update_zoom(view_state, 1.0 + scroll_y * 0.1, mouse_x, mouse_y, width_dp, height_dp)
        
        ! Check for changes
        if (abs(vp%prev_scale_x - view_state%scale_x) > 1e-6 .or. &
            abs(vp%prev_scale_y - view_state%scale_y) > 1e-6 .or. &
            abs(vp%prev_off_x - view_state%off_x) > 1e-6 .or. &
            abs(vp%prev_off_y - view_state%off_y) > 1e-6) then
            view_changed = .true.
        end if
        
        ! Update state
        vp%last_mouse_x = mouse_x
        vp%last_mouse_y = mouse_y
        end associate
end function viewport_unit_real
    
    subroutine process_viewport_size_real_real(width_arg, height_arg, ctx, w_dp, h_dp)
        ! Convert real dimensions to dp with minimum size enforcement
        real, intent(in) :: width_arg, height_arg
        type(ui_context), intent(in) :: ctx
        real, intent(out) :: w_dp, h_dp
        
        ! Convert width (required parameter)
        w_dp = convert_to_dp(width_arg, ctx)
        
        ! Convert height (required parameter)
        h_dp = convert_to_dp(height_arg, ctx)
        
        ! Ensure minimum usable size
        w_dp = max(w_dp, ctx%em_dp * 2.0)
        h_dp = max(h_dp, ctx%em_dp * 1.5)
    end subroutine process_viewport_size_real_real
    
    subroutine process_viewport_size_unit_unit(width_arg, height_arg, ctx, w_dp, h_dp)
        ! Convert unit_value dimensions to dp with minimum size enforcement
        type(unit_value), intent(in) :: width_arg, height_arg
        type(ui_context), intent(in) :: ctx
        real, intent(out) :: w_dp, h_dp
        
        ! Convert width (required parameter)
        w_dp = convert_to_dp(width_arg, ctx)
        
        ! Convert height (required parameter)
        h_dp = convert_to_dp(height_arg, ctx)
        
        ! Ensure minimum usable size
        w_dp = max(w_dp, ctx%em_dp * 2.0)
        h_dp = max(h_dp, ctx%em_dp * 1.5)
    end subroutine process_viewport_size_unit_unit
    
    subroutine process_viewport_size_real_unit(width_arg, height_arg, ctx, w_dp, h_dp)
        ! Convert mixed real/unit dimensions to dp with minimum size enforcement
        real, intent(in) :: width_arg
        type(unit_value), intent(in) :: height_arg
        type(ui_context), intent(in) :: ctx
        real, intent(out) :: w_dp, h_dp
        
        ! Convert width (required parameter)
        w_dp = convert_to_dp(width_arg, ctx)
        
        ! Convert height (required parameter)
        h_dp = convert_to_dp(height_arg, ctx)
        
        ! Ensure minimum usable size
        w_dp = max(w_dp, ctx%em_dp * 2.0)
        h_dp = max(h_dp, ctx%em_dp * 1.5)
    end subroutine process_viewport_size_real_unit
    
    subroutine process_viewport_size_unit_real(width_arg, height_arg, ctx, w_dp, h_dp)
        ! Convert mixed unit/real dimensions to dp with minimum size enforcement
        type(unit_value), intent(in) :: width_arg
        real, intent(in) :: height_arg
        type(ui_context), intent(in) :: ctx
        real, intent(out) :: w_dp, h_dp
        
        ! Convert width (required parameter)
        w_dp = convert_to_dp(width_arg, ctx)
        
        ! Convert height (required parameter)
        h_dp = convert_to_dp(height_arg, ctx)
        
        ! Ensure minimum usable size
        w_dp = max(w_dp, ctx%em_dp * 2.0)
        h_dp = max(h_dp, ctx%em_dp * 1.5)
    end subroutine process_viewport_size_unit_real

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

end module fortui_widgets