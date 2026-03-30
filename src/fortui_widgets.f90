module fortui_widgets
! Immediate-mode widgets with internal state management
! Widgets render themselves directly via tui_set_cell during their call
use iso_c_binding
use fortui_context, only: fortui_context_t, get_default_context
use fortui_core, only: view
use fortui_layout, only: layout_get_cursor, layout_advance
use fortui_render, only: render_is_active, render_is_gui, &
    render_set_cell, render_fill_rect, render_draw_text, &
    render_draw_border, &
    RC_DEFAULT, RC_WHITE, RC_BLACK, RC_CYAN, RC_YELLOW, &
    RC_GREEN, RC_RED, RC_BLUE, RC_BOLD, RC_REVERSE
use fortui_input, only: input_get_mouse_x, input_get_mouse_y, &
    input_get_mouse_left, input_get_scroll_y, input_get_key, &
    input_register_focusable, input_has_focus, input_set_focus, &
    KEY_ENTER, KEY_SPACE, KEY_ARROW_LEFT, KEY_ARROW_RIGHT
implicit none
private

public :: button, text, slider, checkbox, viewport

! Widget state types for context storage
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
    integer :: ix, iy, iw, i, mx, my, fg, bg
    logical :: hover, focused

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        clicked = .false.
        return
    end if

    if (.not. ctx%is_valid()) then
        clicked = .false.
        return
    end if

    call input_register_focusable(id)
    focused = input_has_focus(id)

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

    ! Hit test (mouse)
    ix = int(cx)
    iy = int(cy)
    iw = int(w_cells)
    clicked = .false.
    hover = .false.

    mx = input_get_mouse_x()
    my = input_get_mouse_y()
    if (mx >= ix .and. mx < ix + iw .and. my == iy) then
        hover = .true.
        if (input_get_mouse_left()) then
            clicked = .true.
            call input_set_focus(id)
        end if
    end if

    ! Keyboard activation
    if (focused) then
        if (input_get_key() == KEY_ENTER .or. &
            input_get_key() == KEY_SPACE) then
            clicked = .true.
        end if
    end if

    if (state_index > 0) then
        select type(s => ctx%widget_states%entries(state_index)%state)
        type is (button_state)
            s%pos_x = cx
            s%pos_y = cy
            s%size_w = w_cells
            s%size_h = h_cells
            s%hover = hover
            s%clicked_this_frame = clicked
            s%last_frame_clicked = ctx%frame_count
        end select
    end if

    ! Render button
    if (render_is_active()) then
        if (clicked) then
            fg = RC_BLACK
            bg = RC_WHITE
        else if (focused) then
            fg = RC_BLACK + RC_BOLD
            bg = RC_YELLOW
        else if (hover) then
            fg = RC_BLACK + RC_BOLD
            bg = RC_CYAN
        else
            fg = RC_WHITE
            bg = RC_BLUE
        end if

        if (render_is_gui()) then
            call render_fill_rect(ix, iy, iw, 1, bg)
            call render_draw_text(ix + 1, iy, &
                trim(display_label), fg, bg)
        else
            call render_set_cell(ix, iy, iachar('['), fg, bg)
            call render_set_cell(ix + 1, iy, &
                iachar(' '), fg, bg)
            do i = 1, min(len_trim(display_label), iw - 4)
                call render_set_cell(ix + 1 + i, iy, &
                    iachar(display_label(i:i)), fg, bg)
            end do
            call render_set_cell(ix + iw - 2, iy, &
                iachar(' '), fg, bg)
            call render_set_cell(ix + iw - 1, iy, &
                iachar(']'), fg, bg)
        end if
    end if

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
    integer :: ix, iy, iw, i, fg, bg

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
            select type(s => &
                ctx%widget_states%entries(state_index)%state)
            type is (text_state)
                if (present(value)) s%value = value
                s%pos_x = cx
                s%pos_y = cy
                s%size_w = w_cells
                s%size_h = h_cells
            end select
        end if
    end if

    ! Render plain text
    if (render_is_active()) then
        ix = int(cx)
        iy = int(cy)
        iw = int(w_cells)
        fg = RC_DEFAULT
        bg = RC_DEFAULT
        if (present(text_size)) then
            if (text_size > 1.5) fg = RC_DEFAULT + RC_BOLD
        end if

        if (render_is_gui()) then
            call render_draw_text(ix, iy, &
                display_value(1:min(len_trim(display_value), &
                iw)), fg, bg)
        else
            do i = 1, min(len_trim(display_value), iw)
                call render_set_cell(ix + i - 1, iy, &
                    iachar(display_value(i:i)), fg, bg)
            end do
        end if
    end if

    call layout_advance(w_cells, h_cells)
