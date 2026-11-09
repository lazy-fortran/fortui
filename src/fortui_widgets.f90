module fortui_widgets
!! Backend-free immediate composition widgets.
!!
!! Identity: a widget id is scoped by the enclosing containers that carry an id
!! (split_begin, column_begin(id=...)); `key=` distinguishes widgets created in a
!! loop. The resulting identity "scope/id#key" must be unique in a frame;
!! duplicates are reported and skipped. Static text needs no id.
!!
!! A widget that reports consumed input (activation, toggle, changed value,
!! canvas click) schedules one follow-up frame, so state changed by the inline
!! handler becomes visible without the application requesting a frame.
use iso_fortran_env, only: int32
use fortui_context, only: fortui_context_t, get_default_context
use fortui_frame, only: ui_node_t, canvas_view_t, ui_label_t, UI_TEXT, UI_BUTTON, &
    UI_SLIDER, UI_CHECKBOX, UI_TAB, UI_CANVAS, UI_SCROLL_TEXT, UI_TEXT_INPUT, &
    LAYER_VERTICES, SCROLL_PADDING, SCROLLBAR_WIDTH, INPUT_PADDING, CONTROL_PADDING, &
    style_size, style_weight
use fortui_layout, only: layout_get_cursor, layout_advance, layout_available, &
    layout_scope, layout_fill_width, layout_place
use fortui_input, only: input_activated, input_focused, input_active, input_hovered, &
    input_wheel_for, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN, &
    KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, KEY_ENTER, KEY_PAGE_UP, KEY_PAGE_DOWN
use fortui_canvas, only: canvas_events_t, canvas_to_world
use fortui_text, only: text_width, text_line_height, text_wrap, text_caret_from_x, &
    utf8_boundary, utf8_prev, utf8_next, ui_str, TEXT_DEFAULT_SIZE
use fortui_error, only: report_error
implicit none
private

real, parameter :: CONTROL_HEIGHT = 32.0
integer, parameter :: MAX_ID = 96

interface slider
    !! slider(id, lo, hi, value [, step, key, width, enabled]) for real or
    !! integer values; returns whether `value` changed.
    module procedure slider_real, slider_int
end interface slider

interface canvas_points
    !! Self-contained: canvas_points(key, generation, xy, rgba, ...).
    !! Shared vertices: canvas_points(key, vertices, rgba, ...).
    module procedure canvas_points_own, canvas_points_shared
end interface canvas_points

interface canvas_lines
    !! Self-contained: canvas_lines(key, generation, xy, rgba, segments, ...).
    !! Shared vertices: canvas_lines(key, vertices, segments, rgba, ...).
    module procedure canvas_lines_own, canvas_lines_shared
end interface canvas_lines

public :: text, button, slider, checkbox, tabs
public :: canvas_begin, canvas_end, canvas_vertices, canvas_points, canvas_lines
public :: canvas_label, scroll_text, text_input

contains

! --- identity --------------------------------------------------------------

function scoped_id(id, key) result(full)
    !! "scope/id" or "scope/id#key" (at most MAX_ID characters).
    character(*), intent(in) :: id
    integer, intent(in), optional :: key
    character(len=:), allocatable :: full, scope

    scope = layout_scope()
    if (len(scope) > 0) then
        full = scope // "/" // trim(id)
    else
        full = trim(id)
    end if
    if (present(key)) full = full // "#" // ui_str(key)
    if (len(full) > MAX_ID) full = full(1:MAX_ID)
end function scoped_id

logical function claim(ctx, full, proc)
    !! Whether `full` is still unused in the current frame (else reported).
    type(fortui_context_t), intent(inout) :: ctx
    character(*), intent(in) :: full, proc

    claim = ctx%current_frame%find(full) == 0
    if (.not. claim) call ctx%report_duplicate(full, proc)
end function claim

logical function composing(ctx)
    type(fortui_context_t), pointer, intent(in) :: ctx
    composing = associated(ctx)
    if (composing) composing = ctx%in_frame
end function composing

real function resolve_width(width, natural) result(w)
    !! Explicit width, UI_FILL (remaining container width) or the natural width.
    real, intent(in), optional :: width
    real, intent(in) :: natural

    w = natural
    if (.not. present(width)) return
    if (width < 0.0) then
        w = layout_fill_width()
    else
        w = width
    end if
