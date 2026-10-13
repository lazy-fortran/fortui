module fortui_layout
!! Immediate composition layout state in backend-neutral logical units (dp).
implicit none
private

integer, parameter :: MAX_LAYOUT_DEPTH = 32
integer, parameter :: DIR_COLUMN = 1
integer, parameter :: DIR_ROW = 2

type :: layout_entry_t
    integer :: direction = DIR_COLUMN
    real :: gap = 0.0
    real :: origin_x = 0.0
    real :: origin_y = 0.0
    real :: cursor_x = 0.0
    real :: cursor_y = 0.0
    real :: max_cross = 0.0
    integer :: item_count = 0
    ! Region available to this container (bounds for fill-remaining sizing).
    real :: region_x = 0.0
    real :: region_y = 0.0
    real :: region_w = 1.0e9
    real :: region_h = 1.0e9
    ! Split panes: 1 first pane, 2 second pane; split_* is the whole split region.
    integer :: split_role = 0
    real :: split_x = 0.0
    real :: split_y = 0.0
    real :: split_w = 0.0
    real :: split_h = 0.0
    real :: split_first = 0.0
    real :: split_gap = 0.0
end type layout_entry_t

type(layout_entry_t), save :: layout_stack(MAX_LAYOUT_DEPTH)
integer, save :: stack_depth = 0

public :: layout_reset, layout_get_cursor, layout_advance, layout_depth
public :: column_begin, column_end, row_begin, row_end
public :: layout_available, split_begin, split_next, split_end

contains

subroutine layout_reset(width, height)
    real, intent(in), optional :: width, height

    stack_depth = 1
    layout_stack(1) = layout_entry_t(direction=DIR_COLUMN)
    if (present(width)) layout_stack(1)%region_w = max(0.0, width)
    if (present(height)) layout_stack(1)%region_h = max(0.0, height)
end subroutine layout_reset

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

subroutine split_begin(first_width, gap)
    !! Horizontal split filling the available space: a fixed-width first pane and
    !! a second pane taking the remaining width. Call split_next between panes.
    real, intent(in) :: first_width
    real, intent(in), optional :: gap
    real :: x, y, w, h, g, first

    g = 0.0
    if (present(gap)) g = max(0.0, gap)
    call layout_get_cursor(x, y)
    call layout_available(w, h)
    first = max(0.0, min(first_width, w))
    call push_region(DIR_COLUMN, 0.0, x, y, first, h)
    associate(e => layout_stack(stack_depth))
        e%split_role = 1
        e%split_x = x
        e%split_y = y
        e%split_w = w
        e%split_h = h
        e%split_first = first
        e%split_gap = g
    end associate
end subroutine split_begin

subroutine split_next()
    type(layout_entry_t) :: pane

    if (stack_depth <= 1) return
    pane = layout_stack(stack_depth)
    if (pane%split_role /= 1) error stop "fortui: split_next without split_begin"
    stack_depth = stack_depth - 1
    call push_region(DIR_COLUMN, 0.0, pane%split_x + pane%split_first + pane%split_gap, &
        pane%split_y, max(0.0, pane%split_w - pane%split_first - pane%split_gap), &
        pane%split_h)
    layout_stack(stack_depth) = pane_copy(layout_stack(stack_depth), pane)
end subroutine split_next

pure function pane_copy(target, pane) result(out)
    type(layout_entry_t), intent(in) :: target, pane
    type(layout_entry_t) :: out
    out = target
    out%split_role = 2
    out%split_x = pane%split_x
    out%split_y = pane%split_y
    out%split_w = pane%split_w
    out%split_h = pane%split_h
    out%split_first = pane%split_first
    out%split_gap = pane%split_gap
end function pane_copy

subroutine split_end()
    real :: w, h

    if (stack_depth <= 1) return
    if (layout_stack(stack_depth)%split_role == 0) &
        error stop "fortui: split_end without split_begin"
    w = layout_stack(stack_depth)%split_w
    h = layout_stack(stack_depth)%split_h
    stack_depth = stack_depth - 1
    call layout_advance(w, h)
end subroutine split_end

subroutine push_region(direction, gap, x, y, w, h)
    integer, intent(in) :: direction
    real, intent(in) :: gap, x, y, w, h

    if (stack_depth >= MAX_LAYOUT_DEPTH) error stop "fortui: layout nesting exceeds MAX_LAYOUT_DEPTH"
    stack_depth = stack_depth + 1
    layout_stack(stack_depth) = layout_entry_t(direction=direction, gap=gap, &
        origin_x=x, origin_y=y, cursor_x=x, cursor_y=y, region_x=x, region_y=y, &
        region_w=w, region_h=h)
end subroutine push_region

subroutine column_begin(gap)
    real, intent(in), optional :: gap
    call push_layout(DIR_COLUMN, gap)
end subroutine column_begin

subroutine row_begin(gap)
    real, intent(in), optional :: gap
    call push_layout(DIR_ROW, gap)
end subroutine row_begin

subroutine column_end()
    call pop_layout()
end subroutine column_end

subroutine row_end()
    call pop_layout()
end subroutine row_end

subroutine push_layout(direction, gap)
    integer, intent(in) :: direction
    real, intent(in), optional :: gap
    real :: x, y, w, h, actual_gap

    if (stack_depth == 0) call layout_reset()

    actual_gap = 0.0
    if (present(gap)) actual_gap = max(0.0, gap)
    call layout_get_cursor(x, y)
    call layout_available(w, h)
    call push_region(direction, actual_gap, x, y, w, h)
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

subroutine layout_advance(width, height)
    real, intent(in) :: width, height
    real :: gap_offset

    if (stack_depth == 0) call layout_reset()

    gap_offset = 0.0
    if (layout_stack(stack_depth)%item_count > 0) gap_offset = layout_stack(stack_depth)%gap
    layout_stack(stack_depth)%item_count = layout_stack(stack_depth)%item_count + 1

    if (layout_stack(stack_depth)%direction == DIR_COLUMN) then
        layout_stack(stack_depth)%cursor_y = layout_stack(stack_depth)%cursor_y + gap_offset + max(0.0, height)
        layout_stack(stack_depth)%max_cross = max(layout_stack(stack_depth)%max_cross, max(0.0, width))
    else
        layout_stack(stack_depth)%cursor_x = layout_stack(stack_depth)%cursor_x + gap_offset + max(0.0, width)
        layout_stack(stack_depth)%max_cross = max(layout_stack(stack_depth)%max_cross, max(0.0, height))
    end if
end subroutine layout_advance

integer function layout_depth()
    layout_depth = stack_depth
end function layout_depth

end module fortui_layout
