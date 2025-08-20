module fortui_unit_types
! Abstract unit type system for UI context integration with backend measurement
! Provides polymorphic dispatch and class(unit_type) support for ui_init()
use fortui_units, only: ui_context
implicit none
private

! Public abstract type and concrete implementations
public :: unit_type
public :: dp_unit_t, em_unit_t, sp_unit_t, px_unit_t, cw_unit_t, ch_unit_t
public :: inches_unit_t, cm_unit_t, mm_unit_t, points_unit_t

! Public constructor functions for abstract types
public :: dp_unit, em_unit, sp_unit, px_unit, cw_unit, ch_unit
public :: inches_unit, cm_unit, mm_unit, points_unit

! Physical unit conversion constants (DPI-independent base values)
real, parameter :: INCHES_TO_DP_BASE = 96.0    ! 96 dp per inch at base DPI
real, parameter :: CM_TO_DP_BASE = 37.795      ! ~96/2.54 dp per cm
real, parameter :: MM_TO_DP_BASE = 3.7795      ! ~96/25.4 dp per mm
real, parameter :: POINTS_TO_DP_BASE = 1.333   ! ~96/72 dp per point

! Abstract unit type with deferred to_dp method
type, abstract :: unit_type
    real :: value
contains
    procedure(to_dp_interface), deferred :: to_dp
end type unit_type

! Abstract interface for unit conversion
abstract interface
    real function to_dp_interface(this, ctx) result(dp_value)
        import :: unit_type, ui_context
        class(unit_type), intent(in) :: this
        type(ui_context), intent(in) :: ctx
    end function to_dp_interface
end interface

! Concrete unit type implementations

! Density-independent pixel unit (base unit)
type, extends(unit_type) :: dp_unit_t
contains
    procedure :: to_dp => dp_to_dp
end type dp_unit_t

! Em unit (relative to font size)
type, extends(unit_type) :: em_unit_t
contains
    procedure :: to_dp => em_to_dp
end type em_unit_t

! Scaled pixel unit (accessibility text scaling)
type, extends(unit_type) :: sp_unit_t
contains
    procedure :: to_dp => sp_to_dp
end type sp_unit_t

! Physical pixel unit (HiDPI scaling)
type, extends(unit_type) :: px_unit_t
contains
    procedure :: to_dp => px_to_dp
end type px_unit_t

! Cell width unit (TUI cell-based)
type, extends(unit_type) :: cw_unit_t
contains
    procedure :: to_dp => cw_to_dp
end type cw_unit_t

! Cell height unit (TUI cell-based)
type, extends(unit_type) :: ch_unit_t
contains
    procedure :: to_dp => ch_to_dp
end type ch_unit_t

! Physical unit types

! Inches unit (physical measurement)
type, extends(unit_type) :: inches_unit_t
contains
    procedure :: to_dp => inches_to_dp
end type inches_unit_t

! Centimeters unit (physical measurement)
type, extends(unit_type) :: cm_unit_t
contains
    procedure :: to_dp => cm_to_dp
end type cm_unit_t

! Millimeters unit (physical measurement)
type, extends(unit_type) :: mm_unit_t
contains
    procedure :: to_dp => mm_to_dp
end type mm_unit_t

! Points unit (typography, 1/72 inch)
type, extends(unit_type) :: points_unit_t
contains
    procedure :: to_dp => points_to_dp
end type points_unit_t

contains

! Constructor functions for abstract unit types

function dp_unit(value) result(unit)
    real, intent(in) :: value
    type(dp_unit_t) :: unit
    
    unit%value = value
end function dp_unit

function em_unit(value) result(unit)
    real, intent(in) :: value
    type(em_unit_t) :: unit
    
    unit%value = value
end function em_unit

function sp_unit(value) result(unit)
    real, intent(in) :: value
    type(sp_unit_t) :: unit
    
    unit%value = value
end function sp_unit

function px_unit(value) result(unit)
    real, intent(in) :: value
    type(px_unit_t) :: unit
    
    unit%value = value
end function px_unit

function cw_unit(value) result(unit)
    real, intent(in) :: value
    type(cw_unit_t) :: unit
    
    unit%value = value
end function cw_unit

function ch_unit(value) result(unit)
    real, intent(in) :: value
    type(ch_unit_t) :: unit
    
    unit%value = value
end function ch_unit

function inches_unit(value) result(unit)
    real, intent(in) :: value
    type(inches_unit_t) :: unit
    
    unit%value = value
end function inches_unit

function cm_unit(value) result(unit)
    real, intent(in) :: value
    type(cm_unit_t) :: unit
    
    unit%value = value
end function cm_unit

function mm_unit(value) result(unit)
    real, intent(in) :: value
    type(mm_unit_t) :: unit
    
    unit%value = value
end function mm_unit

function points_unit(value) result(unit)
    real, intent(in) :: value
    type(points_unit_t) :: unit
    
    unit%value = value
end function points_unit

! Concrete to_dp method implementations

real function dp_to_dp(this, ctx) result(dp_value)
    ! Identity conversion - dp is the base unit
    class(dp_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    dp_value = this%value
end function dp_to_dp

real function em_to_dp(this, ctx) result(dp_value)
    ! Convert em to dp using context font size
    class(em_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    dp_value = this%value * ctx%em_dp
end function em_to_dp

real function sp_to_dp(this, ctx) result(dp_value)
    ! Convert sp to dp using accessibility text scaling
    class(sp_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    dp_value = this%value * ctx%text_scale
end function sp_to_dp

real function px_to_dp(this, ctx) result(dp_value)
    ! Convert px to dp using DPI scaling
    class(px_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    dp_value = this%value / ctx%dpi_scale
end function px_to_dp

real function cw_to_dp(this, ctx) result(dp_value)
    ! Convert cw to dp using TUI cell width
    class(cw_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    dp_value = this%value * ctx%cell_w_dp
end function cw_to_dp

real function ch_to_dp(this, ctx) result(dp_value)
    ! Convert ch to dp using TUI cell height
    class(ch_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    dp_value = this%value * ctx%cell_h_dp
end function ch_to_dp

! Physical unit to_dp implementations

real function inches_to_dp(this, ctx) result(dp_value)
    ! Convert inches to dp using DPI-aware scaling
    class(inches_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    ! Base conversion scaled by DPI
    dp_value = this%value * INCHES_TO_DP_BASE * ctx%dpi_scale
end function inches_to_dp

real function cm_to_dp(this, ctx) result(dp_value)
    ! Convert centimeters to dp using DPI-aware scaling
    class(cm_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    ! Base conversion scaled by DPI
    dp_value = this%value * CM_TO_DP_BASE * ctx%dpi_scale
end function cm_to_dp

real function mm_to_dp(this, ctx) result(dp_value)
    ! Convert millimeters to dp using DPI-aware scaling
    class(mm_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    ! Base conversion scaled by DPI
    dp_value = this%value * MM_TO_DP_BASE * ctx%dpi_scale
end function mm_to_dp

real function points_to_dp(this, ctx) result(dp_value)
    ! Convert typography points to dp using DPI-aware scaling
    class(points_unit_t), intent(in) :: this
    type(ui_context), intent(in) :: ctx
    
    ! Base conversion scaled by DPI
    dp_value = this%value * POINTS_TO_DP_BASE * ctx%dpi_scale
end function points_to_dp

end module fortui_unit_types