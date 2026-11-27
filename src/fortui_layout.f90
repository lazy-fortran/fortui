module fortui_layout
    !! Immediate composition layout state in backend-neutral logical units, plus
    !! identity scopes: a container with an id prefixes the ids of widgets inside.
    use fortui_error, only: report_error
    use fortui_text, only: utf8_boundary, text_hash
    implicit none
    private

    integer, parameter :: MAX_LAYOUT_DEPTH = 32
    integer, parameter :: MAX_PANES = 3
    integer, parameter :: DIR_COLUMN = 1
    integer, parameter :: DIR_ROW = 2
    integer, parameter :: KIND_ROOT = 0
    integer, parameter :: KIND_COLUMN = 1
    integer, parameter :: KIND_ROW = 2
    integer, parameter :: KIND_SPLIT = 3
    integer, parameter :: KIND_PANE = 4
    integer, parameter :: KIND_DIALOG = 5
    integer, parameter :: KIND_SCROLL = 6
    integer, parameter :: KIND_POPUP = 7
    integer, parameter :: KIND_TOASTS = 8
    character(len=*), parameter :: KIND_NAMES(0:8) = [character(len=6) :: "root", &
        "column", "row", "split", "pane", "dialog", "scroll", "popup", "toasts"]

    ! Layers of nodes, painted and hit in this order from the top: modal
    ! dialogs, floating popups and notifications, the page.
    integer, parameter :: LAYER_PAGE = 0, LAYER_FLOAT = 1, LAYER_MODAL = 2

    type :: layout_entry_t
        integer :: kind = KIND_ROOT
        ! Index of this container in the frame's box list (0: the page root).
        integer :: box = 0
        integer :: direction = DIR_COLUMN
        real :: gap = 0.0
        real :: origin_x = 0.0
        real :: origin_y = 0.0
        real :: cursor_x = 0.0
        real :: cursor_y = 0.0
        real :: max_cross = 0.0
        ! Rows with a fixed cross size centre shorter items in it (0: top-aligned).
        real :: cross_size = 0.0
        ! Wrapping rows: items that do not fit start a new line; the current
        ! line's top and height, and the widest line so far.
        logical :: wrap = .false.
        real :: line_h = 0.0
        real :: widest = 0.0
        integer :: item_count = 0
        ! Region available to this container (bounds for fill-remaining sizing).
        real :: region_x = 0.0
        real :: region_y = 0.0
        real :: region_w = 1.0e9
        real :: region_h = 1.0e9
        ! Split containers: pane x offsets/widths and the pane being composed.
        integer :: pane_count = 0
        integer :: pane = 0
        real :: pane_x(MAX_PANES) = 0.0
        real :: pane_w(MAX_PANES) = 0.0
        character(len=:), allocatable :: scope
        ! What nodes inside may show of themselves (x, y, w, h; w < 0: all) and
        ! their layer.
        real :: clip(4) = [0.0, 0.0, -1.0, -1.0]
        integer :: layer = LAYER_PAGE
        ! The height the container takes in its parent (scroll viewports;
        ! negative: its content), and whether it takes none (popups).
        real :: fixed_h = -1.0
        logical :: floating = .false.
    end type layout_entry_t

    type, public :: layout_box_t
        !! A container as hosts that lay out themselves (the browser) need it.
        real :: bounds(4) = 0.0
        integer :: kind = KIND_COLUMN
        integer :: parent = 0
        !! Nodes emitted before the container opened: its place among its
        !! parent's nodes.
        integer :: after = 0
        real :: gap = 0.0
        !! Fixed cross size of a row that centres its items (0: none).
        real :: cross = 0.0
        !! A row whose items continue on further lines when they do not fit.
        logical :: wrap = .false.
        !! Fixed width of a pane (negative: none).
        real :: width = -1.0
        !! The id the container was opened with (for page styles), or empty.
        character(len=64) :: id = ""
        !! A name the page styles by (data-look), or empty.
        character(len=32) :: look = ""
        !! The address of the container in the page (the HTML id), or empty.
        character(len=64) :: anchor = ""
        !! Scroll containers: viewport height, content height, offset, space
        !! before and after the composed part (virtual lists), whether the view
        !! follows the end and whether the host reports its offset.
        real :: viewport = -1.0, content = 0.0, offset = 0.0
        real :: pad_before = 0.0, pad_after = 0.0
        logical :: stick = .false., reports = .false.
        !! Dialogs: the accessible name.
        character(len=:), allocatable :: label
    end type layout_box_t

    type(layout_entry_t), save :: layout_stack(MAX_LAYOUT_DEPTH)
    type(layout_box_t), allocatable, save :: boxes(:)
    integer, save :: box_count = 0, nodes_emitted = 0
    integer, save :: stack_depth = 0

    ! Page addresses given in the frame being composed (open addressing; a free
    ! slot is blank), and the duplicates already reported.
    character(len=64), allocatable, save :: anchors(:)
    integer, save :: anchor_count = 0
    character(len=64), save :: anchors_told(16) = ""
    integer, save :: told_count = 0

    public :: layout_reset, layout_get_cursor, layout_advance, layout_depth, layout_place
    public :: column_begin, column_end, row_begin, row_end, dialog_begin, dialog_end
    public :: layout_available, split_begin, split_next, split_end
    public :: layout_scope, layout_fill_width, layout_check_balance
    public :: layout_boxes, layout_note_node
    public :: layout_marks
    public :: KIND_COLUMN, KIND_ROW, KIND_SPLIT, KIND_PANE, KIND_DIALOG, KIND_SCROLL, &
        KIND_POPUP, KIND_TOASTS
    public :: LAYER_PAGE, LAYER_FLOAT, LAYER_MODAL
    public :: scroll_region_begin, scroll_region_end, float_begin, float_end, layout_node_view
    public :: layout_set_padding

