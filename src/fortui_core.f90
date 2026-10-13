module fortui_core
!! FortUI lifecycle, frame transactions and idle scheduling. The core knows only
!! the abstract backend interface; applications inject a backend value.
use fortui_context, only: fortui_context_t, create_context, destroy_context, &
    get_default_context, set_default_context
use fortui_input, only: input_begin_frame, input_route, input_update_pointer, &
    input_scroll, input_set_key, input_type_text, input_set_time, input_key_arrived, &
    KEY_ESCAPE
use fortui_layout, only: layout_reset, layout_check_balance
use fortui_frame, only: UI_TEXT_INPUT, style_weight
use fortui_backend, only: ui_backend_t, ui_backend_caps_t, ui_window_config_t
use fortui_text, only: text_use_fixed_metrics, text_width
use fortui_error, only: report_error
implicit none
private

interface ui_init
    !! Start FortUI with an injected backend (see also fortui_backends).
    module procedure ui_init_backend
end interface ui_init

public :: ui_init, ui_init_backend, ui_shutdown, ui_frame_begin, ui_present
public :: ui_should_close, ui_request_quit, ui_is_initialized, ui_get_backend
public :: ui_request_frame, ui_set_continuous, ui_window_size, ui_scale
public :: ui_key_pressed, ui_text_width, ui_backend_capabilities, ui_backend_caps_t

contains

subroutine ui_init_backend(backend, width, height, title, target_fps, vsync, stat)
    !! Start FortUI with `backend`, a backend value such as `headless_backend_t()`.
    !! The runtime keeps its own copy and creates the platform resources; a host
    !! that is unavailable is an error (stat /= 0), never a fallback.
    !! target_fps = 0 means unlimited (useful for benchmarks with vsync off).
    class(ui_backend_t), intent(in) :: backend
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in), optional :: target_fps
    logical, intent(in), optional :: vsync
    integer, intent(out), optional :: stat

    type(fortui_context_t), pointer :: ctx
    type(ui_window_config_t) :: config

    if (present(stat)) stat = 0
    ctx => get_default_context()
    if (associated(ctx)) call ui_shutdown()

    config%width = max(1, width)
    config%height = max(1, height)
    config%title = title
    if (present(target_fps)) config%target_fps = max(0, target_fps)
    if (present(vsync)) config%vsync = vsync

    ctx => create_context()
    allocate(ctx%backend, source=backend)
    ctx%backend%config = config
    ctx%input%width = config%width
    ctx%input%height = config%height
    if (.not. ctx%backend%init()) then
        call report_error("fortui_core", "ui_init", "backend '" // &
            ctx%backend%name() // "' could not be initialized")
        call destroy_context(ctx)
        if (present(stat)) stat = 2
        return
    end if
    ctx%backend_name = ctx%backend%name()
    call ctx%backend%install_text_metrics()
    ctx%initialized = .true.
    call set_default_context(ctx)
end subroutine ui_init_backend

subroutine ui_frame_begin()
    !! Start one composition: poll the host (blocking only when the previous
    !! present allowed idle waiting), route input against the previous frame.
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        call report_error("fortui_core", "ui_frame_begin", "FortUI is not initialized")
        return
    end if
    if (ctx%in_frame) then
        call report_error("fortui_core", "ui_frame_begin", "frame already open")
        return
    end if

    call input_begin_frame(ctx%input)
    call ctx%backend%poll(ctx%input, ctx%wait_next)
    ! Synthetic events (automation/tests) are normalized input for any backend.
    call apply_injected(ctx)

    call input_route(ctx%input, ctx%previous_frame)
    ctx%text_focused = focused_kind(ctx) == UI_TEXT_INPUT
    ! Escape leaves a focused text field; otherwise it is an ordinary key.
    if (ctx%text_focused .and. input_key_arrived(ctx%input, KEY_ESCAPE)) &
        ctx%input%focus_id = ""

    call ctx%current_frame%reset()
    ctx%canvas_node = 0
    call layout_reset(real(ctx%input%width), real(ctx%input%height))
    ctx%frame_count = ctx%frame_count + 1
    ctx%in_frame = .true.
end subroutine ui_frame_begin

subroutine ui_present()
    !! Close the composition: check container balance, release absent widgets
    !! and layers, decide idle waiting and hand the frame to the backend.
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) return
    if (.not. ctx%in_frame) return

    if (ctx%canvas_node /= 0) then
        call report_error("fortui_core", "ui_present", &
            "canvas_begin without canvas_end at frame end")
        ctx%canvas_node = 0
    end if
    call layout_check_balance()
    call ctx%canvas%collect(ctx%frame_count)
    call ctx%collect_states()
    ctx%wait_next = .not. (ctx%continuous .or. ctx%frame_requested .or. ctx%followup)
    if (ctx%wait_next) ctx%waiting_presents = ctx%waiting_presents + 1
    if (ctx%followup) ctx%followups = ctx%followups + 1
    ctx%frame_requested = .false.
    ctx%followup = .false.
    call ctx%backend%present(ctx%current_frame, ctx%canvas)
    call ctx%swap_frames()
    ctx%in_frame = .false.
