module fortui_layout_constructors
! Layout constructor functions (column, row) and node type
! Provides immediate-mode layout construction with gap and children parameters
implicit none
private

! Public types
public :: node

! Public constructors
public :: column, row

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

end module fortui_layout_constructors
