module fortui_widgets
!! Backend-free immediate composition widgets.
use iso_fortran_env, only: int32
use fortui_context, only: fortui_context_t, get_default_context
use fortui_frame, only: ui_node_t, view, canvas_view_t, ui_layer_ref_t, ui_label_t, &
    UI_TEXT, UI_BUTTON, UI_SLIDER, UI_CHECKBOX, UI_VIEWPORT, UI_CANVAS, &
    UI_SCROLL_TEXT, UI_TEXT_INPUT, LAYER_POINTS, LAYER_LINES, SCROLL_PADDING, &
    SCROLLBAR_WIDTH, INPUT_PADDING
use fortui_layout, only: layout_get_cursor, layout_advance, layout_available
use fortui_input, only: input_activated, input_focused, input_active, input_hovered, &
    input_scroll_for, input_key_for, input_wheel_for, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, &
    KEY_ARROW_UP, KEY_ARROW_DOWN, KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, &
    KEY_ENTER, KEY_PAGE_UP, KEY_PAGE_DOWN
use fortui_canvas, only: canvas_events_t, canvas_to_world
use fortui_text, only: text_width, text_line_height, text_wrap, text_caret_from_x, &
    utf8_boundary, utf8_prev, utf8_next, TEXT_DEFAULT_SIZE
use fortui_error, only: report_error
implicit none
private

real, parameter :: CONTROL_HEIGHT = 32.0
real, parameter :: CONTROL_PADDING = 24.0

public :: text, button, slider, checkbox, viewport, view
public :: canvas_begin, canvas_end, canvas_points, canvas_lines, canvas_label
public :: scroll_text, text_input

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
    node%text_size = TEXT_DEFAULT_SIZE * scale
    node%width = text_width(trim(node%text), node%text_size)
    node%height = text_line_height(node%text_size)
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
    node%width = max(72.0, text_width(trim(node%text), node%text_size) + CONTROL_PADDING)
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
    node%width = max(72.0, text_width(trim(node%text), node%text_size) + 40.0)
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

subroutine canvas_begin(id, view_state, events, width, height, fill)
    !! Declare a custom-graphics canvas. Size defaults to the remaining space of
    !! the current container. Pointer events are reported in canvas coordinates.
    character(*), intent(in) :: id
    type(canvas_view_t), intent(in) :: view_state
    type(canvas_events_t), intent(out) :: events
    real, intent(in), optional :: width, height
    integer(int32), intent(in), optional :: fill

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    real :: aw, ah, wx, wy
    integer :: st
    logical :: active

    events = canvas_events_t()
    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%in_frame) return
    if (ctx%canvas_node /= 0) then
        call report_error("fortui_widgets", "canvas_begin", "nested canvas_begin")
        return
    end if

    node%kind = UI_CANVAS
    node%id = trim(id)
    node%focusable = .true.
    node%canvas_view = view_state
    node%fill = 0
    if (present(fill)) node%fill = fill
    call layout_get_cursor(node%x, node%y)
    call layout_available(aw, ah)
    node%width = aw
    node%height = ah
    if (present(width)) node%width = max(1.0, width)
    if (present(height)) node%height = max(1.0, height)
    call decorate_from_input(ctx, node)

    st = ctx%state(id)
    associate(inp => ctx%input, s => ctx%states(st))
        active = input_active(inp, id)
        events%width = node%width
        events%height = node%height
        events%hovered = node%hovered
        events%local_x = inp%pointer_x - node%x
        events%local_y = inp%pointer_y - node%y
        call canvas_to_world(view_state, events%local_x, events%local_y, &
            events%x, events%y)
        call canvas_to_world(view_state, inp%press_x - node%x, inp%press_y - node%y, &
            wx, wy)
        events%press_x = wx
        events%press_y = wy
        events%pressed = inp%pointer_pressed .and. active
        events%captured = active .and. inp%pointer_down
        events%dragging = events%captured .and. inp%drag_exceeded
        events%drag_started = events%dragging .and. .not. s%dragging
        events%released = inp%pointer_released .and. s%captured
        events%drag_ended = s%dragging .and. .not. events%dragging
        if (events%captured) then
            events%drag_dx = inp%pointer_dx
            events%drag_dy = inp%pointer_dy
        end if
        events%clicked = len_trim(inp%click_id) > 0 .and. trim(inp%click_id) == trim(id)
        events%double_clicked = len_trim(inp%double_click_id) > 0 .and. &
            trim(inp%double_click_id) == trim(id)
        events%wheel = input_wheel_for(inp, id)
        s%dragging = events%dragging
        s%captured = events%captured
    end associate

    node%layer_first = ctx%current_frame%layer_count + 1
    node%label_first = ctx%current_frame%label_count + 1
    ctx%canvas_node = ctx%current_frame%append(node)
    call layout_advance(node%width, node%height)
