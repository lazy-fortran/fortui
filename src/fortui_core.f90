module fortui_core
! Core types and lifecycle management for fortui
! Provides backend-agnostic node and view types for UI tree construction
use fortui_backend
use fortui_context, only: fortui_context_t, get_default_context, create_context, set_default_context
use iso_c_binding
use iso_fortran_env, only: error_unit
implicit none
private

! Layout dimension constants
real, parameter :: DEFAULT_ROW_HEIGHT_DP = 32.0  ! Basic row height for vertical layout
real, parameter :: DEFAULT_COLUMN_WIDTH_DP = 64.0  ! Basic column width

! Public types  
public :: ui_element, node, view, widget_wrapper

! Public procedures - with context-aware overloads
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy, ui_get_context
public :: is_gui_available, is_headless_environment, resolve_backend
public :: set_environment_variable_simulation, clear_environment_variable_simulation
! Context-aware function variants (new API)
public :: ui_init_with_context, ui_shutdown_with_context
public :: ui_frame_begin_with_context, ui_present_with_context, ui_should_close_with_context
! Layout constructors
public :: column, row
! Widget wrapper for layout integration
public :: widget
! Context management (for new API)
public :: fortui_context_t, create_context

! Internal state management
type :: ui_state_t
    logical :: initialized = .false.
    character(len=32) :: active_backend = ""
    class(backend_interface), pointer :: backend => null()
    integer :: window_width = 0
    integer :: window_height = 0
    character(len=256) :: window_title = ""
    integer :: target_fps = 60
    logical :: vsync_enabled = .true.
    character(len=32) :: idle_mode = "adaptive"
    integer :: idle_fps = 12
    logical :: should_quit = .false.
    real :: dpi_scale = 1.0
end type ui_state_t


! Interface for ui_init to support both integer and abstract unit parameters
interface ui_init
    module procedure ui_init_integer
    module procedure ui_init_abstract
end interface

! Context-aware function interfaces for overloading
interface ui_shutdown
    module procedure ui_shutdown_default
    module procedure ui_shutdown_with_context
end interface

interface ui_frame_begin
    module procedure ui_frame_begin_default
    module procedure ui_frame_begin_with_context
end interface

interface ui_present
    module procedure ui_present_default
    module procedure ui_present_with_context
end interface

interface ui_should_close
    module procedure ui_should_close_default
    module procedure ui_should_close_with_context
end interface

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

! Pan/zoom state for plot areas with default values from DESIGN.md
type :: view
    real :: scale_x = 1.0  ! Zoom factor X-axis
    real :: scale_y = 1.0  ! Zoom factor Y-axis
    real :: off_x = 0.0    ! Pan offset X-axis
    real :: off_y = 0.0    ! Pan offset Y-axis
end type view

! Termbox2 C library interface types and constants
! Event structure for C interoperability
type, bind(C) :: tb_event
    integer(c_int) :: type
    integer(c_int) :: mod
    integer(c_int) :: key
    integer(c_int32_t) :: ch
    integer(c_int) :: w, h
    integer(c_int) :: x, y
end type tb_event

! Cell structure for terminal rendering
type, bind(C) :: tb_cell
    integer(c_int32_t) :: ch
    integer(c_int) :: fg
    integer(c_int) :: bg
end type tb_cell

! Termbox2 constants
integer, parameter :: TB_KEY_ESC = 27
integer, parameter :: TB_KEY_CTRL_C = 3
integer, parameter :: TB_KEY_CTRL_D = 4
integer, parameter :: TB_KEY_CTRL_Z = 26
integer, parameter :: TB_KEY_ARROW_UP = 65517
integer, parameter :: TB_KEY_ARROW_DOWN = 65518
integer, parameter :: TB_KEY_ARROW_LEFT = 65515
integer, parameter :: TB_KEY_ARROW_RIGHT = 65516
integer, parameter :: TB_KEY_ENTER = 13
integer, parameter :: TB_KEY_TAB = 9
integer, parameter :: TB_KEY_SPACE = 32
integer, parameter :: TB_KEY_BACKSPACE = 8
integer, parameter :: TB_KEY_DELETE = 127
integer, parameter :: TB_EVENT_KEY = 1
integer, parameter :: TB_EVENT_RESIZE = 2
integer, parameter :: TB_EVENT_MOUSE = 3
! Mouse event types
integer, parameter :: TB_KEY_MOUSE_LEFT = 65508
integer, parameter :: TB_KEY_MOUSE_MIDDLE = 65509
integer, parameter :: TB_KEY_MOUSE_RIGHT = 65510
integer, parameter :: TB_KEY_MOUSE_WHEEL_UP = 65511
integer, parameter :: TB_KEY_MOUSE_WHEEL_DOWN = 65512
! Color constants
integer, parameter :: TB_COLOR_BLACK = 0
integer, parameter :: TB_COLOR_RED = 1
integer, parameter :: TB_COLOR_GREEN = 2
integer, parameter :: TB_COLOR_YELLOW = 3
integer, parameter :: TB_COLOR_BLUE = 4
integer, parameter :: TB_COLOR_MAGENTA = 5
integer, parameter :: TB_COLOR_CYAN = 6
integer, parameter :: TB_COLOR_WHITE = 7
integer, parameter :: TB_COLOR_DEFAULT = 0

