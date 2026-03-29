module fortui_widgets
! Immediate-mode widgets with internal state management
use iso_c_binding
use fortui_context, only: fortui_context_t, get_default_context
use fortui_core, only: view
use fortui_layout, only: layout_get_cursor, layout_advance
implicit none
private

! Widget functions (immediate-mode only)
public :: button, text, slider, checkbox, viewport

! Button widget state for context storage
type :: button_state
    logical :: pressed = .false.
    logical :: hover = .false.
    logical :: clicked_this_frame = .false.
    integer :: last_frame_clicked = -1
    real :: pos_x = 0.0
    real :: pos_y = 0.0
    real :: size_w = 0.0
    real :: size_h = 0.0
end type button_state

! Widget state types for context storage
type :: text_state
    character(len=1024) :: value = ""
    logical :: focused = .false.
    integer :: cursor_pos = 1
    real :: pos_x = 0.0
    real :: pos_y = 0.0
    real :: size_w = 0.0
    real :: size_h = 0.0
end type text_state

type :: slider_state
    real :: current_value = 0.0
    logical :: dragging = .false.
    real :: last_mouse_x = 0.0
    real :: pos_x = 0.0
    real :: pos_y = 0.0
    real :: size_w = 0.0
    real :: size_h = 0.0
end type slider_state

type :: checkbox_state
    logical :: checked = .false.
    logical :: hover = .false.
    real :: pos_x = 0.0
    real :: pos_y = 0.0
    real :: size_w = 0.0
    real :: size_h = 0.0
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
    real :: pos_x = 0.0
    real :: pos_y = 0.0
end type viewport_state

contains

logical function button(id, label, width, height) result(clicked)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height

    type(fortui_context_t), pointer :: ctx
    character(len=256) :: display_label
    integer :: state_index
    type(button_state) :: new_state
    real :: w_cells, h_cells, cx, cy

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        clicked = .false.
        return
    end if

    if (.not. ctx%is_valid()) then
        clicked = .false.
        return
    end if

    if (present(label)) then
        display_label = label
    else
        display_label = id
    end if

    if (present(width)) then
        w_cells = width
    else
        w_cells = real(len_trim(display_label)) + 4.0
    end if

    if (present(height)) then
        h_cells = height
    else
        h_cells = 1.0
    end if

    call layout_get_cursor(cx, cy)

    state_index = ctx%widget_states%get(id, "button")
    if (state_index == 0) then
        new_state = button_state()
        new_state%pos_x = cx
        new_state%pos_y = cy
        new_state%size_w = w_cells
        new_state%size_h = h_cells
        call ctx%widget_states%set(id, "button", new_state)
        state_index = ctx%widget_states%get(id, "button")
    end if

    if (state_index == 0) then
        clicked = .false.
        return
    end if

    select type(state_obj => ctx%widget_states%entries(state_index)%state)
    type is (button_state)
        state_obj%pos_x = cx
        state_obj%pos_y = cy
        state_obj%size_w = w_cells
        state_obj%size_h = h_cells
        if (state_obj%last_frame_clicked == ctx%frame_count) then
            clicked = state_obj%clicked_this_frame
        else
            clicked = .false.
            state_obj%clicked_this_frame = clicked
            state_obj%last_frame_clicked = ctx%frame_count
        end if
    class default
        clicked = .false.
    end select

    call layout_advance(w_cells, h_cells)
end function button

