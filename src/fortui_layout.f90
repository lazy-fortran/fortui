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
end type layout_entry_t

type(layout_entry_t), save :: layout_stack(MAX_LAYOUT_DEPTH)
integer, save :: stack_depth = 0

public :: layout_reset, layout_get_cursor, layout_advance, layout_depth
public :: column_begin, column_end, row_begin, row_end

contains

subroutine layout_reset()
    stack_depth = 1
    layout_stack(1) = layout_entry_t(direction=DIR_COLUMN)
end subroutine layout_reset

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
    real :: x, y, actual_gap

    if (stack_depth == 0) call layout_reset()
    if (stack_depth >= MAX_LAYOUT_DEPTH) error stop "fortui: layout nesting exceeds MAX_LAYOUT_DEPTH"

    actual_gap = 0.0
    if (present(gap)) actual_gap = max(0.0, gap)
    call layout_get_cursor(x, y)

    stack_depth = stack_depth + 1
    layout_stack(stack_depth) = layout_entry_t( &
        direction=direction, gap=actual_gap, origin_x=x, origin_y=y, &
        cursor_x=x, cursor_y=y)
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
