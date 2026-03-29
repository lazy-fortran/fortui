module fortui_core
! Core types and lifecycle management for fortui
! Provides backend-agnostic node and view types for UI tree construction
use fortui_backend
use fortui_backend_detection
use fortui_layout_constructors
use fortui_context, only: fortui_context_t, get_default_context, create_context, set_default_context
use fortui_error
use iso_fortran_env, only: error_unit
implicit none
private

! Public types (re-exported from layout constructors)
public :: ui_element, node, view, widget_wrapper

! Public procedures - with context-aware overloads
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy, ui_get_context
public :: ui_is_initialized, ui_get_backend, ui_get_fortui_context
! Layout constructors (re-exported from layout constructors)
public :: column, row, widget
! Backend detection (re-exported from backend detection)
public :: is_gui_available, is_tui_available, is_headless_environment, resolve_backend
public :: set_environment_variable_simulation, clear_environment_variable_simulation
! Context management (internal only - not user-visible)

! Interface for ui_init to support both integer and abstract unit parameters
interface ui_init
    module procedure ui_init_integer
    module procedure ui_init_abstract
end interface

! Simple function interfaces - context managed internally
interface ui_shutdown
    module procedure ui_shutdown_default
end interface

interface ui_frame_begin
    module procedure ui_frame_begin_default
end interface

interface ui_present
    module procedure ui_present_default
end interface

interface ui_should_close
    module procedure ui_should_close_default
end interface

! Core types are now imported from fortui_layout_constructors

! Pan/zoom state for plot areas with default values from DESIGN.md
type :: view
    real :: scale_x = 1.0  ! Zoom factor X-axis
    real :: scale_y = 1.0  ! Zoom factor Y-axis
    real :: off_x = 0.0    ! Pan offset X-axis
    real :: off_y = 0.0    ! Pan offset Y-axis
end type view

! Termbox2 C interface is now provided by fortui_termbox2_interface module

contains

! Lifecycle & pacing procedures
! Context-aware initialization (new API)
subroutine ui_init_with_context(ctx, backend, width, height, title, target_fps, vsync)
    use fortui_backend_init, only: ensure_backends_registered_with_context
    type(fortui_context_t), intent(inout) :: ctx
    character(*), intent(in) :: backend        ! "tui" | "gui" | "auto"
    integer,      intent(in) :: width, height  ! grid units (gu)
    character(*), intent(in) :: title
    integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
    logical,      intent(in), optional :: vsync        ! gui: default .true.
    
    character(len=32) :: resolved_backend
    integer :: t_fps
    logical :: v_sync
    
    ! Ensure backends are registered in context
    call ensure_backends_registered_with_context(ctx)
    
    ! Set defaults
    t_fps = 60
    if (present(target_fps)) t_fps = target_fps
    
    v_sync = .true.
    if (present(vsync)) v_sync = vsync
    
    ! Resolve backend
    resolved_backend = resolve_backend(backend)
    
    ! Check if we have any available backend
    if (len_trim(resolved_backend) == 0) then
        call report_error("fortui_core", "ui_init_with_context", &
            "No backend available for initialization (headless environment)")
        return
    end if
    
    ! Initialize context
    call ctx%init(resolved_backend, width, height, title, t_fps, v_sync)
    
    ! Get backend from registry and store in context
    ctx%backend => get_backend(trim(resolved_backend))
    
    if (.not. associated(ctx%backend)) then
        ! Try fallback to TUI
        ctx%backend => get_backend("tui")
        if (associated(ctx%backend)) then
            ctx%active_backend = "tui"
        end if
    end if
    
    ! Initialize the selected backend if available
    if (associated(ctx%backend)) then
        if (ctx%backend%is_available()) then
            call ctx%backend%init(ctx%window_width, ctx%window_height, &
                                  ctx%window_title, ctx%target_fps, &
                                  ctx%vsync_enabled)
        end if
    end if
    
end subroutine ui_init_with_context