end function resolve_width

! --- static and simple controls ------------------------------------------------

subroutine text(value, style, size, width, ellipsis, id, tone)
    !! Static text. `style` is a token (UI_BODY default, UI_CAPTION, UI_HEADING,
    !! UI_TITLE, UI_CODE); `tone` a UI_TONE_* token for its colour; `size`
    !! overrides its logical size. With `ellipsis`, text wider than `width`
    !! (default: the remaining container width) is shortened with an ellipsis by
    !! the backend. `id` is only needed for later reference.
    character(*), intent(in) :: value
    integer, intent(in), optional :: style
    real, intent(in), optional :: size, width
    logical, intent(in), optional :: ellipsis
    character(*), intent(in), optional :: id
    integer, intent(in), optional :: tone

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node

    ctx => get_default_context()
    if (.not. composing(ctx)) return

    node%kind = UI_TEXT
    if (present(tone)) node%tone = tone
    if (present(id)) then
        node%id = scoped_id(id)
        if (.not. claim(ctx, trim(node%id), "text")) return
    end if
    node%text = value
    if (present(style)) node%style = style
    node%text_size = style_size(node%style)
    if (present(size)) node%text_size = max(1.0, size)
    node%width = resolve_width(width, &
        text_width(value, node%text_size, style_weight(node%style)))
    if (present(ellipsis)) node%ellipsis = ellipsis
    if (node%ellipsis .and. .not. present(width)) &
        node%width = min(node%width, layout_fill_width())
    node%height = text_line_height(node%text_size)
    call place_and_emit(ctx, node)
end subroutine text

logical function button(id, label, key, width, height, enabled, ellipsis, size) &
    result(clicked)
    !! Push button; true once when activated (pointer release or Enter/Space).
    !! `size` is the logical text size of the label.
    character(*), intent(in) :: id
    character(*), intent(in), optional :: label
    integer, intent(in), optional :: key
    real, intent(in), optional :: width, height, size
    logical, intent(in), optional :: enabled, ellipsis

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node

    clicked = .false.
    ctx => get_default_context()
    if (.not. composing(ctx)) return

    node%kind = UI_BUTTON
    node%id = scoped_id(id, key)
    if (.not. claim(ctx, trim(node%id), "button")) return
    node%text = trim(id)
    if (present(label)) node%text = label
    if (present(size)) node%text_size = max(1.0, size)
    node%width = resolve_width(width, max(72.0, text_width(trim(node%text), &
        node%text_size) + 2.0 * CONTROL_PADDING))
    node%height = CONTROL_HEIGHT
    if (present(height)) node%height = max(0.0, height)
    if (present(ellipsis)) node%ellipsis = ellipsis
    call set_enabled(node, enabled)

    call decorate_from_input(ctx, node)
    if (.not. node%disabled) clicked = input_activated(ctx%input, trim(node%id))
    if (clicked) ctx%followup = .true.
    call place_and_emit(ctx, node)
end function button

logical function checkbox(id, checked, label, key, width, enabled) result(toggled)
    !! Checkbox bound to the caller's `checked`; true when toggled this frame.
    character(*), intent(in) :: id
    logical, intent(inout) :: checked
    character(*), intent(in), optional :: label
    integer, intent(in), optional :: key
    real, intent(in), optional :: width
    logical, intent(in), optional :: enabled

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node

    toggled = .false.
    ctx => get_default_context()
    if (.not. composing(ctx)) return

    node%kind = UI_CHECKBOX
    node%id = scoped_id(id, key)
    if (.not. claim(ctx, trim(node%id), "checkbox")) return
    if (present(label)) node%text = label
    node%width = resolve_width(width, max(72.0, text_width(trim(node%text), &
        node%text_size) + 40.0))
    node%height = CONTROL_HEIGHT
    call set_enabled(node, enabled)

    if (.not. node%disabled .and. input_activated(ctx%input, trim(node%id))) then
        checked = .not. checked
        toggled = .true.
        ctx%followup = .true.
    end if
    node%checked = checked

    call decorate_from_input(ctx, node)
    call place_and_emit(ctx, node)
end function checkbox

