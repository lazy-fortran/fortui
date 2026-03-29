module fortui_layout_constructors
! Layout constructor functions (column, row) and node type
! Provides both tree-based (column/row) and immediate-mode (begin/end) layout
use fortui_layout, only: layout_push_column, layout_push_row, layout_pop
implicit none
private

! Public types
public :: node

! Tree-based constructors (for backend render tree)
public :: column, row

! Immediate-mode layout (cursor-based positioning)
public :: column_begin, column_end, row_begin, row_end

! Core UI tree building block
type :: node
    character(len=32) :: layout_type = "none"    ! "column", "row", "none"
    real :: gap_dp = 0.0                         ! Gap in dp units
    type(node), allocatable :: children(:)
end type node

contains

function column(gap, children) result(n)
    real, intent(in), optional :: gap
    type(node), intent(in), optional :: children(:)
    type(node) :: n

    n%layout_type = "column"

    if (present(gap)) then
        n%gap_dp = gap
    else
        n%gap_dp = 0.0
    end if

    if (present(children)) then
        allocate(n%children(size(children)), source=children)
    end if
end function column

function row(gap, children) result(n)
    real, intent(in), optional :: gap
    type(node), intent(in), optional :: children(:)
    type(node) :: n

    n%layout_type = "row"

    if (present(gap)) then
        n%gap_dp = gap
    else
        n%gap_dp = 0.0
    end if

    if (present(children)) then
        allocate(n%children(size(children)), source=children)
    end if
end function row

subroutine column_begin(gap)
    real, intent(in), optional :: gap

    call layout_push_column(gap)
end subroutine column_begin

subroutine column_end()
    call layout_pop()
end subroutine column_end

subroutine row_begin(gap)
    real, intent(in), optional :: gap

    call layout_push_row(gap)
end subroutine row_begin

subroutine row_end()
    call layout_pop()
end subroutine row_end

end module fortui_layout_constructors
