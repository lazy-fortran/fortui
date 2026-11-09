module fortui_layout
!! Immediate composition layout state in backend-neutral logical units, plus
!! identity scopes: a container with an id prefixes the ids of widgets inside.
use fortui_error, only: report_error
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
character(len=*), parameter :: KIND_NAMES(0:4) = [character(len=6) :: "root", &
    "column", "row", "split", "pane"]

type :: layout_entry_t
    integer :: kind = KIND_ROOT
    integer :: direction = DIR_COLUMN
    real :: gap = 0.0
    real :: origin_x = 0.0
    real :: origin_y = 0.0
    real :: cursor_x = 0.0
    real :: cursor_y = 0.0
    real :: max_cross = 0.0
    ! Rows with a fixed cross size centre shorter items in it (0: top-aligned).
    real :: cross_size = 0.0
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
end type layout_entry_t

type(layout_entry_t), save :: layout_stack(MAX_LAYOUT_DEPTH)
integer, save :: stack_depth = 0

public :: layout_reset, layout_get_cursor, layout_advance, layout_depth, layout_place
public :: column_begin, column_end, row_begin, row_end
public :: layout_available, split_begin, split_next, split_end
public :: layout_scope, layout_fill_width, layout_check_balance

contains

subroutine layout_reset(width, height)
    real, intent(in), optional :: width, height

    stack_depth = 1
    layout_stack(1) = layout_entry_t(direction=DIR_COLUMN, scope="")
    if (present(width)) layout_stack(1)%region_w = max(0.0, width)
    if (present(height)) layout_stack(1)%region_h = max(0.0, height)
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
    stack_depth = stack_depth + 1
    layout_stack(stack_depth) = layout_entry_t(kind=kind, direction=direction, &
        gap=gap, origin_x=x, origin_y=y, cursor_x=x, cursor_y=y, region_x=x, &
        region_y=y, region_w=w, region_h=h, scope=scope)
end subroutine push_region

subroutine column_begin(gap, id)
    !! Vertical container; `id` (optional) scopes the identities inside.
    real, intent(in), optional :: gap
    character(*), intent(in), optional :: id
    call push_layout(KIND_COLUMN, DIR_COLUMN, gap, id)
end subroutine column_begin

subroutine row_begin(gap, id, height)
    !! Horizontal container; `id` (optional) scopes the identities inside. With
    !! `height`, the row is at least that tall and centres shorter items in it.
    real, intent(in), optional :: gap, height
    character(*), intent(in), optional :: id
    call push_layout(KIND_ROW, DIR_ROW, gap, id)
    if (present(height)) layout_stack(stack_depth)%cross_size = max(0.0, height)
end subroutine row_begin

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

    if (layout_stack(stack_depth)%direction == DIR_COLUMN) then
        width = layout_stack(stack_depth)%max_cross
        height = layout_stack(stack_depth)%cursor_y - layout_stack(stack_depth)%origin_y
    else
        width = layout_stack(stack_depth)%cursor_x - layout_stack(stack_depth)%origin_x
        height = layout_stack(stack_depth)%max_cross
    end if

    stack_depth = stack_depth - 1
    call layout_advance(width, height)
end subroutine pop_layout

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

subroutine layout_place(height, x, y)
    !! Position of the next item of this height: the cursor, centred across a
    !! row of fixed height.
    real, intent(in) :: height
    real, intent(out) :: x, y

    call layout_get_cursor(x, y)
    associate(e => layout_stack(stack_depth))
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
            e%max_cross = max(e%max_cross, max(0.0, height), e%cross_size)
        end if
    end associate
end subroutine layout_advance

integer function layout_depth()
    layout_depth = stack_depth
end function layout_depth

end module fortui_layout
