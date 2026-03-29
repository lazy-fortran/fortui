module fortui_layout
! Immediate-mode cursor-based layout state management
! Maintains a stack of layout scopes (column/row) with cursor tracking
! Widgets read current cursor position and advance it after placement
implicit none
private

public :: layout_reset, layout_push_column, layout_push_row, layout_pop
public :: layout_get_cursor, layout_advance, layout_get_depth

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
end type layout_entry_t

type(layout_entry_t), save :: layout_stack(MAX_LAYOUT_DEPTH)
integer, save :: stack_depth = 0

contains

subroutine layout_reset()
    stack_depth = 1
    layout_stack(1) = layout_entry_t( &
        direction=DIR_COLUMN, gap=0.0, &
        origin_x=0.0, origin_y=0.0, &
        cursor_x=0.0, cursor_y=0.0, &
        max_cross=0.0, item_count=0)
end subroutine layout_reset

subroutine layout_push_column(gap)
    real, intent(in), optional :: gap

    real :: g, cx, cy

    g = 0.0
    if (present(gap)) g = gap

    call layout_get_cursor(cx, cy)

    if (stack_depth >= MAX_LAYOUT_DEPTH) return
    stack_depth = stack_depth + 1
    layout_stack(stack_depth) = layout_entry_t( &
        direction=DIR_COLUMN, gap=g, &
        origin_x=cx, origin_y=cy, &
        cursor_x=cx, cursor_y=cy, &
        max_cross=0.0, item_count=0)
end subroutine layout_push_column

subroutine layout_push_row(gap)
    real, intent(in), optional :: gap

    real :: g, cx, cy

    g = 0.0
    if (present(gap)) g = gap

    call layout_get_cursor(cx, cy)

    if (stack_depth >= MAX_LAYOUT_DEPTH) return
    stack_depth = stack_depth + 1
    layout_stack(stack_depth) = layout_entry_t( &
        direction=DIR_ROW, gap=g, &
        origin_x=cx, origin_y=cy, &
        cursor_x=cx, cursor_y=cy, &
        max_cross=0.0, item_count=0)
end subroutine layout_push_row

subroutine layout_pop()
    real :: w, h

    if (stack_depth <= 1) return

    if (layout_stack(stack_depth)%direction == DIR_COLUMN) then
        w = layout_stack(stack_depth)%max_cross
        h = layout_stack(stack_depth)%cursor_y &
            - layout_stack(stack_depth)%origin_y
    else
        w = layout_stack(stack_depth)%cursor_x &
            - layout_stack(stack_depth)%origin_x
        h = layout_stack(stack_depth)%max_cross
    end if

    stack_depth = stack_depth - 1

    call layout_advance(w, h)
end subroutine layout_pop

subroutine layout_get_cursor(x, y)
    real, intent(out) :: x, y

    if (stack_depth < 1) then
        x = 0.0
        y = 0.0
        return
    end if

    x = layout_stack(stack_depth)%cursor_x
    y = layout_stack(stack_depth)%cursor_y
end subroutine layout_get_cursor

subroutine layout_advance(width, height)
    real, intent(in) :: width, height

    real :: gap_offset

    if (stack_depth < 1) return

    gap_offset = 0.0
    if (layout_stack(stack_depth)%item_count > 0) then
        gap_offset = layout_stack(stack_depth)%gap
    end if

    layout_stack(stack_depth)%item_count = &
        layout_stack(stack_depth)%item_count + 1

    if (layout_stack(stack_depth)%direction == DIR_COLUMN) then
        layout_stack(stack_depth)%cursor_y = &
            layout_stack(stack_depth)%cursor_y + gap_offset + height
        if (width > layout_stack(stack_depth)%max_cross) then
            layout_stack(stack_depth)%max_cross = width
        end if
    else
        layout_stack(stack_depth)%cursor_x = &
            layout_stack(stack_depth)%cursor_x + gap_offset + width
        if (height > layout_stack(stack_depth)%max_cross) then
            layout_stack(stack_depth)%max_cross = height
        end if
    end if
end subroutine layout_advance

integer function layout_get_depth()
    layout_get_depth = stack_depth
end function layout_get_depth

end module fortui_layout
