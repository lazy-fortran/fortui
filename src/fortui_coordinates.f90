module fortui_coordinates
! Coordinate system abstraction for Issue #62
! Provides type-safe coordinate transformations with division-by-zero protection
! Eliminates direct division operations throughout the codebase
use iso_fortran_env, only: real32
implicit none
private

public :: coordinate_t, SCREEN_SPACE, VIEWPORT_SPACE, LOGICAL_SPACE
public :: coordinate_transformer_t, create_transformer, create_screen_coord
public :: safe_px_to_dp, safe_dp_to_px, safe_scale_coordinate, create_viewport_coord, create_logical_coord
public :: coordinate_error_t, COORD_SUCCESS, COORD_ERROR_ZERO_SCALE, coordinate_to_string
public :: COORD_ERROR_INVALID_INPUT, COORD_ERROR_OVERFLOW

! Error handling for coordinate operations
integer, parameter :: COORD_SUCCESS = 0
integer, parameter :: COORD_ERROR_ZERO_SCALE = 1
integer, parameter :: COORD_ERROR_INVALID_INPUT = 2
integer, parameter :: COORD_ERROR_OVERFLOW = 3

type :: coordinate_error_t
    integer :: code = COORD_SUCCESS
    character(256) :: message = ""
end type coordinate_error_t

! Discriminated union coordinate type - enforces explicit coordinate space
type :: coordinate_t
    real(real32) :: x = 0.0
    real(real32) :: y = 0.0
    integer :: space_type = 0  ! 1=screen, 2=viewport, 3=logical
end type coordinate_t

! Screen space coordinates (pixels, absolute) - convenience constructor
integer, parameter :: SCREEN_SPACE = 1

! Viewport space coordinates (relative to viewport, 0-1 range) - convenience constructor
integer, parameter :: VIEWPORT_SPACE = 2

! Logical space coordinates (density-independent pixels, dp) - convenience constructor
integer, parameter :: LOGICAL_SPACE = 3

! Coordinate transformation context with validation
type :: coordinate_transformer_t
    real(real32) :: dpi_scale = 1.0
    real(real32) :: viewport_width = 1.0
    real(real32) :: viewport_height = 1.0
    logical :: initialized = .false.
contains
    procedure :: validate => transformer_validate
    procedure :: transform_screen_to_logical => transform_s2l
    procedure :: transform_logical_to_screen => transform_l2s
    procedure :: transform_viewport_to_screen => transform_v2s
    procedure :: transform_screen_to_viewport => transform_s2v
end type coordinate_transformer_t

! Procedure pointer type for coordinate string representation
type :: coordinate_to_string_proc
    procedure(coordinate_to_string_proc_interface), pointer, nopass :: proc => null()
end type coordinate_to_string_proc

interface
    function coordinate_to_string_proc_interface(coord) result(str)
        import :: coordinate_t
        type(coordinate_t), intent(in) :: coord
        character(64) :: str
    end function coordinate_to_string_proc_interface
end interface

contains

! Factory function for creating validated transformer
function create_transformer(dpi_scale, viewport_width, viewport_height) result(transformer)
    real(real32), intent(in) :: dpi_scale, viewport_width, viewport_height
    type(coordinate_transformer_t) :: transformer
    type(coordinate_error_t) :: error
    
    transformer%dpi_scale = dpi_scale
    transformer%viewport_width = viewport_width
    transformer%viewport_height = viewport_height
    
    call transformer%validate(error)
    if (error%code == COORD_SUCCESS) then
        transformer%initialized = .true.
    else
        ! Set safe defaults on validation failure
        transformer%dpi_scale = 1.0
        transformer%viewport_width = 1.0
        transformer%viewport_height = 1.0
        transformer%initialized = .true.
    end if
end function create_transformer

! Safe coordinate scaling with division-by-zero protection
function safe_scale_coordinate(value, scale_factor, error) result(scaled_value)
    real(real32), intent(in) :: value, scale_factor
    type(coordinate_error_t), intent(out) :: error
    real(real32) :: scaled_value
    
    error%code = COORD_SUCCESS
    error%message = ""
    
    ! Validate scale factor
    if (abs(scale_factor) < epsilon(1.0_real32)) then
        error%code = COORD_ERROR_ZERO_SCALE
        write(error%message, '(A,E12.5)') "Scale factor too close to zero: ", scale_factor
        scaled_value = value  ! Return unscaled value as safe fallback
        return
    end if
    
    ! Check for potential overflow
    if (abs(value) > huge(1.0_real32) / abs(scale_factor)) then
        error%code = COORD_ERROR_OVERFLOW
        error%message = "Coordinate scaling would cause overflow"
        scaled_value = sign(huge(1.0_real32), value * scale_factor)
        return
    end if
    
    scaled_value = value * scale_factor
