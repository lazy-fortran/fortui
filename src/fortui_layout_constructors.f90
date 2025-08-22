module fortui_layout_constructors
! Layout constructor functions (column, row) and node assignment operations
! Provides immediate-mode layout construction with gap and children parameters
use fortui_units, only: convert_to_dp, ui_get_context, ui_context
implicit none
private

! Public types (re-exported from core)
public :: ui_element, node, widget_wrapper

! Public constructors
public :: column, row, widget

! Internal layout dimension constants
real, parameter :: DEFAULT_ROW_HEIGHT_DP = 32.0  ! Basic row height for vertical layout
real, parameter :: DEFAULT_COLUMN_WIDTH_DP = 64.0  ! Basic column width

! Abstract UI element hierarchy for tree construction
type, abstract :: ui_element
    ! Abstract base for all UI elements (nodes, widgets, layouts)
end type ui_element

! Concrete polymorphic wrapper for mixed widget arrays
type, extends(ui_element) :: widget_wrapper
    class(ui_element), allocatable :: wrapped_element
end type widget_wrapper

! Core UI tree building block - extensible for widgets
type, extends(ui_element) :: node
    ! Layout metadata
    character(len=32) :: layout_type = "none"    ! "column", "row", "none"
    real :: gap_dp = 0.0                         ! Converted gap in dp units
    ! Children array for tree composition
    class(ui_element), allocatable :: children(:)
    ! Backend-agnostic design (identical behavior regardless of compilation flags)
contains
    ! Assignment operator overload for proper memory management
    procedure :: assign_node
    generic :: assignment(=) => assign_node
end type node

contains

! Layout constructor implementations
function column(gap, children) result(n)
    class(*), intent(in), optional :: gap
    class(ui_element), intent(in), optional :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize column layout node
    n%layout_type = "column"
    
    ! Process gap parameter with convert_to_dp()
    if (present(gap)) then
        call ui_get_context(ctx)
        gap_dp_value = convert_to_dp(gap, ctx)
        n%gap_dp = gap_dp_value
    else
        n%gap_dp = 0.0  ! Default gap per test specifications
    end if
    
    ! Handle children array
    if (present(children)) then
        allocate(n%children(size(children)), source=children)
    ! else - children remains unallocated for empty arrays
    end if
end function column

function row(gap, children) result(n)
    class(*), intent(in), optional :: gap
    class(ui_element), intent(in), optional :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize row layout node
    n%layout_type = "row"
    
    ! Process gap parameter with convert_to_dp()
    if (present(gap)) then
        call ui_get_context(ctx)
        gap_dp_value = convert_to_dp(gap, ctx)
        n%gap_dp = gap_dp_value
    else
        n%gap_dp = 0.0  ! Default gap per test specifications
    end if
    
    ! Handle children array
    if (present(children)) then
        allocate(n%children(size(children)), source=children)
    ! else - children remains unallocated for empty arrays
    end if
end function row

! Assignment operator implementation for proper memory management
recursive subroutine assign_node(lhs, rhs)
    class(node), intent(out) :: lhs
    class(node), intent(in) :: rhs
    
    ! Copy basic properties
    lhs%layout_type = rhs%layout_type
    lhs%gap_dp = rhs%gap_dp
    
    ! Deep copy polymorphic children array
    if (allocated(rhs%children)) then
        allocate(lhs%children(size(rhs%children)), source=rhs%children)
    ! else - no children to copy, lhs%children automatically unallocated for intent(out)
    end if
end subroutine assign_node

! Widget wrapper function for layout integration
function widget(element) result(wrapper)
    class(ui_element), intent(in) :: element
    type(widget_wrapper) :: wrapper
    
    allocate(wrapper%wrapped_element, source=element)
end function widget

end module fortui_layout_constructors