subroutine text(id, value, text_size, width, height)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: value
    real, intent(in), optional :: text_size, width, height

    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(text_state) :: new_state
    real :: w_cells, h_cells, cx, cy
    character(len=1024) :: display_value

    display_value = ""
    if (present(value)) display_value = value

    if (present(width)) then
        w_cells = width
    else
        w_cells = max(real(len_trim(display_value)), 1.0)
    end if

    if (present(height)) then
        h_cells = height
    else
        h_cells = 1.0
    end if

    call layout_get_cursor(cx, cy)

    ctx => get_default_context()
    if (associated(ctx)) then
        state_index = ctx%widget_states%get(id, "text")
        if (state_index == 0) then
            new_state = text_state()
            if (present(value)) new_state%value = value
            new_state%pos_x = cx
            new_state%pos_y = cy
            new_state%size_w = w_cells
            new_state%size_h = h_cells
            call ctx%widget_states%set(id, "text", new_state)
        else
            select type(state_obj => ctx%widget_states%entries(state_index)%state)
            type is (text_state)
                if (present(value)) state_obj%value = value
                state_obj%pos_x = cx
                state_obj%pos_y = cy
                state_obj%size_w = w_cells
                state_obj%size_h = h_cells
            end select
        end if
    end if

    call layout_advance(w_cells, h_cells)
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
    real :: w_cells, h_cells, cx, cy

    value_changed = .false.

    min_v = 0.0
    max_v = 100.0
    if (present(min_val)) min_v = min_val
    if (present(max_val)) max_v = max_val

    if (present(width)) then
        w_cells = width
    else
        w_cells = 20.0
    end if

    if (present(height)) then
        h_cells = height
    else
        h_cells = 1.0
    end if

    call layout_get_cursor(cx, cy)

    ctx => get_default_context()
    if (associated(ctx)) then
        state_index = ctx%widget_states%get(id, "slider")
        if (state_index == 0) then
            new_state = slider_state()
            if (present(value)) then
                new_state%current_value = max(min_v, min(max_v, value))
                value = new_state%current_value
            else
                new_state%current_value = min_v
            end if
            new_state%pos_x = cx
            new_state%pos_y = cy
            new_state%size_w = w_cells
            new_state%size_h = h_cells
            call ctx%widget_states%set(id, "slider", new_state)
        else
            select type(state_obj => ctx%widget_states%entries(state_index)%state)
            type is (slider_state)
                if (present(value)) then
                    if (abs(state_obj%current_value - value) > 1e-6) then
                        state_obj%current_value = &
                            max(min_v, min(max_v, value))
                        value_changed = .true.
                    end if
                    value = state_obj%current_value
                end if
                state_obj%pos_x = cx
                state_obj%pos_y = cy
                state_obj%size_w = w_cells
                state_obj%size_h = h_cells
            end select
        end if
    else
        if (present(value)) then
            value = max(min_v, min(max_v, value))
        end if
    end if

    call layout_advance(w_cells, h_cells)
end function slider

logical function checkbox(id, checked, label, width, height) result(toggled)
    character(*), intent(in) :: id
    logical, intent(inout), optional :: checked
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height

    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(checkbox_state) :: new_state
    real :: w_cells, h_cells, cx, cy
    character(len=256) :: display_label

    toggled = .false.

    display_label = ""
    if (present(label)) display_label = label

    if (present(width)) then
        w_cells = width
    else
        w_cells = real(len_trim(display_label)) + 4.0
    end if

    if (present(height)) then
        h_cells = height
    else
        h_cells = 1.0
    end if

    call layout_get_cursor(cx, cy)

    ctx => get_default_context()
    if (associated(ctx)) then
        state_index = ctx%widget_states%get(id, "checkbox")
        if (state_index == 0) then
            new_state = checkbox_state()
            if (present(checked)) new_state%checked = checked
            new_state%pos_x = cx
            new_state%pos_y = cy
            new_state%size_w = w_cells
            new_state%size_h = h_cells
            call ctx%widget_states%set(id, "checkbox", new_state)
        else
            select type(state_obj => ctx%widget_states%entries(state_index)%state)
            type is (checkbox_state)
                if (present(checked)) then
                    if (state_obj%checked .neqv. checked) then
                        state_obj%checked = checked
                        toggled = .true.
                    end if
                    checked = state_obj%checked
                end if
                state_obj%pos_x = cx
                state_obj%pos_y = cy
                state_obj%size_w = w_cells
                state_obj%size_h = h_cells
            end select
        end if
    end if

    call layout_advance(w_cells, h_cells)
end function checkbox

