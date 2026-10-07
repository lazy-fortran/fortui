module fortui_widgets
!! Backend-free immediate composition widgets.
use fortui_context, only: fortui_context_t, get_default_context
use fortui_frame, only: ui_node_t, view, UI_TEXT, UI_BUTTON, UI_SLIDER, UI_CHECKBOX, UI_VIEWPORT
use fortui_layout, only: layout_get_cursor, layout_advance
use fortui_input, only: input_activated, input_focused, input_active, input_hovered, &
    input_scroll_for, input_key_for, KEY_ARROW_LEFT, KEY_ARROW_RIGHT
implicit none
private

real, parameter :: TEXT_HEIGHT = 24.0
real, parameter :: CONTROL_HEIGHT = 32.0
real, parameter :: GLYPH_WIDTH = 8.0
real, parameter :: CONTROL_PADDING = 24.0

public :: text, button, slider, checkbox, viewport, view

contains

subroutine text(id, value, text_size, width, height)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: value
    real, intent(in), optional :: text_size, width, height

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    real :: scale

    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%in_frame) return

    node%kind = UI_TEXT
    node%id = trim(id)
    if (present(value)) node%text = value

    scale = 1.0
    if (present(text_size)) scale = max(0.5, text_size)
    node%width = max(GLYPH_WIDTH, real(max(1, len_trim(node%text))) * GLYPH_WIDTH * scale)
    node%height = TEXT_HEIGHT * scale
    if (present(width)) node%width = max(0.0, width)
    if (present(height)) node%height = max(0.0, height)

    call place_and_emit(ctx, node)
end subroutine text

logical function button(id, label, width, height, enabled) result(clicked)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height
    logical, intent(in), optional :: enabled

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    logical :: is_enabled

    clicked = .false.
    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%in_frame) return

    node%kind = UI_BUTTON
    node%id = trim(id)
    node%text = trim(id)
    if (present(label)) node%text = label
    node%width = max(72.0, real(max(1, len_trim(node%text))) * GLYPH_WIDTH + CONTROL_PADDING)
    node%height = CONTROL_HEIGHT
    if (present(width)) node%width = max(0.0, width)
    if (present(height)) node%height = max(0.0, height)

    is_enabled = .true.
    if (present(enabled)) is_enabled = enabled
    node%disabled = .not. is_enabled
    node%focusable = is_enabled

    call decorate_from_input(ctx, node)
    if (is_enabled) clicked = input_activated(ctx%input, id)
    call place_and_emit(ctx, node)
end function button

logical function slider(id, min_val, max_val, step_val, value, width, height, enabled) result(changed)
    character(*), intent(in) :: id
    real, intent(in), optional :: min_val, max_val, step_val
    real, intent(inout) :: value
    real, intent(in), optional :: width, height
    logical, intent(in), optional :: enabled

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    real :: lo, hi, step, old_value, fraction
    integer :: key
    logical :: is_enabled

    changed = .false.
    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%in_frame) return

    lo = 0.0
    hi = 100.0
    step = 1.0
    if (present(min_val)) lo = min_val
    if (present(max_val)) hi = max_val
    if (hi < lo) then
        fraction = lo
        lo = hi
        hi = fraction
    end if
    if (present(step_val)) step = max(0.0, step_val)

    node%kind = UI_SLIDER
    node%id = trim(id)
    node%width = 200.0
    node%height = CONTROL_HEIGHT
    if (present(width)) node%width = max(1.0, width)
    if (present(height)) node%height = max(1.0, height)

    is_enabled = .true.
    if (present(enabled)) is_enabled = enabled
    node%disabled = .not. is_enabled
    node%focusable = is_enabled

    call layout_get_cursor(node%x, node%y)
    call decorate_from_input(ctx, node)

    old_value = value
    value = max(lo, min(hi, value))

    if (is_enabled .and. input_active(ctx%input, id) .and. ctx%input%pointer_down) then
        fraction = (ctx%input%pointer_x - node%x) / max(node%width, 1.0)
        fraction = max(0.0, min(1.0, fraction))
        value = lo + fraction * (hi - lo)
        if (step > 0.0) value = lo + real(nint((value - lo) / step)) * step
        value = max(lo, min(hi, value))
    end if

    if (is_enabled .and. input_focused(ctx%input, id)) then
        key = input_key_for(ctx%input, id)
        if (key == KEY_ARROW_LEFT) value = max(lo, value - step)
        if (key == KEY_ARROW_RIGHT) value = min(hi, value + step)
    end if

    changed = abs(value - old_value) > epsilon(1.0)
    node%value = value
    node%min_value = lo
    node%max_value = hi

    call emit_at_current_position(ctx, node)
