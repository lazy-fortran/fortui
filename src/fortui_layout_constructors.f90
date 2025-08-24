module fortui_layout_constructors
! Layout constructor functions (column, row) and node assignment operations
! Provides immediate-mode layout construction with gap and children parameters
use fortui_units, only: convert_to_dp, ui_get_context, ui_context, unit_value
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

! Overloaded interfaces for layout constructors to replace class(*) polymorphism
interface column
    module procedure column_no_params
    module procedure column_real_gap
    module procedure column_unit_gap  
    module procedure column_children_only
    module procedure column_real_gap_children
    module procedure column_unit_gap_children
end interface column

interface row
    module procedure row_no_params
    module procedure row_real_gap
    module procedure row_unit_gap
    module procedure row_children_only
    module procedure row_real_gap_children
    module procedure row_unit_gap_children
end interface row

contains

! Layout constructor implementations
function column_no_params() result(n)
    type(node) :: n
    
    ! Initialize column layout node
    n%layout_type = "column"
    n%gap_dp = 0.0  ! Default gap
    ! children remains unallocated for empty arrays
end function column_no_params

function column_real_gap(gap) result(n)
    real, intent(in) :: gap
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize column layout node
    n%layout_type = "column"
    
    ! Process gap parameter with convert_to_dp()
    call ui_get_context(ctx)
    gap_dp_value = convert_to_dp(gap, ctx)
    n%gap_dp = gap_dp_value
    ! children remains unallocated for empty arrays
end function column_real_gap

function column_unit_gap(gap) result(n)
    type(unit_value), intent(in) :: gap
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize column layout node
    n%layout_type = "column"
    
    ! Process gap parameter with convert_to_dp()
    call ui_get_context(ctx)
    gap_dp_value = convert_to_dp(gap, ctx)
    n%gap_dp = gap_dp_value
    ! children remains unallocated for empty arrays
end function column_unit_gap

function column_children_only(children) result(n)
    class(ui_element), intent(in) :: children(:)
    type(node) :: n
    
    ! Initialize column layout node
    n%layout_type = "column"
    n%gap_dp = 0.0  ! Default gap
    
    ! Handle children array
    allocate(n%children(size(children)), source=children)
end function column_children_only

function column_real_gap_children(gap, children) result(n)
    real, intent(in) :: gap
    class(ui_element), intent(in) :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize column layout node
    n%layout_type = "column"
    
    ! Process gap parameter with convert_to_dp()
    call ui_get_context(ctx)
    gap_dp_value = convert_to_dp(gap, ctx)
    n%gap_dp = gap_dp_value
    
    ! Handle children array
    allocate(n%children(size(children)), source=children)
end function column_real_gap_children

function column_unit_gap_children(gap, children) result(n)
    type(unit_value), intent(in) :: gap
    class(ui_element), intent(in) :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize column layout node
    n%layout_type = "column"
    
    ! Process gap parameter with convert_to_dp()
    call ui_get_context(ctx)
    gap_dp_value = convert_to_dp(gap, ctx)
    n%gap_dp = gap_dp_value
    
    ! Handle children array
    allocate(n%children(size(children)), source=children)
end function column_unit_gap_children

function row_no_params() result(n)
    type(node) :: n
    
    ! Initialize row layout node
    n%layout_type = "row"
    n%gap_dp = 0.0  ! Default gap
    ! children remains unallocated for empty arrays
end function row_no_params

function row_real_gap(gap) result(n)
    real, intent(in) :: gap
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize row layout node
    n%layout_type = "row"
    
    ! Process gap parameter with convert_to_dp()
    call ui_get_context(ctx)
    gap_dp_value = convert_to_dp(gap, ctx)
    n%gap_dp = gap_dp_value
    ! children remains unallocated for empty arrays
end function row_real_gap

function row_unit_gap(gap) result(n)
    type(unit_value), intent(in) :: gap
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize row layout node
    n%layout_type = "row"
    
    ! Process gap parameter with convert_to_dp()
    call ui_get_context(ctx)
    gap_dp_value = convert_to_dp(gap, ctx)
    n%gap_dp = gap_dp_value
    ! children remains unallocated for empty arrays
end function row_unit_gap

function row_children_only(children) result(n)
    class(ui_element), intent(in) :: children(:)
    type(node) :: n
    
    ! Initialize row layout node
    n%layout_type = "row"
    n%gap_dp = 0.0  ! Default gap
    
    ! Handle children array
    allocate(n%children(size(children)), source=children)
end function row_children_only

function row_real_gap_children(gap, children) result(n)
    real, intent(in) :: gap
    class(ui_element), intent(in) :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize row layout node
    n%layout_type = "row"
    
    ! Process gap parameter with convert_to_dp()
    call ui_get_context(ctx)
    gap_dp_value = convert_to_dp(gap, ctx)
    n%gap_dp = gap_dp_value
    
    ! Handle children array
    allocate(n%children(size(children)), source=children)
end function row_real_gap_children

function row_unit_gap_children(gap, children) result(n)
    type(unit_value), intent(in) :: gap
    class(ui_element), intent(in) :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize row layout node
    n%layout_type = "row"
    
    ! Process gap parameter with convert_to_dp()
    call ui_get_context(ctx)
    gap_dp_value = convert_to_dp(gap, ctx)
    n%gap_dp = gap_dp_value
    
    ! Handle children array
    allocate(n%children(size(children)), source=children)
end function row_unit_gap_children

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