end subroutine ui_present

subroutine ui_request_frame()
    !! Present the next frame without waiting for input (one-shot), e.g. after
    !! an asynchronous result changed application state outside composition.
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (associated(ctx)) ctx%frame_requested = .true.
end subroutine ui_request_frame

subroutine ui_set_continuous(enabled)
    !! Continuous frames (e.g. during an animation) instead of idle waiting.
    logical, intent(in) :: enabled
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (associated(ctx)) ctx%continuous = enabled
end subroutine ui_set_continuous

logical function ui_key_pressed(key) result(pressed)
    !! Application shortcut query: `key` (KEY_*) arrived in the current frame and
    !! was not consumed by a focused text field. A true result schedules a
    !! follow-up frame so that the reaction becomes visible.
    integer, intent(in) :: key
    type(fortui_context_t), pointer :: ctx
    pressed = .false.
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    if (.not. ctx%in_frame .or. ctx%text_focused) return
    pressed = input_key_arrived(ctx%input, key)
    if (pressed) ctx%followup = .true.
end function ui_key_pressed

real function ui_text_width(value, size, style) result(width)
    !! Logical width of UTF-8 `value` at logical `size` with the active backend's
    !! metrics; `style` is a style token (UI_BODY, UI_HEADING, ...).
    character(*), intent(in) :: value
    real, intent(in) :: size
    integer, intent(in), optional :: style
    if (present(style)) then
        width = text_width(value, size, style_weight(style))
    else
        width = text_width(value, size)
    end if
end function ui_text_width

subroutine ui_window_size(width, height)
    !! Current window size in logical units.
    real, intent(out) :: width, height
    type(fortui_context_t), pointer :: ctx

    width = 0.0
    height = 0.0
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    width = real(ctx%input%width)
    height = real(ctx%input%height)
end subroutine ui_window_size

real function ui_scale()
    !! Framebuffer pixels per logical unit (high-DPI factor).
    type(fortui_context_t), pointer :: ctx
    ui_scale = 1.0
    ctx => get_default_context()
    if (associated(ctx)) ui_scale = ctx%input%scale
end function ui_scale

subroutine apply_injected(ctx)
    type(fortui_context_t), intent(inout) :: ctx
    integer :: k

    if (ctx%inject_time >= 0.0d0) call input_set_time(ctx%input, ctx%inject_time)
    if (ctx%inject_resize) then
        ctx%input%width = ctx%inject_width
        ctx%input%height = ctx%inject_height
        ctx%input%resized = .true.
    end if
    if (ctx%inject_pointer) call input_update_pointer(ctx%input, ctx%inject_x, &
        ctx%inject_y, ctx%inject_down)
    if (abs(ctx%inject_wheel) > 0.0) call input_scroll(ctx%input, &
        nint(sign(1.0, ctx%inject_wheel)), ctx%inject_wheel)
    do k = 1, ctx%inject_key_count
        call input_set_key(ctx%input, ctx%inject_keys(k))
    end do
    if (ctx%inject_text_len > 0) call input_type_text(ctx%input, &
        ctx%inject_text(1:ctx%inject_text_len))
    ctx%inject_pointer = .false.
    ctx%inject_wheel = 0.0
    ctx%inject_key_count = 0
    ctx%inject_text_len = 0
    ctx%inject_resize = .false.
end subroutine apply_injected

integer function focused_kind(ctx) result(kind)
    type(fortui_context_t), intent(in) :: ctx
    integer :: i

    kind = 0
    if (len_trim(ctx%input%focus_id) == 0) return
    i = ctx%previous_frame%find(ctx%input%focus_id)
    if (i > 0) kind = ctx%previous_frame%nodes(i)%kind
end function focused_kind

logical function ui_should_close()
    !! The application or the host asked to quit.
    type(fortui_context_t), pointer :: ctx

    ui_should_close = .true.
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    if (.not. ctx%initialized) return
    ui_should_close = ctx%should_quit .or. ctx%backend%should_close()
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

    if (allocated(ctx%backend)) call ctx%backend%shutdown()
    call text_use_fixed_metrics()
    call layout_reset()
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

function ui_backend_capabilities() result(caps)
    !! Capabilities of the active backend (all false when not initialized).
    type(ui_backend_caps_t) :: caps
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    if (allocated(ctx%backend)) caps = ctx%backend%capabilities()
end function ui_backend_capabilities

end module fortui_core