end subroutine text

logical function slider(id, min_val, max_val, step_val, value, &
    width, height) result(value_changed)
    character(*), intent(in) :: id
    real, intent(in), optional :: min_val, max_val, step_val
    real, intent(inout), optional :: value
    real, intent(in), optional :: width, height

    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(slider_state) :: new_state
    real :: min_v, max_v, step_v, cur_val, frac
    real :: w_cells, h_cells, cx, cy
    integer :: ix, iy, iw, i, knob_pos, track_w, mx, my
    integer :: fg, bg, key
    logical :: focused

    value_changed = .false.

    min_v = 0.0
    max_v = 100.0
    step_v = 1.0
    if (present(min_val)) min_v = min_val
    if (present(max_val)) max_v = max_val
    if (present(step_val)) step_v = step_val

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

    call input_register_focusable(id)
    focused = input_has_focus(id)

    ctx => get_default_context()
    cur_val = min_v
    if (present(value)) cur_val = max(min_v, min(max_v, value))

    if (associated(ctx)) then
        state_index = ctx%widget_states%get(id, "slider")
        if (state_index == 0) then
            new_state = slider_state()
            new_state%current_value = cur_val
            new_state%pos_x = cx
            new_state%pos_y = cy
            new_state%size_w = w_cells
            new_state%size_h = h_cells
            call ctx%widget_states%set(id, "slider", new_state)
        else
            select type(s => &
                ctx%widget_states%entries(state_index)%state)
            type is (slider_state)
                s%pos_x = cx
                s%pos_y = cy
                s%size_w = w_cells
                s%size_h = h_cells
                cur_val = s%current_value
            end select
        end if

        ! Input: click on track sets value
        ix = int(cx)
        iy = int(cy)
        iw = int(w_cells)
        track_w = iw - 2
        mx = input_get_mouse_x()
        my = input_get_mouse_y()

        if (input_get_mouse_left() .and. my == iy .and. &
            mx > ix .and. mx < ix + iw - 1 .and. &
            track_w > 0) then
            frac = real(mx - ix - 1) / real(track_w - 1)
            frac = max(0.0, min(1.0, frac))
            cur_val = min_v + frac * (max_v - min_v)
            if (step_v > 0.0) then
                cur_val = min_v + &
                    nint((cur_val - min_v) / step_v) * step_v
            end if
            cur_val = max(min_v, min(max_v, cur_val))

            state_index = ctx%widget_states%get(id, "slider")
            if (state_index > 0) then
                select type(s => &
                    ctx%widget_states%entries(state_index)%state)
                type is (slider_state)
                    s%current_value = cur_val
                end select
            end if
            value_changed = .true.
            call input_set_focus(id)
        end if

        ! Keyboard: arrow keys adjust value when focused
        if (focused) then
            key = input_get_key()
            if (key == KEY_ARROW_RIGHT) then
                cur_val = min(max_v, cur_val + step_v)
                value_changed = .true.
            else if (key == KEY_ARROW_LEFT) then
                cur_val = max(min_v, cur_val - step_v)
                value_changed = .true.
            end if

            if (value_changed) then
                state_index = ctx%widget_states%get(id, "slider")
                if (state_index > 0) then
                    select type(s => &
                        ctx%widget_states%entries(state_index)%state)
                    type is (slider_state)
                        s%current_value = cur_val
                    end select
                end if
            end if
        end if
    end if

    if (present(value)) then
        if (abs(cur_val - value) > 1e-6) value_changed = .true.
        value = cur_val
    end if

    ! Render slider
    if (render_is_active()) then
        ix = int(cx)
        iy = int(cy)
        iw = int(w_cells)
        track_w = iw - 2
        fg = RC_DEFAULT
        bg = RC_DEFAULT

        if (max_v > min_v) then
            frac = (cur_val - min_v) / (max_v - min_v)
        else
            frac = 0.0
        end if
        knob_pos = max(0, min(track_w - 1, &
            int(frac * real(track_w - 1))))

        if (render_is_gui()) then
            ! Track background
            call render_fill_rect(ix, iy, iw, 1, RC_BLACK)
            ! Filled portion
            if (knob_pos > 0) then
                call render_fill_rect(ix, iy, &
                    knob_pos + 1, 1, RC_CYAN)
            end if
            ! Knob
            if (focused) then
                call render_fill_rect(ix + knob_pos, iy, &
                    2, 1, RC_YELLOW)
            else
                call render_fill_rect(ix + knob_pos, iy, &
                    2, 1, RC_WHITE)
            end if
        else
            if (focused) then
                call render_set_cell(ix, iy, iachar('['), &
                    RC_YELLOW + RC_BOLD, bg)
            else
                call render_set_cell(ix, iy, &
                    iachar('['), fg, bg)
            end if

            do i = 0, track_w - 1
                if (i < knob_pos) then
                    call render_set_cell(ix + 1 + i, iy, &
                        iachar('='), RC_CYAN, bg)
                else if (i == knob_pos) then
                    if (focused) then
                        call render_set_cell(ix + 1 + i, &
                            iy, iachar('|'), &
                            RC_YELLOW + RC_BOLD, bg)
                    else
                        call render_set_cell(ix + 1 + i, &
                            iy, iachar('|'), &
                            RC_WHITE + RC_BOLD, bg)
                    end if
                else
                    call render_set_cell(ix + 1 + i, iy, &
                        iachar('-'), RC_DEFAULT, bg)
                end if
            end do

            if (focused) then
                call render_set_cell(ix + iw - 1, iy, &
                    iachar(']'), RC_YELLOW + RC_BOLD, bg)
            else
                call render_set_cell(ix + iw - 1, iy, &
                    iachar(']'), fg, bg)
            end if
        end if
    end if

    call layout_advance(w_cells, h_cells)