logical function viewport(id, width, height, view_state) result(view_changed)
    character(*), intent(in) :: id
    real, intent(in) :: width, height
    type(view), intent(inout) :: view_state

    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(viewport_state) :: new_state
    real :: width_cells, height_cells
    real :: mouse_x, mouse_y, scroll_x, scroll_y
    logical :: mouse_left, mouse_right, mouse_middle
    real :: cx, cy

    view_changed = .false.

    width_cells = max(width, 4.0)
    height_cells = max(height, 3.0)

    call layout_get_cursor(cx, cy)

    ctx => get_default_context()
    if (.not. associated(ctx)) return

    state_index = ctx%widget_states%get(id, "viewport")
    if (state_index == 0) then
        new_state = viewport_state()
        new_state%prev_scale_x = view_state%scale_x
        new_state%prev_scale_y = view_state%scale_y
        new_state%prev_off_x = view_state%off_x
        new_state%prev_off_y = view_state%off_y
        new_state%viewport_w = width_cells
        new_state%viewport_h = height_cells
        new_state%pos_x = cx
        new_state%pos_y = cy
        call ctx%widget_states%set(id, "viewport", new_state)
        state_index = ctx%widget_states%get(id, "viewport")
    end if

    if (state_index == 0) return

    select type(state_obj => ctx%widget_states%entries(state_index)%state)
    type is (viewport_state)
        state_obj%pos_x = cx
        state_obj%pos_y = cy

        view_changed = &
            (abs(view_state%scale_x - state_obj%prev_scale_x) > 1e-6) &
            .or. (abs(view_state%scale_y - state_obj%prev_scale_y) &
                > 1e-6) &
            .or. (abs(view_state%off_x - state_obj%prev_off_x) > 1e-6) &
            .or. (abs(view_state%off_y - state_obj%prev_off_y) > 1e-6)

        state_obj%viewport_w = width_cells
        state_obj%viewport_h = height_cells

        call get_input_state(mouse_x, mouse_y, mouse_left, &
                             mouse_right, mouse_middle, &
                             scroll_x, scroll_y)

        if (abs(scroll_y) > 1e-6) then
            call update_zoom(view_state, 1.0 + scroll_y * 0.1, &
                            mouse_x - state_obj%viewport_x, &
                            mouse_y - state_obj%viewport_y, &
                            state_obj%viewport_w, &
                            state_obj%viewport_h)
            view_changed = .true.
        end if

        if (mouse_left) then
            if (.not. state_obj%dragging) then
                state_obj%dragging = .true.
                state_obj%last_mouse_x = mouse_x
                state_obj%last_mouse_y = mouse_y
            else
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

        state_obj%prev_scale_x = view_state%scale_x
        state_obj%prev_scale_y = view_state%scale_y
        state_obj%prev_off_x = view_state%off_x
        state_obj%prev_off_y = view_state%off_y
    end select

    call layout_advance(width_cells, height_cells)

contains

    subroutine update_pan(view_state, mouse_delta_x, mouse_delta_y, &
                          viewport_width, viewport_height)
        type(view), intent(inout) :: view_state
        real, intent(in) :: mouse_delta_x, mouse_delta_y
        real, intent(in) :: viewport_width, viewport_height

        if (viewport_width > 0.0 .and. viewport_height > 0.0) then
            view_state%off_x = view_state%off_x - &
                mouse_delta_x / (viewport_width * view_state%scale_x)
            view_state%off_y = view_state%off_y - &
                mouse_delta_y / (viewport_height * view_state%scale_y)
        end if
    end subroutine update_pan

    subroutine update_zoom(view_state, zoom_factor, mouse_x, mouse_y, &
                           viewport_width, viewport_height)
        type(view), intent(inout) :: view_state
        real, intent(in) :: zoom_factor, mouse_x, mouse_y
        real, intent(in) :: viewport_width, viewport_height

        real :: old_scale_x, old_scale_y
        real :: view_x, view_y
        real :: new_scale_x, new_scale_y

        old_scale_x = view_state%scale_x
        old_scale_y = view_state%scale_y

        new_scale_x = old_scale_x * zoom_factor
        new_scale_y = old_scale_y * zoom_factor

        new_scale_x = max(0.01, min(100.0, new_scale_x))
        new_scale_y = max(0.01, min(100.0, new_scale_y))

        if (abs(new_scale_x - old_scale_x) > 1e-6 .or. &
            abs(new_scale_y - old_scale_y) > 1e-6) then
            view_state%scale_x = new_scale_x
            view_state%scale_y = new_scale_y

            if (viewport_width > 0.0 .and. &
                viewport_height > 0.0) then
                view_x = mouse_x / viewport_width
                view_y = mouse_y / viewport_height

                view_x = max(0.0, min(1.0, view_x))
                view_y = max(0.0, min(1.0, view_y))

                if (old_scale_x > 0.0 .and. &
                    old_scale_y > 0.0) then
                    if (abs(old_scale_x) > epsilon(1.0) .and. &
                        abs(view_state%scale_x) > &
                            epsilon(1.0)) then
                        view_state%off_x = view_state%off_x + &
                            view_x * (1.0/old_scale_x - &
                                1.0/view_state%scale_x)
                    end if
                    if (abs(old_scale_y) > epsilon(1.0) .and. &
                        abs(view_state%scale_y) > &
                            epsilon(1.0)) then
                        view_state%off_y = view_state%off_y + &
                            view_y * (1.0/old_scale_y - &
                                1.0/view_state%scale_y)
                    end if
                end if
            end if
        end if
    end subroutine update_zoom

    subroutine get_input_state(mouse_x, mouse_y, mouse_left, &
                              mouse_right, mouse_middle, &
                              scroll_x, scroll_y)
        real, intent(out) :: mouse_x, mouse_y, scroll_x, scroll_y
        logical, intent(out) :: mouse_left, mouse_right, mouse_middle

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