end function safe_scale_coordinate

! Safe pixel to dp conversion (Issue #62 fix)
function safe_px_to_dp(px_value, dpi_scale, error) result(dp_value)
    real(real32), intent(in) :: px_value, dpi_scale
    type(coordinate_error_t), intent(out) :: error
    real(real32) :: dp_value
    
    error%code = COORD_SUCCESS
    error%message = ""
    
    ! Validate DPI scale (cannot be zero or negative)
    if (dpi_scale <= epsilon(1.0_real32)) then
        error%code = COORD_ERROR_ZERO_SCALE
        write(error%message, '(A,E12.5)') "Invalid DPI scale for px->dp conversion: ", dpi_scale
        dp_value = px_value  ! Return px value as dp (1:1 mapping)
        return
    end if
    
    ! Check for potential overflow in division
    if (abs(px_value) > huge(1.0_real32) * dpi_scale) then
        error%code = COORD_ERROR_OVERFLOW
        error%message = "Pixel to DP conversion would cause overflow"
        dp_value = sign(huge(1.0_real32), px_value / dpi_scale)
        return
    end if
    
    dp_value = px_value / dpi_scale
end function safe_px_to_dp

! Safe dp to pixel conversion
function safe_dp_to_px(dp_value, dpi_scale, error) result(px_value)
    real(real32), intent(in) :: dp_value, dpi_scale
    type(coordinate_error_t), intent(out) :: error
    real(real32) :: px_value
    
    px_value = safe_scale_coordinate(dp_value, dpi_scale, error)
end function safe_dp_to_px

! Transformer validation
subroutine transformer_validate(self, error)
    class(coordinate_transformer_t), intent(in) :: self
    type(coordinate_error_t), intent(out) :: error
    
    error%code = COORD_SUCCESS
    error%message = ""
    
    ! Validate DPI scale
    if (self%dpi_scale <= 0.0 .or. self%dpi_scale > 10.0) then
        error%code = COORD_ERROR_INVALID_INPUT
        write(error%message, '(A,F6.2)') "Invalid DPI scale: ", self%dpi_scale
        return
    end if
    
    ! Validate viewport dimensions
    if (self%viewport_width <= 0.0 .or. self%viewport_height <= 0.0) then
        error%code = COORD_ERROR_INVALID_INPUT
        write(error%message, '(A,F8.2,A,F8.2)') "Invalid viewport: ", &
            self%viewport_width, " x ", self%viewport_height
        return
    end if
end subroutine transformer_validate

! Screen to logical space transformation
function transform_s2l(self, screen_coord, error) result(logical_coord)
    class(coordinate_transformer_t), intent(in) :: self
    type(coordinate_t), intent(in) :: screen_coord
    type(coordinate_error_t), intent(out) :: error
    type(coordinate_t) :: logical_coord
    
    if (screen_coord%space_type /= SCREEN_SPACE) then
        error%code = COORD_ERROR_INVALID_INPUT
        error%message = "Expected screen space coordinate for transform_s2l"
        return
    end if
    
    logical_coord%space_type = LOGICAL_SPACE
    logical_coord%x = safe_px_to_dp(screen_coord%x, self%dpi_scale, error)
    if (error%code /= COORD_SUCCESS) return
    
    logical_coord%y = safe_px_to_dp(screen_coord%y, self%dpi_scale, error)
end function transform_s2l

! Logical to screen space transformation
function transform_l2s(self, logical_coord, error) result(screen_coord)
    class(coordinate_transformer_t), intent(in) :: self
    type(coordinate_t), intent(in) :: logical_coord
    type(coordinate_error_t), intent(out) :: error
    type(coordinate_t) :: screen_coord
    
    if (logical_coord%space_type /= LOGICAL_SPACE) then
        error%code = COORD_ERROR_INVALID_INPUT
        error%message = "Expected logical space coordinate for transform_l2s"
        return
    end if
    
    screen_coord%space_type = SCREEN_SPACE
    screen_coord%x = safe_dp_to_px(logical_coord%x, self%dpi_scale, error)
    if (error%code /= COORD_SUCCESS) return
    
    screen_coord%y = safe_dp_to_px(logical_coord%y, self%dpi_scale, error)
end function transform_l2s

! Viewport to screen space transformation
function transform_v2s(self, viewport_coord, error) result(screen_coord)
    class(coordinate_transformer_t), intent(in) :: self
    type(coordinate_t), intent(in) :: viewport_coord
    type(coordinate_error_t), intent(out) :: error
    type(coordinate_t) :: screen_coord
    
    if (viewport_coord%space_type /= VIEWPORT_SPACE) then
        error%code = COORD_ERROR_INVALID_INPUT
        error%message = "Expected viewport space coordinate for transform_v2s"
        return
    end if
    
    ! Validate viewport coordinates (should be 0-1)
    if (viewport_coord%x < 0.0 .or. viewport_coord%x > 1.0 .or. &
        viewport_coord%y < 0.0 .or. viewport_coord%y > 1.0) then
        error%code = COORD_ERROR_INVALID_INPUT
        write(error%message, '(A,F6.3,A,F6.3,A)') "Viewport coordinates out of range: (", &
            viewport_coord%x, ", ", viewport_coord%y, ")"
        screen_coord%space_type = SCREEN_SPACE
        screen_coord%x = 0.0
        screen_coord%y = 0.0
        return
    end if
    
    error%code = COORD_SUCCESS
    screen_coord%space_type = SCREEN_SPACE
    screen_coord%x = viewport_coord%x * self%viewport_width
    screen_coord%y = viewport_coord%y * self%viewport_height
end function transform_v2s

! Screen to viewport space transformation
function transform_s2v(self, screen_coord, error) result(viewport_coord)
    class(coordinate_transformer_t), intent(in) :: self
    type(coordinate_t), intent(in) :: screen_coord
    type(coordinate_error_t), intent(out) :: error
    type(coordinate_t) :: viewport_coord
    
    if (screen_coord%space_type /= SCREEN_SPACE) then
        error%code = COORD_ERROR_INVALID_INPUT
        error%message = "Expected screen space coordinate for transform_s2v"
        return
    end if
    
    ! Safe division with zero-check
    if (self%viewport_width <= epsilon(1.0_real32)) then
        error%code = COORD_ERROR_ZERO_SCALE
        error%message = "Viewport width too close to zero for screen->viewport conversion"
        viewport_coord%space_type = VIEWPORT_SPACE
        viewport_coord%x = 0.0
        viewport_coord%y = 0.0
        return
    end if
    
    if (self%viewport_height <= epsilon(1.0_real32)) then
        error%code = COORD_ERROR_ZERO_SCALE
        error%message = "Viewport height too close to zero for screen->viewport conversion"
        viewport_coord%space_type = VIEWPORT_SPACE
        viewport_coord%x = 0.0
        viewport_coord%y = 0.0
        return
    end if
    
    error%code = COORD_SUCCESS
    viewport_coord%space_type = VIEWPORT_SPACE
    viewport_coord%x = screen_coord%x / self%viewport_width
    viewport_coord%y = screen_coord%y / self%viewport_height
end function transform_s2v

! Coordinate constructors
function create_screen_coord(x, y) result(coord)
    real(real32), intent(in) :: x, y
    type(coordinate_t) :: coord
    coord%x = x
    coord%y = y
    coord%space_type = SCREEN_SPACE
end function create_screen_coord

function create_viewport_coord(x, y) result(coord)
    real(real32), intent(in) :: x, y
    type(coordinate_t) :: coord
    coord%x = x
    coord%y = y
    coord%space_type = VIEWPORT_SPACE
end function create_viewport_coord

function create_logical_coord(x, y) result(coord)
    real(real32), intent(in) :: x, y
    type(coordinate_t) :: coord
    coord%x = x
    coord%y = y
    coord%space_type = LOGICAL_SPACE
end function create_logical_coord

! Single string representation function for all coordinate types
function coordinate_to_string(coord) result(str)
    type(coordinate_t), intent(in) :: coord
    character(64) :: str
    
    select case (coord%space_type)
    case (SCREEN_SPACE)
        write(str, '(A,F8.2,A,F8.2,A)') "screen(", coord%x, ", ", coord%y, ")"
    case (VIEWPORT_SPACE)
        write(str, '(A,F6.3,A,F6.3,A)') "viewport(", coord%x, ", ", coord%y, ")"
    case (LOGICAL_SPACE)
        write(str, '(A,F8.2,A,F8.2,A)') "logical(", coord%x, ", ", coord%y, "dp)"
    case default
        write(str, '(A,F8.2,A,F8.2,A)') "unknown(", coord%x, ", ", coord%y, ")"
    end select
end function coordinate_to_string

end module fortui_coordinates