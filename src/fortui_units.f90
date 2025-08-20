module fortui_units
! Comprehensive units system for fortui with function syntax
! Provides ergonomic unit constructor functions and cross-backend conversion
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

! Global context storage (initialized with defaults)
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

real function convert_to_dp(unit_arg, ctx) result(dp_val)
    ! Convert any unit type or bare real to density-independent pixels
    ! Uses runtime type checking for class(*) polymorphism
    class(*), intent(in) :: unit_arg
    type(ui_context), intent(in) :: ctx
    
    select type(unit_arg)
        type is (unit_value)
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
                    ! Convert px to dp: value / dpi_scale
                    dp_val = unit_arg%value / ctx%dpi_scale
                    
                case ("cw")
                    ! Convert cw to dp: value * cell_w_dp (TUI cell width)
                    dp_val = unit_arg%value * ctx%cell_w_dp
                    
                case ("ch")
                    ! Convert ch to dp: value * cell_h_dp (TUI cell height)
                    dp_val = unit_arg%value * ctx%cell_h_dp
                    
                case default
                    ! Unknown unit type - this should not happen with proper operators
                    print *, "convert_to_dp: Error - Unknown unit type '", &
                        trim(unit_arg%unit_type), "'"
                    dp_val = unit_arg%value  ! Fallback to raw value
            end select
            
        type is (real)
            ! Handle bare real values - treat as dp by default per DESIGN.md
            dp_val = unit_arg
            
        type is (integer)
            ! Handle integer values - convert to real and treat as dp
            dp_val = real(unit_arg)
            
        class default
            ! Unsupported type - provide clear error message
            print *, "convert_to_dp: Error - Unsupported type passed to convert_to_dp"
            print *, "  Supported types: unit_value, real, integer"
            dp_val = 0.0  ! Safe fallback value
    end select
end function convert_to_dp

! UI context management functions

subroutine ui_get_context(ctx)
    ! Retrieve current UI context
    type(ui_context), intent(out) :: ctx
    
    ctx = global_context
end subroutine ui_get_context

subroutine ui_set_context(ctx)
    ! Set new UI context values
    type(ui_context), intent(in) :: ctx
    
    global_context = ctx
end subroutine ui_set_context

end module fortui_units