end function slider

logical function checkbox(id, checked, label, width, height) &
    result(toggled)
    character(*), intent(in) :: id
    logical, intent(inout), optional :: checked
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height

    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(checkbox_state) :: new_state
    real :: w_cells, h_cells, cx, cy
    character(len=256) :: display_label
    integer :: ix, iy, iw, i, mx, my, fg, bg
    logical :: is_checked, hover, focused

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

    call input_register_focusable(id)
    focused = input_has_focus(id)

    is_checked = .false.
    if (present(checked)) is_checked = checked

    ctx => get_default_context()
    if (associated(ctx)) then
        state_index = ctx%widget_states%get(id, "checkbox")
        if (state_index == 0) then
            new_state = checkbox_state()
            new_state%checked = is_checked
            new_state%pos_x = cx
            new_state%pos_y = cy
            new_state%size_w = w_cells
            new_state%size_h = h_cells
            call ctx%widget_states%set(id, "checkbox", new_state)
        else
            select type(s => &
                ctx%widget_states%entries(state_index)%state)
            type is (checkbox_state)
                s%pos_x = cx
                s%pos_y = cy
                s%size_w = w_cells
                s%size_h = h_cells
                is_checked = s%checked
            end select
        end if

        ! Input: click toggles
        ix = int(cx)
        iy = int(cy)
        iw = int(w_cells)
        mx = input_get_mouse_x()
        my = input_get_mouse_y()
        hover = (mx >= ix .and. mx < ix + iw .and. my == iy)

        if (hover .and. input_get_mouse_left()) then
            is_checked = .not. is_checked
            toggled = .true.
            call input_set_focus(id)
        end if

        ! Keyboard: Enter/Space toggles when focused
        if (focused) then
            if (input_get_key() == KEY_ENTER .or. &
                input_get_key() == KEY_SPACE) then
                is_checked = .not. is_checked
                toggled = .true.
            end if
        end if

        if (toggled) then
            state_index = ctx%widget_states%get(id, "checkbox")
            if (state_index > 0) then
                select type(s => &
                    ctx%widget_states%entries(state_index)%state)
                type is (checkbox_state)
                    s%checked = is_checked
                end select
            end if
        end if
    end if

    if (present(checked)) checked = is_checked

    ! Render checkbox
    if (render_is_active()) then
        ix = int(cx)
        iy = int(cy)
        iw = int(w_cells)

        if (focused) then
            fg = RC_YELLOW + RC_BOLD
        else
            fg = RC_DEFAULT
        end if
        bg = RC_DEFAULT

        if (render_is_gui()) then
            ! Checkbox box
            if (is_checked) then
                call render_fill_rect(ix, iy, 2, 1, RC_GREEN)
                call render_draw_text(ix, iy, "x", &
                    RC_WHITE, RC_GREEN)
            else if (focused) then
                call render_fill_rect(ix, iy, 2, 1, RC_YELLOW)
            else
                call render_fill_rect(ix, iy, 2, 1, RC_WHITE)
            end if
            ! Label
            if (len_trim(display_label) > 0) then
                call render_draw_text(ix + 3, iy, &
                    trim(display_label), fg, bg)
            end if
        else
            call render_set_cell(ix, iy, &
                iachar('['), fg, bg)
            if (is_checked) then
                call render_set_cell(ix + 1, iy, &
                    iachar('x'), RC_GREEN + RC_BOLD, bg)
            else
                call render_set_cell(ix + 1, iy, &
                    iachar(' '), fg, bg)
            end if
            call render_set_cell(ix + 2, iy, &
                iachar(']'), fg, bg)
            call render_set_cell(ix + 3, iy, &
                iachar(' '), fg, bg)

            do i = 1, min(len_trim(display_label), iw - 4)
                call render_set_cell(ix + 3 + i, iy, &
                    iachar(display_label(i:i)), fg, bg)
            end do
        end if
    end if

    call layout_advance(w_cells, h_cells)