end subroutine canvas_begin

subroutine canvas_end(view_state)
    !! Close the canvas; an updated view (e.g. after wheel zoom) is recorded.
    type(canvas_view_t), intent(in), optional :: view_state
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) return
    if (ctx%canvas_node == 0) return
    if (present(view_state)) ctx%current_frame%nodes(ctx%canvas_node)%canvas_view = view_state
    ctx%canvas_node = 0
end subroutine canvas_end

logical function canvas_ready(ctx, proc)
    type(fortui_context_t), pointer, intent(in) :: ctx
    character(*), intent(in) :: proc

    canvas_ready = .false.
    if (.not. associated(ctx)) return
    if (.not. ctx%in_frame) return
    if (ctx%canvas_node == 0) then
        call report_error("fortui_widgets", proc, "called outside canvas_begin/canvas_end")
        return
    end if
    canvas_ready = .true.
end function canvas_ready

subroutine canvas_points(key, generation, xy, rgba, sizes, size, world_size, min_pixels)
    !! Retained point-sprite layer. Data is copied only when `generation` changes.
    !! xy(2,n) world positions; rgba(n) or rgba(1) packed colours (ui_rgba);
    !! sizes(n) diameters or uniform `size`; world_size scales sizes with zoom.
    character(*), intent(in) :: key
    integer, intent(in) :: generation
    real, intent(in) :: xy(:, :)
    integer(int32), intent(in) :: rgba(:)
    real, intent(in), optional :: sizes(:)
    real, intent(in), optional :: size
    logical, intent(in), optional :: world_size
    real, intent(in), optional :: min_pixels

    type(fortui_context_t), pointer :: ctx
    integer :: slot, n
    real :: uniform

    ctx => get_default_context()
    if (.not. canvas_ready(ctx, "canvas_points")) return
    slot = ctx%canvas%acquire(layer_key(ctx, key), LAYER_POINTS, ctx%frame_count)
    associate(l => ctx%canvas%layers(slot))
        if (.not. l%has_data .or. l%generation /= generation) then
            n = ubound(xy, 2)
            if (ubound(xy, 1) < 2) n = 0
            if (present(sizes)) n = min(n, ubound(sizes, 1))
            if (ubound(rgba, 1) < n .and. ubound(rgba, 1) /= 1) n = min(n, ubound(rgba, 1))
            if (ubound(rgba, 1) < 1) n = 0
            uniform = 4.0
            if (present(size)) uniform = size
            l%xy = xy(1:2, 1:n)
            if (present(sizes)) then
                l%sizes = sizes(1:n)
            else
                if (allocated(l%sizes)) deallocate(l%sizes)
                allocate(l%sizes(n), source=uniform)
            end if
            if (ubound(rgba, 1) >= n .and. n > 0) then
                l%rgba = rgba(1:n)
            else
                if (allocated(l%rgba)) deallocate(l%rgba)
                allocate(l%rgba(n), source=rgba(1))
            end if
            l%vertex_count = n
            l%generation = generation
            l%has_data = .true.
        end if
        l%world_size = .true.
        if (present(world_size)) l%world_size = world_size
        l%min_pixels = 1.0
        if (present(min_pixels)) l%min_pixels = max(0.0, min_pixels)
        call add_layer_ref(ctx, slot)
    end associate