! Terminal state types removed - now managed by TUI backend implementation


! Real termbox2 C library interface
interface
    ! Core termbox2 functions
    integer(c_int) function tb_init() bind(C, name="tb_init")
        import :: c_int
    end function tb_init
    
    subroutine tb_shutdown() bind(C, name="tb_shutdown")
    end subroutine tb_shutdown
    
    integer(c_int) function tb_width() bind(C, name="tb_width")
        import :: c_int
    end function tb_width
    
    integer(c_int) function tb_height() bind(C, name="tb_height")
        import :: c_int
    end function tb_height
    
    integer(c_int) function tb_peek_event(event, timeout_ms) &
        bind(C, name="tb_peek_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
        integer(c_int), intent(in), value :: timeout_ms
    end function tb_peek_event
    
    subroutine tb_set_cell(x, y, ch, fg, bg) bind(C, name="tb_set_cell")
        import :: c_int, c_int32_t
        integer(c_int), intent(in), value :: x, y
        integer(c_int32_t), intent(in), value :: ch
        integer(c_int), intent(in), value :: fg, bg
    end subroutine tb_set_cell
    
    subroutine tb_clear() bind(C, name="tb_clear")
    end subroutine tb_clear
    
    subroutine tb_present() bind(C, name="tb_present")
    end subroutine tb_present
    
    subroutine tb_set_cursor(x, y) bind(C, name="tb_set_cursor")
        import :: c_int
        integer(c_int), intent(in), value :: x, y
    end subroutine tb_set_cursor
    
    subroutine tb_hide_cursor() bind(C, name="tb_hide_cursor")
    end subroutine tb_hide_cursor
end interface

contains

! Lifecycle & pacing procedures
! Context-aware initialization (new API)
subroutine ui_init_with_context(ctx, backend, width, height, title, target_fps, vsync)
    use fortui_backend_init, only: ensure_backends_registered_with_context, initialize_renderer
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
    
    ! Initialize the appropriate renderer
    call initialize_renderer(ctx, trim(resolved_backend))
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
    ! UI initialization with abstract unit type support
    use fortui_unit_types, only: unit_type
    use fortui_units, only: ui_context, ui_get_context
    use fortui_platform_measurement, only: validate_context
    
    character(*), intent(in) :: backend
    class(unit_type), intent(in) :: width, height  ! Abstract unit types
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
    
    ! Convert abstract units to dp using polymorphic interface
    width_dp = width%to_dp(ctx%units)
    height_dp = height%to_dp(ctx%units)
    
    ! Convert dp to integer grid units for backend initialization
    width_int = nint(width_dp / ctx%units%cell_w_dp)
    height_int = nint(height_dp / ctx%units%cell_h_dp)
    
    ! Ensure minimum dimensions
    width_int = max(1, width_int)
    height_int = max(1, height_int)
    
    ! Call context-aware initialization
    call ui_init_with_context(ctx, backend, width_int, height_int, title, target_fps, vsync)
    
    ! Update context with enhanced measurement if backend supports it
    call setup_enhanced_context(backend, ctx%units)
    
    ! Context-aware initialization complete - no legacy state to maintain
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
        print *, "ui_set_idle_policy: Error - No default context available"
        return
    end if
    
    ! Validate mode parameter
    select case (trim(mode))
    case ("steady", "adaptive")
        ctx%idle_mode = trim(mode)
    case default
        print *, "ui_set_idle_policy: Warning - Invalid mode '", trim(mode), &
             "', using 'adaptive'"
        ctx%idle_mode = "adaptive"
    end select
    
    ! Set idle FPS if provided (only meaningful for adaptive mode)
    if (present(idle_fps)) then
        ctx%idle_fps = max(1, idle_fps)
    end if
    
    ! Apply policy for GUI backend only
#ifdef ENABLE_GUI
    if (trim(ctx%active_backend) == "gui") then
        print *, "ui_set_idle_policy: mode=", trim(ctx%idle_mode)
        if (present(idle_fps)) print *, "  idle_fps=", ctx%idle_fps
    end if
#else
    ! GUI backend disabled at compile time
    if (trim(ctx%active_backend) == "gui") then
        print *, "ui_set_idle_policy: Error - GUI backend not available (disabled at compile time)"
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
        write(error_unit, '(A)') "ui_present_with_context: Error - Context not initialized"
        return
    end if
    
    if (.not. ctx%in_frame) then
        write(error_unit, '(A)') "ui_present_with_context: Error - Not in frame. Call ui_frame_begin first."
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
    end if
    
    ! Context-aware shutdown complete - no legacy state to clean up
end subroutine ui_shutdown_default

! Internal backend resolution and management functions

function resolve_backend(requested) result(backend)
    character(*), intent(in) :: requested
    character(len=32) :: backend
    character(len=256) :: env_var
    integer :: ios
    
    ! Check for environment variable override
    call get_environment_variable("FORTUI_BACKEND", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        backend = trim(env_var)
        return
    end if
    
    ! Handle case sensitivity
    select case (trim(adjustl(requested)))
    case ("TUI", "tui", "terminal", "console")
        backend = "tui"
    case ("GUI", "gui", "window", "graphics")
        backend = "gui"
    case ("auto", "AUTO", "")
        ! Auto-detect best available backend
        backend = select_best_backend()
        if (len_trim(backend) == 0) then
            backend = "tui"  ! Fallback if no backend available
        end if
    case default
        ! Invalid backend - fall back to TUI
        print *, "resolve_backend: Warning - Unknown backend '", trim(requested), &
             "', using TUI"
        backend = "tui"
    end select
    
    ! Validate that selected backend is actually available
    if (trim(backend) == "gui" .and. .not. is_gui_available()) then
        print *, "resolve_backend: GUI backend not available, falling back to TUI"
        backend = "tui"
    end if
end function resolve_backend

logical function is_gui_available()
    ! Check if GUI backend can be initialized
    class(backend_interface), pointer :: gui_backend
    
    gui_backend => get_backend("gui")
    if (associated(gui_backend)) then
        is_gui_available = gui_backend%is_available()
    else
        is_gui_available = .false.
    end if
end function is_gui_available

logical function is_headless_environment()
    ! Detect headless environment (no display available)
    character(len=256) :: env_var
    integer :: ios
    
    ! Check for explicit headless flag
    call get_environment_variable("FORTUI_HEADLESS", env_var, status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for CI environment
    call get_environment_variable("CI", env_var, status=ios)
    if (ios == 0) then
        is_headless_environment = .true.
        return
    end if
    
    call get_environment_variable("GITHUB_ACTIONS", env_var, status=ios)
    if (ios == 0) then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for SSH session
    call get_environment_variable("SSH_CLIENT", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_headless_environment = .true.
        return
    end if
    
    call get_environment_variable("SSH_TTY", env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        is_headless_environment = .true.
        return
    end if
    
    ! Check for display availability
    call get_environment_variable("DISPLAY", env_var, status=ios)
    if (ios /= 0 .or. len_trim(env_var) == 0) then
        ! No X11 DISPLAY, check for Wayland
        call get_environment_variable("WAYLAND_DISPLAY", env_var, status=ios)
        if (ios /= 0 .or. len_trim(env_var) == 0) then
            is_headless_environment = .true.
            return
        end if
    end if
    
    is_headless_environment = .false.
end function is_headless_environment


subroutine set_environment_variable_simulation(name, value)
    character(*), intent(in) :: name, value
    ! This is a stub for testing - real implementation would set env vars
    print *, "  [SIMULATION] Setting ", trim(name), "=", trim(value)
end subroutine set_environment_variable_simulation

subroutine clear_environment_variable_simulation(name)
    character(*), intent(in) :: name
    ! This is a stub for testing - real implementation would clear env vars
    print *, "  [SIMULATION] Clearing ", trim(name)
end subroutine clear_environment_variable_simulation

! TUI backend initialization is now handled through the backend interface

! GUI backend initialization is now handled through the backend interface

! TUI backend helper functions are now handled by the TUI backend implementation


! Backend-specific frame management is now handled by the backend implementations



! All backend-specific operations now handled through backend interface

! TUI presentation now handled through backend interface



! GUI rendering is now handled through backend interface

! Backend-specific quit detection and shutdown is now handled by the backend implementations

! GUI shutdown is now handled through backend interface

! Layout constructor implementations
function column(gap, children) result(n)
    use fortui_units, only: convert_to_dp, ui_get_context, ui_context
    class(*), intent(in), optional :: gap
    class(ui_element), intent(in), optional :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize column layout node
    n = node()
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
    use fortui_units, only: convert_to_dp, ui_get_context, ui_context
    class(*), intent(in), optional :: gap
    class(ui_element), intent(in), optional :: children(:)
    type(node) :: n
    
    type(ui_context) :: ctx
    real :: gap_dp_value
    
    ! Initialize row layout node
    n = node()
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

! Mock termbox2 implementations removed - now handled by TUI backend

! Real termbox2 implementations removed - now handled by TUI backend

! Terminal control procedures removed - now handled by TUI backend

! Widget wrapper function for layout integration
function widget(element) result(wrapper)
    class(ui_element), intent(in) :: element
    type(widget_wrapper) :: wrapper
    
    allocate(wrapper%wrapped_element, source=element)
end function widget

end module fortui_core