end function checkbox

logical function viewport(id, width, height, view_state) &
    result(view_changed)
    character(*), intent(in) :: id
    real, intent(in) :: width, height
    type(view), intent(inout) :: view_state

    type(fortui_context_t), pointer :: ctx
    integer :: state_index
    type(viewport_state) :: new_state
    real :: width_cells, height_cells, cx, cy
    integer :: ix, iy, iw, ih, i, mx, my, scroll
    integer :: fg, bg
    character(len=64) :: info_str

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

    ix = int(cx)
    iy = int(cy)
    iw = int(width_cells)
    ih = int(height_cells)

    select type(s => ctx%widget_states%entries(state_index)%state)
    type is (viewport_state)
        s%pos_x = cx
        s%pos_y = cy
        s%viewport_w = width_cells
        s%viewport_h = height_cells

        mx = input_get_mouse_x()
        my = input_get_mouse_y()

        ! Scroll to zoom
        if (mx >= ix .and. mx < ix + iw .and. &
            my >= iy .and. my < iy + ih) then
            scroll = input_get_scroll_y()
            if (scroll /= 0) then
                view_state%scale_x = view_state%scale_x * &
                    (1.0 + real(scroll) * 0.1)
                view_state%scale_y = view_state%scale_y * &
                    (1.0 + real(scroll) * 0.1)
                view_state%scale_x = max(0.01, &
                    min(100.0, view_state%scale_x))
                view_state%scale_y = max(0.01, &
                    min(100.0, view_state%scale_y))
                view_changed = .true.
            end if

            ! Drag to pan
            if (input_get_mouse_left()) then
                if (.not. s%dragging) then
                    s%dragging = .true.
                    s%last_mouse_x = real(mx)
                    s%last_mouse_y = real(my)
                else
                    view_state%off_x = view_state%off_x - &
                        (real(mx) - s%last_mouse_x) / &
                        (width_cells * view_state%scale_x)
                    view_state%off_y = view_state%off_y - &
                        (real(my) - s%last_mouse_y) / &
                        (height_cells * view_state%scale_y)
                    s%last_mouse_x = real(mx)
                    s%last_mouse_y = real(my)
                    view_changed = .true.
                end if
            else
                s%dragging = .false.
            end if
        else
            s%dragging = .false.
        end if

        view_changed = view_changed .or. &
            (abs(view_state%scale_x - s%prev_scale_x) > 1e-6) &
            .or. (abs(view_state%scale_y - s%prev_scale_y) &
                > 1e-6) &
            .or. (abs(view_state%off_x - s%prev_off_x) > 1e-6) &
            .or. (abs(view_state%off_y - s%prev_off_y) > 1e-6)

        s%prev_scale_x = view_state%scale_x
        s%prev_scale_y = view_state%scale_y
        s%prev_off_x = view_state%off_x
        s%prev_off_y = view_state%off_y
    end select

    ! Render viewport
    if (render_is_active()) then
        fg = RC_DEFAULT
        bg = RC_DEFAULT

        if (render_is_gui()) then
            call render_draw_border(ix, iy, iw, ih, &
                RC_WHITE, RC_DEFAULT)
            if (ih > 2 .and. iw > 4) then
                write(info_str, '(A,F5.1,A,F5.1,A,F5.1)') &
                    'z=', view_state%scale_x, &
                    ' x=', view_state%off_x, &
                    ' y=', view_state%off_y
                call render_draw_text(ix + 1, iy + 1, &
                    trim(info_str), RC_YELLOW, bg)
            end if
        else
            ! Top border
            call render_set_cell(ix, iy, &
                iachar('+'), fg, bg)
            do i = 1, iw - 2
                call render_set_cell(ix + i, iy, &
                    iachar('-'), fg, bg)
            end do
            call render_set_cell(ix + iw - 1, iy, &
                iachar('+'), fg, bg)

            ! Side borders
            do i = 1, ih - 2
                call render_set_cell(ix, iy + i, &
                    iachar('|'), fg, bg)
                call render_set_cell(ix + iw - 1, iy + i, &
                    iachar('|'), fg, bg)
            end do

            ! Info line
            if (ih > 2 .and. iw > 4) then
                write(info_str, &
                    '(A,F5.1,A,F5.1,A,F5.1)') &
                    'z=', view_state%scale_x, &
                    ' x=', view_state%off_x, &
                    ' y=', view_state%off_y
                do i = 1, min(len_trim(info_str), iw - 4)
                    call render_set_cell(ix + 1 + i, &
                        iy + 1, iachar(info_str(i:i)), &
                        RC_YELLOW, bg)
                end do
            end if

            ! Bottom border
            call render_set_cell(ix, iy + ih - 1, &
                iachar('+'), fg, bg)
            do i = 1, iw - 2
                call render_set_cell(ix + i, iy + ih - 1, &
                    iachar('-'), fg, bg)
            end do
            call render_set_cell(ix + iw - 1, &
                iy + ih - 1, iachar('+'), fg, bg)
        end if
    end if

    call layout_advance(width_cells, height_cells)
end function viewport

end module fortui_widgets