end subroutine canvas_points

subroutine canvas_lines(key, generation, xy, rgba, segments, segment_generation, width)
    !! Retained indexed line layer: vertices xy(2,nv) with per-vertex colours
    !! rgba(nv) (or rgba(1)), and 1-based vertex pairs segments(2,ns).
    !! Vertices re-upload when `generation` changes; segment indices only when
    !! `segment_generation` (default: generation) changes.
    character(*), intent(in) :: key
    integer, intent(in) :: generation
    real, intent(in) :: xy(:, :)
    integer(int32), intent(in) :: rgba(:)
    integer, intent(in) :: segments(:, :)
    integer, intent(in), optional :: segment_generation
    real, intent(in), optional :: width

    type(fortui_context_t), pointer :: ctx
    integer :: slot, n, ns, sgen

    ctx => get_default_context()
    if (.not. canvas_ready(ctx, "canvas_lines")) return
    sgen = generation
    if (present(segment_generation)) sgen = segment_generation
    slot = ctx%canvas%acquire(layer_key(ctx, key), LAYER_LINES, ctx%frame_count)
    associate(l => ctx%canvas%layers(slot))
        if (.not. l%has_data .or. l%generation /= generation) then
            n = ubound(xy, 2)
            if (ubound(xy, 1) < 2 .or. ubound(rgba, 1) < 1) n = 0
            if (ubound(rgba, 1) < n .and. ubound(rgba, 1) /= 1) n = min(n, ubound(rgba, 1))
            l%xy = xy(1:2, 1:n)
            if (ubound(rgba, 1) >= n .and. n > 0) then
                l%rgba = rgba(1:n)
            else
                if (allocated(l%rgba)) deallocate(l%rgba)
                allocate(l%rgba(n), source=rgba(1))
            end if
            l%vertex_count = n
            l%generation = generation
        end if
        if (.not. l%has_data .or. l%index_generation /= sgen) then
            ns = ubound(segments, 2)
            if (ubound(segments, 1) < 2) ns = 0
            if (ns > 0) then
                if (any(segments(1:2, 1:ns) < 1) .or. &
                    any(segments(1:2, 1:ns) > l%vertex_count)) then
                    call report_error("fortui_widgets", "canvas_lines", &
                        "segment index outside vertex range; segments dropped")
                    ns = 0
                end if
            end if
            if (allocated(l%indices)) deallocate(l%indices)
            allocate(l%indices(2 * ns))
            if (ns > 0) l%indices = int(reshape(segments(1:2, 1:ns), [2 * ns]) - 1, int32)
            l%index_count = 2 * ns
            l%index_generation = sgen
        end if
        l%has_data = .true.
        l%line_width = 1.0
        if (present(width)) l%line_width = max(1.0, width)
        call add_layer_ref(ctx, slot)
    end associate
end subroutine canvas_lines

subroutine canvas_label(x, y, value, size, rgba)
    !! Text label centred horizontally below world point (x, y), at a fixed
    !! logical size. Intended for a bounded set (e.g. the top-N visible labels).
    real, intent(in) :: x, y
    character(*), intent(in) :: value
    real, intent(in), optional :: size
    integer(int32), intent(in), optional :: rgba

    type(fortui_context_t), pointer :: ctx
    type(ui_label_t) :: label
    integer :: ignored

    ctx => get_default_context()
    if (.not. canvas_ready(ctx, "canvas_label")) return
    label%x = x
    label%y = y
    label%text = value
    if (present(size)) label%size = max(1.0, size)
    if (present(rgba)) label%rgba = rgba
    ignored = ctx%current_frame%append_label(label)
    associate(node => ctx%current_frame%nodes(ctx%canvas_node))
        node%label_count = node%label_count + 1
    end associate
end subroutine canvas_label

function layer_key(ctx, key) result(full)
    type(fortui_context_t), intent(in) :: ctx
    character(*), intent(in) :: key
    character(len=:), allocatable :: full
    full = trim(ctx%current_frame%nodes(ctx%canvas_node)%id) // "/" // trim(key)
end function layer_key