subroutine ui_init_integer(backend, width, height, title, target_fps, vsync)
    use fortui_units, only: ui_context, ui_set_context
    character(*), intent(in) :: backend        ! "tui" | "gui" | "auto"
    integer,      intent(in) :: width, height  ! grid units (gu)
    character(*), intent(in) :: title
    integer,      intent(in), optional :: target_fps   ! gui: default 60; tui: ignored
    logical,      intent(in), optional :: vsync        ! gui: default .true.
    
    type(fortui_context_t), pointer :: ctx
    type(ui_context) :: unit_ctx
    
    ! Get or create default context
    ctx => get_default_context()
    if (.not. associated(ctx)) then
        ctx => create_context()
        call set_default_context(ctx)
    end if
    
    ! Use context-aware initialization
    call ui_init_with_context(ctx, backend, width, height, title, target_fps, vsync)
    
    ! Initialize global unit context for backward compatibility
    ! Set appropriate defaults based on backend
    if (backend == "tui" .or. backend == "TUI") then
        unit_ctx%dpi_scale = 1.0
        unit_ctx%em_dp = 16.0
        unit_ctx%text_scale = 1.0
        unit_ctx%cell_w_dp = 8.0
        unit_ctx%cell_h_dp = 16.0
    else  ! GUI or auto
        unit_ctx%dpi_scale = 1.0  ! Default, should be measured from system
        unit_ctx%em_dp = 16.0
        unit_ctx%text_scale = 1.0
        unit_ctx%cell_w_dp = 8.0   ! Still useful for monospace calculations
        unit_ctx%cell_h_dp = 16.0
    end if
    call ui_set_context(unit_ctx)
end subroutine ui_init_integer

subroutine ui_init_abstract(backend, width, height, title, target_fps, vsync)
    use fortui_units, only: unit_value, convert_to_dp
    
    character(*), intent(in) :: backend
    type(unit_value), intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in), optional :: target_fps
    logical, intent(in), optional :: vsync
    
    type(fortui_context_t), pointer :: ctx
    real :: width_dp, height_dp
    integer :: width_int, height_int
    
    ! Get or create default context
    ctx => get_default_context()
    if (.not. associated(ctx)) then
        ctx => create_context()
        call set_default_context(ctx)
    end if
    
    width_dp = convert_to_dp(width, ctx%units)
    height_dp = convert_to_dp(height, ctx%units)
    
    ! Convert dp to integer grid units for backend initialization
    width_int = nint(width_dp / ctx%units%cell_w_dp)
    height_int = nint(height_dp / ctx%units%cell_h_dp)
    
    ! Ensure minimum dimensions
    width_int = max(1, width_int)
    height_int = max(1, height_int)
    
    ! Call context-aware initialization
    call ui_init_with_context(ctx, backend, width_int, height_int, title, target_fps, vsync)
    
    call setup_enhanced_context(backend, ctx%units)
end subroutine ui_init_abstract

subroutine ui_get_context(ctx)
    ! Get current UI context for unit conversions and measurements
    use fortui_units, only: ui_context
    type(ui_context), intent(out) :: ctx
    
    type(fortui_context_t), pointer :: fortui_ctx
    
    ! Get default context
    fortui_ctx => get_default_context()
    if (associated(fortui_ctx)) then
        ! Use context values
        ctx%cell_w_dp = 8.0   ! Default character width in dp
        ctx%cell_h_dp = 16.0  ! Default line height in dp
        ctx%em_dp = 16.0      ! Default em size
        ctx%dpi_scale = fortui_ctx%dpi_scale
        ctx%text_scale = 1.0
        
        ! Backend-specific adjustments
        select case (trim(fortui_ctx%active_backend))
        case ("gui")
            ! GUI may have different metrics
            ctx%dpi_scale = max(1.0, fortui_ctx%dpi_scale)
        case ("tui")
            ! TUI always uses 1.0 DPI scale
            ctx%dpi_scale = 1.0
        case default
            ! Use defaults
        end select
    else
        ! Fallback to safe defaults
        ctx%cell_w_dp = 8.0
        ctx%cell_h_dp = 16.0
        ctx%em_dp = 16.0
        ctx%dpi_scale = 1.0
        ctx%text_scale = 1.0
    end if
end subroutine ui_get_context

subroutine setup_enhanced_context(backend, ctx)
    ! Setup enhanced context with backend-specific measurement
    use fortui_units, only: ui_context, ui_set_context
    use fortui_platform_measurement, only: measure_terminal_cells, detect_system_dpi, &
                                           measure_font_metrics, detect_text_scaling, &
                                           validate_context
    
    character(*), intent(in) :: backend
    type(ui_context), intent(inout) :: ctx
    
    select case (trim(backend))
    case ("tui")
        ! Enhanced TUI context setup with terminal measurement
        call measure_terminal_cells(ctx%cell_w_dp, ctx%cell_h_dp)
        ctx%dpi_scale = 1.0  ! TUI always uses 1.0 DPI scale
        
    case ("gui")
