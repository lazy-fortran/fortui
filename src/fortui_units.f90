module fortui_units
! Comprehensive units system for fortui with function syntax
! Provides ergonomic unit constructor functions and cross-backend conversion
use fortui_error, only: report_error, report_warning
implicit none
private

! Public types
public :: unit_value, ui_context

! Public unit constructor functions
public :: dp, em, sp, px, cw, ch


! Public functions
public :: convert_to_dp, ui_get_context, ui_set_context

! Internal unit type for runtime identification
type :: unit_value
    real :: value                          ! Numeric value
    character(len=2) :: unit_type         ! Unit identifier
end type unit_value

! Cross-backend unit conversion context
type :: ui_context
    real :: dpi_scale = 1.0     ! GUI: system DPI scale; TUI: 1.0
    real :: em_dp = 16.0        ! Base font size in dp
    real :: text_scale = 1.0    ! Accessibility text scaling
    real :: cell_w_dp = 8.0     ! TUI: cell width in dp
    real :: cell_h_dp = 16.0    ! TUI: cell height in dp
end type ui_context

! Global context for backward compatibility
! Will be replaced by Context Object Pattern in Issue #64
type(ui_context), save :: global_context = ui_context()

! Interface definitions for unit constructor functions
interface dp
    module procedure make_dp
end interface

interface em
    module procedure make_em
end interface

interface sp
    module procedure make_sp
end interface

interface px
    module procedure make_px
end interface

interface cw
    module procedure make_cw
end interface

interface ch
    module procedure make_ch
end interface

! Overloaded interface for convert_to_dp to replace class(*) polymorphism  
interface convert_to_dp
    module procedure convert_unit_value_to_dp
    module procedure convert_real_to_dp
    module procedure convert_integer_to_dp
end interface convert_to_dp

contains

! Unit constructor function implementations

function make_dp(value) result(unit)
    ! Create density-independent pixel unit
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "dp"
end function make_dp

function make_em(value) result(unit)
    ! Create em unit (relative to font size)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "em"
end function make_em

function make_sp(value) result(unit)
    ! Create scaled pixel unit (accessibility)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "sp"
end function make_sp

function make_px(value) result(unit)
    ! Create physical pixel unit
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "px"
end function make_px

function make_cw(value) result(unit)
    ! Create cell width unit (TUI-friendly)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "cw"
end function make_cw

function make_ch(value) result(unit)
    ! Create cell height unit (TUI-friendly)
    real, intent(in) :: value
    type(unit_value) :: unit
    
    unit%value = value
    unit%unit_type = "ch"
end function make_ch


! Unit conversion engine with runtime type checking

real function convert_unit_value_to_dp(unit_arg, ctx) result(dp_val)
    ! Convert unit_value type to density-independent pixels
    use fortui_coordinates, only: safe_px_to_dp, coordinate_error_t, COORD_SUCCESS
    type(unit_value), intent(in) :: unit_arg
    type(ui_context), intent(in) :: ctx
    type(coordinate_error_t) :: error
    
    ! Handle unit_value types with conversion based on unit_type
    select case (trim(unit_arg%unit_type))
        case ("dp")
            ! Direct assignment - dp is the base unit
            dp_val = unit_arg%value
            
        case ("em")
            ! Convert em to dp: value * em_dp
            dp_val = unit_arg%value * ctx%em_dp
            
        case ("sp")
            ! Convert sp to dp: value * text_scale
            dp_val = unit_arg%value * ctx%text_scale
            
        case ("px")
            ! Convert px to dp using safe coordinate conversion (Issue #62 fix)
            dp_val = safe_px_to_dp(unit_arg%value, ctx%dpi_scale, error)
            ! Error handling is internal to safe_px_to_dp
            
        case ("cw")
            ! Convert cw to dp: value * cell_w_dp (TUI cell width)
            dp_val = unit_arg%value * ctx%cell_w_dp
            
        case ("ch")
            ! Convert ch to dp: value * cell_h_dp (TUI cell height)
            dp_val = unit_arg%value * ctx%cell_h_dp
            
        case default
            ! Unknown unit type - this should not happen with proper operators
            call report_error("fortui_units", "convert_unit_value_to_dp", &
                "Unknown unit type '" // trim(unit_arg%unit_type) // "'")
            dp_val = unit_arg%value  ! Fallback to raw value
    end select
end function convert_unit_value_to_dp

real function convert_real_to_dp(unit_arg, ctx) result(dp_val)
    ! Handle bare real values - treat as dp by default per DESIGN.md
    real, intent(in) :: unit_arg
    type(ui_context), intent(in) :: ctx
    
    dp_val = unit_arg
end function convert_real_to_dp

real function convert_integer_to_dp(unit_arg, ctx) result(dp_val)
    ! Handle integer values - convert to real and treat as dp
    integer, intent(in) :: unit_arg
    type(ui_context), intent(in) :: ctx
    
    dp_val = real(unit_arg)
end function convert_integer_to_dp

! UI context management functions

subroutine ui_get_context(ctx)
    ! Retrieve current UI context
    type(ui_context), intent(out) :: ctx
    
    ! Return the global context
    ctx = global_context
end subroutine ui_get_context

subroutine ui_set_context(ctx)
    ! Set new UI context values
    type(ui_context), intent(in) :: ctx
    
    ! Validate and store the context
    if (ctx%dpi_scale > 0.0 .and. ctx%em_dp > 0.0 .and. &
        ctx%text_scale > 0.0 .and. ctx%cell_w_dp > 0.0 .and. &
        ctx%cell_h_dp > 0.0) then
        global_context = ctx
    else
        call report_warning("fortui_units", "ui_set_context", &
            "Invalid context values, keeping current context")
    end if
end subroutine ui_set_context

end module fortui_units