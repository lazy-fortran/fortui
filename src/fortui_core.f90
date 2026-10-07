module fortui_core
!! FortUI lifecycle and backend selection for the reconciled immediate/retained model.
use fortui_context, only: fortui_context_t, create_context, destroy_context, &
    get_default_context, set_default_context
use fortui_frame, only: view
use fortui_input, only: input_begin_frame, input_route, KEY_ESCAPE
use fortui_layout, only: layout_reset, column_begin, column_end, row_begin, row_end
use fortui_render, only: render_present, BACKEND_NONE, BACKEND_HEADLESS, BACKEND_TUI, BACKEND_GUI
use fortui_error, only: report_error
implicit none
private

public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_request_quit, ui_is_initialized, ui_get_backend
public :: column_begin, column_end, row_begin, row_end
public :: view

contains

subroutine ui_init(backend, width, height, title, target_fps, vsync, stat)
    character(*), intent(in) :: backend
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in), optional :: target_fps
    logical, intent(in), optional :: vsync
    integer, intent(out), optional :: stat

    type(fortui_context_t), pointer :: ctx
    integer :: backend_id, fps
    logical :: use_vsync, ok

    if (present(stat)) stat = 0

    ctx => get_default_context()
    if (associated(ctx)) call ui_shutdown()

    backend_id = resolve_backend(backend)
    if (backend_id == BACKEND_NONE) then
        call report_error("fortui_core", "ui_init", "requested backend is unavailable")
        if (present(stat)) stat = 1
        return
    end if

    fps = 60
    if (present(target_fps)) fps = max(1, target_fps)
    use_vsync = .true.
    if (present(vsync)) use_vsync = vsync

    ctx => create_context()
    ctx%backend_id = backend_id
    ctx%backend_name = backend_name(backend_id)
    ctx%window_width = max(1, width)
    ctx%window_height = max(1, height)
    ctx%window_title = trim(title)
    ctx%target_fps = fps
    ctx%vsync = use_vsync

    ok = init_backend(ctx)
    if (.not. ok) then
        call report_error("fortui_core", "ui_init", "backend initialization failed")
        call destroy_context(ctx)
        if (present(stat)) stat = 2
        return
    end if

    ctx%initialized = .true.
    call set_default_context(ctx)
end subroutine ui_init

subroutine ui_frame_begin(timeout_ms)
    integer, intent(in), optional :: timeout_ms
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%initialized) then
        call report_error("fortui_core", "ui_frame_begin", "FortUI is not initialized")
        return
    end if

    call input_begin_frame(ctx%input)
    select case (ctx%backend_id)
    case (BACKEND_HEADLESS)
        continue
    case (BACKEND_TUI)
        call poll_tui(ctx, timeout_ms)
    case (BACKEND_GUI)
        call poll_gui(ctx)
    end select

    call input_route(ctx%input, ctx%previous_frame)
    if (ctx%input%key == KEY_ESCAPE) ctx%should_quit = .true.

    call ctx%current_frame%reset()
    call layout_reset()
    ctx%frame_count = ctx%frame_count + 1
    ctx%in_frame = .true.
end subroutine ui_frame_begin

subroutine ui_present()
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%initialized) return
    if (.not. ctx%in_frame) return

    call render_present(ctx%current_frame, ctx%backend_id)
    ctx%previous_frame = ctx%current_frame
    ctx%in_frame = .false.
end subroutine ui_present

logical function ui_should_close()
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%initialized) then
        ui_should_close = .true.
        return
    end if

    select case (ctx%backend_id)
    case (BACKEND_HEADLESS)
        ui_should_close = ctx%should_quit
    case (BACKEND_TUI)
        ui_should_close = ctx%should_quit .or. tui_close_requested()
    case (BACKEND_GUI)
        ui_should_close = ctx%should_quit .or. gui_close_requested()
    case default
        ui_should_close = .true.
    end select
end function ui_should_close

subroutine ui_request_quit()
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (associated(ctx)) ctx%should_quit = .true.
end subroutine ui_request_quit

subroutine ui_shutdown()
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) return

    select case (ctx%backend_id)
    case (BACKEND_TUI)
        call shutdown_tui()
    case (BACKEND_GUI)
        call shutdown_gui()
    end select

    call destroy_context(ctx)
end subroutine ui_shutdown

logical function ui_is_initialized()
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    ui_is_initialized = associated(ctx)
    if (associated(ctx)) ui_is_initialized = ctx%initialized
end function ui_is_initialized