logical function slider_real(id, lo, hi, value, step, key, width, enabled) &
    result(changed)
    character(*), intent(in) :: id
    real, intent(in) :: lo, hi
    real, intent(inout) :: value
    real, intent(in), optional :: step
    integer, intent(in), optional :: key
    real, intent(in), optional :: width
    logical, intent(in), optional :: enabled
    real :: s

    s = 0.0
    if (present(step)) s = max(0.0, step)
    changed = slider_core(id, lo, hi, value, s, key, width, enabled)
end function slider_real

logical function slider_int(id, lo, hi, value, step, key, width, enabled) &
    result(changed)
    character(*), intent(in) :: id
    integer, intent(in) :: lo, hi
    integer, intent(inout) :: value
    integer, intent(in), optional :: step
    integer, intent(in), optional :: key
    real, intent(in), optional :: width
    logical, intent(in), optional :: enabled
    real :: r, s
    integer :: old

    s = 1.0
    if (present(step)) s = real(max(1, step))
    old = value
    r = real(value)
    changed = slider_core(id, real(lo), real(hi), r, s, key, width, enabled)
    value = nint(r)
    changed = value /= old
end function slider_int

logical function slider_core(id, lo_in, hi_in, value, step, key, width, enabled) &
    result(changed)
    !! Drag or arrow keys (when focused) move `value` within [lo, hi] in `step`
    !! increments (step 0: continuous drag, 1% per key press).
    character(*), intent(in) :: id
    real, intent(in) :: lo_in, hi_in, step
    real, intent(inout) :: value
    integer, intent(in), optional :: key
    real, intent(in), optional :: width
    logical, intent(in), optional :: enabled

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    real :: lo, hi, old_value, fraction, key_step
    integer :: k

    changed = .false.
    ctx => get_default_context()
    if (.not. composing(ctx)) return

    lo = min(lo_in, hi_in)
    hi = max(lo_in, hi_in)
    key_step = step
    if (key_step <= 0.0) key_step = 0.01 * (hi - lo)

    node%kind = UI_SLIDER
    node%id = scoped_id(id, key)
    if (.not. claim(ctx, trim(node%id), "slider")) return
    node%width = resolve_width(width, 200.0)
    node%height = CONTROL_HEIGHT
    call set_enabled(node, enabled)
    call decorate_from_input(ctx, node)

    old_value = value
    value = max(lo, min(hi, value))
    associate(inp => ctx%input)
        if (.not. node%disabled .and. node%active .and. inp%pointer_down) then
            fraction = (inp%pointer_x - node%x) / max(node%width, 1.0)
            fraction = max(0.0, min(1.0, fraction))
            value = lo + fraction * (hi - lo)
            if (step > 0.0) value = lo + real(nint((value - lo) / step)) * step
            value = max(lo, min(hi, value))
        end if
        if (.not. node%disabled .and. node%focused) then
            do k = 1, inp%key_count
                select case (inp%keys(k))
                case (KEY_ARROW_LEFT, KEY_ARROW_DOWN); value = max(lo, value - key_step)
                case (KEY_ARROW_RIGHT, KEY_ARROW_UP); value = min(hi, value + key_step)
                case (KEY_HOME); value = lo
                case (KEY_END); value = hi
                end select
            end do
        end if
    end associate

    changed = abs(value - old_value) > epsilon(1.0) * max(1.0, abs(old_value))
    if (changed) ctx%followup = .true.
    node%value = value
    node%min_value = lo
    node%max_value = hi
    call emit_at_current_position(ctx, node)
end function slider_core