subroutine add_layer_ref(ctx, slot)
    type(fortui_context_t), intent(inout) :: ctx
    integer, intent(in) :: slot
    type(ui_layer_ref_t) :: ref
    integer :: ignored

    associate(l => ctx%canvas%layers(slot))
        ref%key = l%key
        ref%kind = l%kind
        ref%slot = slot
        ref%generation = l%generation
        ref%index_generation = l%index_generation
        ref%vertex_count = l%vertex_count
        ref%index_count = l%index_count
    end associate
    ignored = ctx%current_frame%append_layer(ref)
    associate(node => ctx%current_frame%nodes(ctx%canvas_node))
        node%layer_count = node%layer_count + 1
    end associate
end subroutine add_layer_ref

subroutine scroll_text(id, value, width, height, text_size, markdown, scroll_to)
    !! Scrollable, word-wrapped multi-line UTF-8 text (wheel, scrollbar drag,
    !! arrow/page keys when focused). Size defaults to the remaining space.
    !! The scroll offset is UI-local; it resets to the top when `value` changes.
    character(*), intent(in) :: id
    character(*), intent(in) :: value
    real, intent(in), optional :: width, height, text_size
    logical, intent(in), optional :: markdown
    real, intent(in), optional :: scroll_to

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    real :: aw, ah, wrap_width, line_h, max_scroll
    integer :: st, k
    logical :: md, active, text_changed

    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%in_frame) return

    node%kind = UI_SCROLL_TEXT
    node%id = trim(id)
    node%focusable = .true.
    node%text_size = TEXT_DEFAULT_SIZE
    if (present(text_size)) node%text_size = max(4.0, text_size)
    md = .false.
    if (present(markdown)) md = markdown
    call layout_get_cursor(node%x, node%y)
    call layout_available(aw, ah)
    node%width = aw
    node%height = ah
    if (present(width)) node%width = max(1.0, width)
    if (present(height)) node%height = max(1.0, height)
    call decorate_from_input(ctx, node)

    st = ctx%state(id)
    associate(s => ctx%states(st), inp => ctx%input)
        wrap_width = max(1.0, node%width - 2.0 * SCROLL_PADDING - SCROLLBAR_WIDTH)
        text_changed = .not. allocated(s%cache_text)
        if (.not. text_changed) text_changed = len(s%cache_text) /= len(value)
        if (.not. text_changed) text_changed = s%cache_text /= value
        if (text_changed .or. abs(s%cache_width - wrap_width) > 1.0e-3 .or. &
            abs(s%cache_size - node%text_size) > 1.0e-3 .or. &
            (s%cache_markdown .neqv. md)) then
            call text_wrap(value, wrap_width, node%text_size, md, s%cache_lines, &
                s%cache_count, s%cache_height)
            s%cache_width = wrap_width
            s%cache_size = node%text_size
            s%cache_markdown = md
            s%wraps = s%wraps + 1
            if (text_changed) then
                s%cache_text = value
                s%scroll = 0.0
            end if
        end if

        line_h = text_line_height(node%text_size)
        s%scroll = s%scroll - input_wheel_for(inp, id) * 3.0 * line_h
        active = input_active(inp, id)
        if (active .and. inp%pointer_pressed .and. &
            inp%pointer_x >= node%x + node%width - SCROLLBAR_WIDTH) then
            s%dragging = .true.
            s%anchor = s%scroll
        end if
        if (s%dragging .and. active .and. inp%pointer_down) then
            s%scroll = s%anchor + (inp%pointer_y - inp%press_y) * &
                (s%cache_height + 2.0 * SCROLL_PADDING) / max(node%height, 1.0)
        else
            s%dragging = .false.
        end if
        if (node%focused) then
            do k = 1, inp%key_count
                select case (inp%keys(k))
                case (KEY_ARROW_UP); s%scroll = s%scroll - line_h
                case (KEY_ARROW_DOWN); s%scroll = s%scroll + line_h
                case (KEY_PAGE_UP); s%scroll = s%scroll - node%height
                case (KEY_PAGE_DOWN); s%scroll = s%scroll + node%height
                case (KEY_HOME); s%scroll = 0.0
                case (KEY_END); s%scroll = huge(1.0)
                end select
            end do
        end if
        if (present(scroll_to)) s%scroll = scroll_to
        max_scroll = max(0.0, s%cache_height + 2.0 * SCROLL_PADDING - node%height)
        s%scroll = max(0.0, min(max_scroll, s%scroll))

        node%body = value
        node%lines = s%cache_lines(1:s%cache_count)
        node%line_count = s%cache_count
        node%content_height = s%cache_height
        node%scroll = s%scroll
        node%markdown = md
    end associate
    call emit_at_current_position(ctx, node)