contains

    subroutine layout_reset(width, height, margin)
        !! Start a frame's layout in a window of `width` x `height`, keeping
        !! `margin` free on every side.
        real, intent(in), optional :: width, height, margin
        real :: m

        stack_depth = 1
        layout_stack(1) = layout_entry_t(direction=DIR_COLUMN, scope="")
        box_count = 0
        nodes_emitted = 0
        if (anchor_count > 0) anchors = ""
        anchor_count = 0
        m = 0.0
        if (present(margin)) m = max(0.0, margin)
        layout_stack(1)%origin_x = m
        layout_stack(1)%origin_y = m
        layout_stack(1)%cursor_x = m
        layout_stack(1)%cursor_y = m
        layout_stack(1)%region_x = m
        layout_stack(1)%region_y = m
        if (present(width)) layout_stack(1)%region_w = max(0.0, width - 2.0 * m)
        if (present(height)) layout_stack(1)%region_h = max(0.0, height - 2.0 * m)
    end subroutine layout_reset

    function layout_scope() result(scope)
        !! Identity scope of the current container ("" at the top level).
        character(len=:), allocatable :: scope
        scope = ""
        if (stack_depth < 1) return
        associate(e => layout_stack(stack_depth))
            if (allocated(e%scope)) scope = e%scope
        end associate
    end function layout_scope

    subroutine layout_check_balance()
        !! Report containers still open at frame end and recover by closing them
        !! (called when a frame is presented).
        integer :: i

        if (stack_depth <= 1) return
        do i = stack_depth, 2, -1
            call report_error("fortui_layout", "ui_present", "unclosed " // &
                trim(KIND_NAMES(layout_stack(i)%kind)) // " '" // layout_stack(i)%scope // &
                "' at frame end (missing *_end)")
        end do
        stack_depth = 1
    end subroutine layout_check_balance

    subroutine layout_available(width, height)
        !! Space from the cursor to the current container's region bounds.
        real, intent(out) :: width, height

        real :: x, y

        call layout_get_cursor(x, y)
        associate(e => layout_stack(stack_depth))
            width = max(0.0, e%region_x + e%region_w - x)
            height = max(0.0, e%region_y + e%region_h - y)
        end associate
    end subroutine layout_available

    real function layout_fill_width() result(width)
        !! Remaining width of the current container from the cursor.
        real :: height
        call layout_available(width, height)
    end function layout_fill_width

    subroutine split_begin(id, first, last, gap)
        !! Horizontal split of the remaining space into panes composed in order,
        !! separated by split_next: with `first` and `last`, three panes (fixed,
        !! filling, fixed); with one of them, two panes; with neither, two halves.
        !! Widths are logical units; `id` scopes the identities inside.
        character(*), intent(in) :: id
        real, intent(in), optional :: first, last, gap
        real :: x, y, w, h, g, a, b
        integer :: n

        g = 0.0
        if (present(gap)) g = max(0.0, gap)
        call layout_get_cursor(x, y)
        call layout_available(w, h)
        if (present(first) .and. present(last)) then
            n = 3
            a = max(0.0, min(first, w))
            b = max(0.0, min(last, w - a))
            call push_region(KIND_SPLIT, DIR_ROW, 0.0, x, y, w, h, id)
            call set_pane(1, x, a)
            call set_pane(2, x + a + g, max(0.0, w - a - b - 2.0 * g))
            call set_pane(3, x + w - b, b)
        else
            n = 2
            if (present(first)) then
                a = max(0.0, min(first, w))
            else if (present(last)) then
                a = max(0.0, w - g - max(0.0, last))
            else
                a = max(0.0, 0.5 * (w - g))
            end if
            call push_region(KIND_SPLIT, DIR_ROW, 0.0, x, y, w, h, id)
            call set_pane(1, x, a)
            call set_pane(2, x + a + g, max(0.0, w - a - g))
        end if
        boxes(layout_stack(stack_depth)%box)%gap = g
        layout_stack(stack_depth)%pane_count = n
        call open_pane(1)

    contains

        subroutine set_pane(k, px, pw)
            integer, intent(in) :: k
            real, intent(in) :: px, pw
            layout_stack(stack_depth)%pane_x(k) = px
            layout_stack(stack_depth)%pane_w(k) = pw
        end subroutine set_pane

    end subroutine split_begin

    subroutine open_pane(k)
        integer, intent(in) :: k
        real :: px, py, pw, ph
        character(len=:), allocatable :: scope

        associate(s => layout_stack(stack_depth))
            s%pane = k
            px = s%pane_x(k)
            pw = s%pane_w(k)
            py = s%region_y
            ph = s%region_h
            scope = s%scope
        end associate
        call push_region(KIND_PANE, DIR_COLUMN, 0.0, px, py, pw, ph, "")
        layout_stack(stack_depth)%scope = scope
    end subroutine open_pane

    subroutine split_next()
        !! Continue with the next pane of the innermost split.
        integer :: k

        if (.not. close_kind(KIND_PANE, "split_next")) return
        k = layout_stack(stack_depth)%pane + 1
        if (k > layout_stack(stack_depth)%pane_count) then
            call report_error("fortui_layout", "split_next", "split '" // &
                layout_stack(stack_depth)%scope // "' has no further pane")
            k = layout_stack(stack_depth)%pane_count
        end if
        call open_pane(k)
    end subroutine split_next

    subroutine split_end()
        real :: w, h

        if (.not. close_kind(KIND_PANE, "split_end")) return
        w = layout_stack(stack_depth)%region_w
        h = layout_stack(stack_depth)%region_h
        stack_depth = stack_depth - 1
        call layout_advance(w, h)
    end subroutine split_end

    logical function close_kind(kind, proc) result(ok)
        !! Pop the innermost container, which must be of `kind`. A pane closes into
        !! its split. Mismatches are reported; the innermost container is still closed.
        integer, intent(in) :: kind
        character(*), intent(in) :: proc

        ok = .false.
        if (stack_depth <= 1) then
            call report_error("fortui_layout", proc, "no open container")
            return
        end if
        if (layout_stack(stack_depth)%kind /= kind) then
            call report_error("fortui_layout", proc, "closes a " // &
                trim(KIND_NAMES(layout_stack(stack_depth)%kind)) // " ('" // &
                layout_stack(stack_depth)%scope // "')")
            if (kind /= KIND_PANE) then
                call pop_layout()
                return
            end if
            ! Unwind to the innermost pane so split_next/split_end stay usable.
            do while (stack_depth > 1 .and. layout_stack(stack_depth)%kind /= KIND_PANE)
                call pop_layout()
            end do
            if (stack_depth <= 1) return
        end if
        if (kind == KIND_PANE) then
            stack_depth = stack_depth - 1
        else
            call pop_layout()
        end if
        ok = .true.
    end function close_kind

    subroutine push_region(kind, direction, gap, x, y, w, h, id)
        integer, intent(in) :: kind, direction
        real, intent(in) :: gap, x, y, w, h
        character(*), intent(in) :: id
        character(len=:), allocatable :: scope

        if (stack_depth >= MAX_LAYOUT_DEPTH) &
            error stop "fortui: layout nesting exceeds MAX_LAYOUT_DEPTH"
        scope = layout_scope()
        if (len_trim(id) > 0) then
            if (len(scope) > 0) then
                scope = scope // "/" // trim(id)
            else
                scope = trim(id)
            end if
        end if
        if (.not. allocated(boxes)) allocate (boxes(64))
        if (box_count >= size(boxes)) boxes = [boxes, boxes]
        box_count = box_count + 1
        boxes(box_count) = layout_box_t(kind=kind, parent=layout_stack(stack_depth)%box, &
            after=nodes_emitted, gap=gap, id=id)
        if (kind == KIND_PANE) boxes(box_count)%width = w
        stack_depth = stack_depth + 1
        layout_stack(stack_depth) = layout_entry_t(kind=kind, direction=direction, &
            gap=gap, origin_x=x, origin_y=y, cursor_x=x, cursor_y=y, region_x=x, &
            region_y=y, region_w=w, region_h=h, scope=scope, box=box_count, &
            clip=layout_stack(stack_depth - 1)%clip, layer=layout_stack(stack_depth - 1)%layer)
    end subroutine push_region

    subroutine dialog_begin(id, width, height, gap, padding, label)
        !! A modal dialog centred in the remaining space; `label` is its
        !! accessible name. While one is open, only it takes the pointer.
        character(*), intent(in) :: id
        real, intent(in) :: width, height, gap, padding
        character(*), intent(in), optional :: label
        real :: x, y, aw, ah, w, h, pad
        call layout_get_cursor(x, y)
        call layout_available(aw, ah)
        w = min(width, aw)
        h = min(height, ah)
        pad = min(padding, min(w, h) * 0.05)
        x = x + max(0.0, (aw - w) * 0.5)
        y = y + max(0.0, (ah - h) * 0.5)
        call push_region(KIND_DIALOG, DIR_COLUMN, gap, x + pad, y + pad, &
            w - 2 * pad, h - 2 * pad, id)
        boxes(box_count)%bounds = [x, y, w, h]
        boxes(box_count)%width = w
        layout_stack(stack_depth)%layer = LAYER_MODAL
        layout_stack(stack_depth)%clip = [0.0, 0.0, -1.0, -1.0]
        if (present(label)) boxes(box_count)%label = label
    end subroutine

    subroutine dialog_end()
        logical :: ok
        ok = close_kind(KIND_DIALOG, "dialog_end")
    end subroutine

    subroutine column_begin(gap, id, look, anchor)
        !! Vertical container; `id` (optional) scopes the identities inside.
        !! `look` names the container for the page's styles and `anchor` is its
        !! address in the page (see `text`).
        real, intent(in), optional :: gap
        character(*), intent(in), optional :: id, look, anchor
        call push_layout(KIND_COLUMN, DIR_COLUMN, gap, id)
        call mark_box(look, anchor)
    end subroutine column_begin

    subroutine row_begin(gap, id, height, look, anchor, wrap)
        !! Horizontal container; `id` (optional) scopes the identities inside.
        !! Items align to the top; with `height`, the row is at least that tall
        !! and centres shorter items in it. With `wrap`, items that do not fit
        !! the available width continue on a further line (toolbars, chips).
        !! `look` names the container for the page's styles and `anchor` is its
        !! address in the page (see `text`).
        real, intent(in), optional :: gap, height
        character(*), intent(in), optional :: id, look, anchor
        logical, intent(in), optional :: wrap
        call push_layout(KIND_ROW, DIR_ROW, gap, id)
        call mark_box(look, anchor)
        if (present(height)) layout_stack(stack_depth)%cross_size = max(0.0, height)
        if (present(height)) boxes(layout_stack(stack_depth)%box)%cross = max(0.0, height)
        if (present(wrap)) then
            layout_stack(stack_depth)%wrap = wrap
            boxes(layout_stack(stack_depth)%box)%wrap = wrap
        end if
    end subroutine row_begin

    subroutine mark_box(look, anchor)
        !! Style name and page address of the container just opened.
        character(*), intent(in), optional :: look, anchor
        integer :: b

        b = layout_stack(stack_depth)%box
        call layout_marks(look, anchor, boxes(b)%look, boxes(b)%anchor)
    end subroutine mark_box

    subroutine layout_marks(look, anchor, look_name, anchor_name)
        !! Store the style name and the page address of an element, where given.
        !! An address another element of the frame already has is reported and
        !! left out, as two elements cannot share an HTML id.
        character(*), intent(in), optional :: look, anchor
        character(*), intent(inout) :: look_name, anchor_name

        if (present(look)) look_name = page_name(look, len(look_name))
        if (.not. present(anchor)) return
        anchor_name = page_name(anchor, len(anchor_name))
        if (.not. claim_anchor(anchor_name)) anchor_name = ""
    end subroutine layout_marks

    function page_name(value, limit) result(name)
        !! `value` without control characters (hosts and the HTML parser treat
        !! them differently), cut to whole UTF-8 characters within `limit` bytes.
        character(*), intent(in) :: value
        integer, intent(in) :: limit
        character(len=:), allocatable :: name
        character(len=len(value)) :: kept
        integer :: i, n, c

        n = 0
        do i = 1, len_trim(value)
            c = iachar(value(i:i))
            if (c < 32 .or. c == 127) cycle
            n = n + 1
            kept(n:n) = value(i:i)
        end do
        name = kept(1:utf8_boundary(kept(1:n), min(n, limit)))
    end function page_name

    logical function claim_anchor(anchor) result(free)
        !! Whether no element of this frame has the page address `anchor` yet;
        !! a duplicate is reported once.
        character(len=64), intent(in) :: anchor
        character(len=64), allocatable :: old(:)
        integer :: i, slot

        free = .true.
        if (len_trim(anchor) == 0) return
        if (.not. allocated(anchors)) then
            allocate(anchors(64))
            anchors = ""
        else if (2 * (anchor_count + 1) > size(anchors)) then
            call move_alloc(anchors, old)
            allocate(anchors(2 * size(old)))
            anchors = ""
            do i = 1, size(old)
                if (len_trim(old(i)) > 0) anchors(anchor_slot(old(i))) = old(i)
            end do
        end if
        slot = anchor_slot(anchor)
        free = len_trim(anchors(slot)) == 0
        if (free) then
            anchors(slot) = anchor
            anchor_count = anchor_count + 1
        else if (.not. any(anchors_told(1:told_count) == anchor)) then
            if (told_count < size(anchors_told)) then
                told_count = told_count + 1
                anchors_told(told_count) = anchor
            end if
            call report_error("fortui_layout", "anchor", "duplicate anchor '" // &
                trim(anchor) // "' in one frame; the later element has none")
        end if
    end function claim_anchor

    integer function anchor_slot(anchor) result(slot)
        !! The slot holding `anchor`, or the free one where it belongs.
        character(len=64), intent(in) :: anchor

        slot = text_hash(anchor, size(anchors) - 1) + 1
        do while (len_trim(anchors(slot)) > 0 .and. anchors(slot) /= anchor)
            slot = mod(slot, size(anchors)) + 1
        end do
    end function anchor_slot

    subroutine column_end()
        logical :: ok
        ok = close_kind(KIND_COLUMN, "column_end")
    end subroutine column_end

    subroutine row_end()
        logical :: ok
        ok = close_kind(KIND_ROW, "row_end")
    end subroutine row_end

    subroutine push_layout(kind, direction, gap, id)
        integer, intent(in) :: kind, direction
        real, intent(in), optional :: gap
        character(*), intent(in), optional :: id
        real :: x, y, w, h, actual_gap

        if (stack_depth == 0) call layout_reset()

        actual_gap = 0.0
        if (present(gap)) actual_gap = max(0.0, gap)
        call layout_get_cursor(x, y)
        call layout_available(w, h)
        if (present(id)) then
            call push_region(kind, direction, actual_gap, x, y, w, h, id)
        else
            call push_region(kind, direction, actual_gap, x, y, w, h, "")
        end if
    end subroutine push_layout

    subroutine pop_layout()
        real :: width, height

        if (stack_depth <= 1) return
        if (layout_stack(stack_depth)%floating) then
            stack_depth = stack_depth - 1
            return
        end if

        if (layout_stack(stack_depth)%direction == DIR_COLUMN) then
            width = layout_stack(stack_depth)%max_cross
            height = layout_stack(stack_depth)%cursor_y - layout_stack(stack_depth)%origin_y
        else
            width = max(layout_stack(stack_depth)%widest, &
                layout_stack(stack_depth)%cursor_x - layout_stack(stack_depth)%origin_x)
            height = layout_stack(stack_depth)%max_cross
        end if
        if (layout_stack(stack_depth)%fixed_h >= 0.0) then
            width = layout_stack(stack_depth)%region_w
            height = layout_stack(stack_depth)%fixed_h
        end if

        stack_depth = stack_depth - 1
        call layout_advance(width, height)
    end subroutine pop_layout

    subroutine scroll_region_begin(id, height, offset, stick, reports, look)
        !! A column of the remaining width that shows `height` of its content,
        !! scrolled down by `offset`; nodes outside are clipped. `stick`: the
        !! host keeps the view at the end while it is there; `reports`: the
        !! host reports the offset it scrolled to (virtual lists).
        character(*), intent(in) :: id
        real, intent(in) :: height, offset
        logical, intent(in) :: stick, reports
        character(*), intent(in), optional :: look
        real :: x, y, w, h

        call layout_get_cursor(x, y)
        call layout_available(w, h)
        call push_region(KIND_SCROLL, DIR_COLUMN, 0.0, x, y - offset, w, 1.0e9, id)
        ! The host reports the offset under the full identity.
        boxes(box_count)%id = layout_stack(stack_depth)%scope
        associate(e => layout_stack(stack_depth), b => boxes(box_count))
            e%fixed_h = max(0.0, height)
            e%clip = intersect(e%clip, [x, y, w, e%fixed_h])
            b%bounds = [x, y, w, e%fixed_h]
            b%viewport = e%fixed_h
            b%offset = offset
            b%stick = stick
            b%reports = reports
        end associate
        call mark_box(look)
    end subroutine scroll_region_begin

    subroutine layout_set_padding(before, after)
        !! Space before and after the composed part of the innermost scroll
        !! container, standing for rows not composed (virtual lists).
        real, intent(in) :: before, after
        associate(e => layout_stack(stack_depth))
            if (e%kind /= KIND_SCROLL) return
            boxes(e%box)%pad_before = max(0.0, before)
            boxes(e%box)%pad_after = max(0.0, after)
            e%cursor_y = e%cursor_y + max(0.0, before)
        end associate
    end subroutine layout_set_padding

    real function scroll_region_end() result(content)
        !! Close the scroll container; the height of its content.
        logical :: ok
        content = 0.0
        if (stack_depth <= 1) return
        associate(e => layout_stack(stack_depth))
            if (e%kind == KIND_SCROLL) then
                content = e%cursor_y - e%origin_y + boxes(e%box)%pad_after
                boxes(e%box)%content = content
            end if
        end associate
        ok = close_kind(KIND_SCROLL, "scroll_region_end")
    end function scroll_region_end

    subroutine float_begin(id, x, y, width, kind, look)
        !! A column above the page at (x, y) that takes no space in its parent:
        !! menus, drop-down lists (KIND_POPUP) and notifications (KIND_TOASTS).
        character(*), intent(in) :: id
        real, intent(in) :: x, y, width
        integer, intent(in) :: kind
        character(*), intent(in), optional :: look
        call push_region(kind, DIR_COLUMN, 0.0, x, y, width, 1.0e9, id)
        ! The host reports a dismissal under the full identity.
        boxes(box_count)%id = layout_stack(stack_depth)%scope
        associate(e => layout_stack(stack_depth))
            e%floating = .true.
            e%layer = max(e%layer, LAYER_FLOAT)
            e%clip = [0.0, 0.0, -1.0, -1.0]
            boxes(box_count)%bounds = [x, y, width, 0.0]
        end associate
        call mark_box(look)
    end subroutine float_begin

    subroutine float_end(bounds)
        !! Close the floating column; its bounds (x, y, w, h).
        real, intent(out), optional :: bounds(4)
        logical :: ok
        integer :: kind
        if (stack_depth <= 1) return
        associate(e => layout_stack(stack_depth))
            kind = e%kind
            boxes(e%box)%bounds(4) = e%cursor_y - e%origin_y
            if (present(bounds)) bounds = boxes(e%box)%bounds
        end associate
        if (kind == KIND_TOASTS) then
            ok = close_kind(KIND_TOASTS, "float_end")
        else
            ok = close_kind(KIND_POPUP, "float_end")
        end if
    end subroutine float_end

    subroutine layout_node_view(clip, layer)
        !! What a node composed now may show (x, y, w, h; w < 0: all) and its layer.
        real, intent(out) :: clip(4)
        integer, intent(out) :: layer
        if (stack_depth == 0) call layout_reset()
        clip = layout_stack(stack_depth)%clip
        layer = layout_stack(stack_depth)%layer
    end subroutine layout_node_view

    pure function intersect(a, b) result(c)
        real, intent(in) :: a(4), b(4)
        real :: c(4), x0, y0, x1, y1
        if (a(3) < 0.0) then
            c = b
            return
        end if
        x0 = max(a(1), b(1))
        y0 = max(a(2), b(2))
        x1 = min(a(1) + a(3), b(1) + b(3))
        y1 = min(a(2) + a(4), b(2) + b(4))
        c = [x0, y0, max(0.0, x1 - x0), max(0.0, y1 - y0)]
    end function intersect

    subroutine layout_get_cursor(x, y)
        real, intent(out) :: x, y

        if (stack_depth == 0) call layout_reset()
        x = layout_stack(stack_depth)%cursor_x
        y = layout_stack(stack_depth)%cursor_y
        ! The next item starts after the container gap that layout_advance will add.
        if (layout_stack(stack_depth)%item_count > 0) then
            if (layout_stack(stack_depth)%direction == DIR_COLUMN) then
                y = y + layout_stack(stack_depth)%gap
            else
                x = x + layout_stack(stack_depth)%gap
            end if
        end if
    end subroutine layout_get_cursor

    subroutine layout_place(height, x, y, width)
        !! Position of the next item of this height: the cursor, centred across a
        !! row of fixed height. In a wrapping row an item of `width` that does not
        !! fit starts the next line.
        real, intent(in) :: height
        real, intent(out) :: x, y
        real, intent(in), optional :: width

        call layout_get_cursor(x, y)
        associate(e => layout_stack(stack_depth))
            if (e%direction == DIR_ROW .and. e%wrap .and. e%item_count > 0 .and. present(width)) then
                if (x + width > e%region_x + e%region_w + 0.5) then
                    e%widest = max(e%widest, e%cursor_x - e%origin_x)
                    e%cursor_x = e%origin_x
                    e%cursor_y = e%cursor_y + e%line_h + e%gap
                    e%line_h = 0.0
                    e%item_count = 0
                    x = e%cursor_x
                    y = e%cursor_y
                end if
            end if
            if (e%direction == DIR_ROW .and. e%cross_size > height) &
                y = y + 0.5 * (e%cross_size - height)
        end associate
    end subroutine layout_place

    subroutine layout_advance(width, height)
        real, intent(in) :: width, height
        real :: gap_offset

        if (stack_depth == 0) call layout_reset()

        associate(e => layout_stack(stack_depth))
            gap_offset = 0.0
            if (e%item_count > 0) gap_offset = e%gap
            e%item_count = e%item_count + 1
            if (e%direction == DIR_COLUMN) then
                e%cursor_y = e%cursor_y + gap_offset + max(0.0, height)
                e%max_cross = max(e%max_cross, max(0.0, width))
            else
                e%cursor_x = e%cursor_x + gap_offset + max(0.0, width)
                e%line_h = max(e%line_h, max(0.0, height))
                e%max_cross = max(e%max_cross, e%cursor_y - e%origin_y + e%line_h, e%cross_size)
            end if
        end associate
    end subroutine layout_advance

    integer function layout_depth()
        layout_depth = stack_depth
    end function layout_depth


    integer function layout_note_node() result(box)
        !! The container of the node being emitted; counts it for box ordering.
        if (stack_depth == 0) call layout_reset()
        box = layout_stack(stack_depth)%box
        nodes_emitted = nodes_emitted + 1
    end function layout_note_node

    subroutine layout_boxes(list, count)
        !! The containers opened in the current composition.
        type(layout_box_t), allocatable, intent(inout) :: list(:)
        integer, intent(out) :: count

        count = box_count
        if (allocated(list)) then
            if (size(list) < count) deallocate (list)
        end if
        if (.not. allocated(list)) allocate (list(max(16, count)))
        if (count > 0) list(1:count) = boxes(1:count)
    end subroutine layout_boxes

end module fortui_layout
