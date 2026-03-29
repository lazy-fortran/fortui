module fortui_core
! Core types and lifecycle management for fortui
! Provides backend-agnostic node and view types for UI tree construction
use fortui_backend
use fortui_backend_detection
use fortui_layout_constructors
use fortui_context, only: fortui_context_t, get_default_context, &
    create_context, set_default_context
use fortui_error
use iso_fortran_env, only: error_unit
implicit none
private

! Public types (re-exported from layout constructors)
public :: node, view

! Public procedures
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy
public :: ui_is_initialized, ui_get_backend
! Layout constructors (re-exported from layout constructors)
public :: column, row

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

! Pan/zoom state for plot areas with default values from DESIGN.md
type :: view
    real :: scale_x = 1.0
    real :: scale_y = 1.0
    real :: off_x = 0.0
    real :: off_y = 0.0
end type view

contains

subroutine ui_init_with_context(ctx, backend, width, height, title, &
                                target_fps, vsync)
    use fortui_backend_init, only: ensure_backends_registered_with_context
    type(fortui_context_t), intent(inout) :: ctx
    character(*), intent(in) :: backend
    integer,      intent(in) :: width, height
    character(*), intent(in) :: title
    integer,      intent(in), optional :: target_fps
    logical,      intent(in), optional :: vsync

    character(len=32) :: resolved_backend
    integer :: t_fps
    logical :: v_sync

    call ensure_backends_registered_with_context(ctx)

    t_fps = 60
    if (present(target_fps)) t_fps = target_fps

    v_sync = .true.
    if (present(vsync)) v_sync = vsync

    resolved_backend = resolve_backend(backend)

    if (len_trim(resolved_backend) == 0) then
        call report_error("fortui_core", "ui_init_with_context", &
            "No backend available for initialization (headless environment)")
        return
    end if

    call ctx%init(resolved_backend, width, height, title, t_fps, v_sync)

    ctx%backend => get_backend(trim(resolved_backend))

    if (.not. associated(ctx%backend)) then
        ctx%backend => get_backend("tui")
        if (associated(ctx%backend)) then
            ctx%active_backend = "tui"
        end if
    end if

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
    character(*), intent(in) :: backend
    integer,      intent(in) :: width, height
    character(*), intent(in) :: title
    integer,      intent(in), optional :: target_fps
    logical,      intent(in), optional :: vsync

    type(fortui_context_t), pointer :: ctx
    type(ui_context) :: unit_ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        ctx => create_context()
        call set_default_context(ctx)
    end if

    call ui_init_with_context(ctx, backend, width, height, title, &
                              target_fps, vsync)

    unit_ctx%dpi_scale = 1.0
    unit_ctx%em_dp = 16.0
    unit_ctx%text_scale = 1.0
    unit_ctx%cell_w_dp = 8.0
    unit_ctx%cell_h_dp = 16.0
    call ui_set_context(unit_ctx)
end subroutine ui_init_integer

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
        call report_warning("fortui_core", "ui_set_idle_policy", &
             "Invalid mode '" // trim(mode) // "', using 'adaptive'")
        ctx%idle_mode = "adaptive"
    end select

    if (present(idle_fps)) then
        ctx%idle_fps = max(1, idle_fps)
    end if

    if (trim(ctx%active_backend) == "gui") then
#ifndef ENABLE_GUI
        call report_error("fortui_core", "ui_set_idle_policy", &
            "GUI backend not available (disabled at compile time)")
#endif
    end if
end subroutine ui_set_idle_policy

subroutine ui_frame_begin_with_context(ctx, timeout_ms)
    type(fortui_context_t), intent(inout) :: ctx
    integer, intent(in), optional :: timeout_ms

    integer :: timeout_val

    if (.not. ctx%initialized) then
        write(error_unit, '(A)') &
            "ui_frame_begin_with_context: Error - Context not initialized"
        return
    end if

    timeout_val = 16
    if (present(timeout_ms)) timeout_val = timeout_ms

    call ctx%begin_frame()

    if (associated(ctx%backend)) then
        call ctx%backend%begin_frame()
    else
        write(error_unit, '(A)') &
            "ui_frame_begin_with_context: Error - No backend available"
        return
    end if
end subroutine ui_frame_begin_with_context

subroutine ui_frame_begin_default(timeout_ms)
    integer, intent(in), optional :: timeout_ms
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (associated(ctx)) then
        call ui_frame_begin_with_context(ctx, timeout_ms)
        return
    end if

    write(error_unit, '(A)') &
        "ui_frame_begin: Error - No default context available"
end subroutine ui_frame_begin_default

subroutine ui_present_with_context(ctx, tree)
    type(fortui_context_t), intent(inout) :: ctx
    type(node), intent(in) :: tree

    if (.not. ctx%initialized) then
        if (.not. ctx%shutting_down) then
            write(error_unit, '(A)') &
                "ui_present_with_context: Error - Context not initialized"
        end if
        return
    end if

    if (.not. ctx%in_frame) return

    if (associated(ctx%backend)) then
        call ctx%backend%render(tree)
    else
        write(error_unit, '(A)') &
            "ui_present_with_context: Error - No backend available"
    end if

    call ctx%end_frame()
end subroutine ui_present_with_context

subroutine ui_present_default(tree)
    type(node), intent(in) :: tree
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (associated(ctx)) then
        call ui_present_with_context(ctx, tree)
        return
    end if

    write(error_unit, '(A)') &
        "ui_present: Error - No default context available"
end subroutine ui_present_default

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
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (associated(ctx)) then
        should_close = ui_should_close_with_context(ctx)
        return
    end if

    should_close = .true.
end function ui_should_close_default

subroutine ui_shutdown_with_context(ctx)
    type(fortui_context_t), intent(inout) :: ctx

    if (associated(ctx%backend)) then
        call ctx%backend%shutdown()
    end if

    call ctx%shutdown()
end subroutine ui_shutdown_with_context

subroutine ui_shutdown_default()
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (associated(ctx)) then
        call ui_shutdown_with_context(ctx)
        call set_default_context(null())
    end if
end subroutine ui_shutdown_default

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
