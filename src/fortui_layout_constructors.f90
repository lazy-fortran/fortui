module fortui_layout_constructors
! PURE IMMEDIATE-MODE layout functions - NO OBJECTS OR CONSTRUCTORS
! Layout happens during widget calls, not through object construction
use fortui_units, only: convert_to_dp, ui_get_context, ui_context, unit_value
implicit none
private

! NO PUBLIC TYPES - PURE IMMEDIATE MODE

! NO PUBLIC CONSTRUCTORS - PURE IMMEDIATE MODE

! Internal layout dimension constants
real, parameter :: DEFAULT_ROW_HEIGHT_DP = 32.0  ! Basic row height for vertical layout
real, parameter :: DEFAULT_COLUMN_WIDTH_DP = 64.0  ! Basic column width

! NO TYPES - PURE IMMEDIATE MODE
! Layout state is managed internally during widget rendering
! NO objects are created or exposed to users

! NO INTERFACES - PURE IMMEDIATE MODE
! Layout happens automatically during widget calls

contains

! NO LAYOUT CONSTRUCTORS - PURE IMMEDIATE MODE
! Layout happens internally during widget rendering

! NO FUNCTIONS - PURE IMMEDIATE MODE

! ALL LAYOUT CONSTRUCTOR CODE REMOVED
! PURE IMMEDIATE MODE - NO OBJECTS OR CONSTRUCTORS

end module fortui_layout_constructors