end subroutine scroll_text

logical function text_input(id, value, width, placeholder, submitted, enabled) &
    result(changed)
    !! Single-line UTF-8 text field. Focus by click or Tab; typing inserts at the
    !! caret; Backspace/Delete/Left/Right/Home/End edit; Enter sets `submitted`.
    !! Returns whether `value` changed in this frame. Width defaults to the
    !! remaining width of the current container.
    character(*), intent(in) :: id
    character(len=:), allocatable, intent(inout) :: value
    real, intent(in), optional :: width
    character(*), intent(in), optional :: placeholder
    logical, intent(out), optional :: submitted
    logical, intent(in), optional :: enabled

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    character(len=:), allocatable :: old
    real :: aw, ah
    integer :: st, k, c, i, done
    logical :: is_enabled, did_submit

    changed = .false.
    did_submit = .false.
    if (present(submitted)) submitted = .false.
    if (.not. allocated(value)) value = ""
    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%in_frame) return

    is_enabled = .true.
    if (present(enabled)) is_enabled = enabled
    node%kind = UI_TEXT_INPUT
    node%id = trim(id)
    node%focusable = is_enabled
    node%disabled = .not. is_enabled
    if (present(placeholder)) node%text = placeholder
    call layout_get_cursor(node%x, node%y)
    call layout_available(aw, ah)
    node%width = max(40.0, aw)
    if (present(width)) node%width = max(1.0, width)
    node%height = CONTROL_HEIGHT
    call decorate_from_input(ctx, node)

    old = value
    st = ctx%state(id)
    associate(s => ctx%states(st), inp => ctx%input)
        c = utf8_boundary(value, s%caret)
        if (is_enabled .and. node%focused) then
            if (input_active(inp, id) .and. inp%pointer_pressed) then
                c = text_caret_from_x(value, node%text_size, &
                    inp%pointer_x - node%x - INPUT_PADDING)
            end if
            done = 0
            do k = 1, inp%key_count
                call insert_typed(inp%key_text_pos(k))
                select case (inp%keys(k))
                case (KEY_BACKSPACE)
                    i = utf8_prev(value, c)
                    value = value(1:i) // value(c + 1:)
                    c = i
                case (KEY_DELETE)
                    i = utf8_next(value, c)
                    value = value(1:c) // value(i + 1:)
                case (KEY_ARROW_LEFT); c = utf8_prev(value, c)
                case (KEY_ARROW_RIGHT); c = utf8_next(value, c)
                case (KEY_HOME); c = 0
                case (KEY_END); c = len(value)
                case (KEY_ENTER); did_submit = .true.
                end select
            end do
            call insert_typed(inp%text_len)
        end if
        s%caret = c
        node%caret = c
    end associate
    changed = len(old) /= len(value)
    if (.not. changed) changed = old /= value
    if (present(submitted)) submitted = did_submit
    node%body = value
    call emit_at_current_position(ctx, node)

contains

    subroutine insert_typed(upto)
        !! Insert typed bytes done+1..upto at the caret, skipping control bytes.
        integer, intent(in) :: upto
        integer :: j, byte

        do j = done + 1, upto
            byte = iachar(ctx%input%text(j:j))
            if (byte < 32 .or. byte == 127) cycle
            value = value(1:c) // ctx%input%text(j:j) // value(c + 1:)
            c = c + 1
        end do
        done = max(done, upto)
    end subroutine insert_typed

end function text_input

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