end function slider

logical function checkbox(id, checked, label, width, height, enabled) result(toggled)
    character(*), intent(in) :: id
    logical, intent(inout) :: checked
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height
    logical, intent(in), optional :: enabled

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    logical :: is_enabled

    toggled = .false.
    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%in_frame) return

    node%kind = UI_CHECKBOX
    node%id = trim(id)
    node%text = ""
    if (present(label)) node%text = label
    node%width = max(72.0, real(max(1, len_trim(node%text))) * GLYPH_WIDTH + 40.0)
    node%height = CONTROL_HEIGHT
    if (present(width)) node%width = max(1.0, width)
    if (present(height)) node%height = max(1.0, height)

    is_enabled = .true.
    if (present(enabled)) is_enabled = enabled
    node%disabled = .not. is_enabled
    node%focusable = is_enabled

    if (is_enabled .and. input_activated(ctx%input, id)) then
        checked = .not. checked
        toggled = .true.
    end if
    node%checked = checked

    call decorate_from_input(ctx, node)
    call place_and_emit(ctx, node)
end function checkbox

logical function viewport(id, width, height, view_state) result(changed)
    character(*), intent(in) :: id
    real, intent(in) :: width, height
    type(view), intent(inout) :: view_state

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    integer :: scroll
    real :: old_sx, old_sy, old_x, old_y

    changed = .false.
    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%in_frame) return

    node%kind = UI_VIEWPORT
    node%id = trim(id)
    node%width = max(32.0, width)
    node%height = max(32.0, height)
    node%focusable = .true.

    call layout_get_cursor(node%x, node%y)
    call decorate_from_input(ctx, node)

    old_sx = view_state%scale_x
    old_sy = view_state%scale_y
    old_x = view_state%off_x
    old_y = view_state%off_y

    scroll = input_scroll_for(ctx%input, id)
    if (scroll /= 0) then
        view_state%scale_x = max(0.01, min(100.0, view_state%scale_x * (1.0 + 0.1 * real(scroll))))
        view_state%scale_y = max(0.01, min(100.0, view_state%scale_y * (1.0 + 0.1 * real(scroll))))
    end if

    if (input_active(ctx%input, id) .and. ctx%input%pointer_down) then
        view_state%off_x = view_state%off_x - ctx%input%pointer_dx / max(node%width * view_state%scale_x, 1.0)
        view_state%off_y = view_state%off_y - ctx%input%pointer_dy / max(node%height * view_state%scale_y, 1.0)
    end if

    changed = abs(view_state%scale_x - old_sx) > epsilon(1.0) .or. &
        abs(view_state%scale_y - old_sy) > epsilon(1.0) .or. &
        abs(view_state%off_x - old_x) > epsilon(1.0) .or. &
        abs(view_state%off_y - old_y) > epsilon(1.0)

    node%camera = view_state
    call emit_at_current_position(ctx, node)
end function viewport

subroutine decorate_from_input(ctx, node)
    type(fortui_context_t), intent(in) :: ctx
    type(ui_node_t), intent(inout) :: node

    call layout_get_cursor(node%x, node%y)
    node%hovered = input_hovered(ctx%input, node%x, node%y, node%width, node%height)
    node%focused = input_focused(ctx%input, node%id)
    node%active = input_active(ctx%input, node%id)
end subroutine decorate_from_input

subroutine place_and_emit(ctx, node)
    type(fortui_context_t), intent(inout) :: ctx
    type(ui_node_t), intent(inout) :: node

    call layout_get_cursor(node%x, node%y)
    if (node%focusable) call decorate_from_input(ctx, node)
    call emit_at_current_position(ctx, node)
end subroutine place_and_emit

subroutine emit_at_current_position(ctx, node)
    type(fortui_context_t), intent(inout) :: ctx
    type(ui_node_t), intent(in) :: node
    integer :: ignored

    ignored = ctx%current_frame%append(node)
    call layout_advance(node%width, node%height)
end subroutine emit_at_current_position

end module fortui_widgets