logical function tabs(id, labels, selected, width, size) result(changed)
    !! Tab bar over `width`, or the remaining row/column width: one equal-width
    !! tab per label; `selected` (1-based) changes by click, Enter/Space or the arrow
    !! keys on a focused tab. Returns whether `selected` changed.
    character(*), intent(in) :: id
    character(*), intent(in) :: labels(:)
    integer, intent(inout) :: selected
    real, intent(in), optional :: width, size

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    real :: x0, y0, total, w
    integer :: k, n, old, j

    changed = .false.
    ctx => get_default_context()
    if (.not. composing(ctx)) return
    n = ubound(labels, 1) ! `size` is the text size argument here
    if (n == 0) return
    old = selected
    selected = max(1, min(n, selected))
    call layout_get_cursor(x0, y0)
    total = layout_fill_width()
    if (present(width)) total = max(0.0, width)
    w = total / real(n)

    do k = 1, n
        node = ui_node_t()
        node%kind = UI_TAB
        node%id = scoped_id(id, k)
        if (.not. claim(ctx, trim(node%id), "tabs")) cycle
        node%text = trim(labels(k))
        if (present(size)) node%text_size = max(1.0, size)
        node%x = x0 + real(k - 1) * w
        node%y = y0
        node%width = w
        node%height = CONTROL_HEIGHT
        node%focusable = .true.
        node%hovered = input_hovered(ctx%input, node%x, node%y, node%width, node%height)
        node%focused = input_focused(ctx%input, trim(node%id))
        node%active = input_active(ctx%input, trim(node%id))
        if (input_activated(ctx%input, trim(node%id))) selected = k
        if (node%focused) then
            do j = 1, ctx%input%key_count
                select case (ctx%input%keys(j))
                case (KEY_ARROW_LEFT); selected = max(1, selected - 1)
                case (KEY_ARROW_RIGHT); selected = min(n, selected + 1)
                end select
            end do
        end if
        j = ctx%current_frame%append(node)
    end do
    do k = 1, n
        j = ctx%current_frame%find(scoped_id(id, k))
        if (j > 0) ctx%current_frame%nodes(j)%checked = k == selected
    end do
    call layout_advance(total, CONTROL_HEIGHT)
    changed = selected /= old
    if (changed) ctx%followup = .true.
end function tabs

! --- canvas -----------------------------------------------------------------------

subroutine canvas_begin(id, view_state, events, width, height, fill)
    !! Declare a custom-graphics canvas. Size defaults to the remaining space of
    !! the current container. Pointer events are reported in canvas coordinates;
    !! a click or double click schedules a follow-up frame.
    character(*), intent(in) :: id
    type(canvas_view_t), intent(in) :: view_state
    type(canvas_events_t), intent(out) :: events
    real, intent(in), optional :: width, height
    integer(int32), intent(in), optional :: fill

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    character(len=:), allocatable :: full
    real :: aw, ah, wx, wy
    integer :: st
    logical :: active

    events = canvas_events_t()
    ctx => get_default_context()
    if (.not. composing(ctx)) return
    if (ctx%canvas_node /= 0) then
        call report_error("fortui_widgets", "canvas_begin", "nested canvas_begin")
        return
    end if

    full = scoped_id(id)
    if (.not. claim(ctx, full, "canvas_begin")) return
    node%kind = UI_CANVAS
    node%id = full
    node%focusable = .true.
    node%canvas_view = view_state
    if (present(fill)) node%fill = fill
    call layout_get_cursor(node%x, node%y)
    call layout_available(aw, ah)
    node%width = aw
    node%height = ah
    if (present(width)) node%width = max(1.0, width)
    if (present(height)) node%height = max(1.0, height)
    call decorate_from_input(ctx, node)

    st = ctx%state(full)
    associate(inp => ctx%input, s => ctx%states(st))
        active = input_active(inp, full)
        events%width = node%width
        events%height = node%height
        events%hovered = node%hovered
        events%pointer_slop = inp%pointer_slop
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
        events%clicked = len_trim(inp%click_id) > 0 .and. trim(inp%click_id) == full
        events%double_clicked = len_trim(inp%double_click_id) > 0 .and. &
            trim(inp%double_click_id) == full
        events%wheel = input_wheel_for(inp, full)
        s%dragging = events%dragging
        s%captured = events%captured
    end associate
    if (events%clicked .or. events%double_clicked) ctx%followup = .true.

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
    if (.not. composing(ctx)) return
    if (ctx%canvas_node == 0) then
        call report_error("fortui_widgets", "canvas_end", &
            "canvas_end without canvas_begin")
        return
    end if
    if (present(view_state)) ctx%current_frame%nodes(ctx%canvas_node)%canvas_view = &
        view_state
    ctx%canvas_node = 0
end subroutine canvas_end

logical function canvas_ready(ctx, proc)
    type(fortui_context_t), pointer, intent(in) :: ctx
    character(*), intent(in) :: proc

    canvas_ready = .false.
    if (.not. composing(ctx)) return
    if (ctx%canvas_node == 0) then
        call report_error("fortui_widgets", proc, &
            "called outside canvas_begin/canvas_end")
        return
    end if
    canvas_ready = .true.
end function canvas_ready