function ui_get_backend() result(name)
    character(len=32) :: name
    type(fortui_context_t), pointer :: ctx

    name = ""
    ctx => get_default_context()
    if (associated(ctx)) name = ctx%backend_name
end function ui_get_backend

integer function resolve_backend(requested) result(id)
    character(*), intent(in) :: requested
    character(len=64) :: choice, env_value
    integer :: status

    choice = lower(trim(requested))
    call get_environment_variable("FORTUI_BACKEND", env_value, status=status)
    if (status == 0 .and. len_trim(env_value) > 0) choice = lower(trim(env_value))

    select case (trim(choice))
    case ("headless")
        id = BACKEND_HEADLESS
    case ("tui", "terminal", "console")
        if (tui_available()) then
            id = BACKEND_TUI
        else
            id = BACKEND_NONE
        end if
    case ("gui", "graphics", "window")
        if (gui_available()) then
            id = BACKEND_GUI
        else
            id = BACKEND_NONE
        end if
    case ("auto", "")
        if (gui_available()) then
            id = BACKEND_GUI
        else if (tui_available()) then
            id = BACKEND_TUI
        else
            call get_environment_variable("FORTUI_HEADLESS", env_value, status=status)
            if (status == 0 .and. trim(env_value) == "1") then
                id = BACKEND_HEADLESS
            else
                id = BACKEND_NONE
            end if
        end if
    case default
        id = BACKEND_NONE
    end select
end function resolve_backend

logical function init_backend(ctx)
    type(fortui_context_t), intent(in) :: ctx

    select case (ctx%backend_id)
    case (BACKEND_HEADLESS)
        init_backend = .true.
    case (BACKEND_TUI)
        init_backend = init_tui()
    case (BACKEND_GUI)
        init_backend = init_gui(ctx)
    case default
        init_backend = .false.
    end select
end function init_backend

logical function init_tui()
    use fortui_tui, only: tui_init
    init_tui = tui_init()
end function init_tui

logical function init_gui(ctx)
    use fortui_context, only: fortui_context_t
    type(fortui_context_t), intent(in) :: ctx
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_init
    init_gui = gui_init(ctx%window_width, ctx%window_height, trim(ctx%window_title), &
        ctx%target_fps, ctx%vsync)
#else
    init_gui = .false.
#endif
end function init_gui

subroutine poll_tui(ctx, timeout_ms)
    use fortui_context, only: fortui_context_t
    use fortui_tui, only: tui_poll
    type(fortui_context_t), intent(inout) :: ctx
    integer, intent(in), optional :: timeout_ms

    if (present(timeout_ms)) then
        call tui_poll(ctx%input, timeout_ms)
    else
        call tui_poll(ctx%input)
    end if
end subroutine poll_tui

subroutine poll_gui(ctx)
    use fortui_context, only: fortui_context_t
    type(fortui_context_t), intent(inout) :: ctx
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_poll
    call gui_poll(ctx%input)
#endif
end subroutine poll_gui

logical function tui_available()
    use fortui_tui, only: tui_is_available
    tui_available = tui_is_available()
end function tui_available

logical function gui_available()
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_is_available
    gui_available = gui_is_available()
#else
    gui_available = .false.
#endif
end function gui_available

logical function tui_close_requested()
    use fortui_tui, only: tui_should_close
    tui_close_requested = tui_should_close()
end function tui_close_requested

logical function gui_close_requested()
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_should_close
    gui_close_requested = gui_should_close()
#else
    gui_close_requested = .true.
#endif
end function gui_close_requested

subroutine shutdown_tui()
    use fortui_tui, only: tui_shutdown
    call tui_shutdown()
end subroutine shutdown_tui

subroutine shutdown_gui()
#ifdef ENABLE_GUI
    use fortui_gui, only: gui_shutdown
    call gui_shutdown()
#endif
end subroutine shutdown_gui

pure function backend_name(id) result(name)
    integer, intent(in) :: id
    character(len=32) :: name

    select case (id)
    case (BACKEND_HEADLESS); name = "headless"
    case (BACKEND_TUI); name = "tui"
    case (BACKEND_GUI); name = "gui"
    case default; name = ""
    end select
end function backend_name

pure function lower(value) result(out)
    character(*), intent(in) :: value
    character(len=len(value)) :: out
    integer :: i, code

    out = value
    do i = 1, len(value)
        code = iachar(out(i:i))
        if (code >= iachar('A') .and. code <= iachar('Z')) out(i:i) = achar(code + 32)
    end do
end function lower

end module fortui_core