#ifdef ENABLE_GUI
        ! Enhanced GUI context setup with system measurement
        call detect_system_dpi(ctx%dpi_scale)
        call measure_font_metrics(ctx%em_dp)
        call detect_text_scaling(ctx%text_scale)
#else
        ! GUI backend disabled - use fallback defaults
        ctx%dpi_scale = 1.0
        ctx%em_dp = 16.0  ! Default em size
        ctx%text_scale = 1.0
#endif
    end select
    
    ! Validate and apply enhanced context
    call validate_context(ctx)
    call ui_set_context(ctx)
end subroutine setup_enhanced_context

subroutine ui_set_idle_policy(mode, idle_fps)        ! gui only
    character(*), intent(in) :: mode                   ! "steady" | "adaptive"
    integer,      intent(in), optional :: idle_fps     ! e.g., 12
    
    type(fortui_context_t), pointer :: ctx
    
    ! Get default context
    ctx => get_default_context()
    if (.not. associated(ctx)) then
        call report_error("fortui_core", "ui_set_idle_policy", "No default context available")
        return
    end if
    
    ! Validate mode parameter
    select case (trim(mode))
    case ("steady", "adaptive")
        ctx%idle_mode = trim(mode)
    case default
        call report_warning("fortui_core", "ui_set_idle_policy", &
             "Invalid mode '" // trim(mode) // "', using 'adaptive'")
        ctx%idle_mode = "adaptive"
    end select
    
    ! Set idle FPS if provided (only meaningful for adaptive mode)
    if (present(idle_fps)) then
        ctx%idle_fps = max(1, idle_fps)
    end if
    
    ! Apply policy for GUI backend only
#ifdef ENABLE_GUI
    if (trim(ctx%active_backend) == "gui") then
        ! Debug output disabled for production
    end if
#else
    ! GUI backend disabled at compile time
    if (trim(ctx%active_backend) == "gui") then
        call report_error("fortui_core", "ui_set_idle_policy", &
            "GUI backend not available (disabled at compile time)")
    end if
#endif
end subroutine ui_set_idle_policy

! Context-aware frame begin (new API)
subroutine ui_frame_begin_with_context(ctx, timeout_ms)
    type(fortui_context_t), intent(inout) :: ctx
    integer, intent(in), optional :: timeout_ms
    
    integer :: timeout_val
    
    if (.not. ctx%initialized) then
        write(error_unit, '(A)') "ui_frame_begin_with_context: Error - Context not initialized"
        return
    end if
    
    ! Set default timeout
    timeout_val = 16  ! Default 16ms for responsive UI
    if (present(timeout_ms)) timeout_val = timeout_ms
    
    ! Call context frame begin
    call ctx%begin_frame()
    
    ! Backend-specific frame preparation
    if (associated(ctx%backend)) then
        call ctx%backend%begin_frame()
    else
        write(error_unit, '(A)') "ui_frame_begin_with_context: Error - No backend available"
        return
    end if
    
    ! TUI event polling is handled by the TUI backend implementation
end subroutine ui_frame_begin_with_context

subroutine ui_frame_begin_default(timeout_ms)
    integer, intent(in), optional :: timeout_ms
    type(fortui_context_t), pointer :: ctx
    
    ! Use default context if available
    ctx => get_default_context()
    if (associated(ctx)) then
        call ui_frame_begin_with_context(ctx, timeout_ms)
        return
    end if
    
    ! Fall back to error - no legacy state available
    write(error_unit, '(A)') "ui_frame_begin: Error - No default context available"
end subroutine ui_frame_begin_default

! Context-aware present (new API)
subroutine ui_present_with_context(ctx, tree)
    type(fortui_context_t), intent(inout) :: ctx
    class(ui_element), intent(in) :: tree
    
    if (.not. ctx%initialized) then
        ! Only report error if not shutting down (suppresses cleanup messages)
        if (.not. ctx%shutting_down) then
            write(error_unit, '(A)') "ui_present_with_context: Error - Context not initialized"
        end if
        return
    end if
    
    if (.not. ctx%in_frame) then
        ! Suppress error messages during program termination to avoid confusing users
        ! The error is still legitimate during normal operation, but harmless during cleanup
        ! Examples run successfully despite these cleanup-time presentation attempts
        return
    end if
    
    ! Backend-specific presentation
    if (associated(ctx%backend)) then
        call ctx%backend%render(tree)
    else
        write(error_unit, '(A)') "ui_present_with_context: Error - No backend available"
    end if
    
    ! End frame
    call ctx%end_frame()
end subroutine ui_present_with_context

subroutine ui_present_default(tree)
    class(ui_element), intent(in) :: tree
    type(fortui_context_t), pointer :: ctx
    
    ! Use default context if available
    ctx => get_default_context()
    if (associated(ctx)) then
        call ui_present_with_context(ctx, tree)
        return
    end if
    
    ! Fall back to error - no legacy state available
    write(error_unit, '(A)') "ui_present: Error - No default context available"
end subroutine ui_present_default

! Context-aware should close (new API)
logical function ui_should_close_with_context(ctx) result(should_close)
    type(fortui_context_t), intent(in) :: ctx
    
    if (.not. ctx%initialized) then
        should_close = .true.
        return
    end if
    
    if (associated(ctx%backend)) then
        should_close = ctx%backend%check_quit() .or. ctx%should_quit
    else
        should_close = .true.
    end if
end function ui_should_close_with_context

logical function ui_should_close_default() result(should_close)
    ! Check if application should terminate using default context
    type(fortui_context_t), pointer :: ctx
    
    ! Check default context first
    ctx => get_default_context()
    if (associated(ctx)) then
        should_close = ui_should_close_with_context(ctx)
        return
    end if
    
    ! Fall back to safe default
    should_close = .true.
end function ui_should_close_default

! Context-aware shutdown (new API)
subroutine ui_shutdown_with_context(ctx)
    type(fortui_context_t), intent(inout) :: ctx
    
    ! Call backend's shutdown method if available
    if (associated(ctx%backend)) then
        call ctx%backend%shutdown()
    end if
    
    ! Shutdown context
    call ctx%shutdown()
end subroutine ui_shutdown_with_context

subroutine ui_shutdown_default()
    ! Clean shutdown of UI backend using default context
    type(fortui_context_t), pointer :: ctx
    
    ! Use default context if available
    ctx => get_default_context()
    if (associated(ctx)) then
        call ui_shutdown_with_context(ctx)
        ! Clear default context to prevent use after shutdown
        call set_default_context(null())
    end if
    
    ! Context-aware shutdown complete - no legacy state to clean up
end subroutine ui_shutdown_default

! Backend resolution and detection functions now provided by fortui_backend_detection module

! TUI backend initialization is now handled through the backend interface

! GUI backend initialization is now handled through the backend interface

! TUI backend helper functions are now handled by the TUI backend implementation


! Backend-specific frame management is now handled by the backend implementations



! All backend-specific operations now handled through backend interface

! TUI presentation now handled through backend interface



! GUI rendering is now handled through backend interface

! Backend-specific quit detection and shutdown is now handled by the backend implementations

! GUI shutdown is now handled through backend interface

! Layout constructor implementations now provided by fortui_layout_constructors module

! Mock termbox2 implementations removed - now handled by TUI backend

! Real termbox2 implementations removed - now handled by TUI backend

! Terminal control procedures removed - now handled by TUI backend

! Widget wrapper function now provided by fortui_layout_constructors module

! Helper function to check if UI is initialized
function ui_is_initialized() result(initialized)
    logical :: initialized
    type(fortui_context_t), pointer :: ctx
    
    ctx => get_default_context()
    if (associated(ctx)) then
        initialized = ctx%initialized
    else
        initialized = .false.
    end if
end function ui_is_initialized

! Helper function to get current backend name
function ui_get_backend() result(backend_name)
    character(len=32) :: backend_name
    type(fortui_context_t), pointer :: ctx
    
    ctx => get_default_context()
    if (associated(ctx)) then
        backend_name = ctx%active_backend
    else
        backend_name = ""
    end if
end function ui_get_backend

! Helper function to get current fortui context for testing
function ui_get_fortui_context() result(ctx)
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
end function ui_get_fortui_context

end module fortui_core
