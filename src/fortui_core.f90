module fortui_core
! Core types and lifecycle management for fortui
! Provides backend-agnostic node and view types for UI tree construction
use fortui_layout, only: node, column, row, &
    column_begin, column_end, row_begin, row_end
use fortui_context, only: fortui_context_t, get_default_context, &
    create_context, set_default_context
use fortui_render, only: render_backend, RENDER_NONE, &
    RENDER_TUI, RENDER_GUI
use fortui_error
use iso_fortran_env, only: error_unit
implicit none
private

! Public types (re-exported from layout)
public :: node, view

! Public procedures
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present
public :: ui_should_close
public :: ui_set_idle_policy
public :: ui_is_initialized, ui_get_backend
! Layout constructors (re-exported from layout)
public :: column, row
! Immediate-mode layout (cursor-based positioning)
public :: column_begin, column_end, row_begin, row_end

interface ui_init
    module procedure ui_init_integer
end interface

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

! Pan/zoom state for plot areas
type :: view
    real :: scale_x = 1.0
    real :: scale_y = 1.0
    real :: off_x = 0.0
    real :: off_y = 0.0
end type view

contains

! Resolve backend name to integer ID, handling env overrides
function resolve_backend(requested) result(backend_id)
    character(*), intent(in) :: requested
    integer :: backend_id

    character(len=256) :: env_var
    character(len=32) :: backend_name
    integer :: ios

    ! Check for environment variable override
    call get_environment_variable("FORTUI_BACKEND", env_var, &
        status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        backend_name = trim(env_var)
    else
        ! Handle case sensitivity
        select case (trim(adjustl(requested)))
        case ("TUI", "tui", "terminal", "console")
            backend_name = "tui"
        case ("GUI", "gui", "window", "graphics")
            backend_name = "gui"
        case ("auto", "AUTO", "")
            backend_name = "auto"
        case default
            call report_warning("fortui_core", &
                "resolve_backend", &
                "Unknown backend '" // trim(requested) &
                // "', using TUI")
            backend_name = "tui"
        end select
    end if

    ! Auto-detect: prefer GUI if available, else TUI
    if (trim(backend_name) == "auto") then
        if (is_gui_available()) then
            backend_id = RENDER_GUI
            return
        end if
        if (is_tui_available()) then
            backend_id = RENDER_TUI
            return
        end if
        backend_id = RENDER_NONE
        return
    end if

    ! GUI requested: validate availability
    if (trim(backend_name) == "gui") then
        if (is_gui_available()) then
            backend_id = RENDER_GUI
            return
        end if
        call report_warning("fortui_core", &
            "resolve_backend", &
            "GUI backend not available, falling back " &
            // "to TUI")
        backend_name = "tui"
    end if

    ! TUI requested: validate availability
    if (trim(backend_name) == "tui") then
        if (is_tui_available()) then
            backend_id = RENDER_TUI
            return
        end if
        call report_error("fortui_core", "resolve_backend", &
            "TUI backend not available " &
            // "(headless environment)")
        backend_id = RENDER_NONE
        return
    end if

    backend_id = RENDER_NONE
end function resolve_backend

logical function is_gui_available()
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_is_available
#endif
#ifdef ENABLE_GUI
    is_gui_available = gui_is_available()
#else
    is_gui_available = .false.
#endif
end function is_gui_available

logical function is_tui_available()
    use fortui_tui, only: tui_is_available_fn => tui_is_available
    is_tui_available = tui_is_available_fn()
end function is_tui_available

subroutine ui_init_integer(backend, width, height, title, &
    target_fps, vsync)
    use fortui_context, only: ui_context, ui_set_context
    character(*), intent(in) :: backend
    integer,      intent(in) :: width, height
    character(*), intent(in) :: title
    integer,      intent(in), optional :: target_fps
    logical,      intent(in), optional :: vsync

    type(fortui_context_t), pointer :: ctx
    type(ui_context) :: unit_ctx
    integer :: t_fps, backend_id
    logical :: v_sync

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        ctx => create_context()
        call set_default_context(ctx)
    end if

    t_fps = 60
    if (present(target_fps)) t_fps = target_fps

    v_sync = .true.
    if (present(vsync)) v_sync = vsync

    backend_id = resolve_backend(backend)

    if (backend_id == RENDER_NONE) then
        call report_error("fortui_core", "ui_init", &
            "No backend available for initialization " &
            // "(headless environment)")
        return
    end if

    ! Initialize context state
    call ctx%init(backend, width, height, title, t_fps, v_sync)
    ctx%active_backend_id = backend_id

    ! Set active_backend name
    select case (backend_id)
    case (RENDER_TUI)
        ctx%active_backend = "tui"
    case (RENDER_GUI)
        ctx%active_backend = "gui"
    end select

    ! Initialize the actual backend and set render dispatch flag
    call init_backend(backend_id, width, height, title, &
        t_fps, v_sync)
    render_backend = backend_id

    unit_ctx%dpi_scale = 1.0
    unit_ctx%em_dp = 16.0
    unit_ctx%text_scale = 1.0
    unit_ctx%cell_w_dp = 8.0
    unit_ctx%cell_h_dp = 16.0
    call ui_set_context(unit_ctx)
end subroutine ui_init_integer

subroutine init_backend(backend_id, width, height, title, &
    target_fps, vsync)
    integer, intent(in) :: backend_id, width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync

    select case (backend_id)
    case (RENDER_TUI)
        call init_tui_backend(width, height, title, &
            target_fps, vsync)
    case (RENDER_GUI)
        call init_gui_backend(width, height, title, &
            target_fps, vsync)
    end select
end subroutine init_backend

subroutine init_tui_backend(width, height, title, &
    target_fps, vsync)
    use fortui_tui, only: tui_init
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync

    call tui_init(width, height, title, target_fps, vsync)
end subroutine init_tui_backend

subroutine init_gui_backend(width, height, title, &
    target_fps, vsync)
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_init
#endif
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync

#ifdef ENABLE_GUI
    call gui_init(width, height, title, target_fps, vsync)
#endif
end subroutine init_gui_backend

subroutine ui_set_idle_policy(mode, idle_fps)
    character(*), intent(in) :: mode
    integer,      intent(in), optional :: idle_fps

    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        call report_error("fortui_core", "ui_set_idle_policy", &
            "No default context available")
        return
    end if

    select case (trim(mode))
    case ("steady", "adaptive")
        ctx%idle_mode = trim(mode)
    case default
        call report_warning("fortui_core", &
            "ui_set_idle_policy", &
            "Invalid mode '" // trim(mode) &
            // "', using 'adaptive'")
        ctx%idle_mode = "adaptive"
    end select

    if (present(idle_fps)) then
        ctx%idle_fps = max(1, idle_fps)
    end if
end subroutine ui_set_idle_policy

subroutine ui_frame_begin_default(timeout_ms)
    use fortui_layout, only: layout_reset
    use fortui_input, only: input_focus_begin_frame
    integer, intent(in), optional :: timeout_ms

    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        write(error_unit, '(A)') &
            "ui_frame_begin: Error - No default context"
        return
    end if

    if (.not. ctx%initialized) then
        write(error_unit, '(A)') &
            "ui_frame_begin_with_context: Error - " &
            // "Context not initialized"
        return
    end if

    call ctx%begin_frame()
    call layout_reset()

    ! Call backend begin_frame
    select case (ctx%active_backend_id)
    case (RENDER_TUI)
        call begin_frame_tui()
    case (RENDER_GUI)
        call begin_frame_gui()
    case default
        write(error_unit, '(A)') &
            "ui_frame_begin: Error - No backend available"
        return
    end select

    call input_focus_begin_frame()
end subroutine ui_frame_begin_default

subroutine begin_frame_tui()
    use fortui_tui, only: tui_begin_frame
    call tui_begin_frame()
end subroutine begin_frame_tui

subroutine begin_frame_gui()
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_begin_frame
#endif
#ifdef ENABLE_GUI
    call gui_begin_frame()
#endif
end subroutine begin_frame_gui

subroutine ui_present_default(tree)
    type(node), intent(in) :: tree
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        write(error_unit, '(A)') &
            "ui_present: Error - No default context"
        return
    end if

    if (.not. ctx%initialized) then
        if (.not. ctx%shutting_down) then
            write(error_unit, '(A)') &
                "ui_present_with_context: Error - " &
                // "Context not initialized"
        end if
        return
    end if

    if (.not. ctx%in_frame) return

    ! Call backend render
    select case (ctx%active_backend_id)
    case (RENDER_TUI)
        call do_render_tui()
    case (RENDER_GUI)
        call do_render_gui()
    end select

    call ctx%end_frame()
end subroutine ui_present_default

subroutine do_render_tui()
    use fortui_tui, only: tui_render
    call tui_render()
end subroutine do_render_tui

subroutine do_render_gui()
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_render
#endif
#ifdef ENABLE_GUI
    call gui_render()
#endif
end subroutine do_render_gui

logical function ui_should_close_default() result(should_close)
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        should_close = .true.
        return
    end if

    if (.not. ctx%initialized) then
        should_close = .true.
        return
    end if

    select case (ctx%active_backend_id)
    case (RENDER_TUI)
        should_close = check_quit_tui() .or. ctx%should_quit
    case (RENDER_GUI)
        should_close = check_quit_gui() .or. ctx%should_quit
    case default
        should_close = .true.
    end select
end function ui_should_close_default

logical function check_quit_tui()
    use fortui_tui, only: tui_check_quit
    check_quit_tui = tui_check_quit()
end function check_quit_tui

logical function check_quit_gui()
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_check_quit
#endif
#ifdef ENABLE_GUI
    check_quit_gui = gui_check_quit()
#else
    check_quit_gui = .true.
#endif
end function check_quit_gui

subroutine ui_shutdown_default()
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) return

    ! Shutdown the active backend
    select case (ctx%active_backend_id)
    case (RENDER_TUI)
        call shutdown_tui()
    case (RENDER_GUI)
        call shutdown_gui()
    end select

    render_backend = RENDER_NONE
    call ctx%shutdown()
    call set_default_context(null())
end subroutine ui_shutdown_default

subroutine shutdown_tui()
    use fortui_tui, only: tui_shutdown
    call tui_shutdown()
end subroutine shutdown_tui

subroutine shutdown_gui()
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_shutdown
#endif
#ifdef ENABLE_GUI
    call gui_shutdown()
#endif
end subroutine shutdown_gui

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

end module fortui_core