function layer_key(ctx, key) result(full)
    type(fortui_context_t), intent(in) :: ctx
    character(*), intent(in) :: key
    character(len=:), allocatable :: full
    full = trim(ctx%current_frame%nodes(ctx%canvas_node)%id) // "/" // trim(key)
end function layer_key

subroutine canvas_vertices(key, generation, xy)
    !! Shared vertex layer: world positions xy(2,n), copied only when
    !! `generation` changes. Point and line layers reference it by `key`.
    character(*), intent(in) :: key
    integer, intent(in) :: generation
    real, intent(in) :: xy(:, :)

    type(fortui_context_t), pointer :: ctx
    integer :: slot

    ctx => get_default_context()
    if (.not. canvas_ready(ctx, "canvas_vertices")) return
    slot = ctx%canvas%submit_vertices(layer_key(ctx, key), generation, xy, &
        ctx%frame_count)
end subroutine canvas_vertices

integer function vertex_slot(ctx, vertices, proc) result(slot)
    !! Slot of the vertex layer `vertices` submitted earlier in this frame.
    type(fortui_context_t), intent(in) :: ctx
    character(*), intent(in) :: vertices, proc

    slot = ctx%canvas%lookup(layer_key(ctx, vertices))
    if (slot > 0) then
        if (ctx%canvas%layers(slot)%kind /= LAYER_VERTICES .or. &
            ctx%canvas%layers(slot)%last_frame /= ctx%frame_count) slot = 0
    end if
    if (slot == 0) call report_error("fortui_widgets", proc, "vertex layer '" // &
        trim(vertices) // "' was not declared by canvas_vertices in this canvas")
end function vertex_slot

subroutine canvas_points_own(key, generation, xy, rgba, sizes, size, world_size, &
    min_pixels)
    !! Retained point-sprite layer with its own positions xy(2,n); data is copied
    !! only when `generation` changes. rgba(n) or rgba(1) packed colours
    !! (ui_rgba); sizes(n) diameters or uniform `size`; world_size scales sizes
    !! with zoom; min_pixels is the smallest drawn diameter.
    character(*), intent(in) :: key
    integer, intent(in) :: generation
    real, intent(in) :: xy(:, :)
    integer(int32), intent(in) :: rgba(:)
    real, intent(in), optional :: sizes(:)
    real, intent(in), optional :: size
    logical, intent(in), optional :: world_size
    real, intent(in), optional :: min_pixels

    type(fortui_context_t), pointer :: ctx
    integer :: vslot, slot

    ctx => get_default_context()
    if (.not. canvas_ready(ctx, "canvas_points")) return
    vslot = ctx%canvas%submit_vertices(layer_key(ctx, key) // "@xy", generation, xy, &
        ctx%frame_count)
    if (vslot == 0) return
    slot = ctx%canvas%submit_points(layer_key(ctx, key), vslot, generation, rgba, &
        sizes, size, ctx%frame_count)
    call finish_points(ctx, slot, world_size, min_pixels)
end subroutine canvas_points_own

subroutine canvas_points_shared(key, vertices, rgba, sizes, size, world_size, &
    min_pixels, generation)
    !! Point layer drawing the shared vertex layer `vertices`. Colours/sizes are
    !! copied when `generation` (default: the vertex generation) or the vertex
    !! count changes.
    character(*), intent(in) :: key, vertices
    integer(int32), intent(in) :: rgba(:)
    real, intent(in), optional :: sizes(:)
    real, intent(in), optional :: size
    logical, intent(in), optional :: world_size
    real, intent(in), optional :: min_pixels
    integer, intent(in), optional :: generation

    type(fortui_context_t), pointer :: ctx
    integer :: vslot, slot, gen

    ctx => get_default_context()
    if (.not. canvas_ready(ctx, "canvas_points")) return
    vslot = vertex_slot(ctx, vertices, "canvas_points")
    if (vslot == 0) return
    gen = ctx%canvas%layers(vslot)%generation
    if (present(generation)) gen = generation
    slot = ctx%canvas%submit_points(layer_key(ctx, key), vslot, gen, rgba, sizes, &
        size, ctx%frame_count)
    call finish_points(ctx, slot, world_size, min_pixels)
end subroutine canvas_points_shared

subroutine finish_points(ctx, slot, world_size, min_pixels)
    type(fortui_context_t), intent(inout) :: ctx
    integer, intent(in) :: slot
    logical, intent(in), optional :: world_size
    real, intent(in), optional :: min_pixels

    if (slot == 0) return
    associate(l => ctx%canvas%layers(slot))
        l%world_size = .true.
        if (present(world_size)) l%world_size = world_size
        l%min_pixels = 1.0
        if (present(min_pixels)) l%min_pixels = max(0.0, min_pixels)
    end associate
    call add_layer_ref(ctx, slot)
end subroutine finish_points

subroutine canvas_lines_own(key, generation, xy, rgba, segments, segment_generation, &
    width)
    !! Retained indexed line layer with its own vertices xy(2,nv), per-vertex
    !! colours rgba(nv) (or rgba(1)) and 1-based vertex pairs segments(2,ns).
    !! Vertices/colours are copied when `generation` changes; segments when
    !! `segment_generation` (default: generation) or the vertex count changes.
    character(*), intent(in) :: key
    integer, intent(in) :: generation
    real, intent(in) :: xy(:, :)
    integer(int32), intent(in) :: rgba(:)
    integer, intent(in) :: segments(:, :)
    integer, intent(in), optional :: segment_generation
    real, intent(in), optional :: width

    type(fortui_context_t), pointer :: ctx
    integer :: vslot, slot, sgen

    ctx => get_default_context()
    if (.not. canvas_ready(ctx, "canvas_lines")) return
    sgen = generation
    if (present(segment_generation)) sgen = segment_generation
    vslot = ctx%canvas%submit_vertices(layer_key(ctx, key) // "@xy", generation, xy, &
        ctx%frame_count)
    if (vslot == 0) return
    slot = ctx%canvas%submit_lines(layer_key(ctx, key), vslot, generation, rgba, sgen, &
        segments, ctx%frame_count)
    call finish_lines(ctx, slot, width)
end subroutine canvas_lines_own

subroutine canvas_lines_shared(key, vertices, segments, rgba, generation, width)
    !! Line layer over the shared vertex layer `vertices`: 1-based vertex pairs
    !! segments(2,ns) and per-vertex colours rgba(n) or rgba(1). Both are copied
    !! when `generation` (default: the vertex generation) or the vertex count
    !! changes; segments outside the vertex range are dropped and reported.
    character(*), intent(in) :: key, vertices
    integer, intent(in) :: segments(:, :)
    integer(int32), intent(in) :: rgba(:)
    integer, intent(in), optional :: generation
    real, intent(in), optional :: width

    type(fortui_context_t), pointer :: ctx
    integer :: vslot, slot, gen

    ctx => get_default_context()
    if (.not. canvas_ready(ctx, "canvas_lines")) return
    vslot = vertex_slot(ctx, vertices, "canvas_lines")
    if (vslot == 0) return
    gen = ctx%canvas%layers(vslot)%generation
    if (present(generation)) gen = generation
    slot = ctx%canvas%submit_lines(layer_key(ctx, key), vslot, gen, rgba, gen, &
        segments, ctx%frame_count)
    call finish_lines(ctx, slot, width)
end subroutine canvas_lines_shared

subroutine finish_lines(ctx, slot, width)
    type(fortui_context_t), intent(inout) :: ctx
    integer, intent(in) :: slot
    real, intent(in), optional :: width

    if (slot == 0) return
    ctx%canvas%layers(slot)%line_width = 1.0
    if (present(width)) ctx%canvas%layers(slot)%line_width = max(1.0, width)
    call add_layer_ref(ctx, slot)
end subroutine finish_lines

subroutine add_layer_ref(ctx, slot)
    type(fortui_context_t), intent(inout) :: ctx
    integer, intent(in) :: slot
    integer :: ignored

    ignored = ctx%current_frame%append_layer(ctx%canvas%ref(slot))
    associate(node => ctx%current_frame%nodes(ctx%canvas_node))
        node%layer_count = node%layer_count + 1
    end associate
end subroutine add_layer_ref

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

! --- text views -----------------------------------------------------------------------

subroutine scroll_text(id, value, size, markdown, width, height, scroll_to)
    !! Scrollable, word-wrapped multi-line UTF-8 text (wheel, scrollbar drag,
    !! arrow/page keys when focused). Size defaults to the remaining space.
    !! The scroll offset is UI-local; it resets to the top when `value` changes.
    character(*), intent(in) :: id
    character(*), intent(in) :: value
    real, intent(in), optional :: size
    logical, intent(in), optional :: markdown
    real, intent(in), optional :: width, height
    real, intent(in), optional :: scroll_to

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    real :: aw, ah, wrap_width, line_h, max_scroll
    integer :: st, k
    logical :: md, active, text_changed

    ctx => get_default_context()
    if (.not. composing(ctx)) return

    node%kind = UI_SCROLL_TEXT
    node%id = scoped_id(id)
    if (.not. claim(ctx, trim(node%id), "scroll_text")) return
    node%focusable = .true.
    node%text_size = TEXT_DEFAULT_SIZE
    if (present(size)) node%text_size = max(4.0, size)
    md = .false.
    if (present(markdown)) md = markdown
    call layout_get_cursor(node%x, node%y)
    call layout_available(aw, ah)
    node%width = aw
    node%height = ah
    if (present(width)) node%width = resolve_width(width, aw)
    if (present(height)) node%height = max(1.0, height)
    call decorate_from_input(ctx, node)

    st = ctx%state(trim(node%id))
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
        s%scroll = s%scroll - input_wheel_for(inp, trim(node%id)) * 3.0 * line_h
        active = node%active
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

logical function text_input(id, value, placeholder, submitted, width, enabled, key, &
    size) &
    result(changed)
    !! Single-line UTF-8 text field. Focus by click or Tab; typing inserts at the
    !! caret; Backspace/Delete/Left/Right/Home/End edit; Enter sets `submitted`;
    !! Escape leaves the field. Each edit commits to `value` (no draft session).
    !! Returns whether `value` changed in this frame. Width defaults to the
    !! remaining width of the current container.
    character(*), intent(in) :: id
    character(len=:), allocatable, intent(inout) :: value
    character(*), intent(in), optional :: placeholder
    logical, intent(out), optional :: submitted
    real, intent(in), optional :: width, size
    logical, intent(in), optional :: enabled
    integer, intent(in), optional :: key

    type(fortui_context_t), pointer :: ctx
    type(ui_node_t) :: node
    character(len=:), allocatable :: old
    integer :: st, k, c, i, done
    logical :: did_submit

    changed = .false.
    did_submit = .false.
    if (present(submitted)) submitted = .false.
    if (.not. allocated(value)) value = ""
    ctx => get_default_context()
    if (.not. composing(ctx)) return

    node%kind = UI_TEXT_INPUT
    node%id = scoped_id(id, key)
    if (.not. claim(ctx, trim(node%id), "text_input")) return
    call set_enabled(node, enabled)
    if (present(placeholder)) node%text = placeholder
    node%width = max(40.0, resolve_width(width, layout_fill_width()))
    node%height = CONTROL_HEIGHT
    if (present(size)) node%text_size = max(1.0, size)
    call decorate_from_input(ctx, node)

    old = value
    st = ctx%state(trim(node%id))
    associate(s => ctx%states(st), inp => ctx%input)
        c = utf8_boundary(value, s%caret)
        if (.not. node%disabled .and. node%focused) then
            if (node%active .and. inp%pointer_pressed) then
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
    if (changed .or. did_submit) ctx%followup = .true.
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

! --- helpers --------------------------------------------------------------------------

subroutine set_enabled(node, enabled)
    type(ui_node_t), intent(inout) :: node
    logical, intent(in), optional :: enabled
    node%disabled = .false.
    if (present(enabled)) node%disabled = .not. enabled
    node%focusable = .not. node%disabled
end subroutine set_enabled

subroutine decorate_from_input(ctx, node)
    type(fortui_context_t), intent(in) :: ctx
    type(ui_node_t), intent(inout) :: node

    call layout_place(node%height, node%x, node%y)
    node%hovered = input_hovered(ctx%input, node%x, node%y, node%width, node%height)
    if (len_trim(node%id) == 0 .or. node%disabled) return
    node%focused = input_focused(ctx%input, trim(node%id))
    node%active = input_active(ctx%input, trim(node%id))
end subroutine decorate_from_input

subroutine place_and_emit(ctx, node)
    type(fortui_context_t), intent(inout) :: ctx
    type(ui_node_t), intent(inout) :: node

    call layout_place(node%height, node%x, node%y)
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
