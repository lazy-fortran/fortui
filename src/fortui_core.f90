module fortui_core
!! FortUI lifecycle and backend selection for the reconciled immediate/retained model.
use fortui_context, only: fortui_context_t, create_context, destroy_context, &
    get_default_context, set_default_context
use fortui_frame, only: view
use fortui_input, only: input_begin_frame, input_route, input_update_pointer, &
    input_scroll, input_set_key, input_type_text, input_set_time, input_has_events, &
    KEY_ESCAPE
use fortui_layout, only: layout_reset, column_begin, column_end, row_begin, row_end, &
    split_begin, split_next, split_end
use fortui_frame, only: UI_TEXT_INPUT
use fortui_backend, only: ui_backend_t, ui_backend_caps_t
use fortui_backend_registry, only: create_backend
use fortui_text, only: text_use_fixed_metrics, text_set_font_files
use fortui_error, only: report_error
implicit none
private

type, public :: ui_stats_t
    !! Backend-neutral runtime counters for tests and performance probes.
    integer :: frames = 0
    integer :: waiting_presents = 0
    logical :: last_present_waits = .false.
    integer :: vertex_uploads = 0
    integer :: index_uploads = 0
    integer :: active_layers = 0
end type ui_stats_t

public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_request_quit, ui_is_initialized, ui_get_backend
public :: column_begin, column_end, row_begin, row_end
public :: split_begin, split_next, split_end
public :: view
public :: ui_request_frame, ui_set_continuous, ui_window_size, ui_scale, ui_stats
public :: ui_canvas_layer_uploads, ui_set_font
public :: ui_inject_pointer, ui_inject_wheel, ui_inject_key, ui_inject_text
public :: ui_inject_time, ui_inject_resize
public :: ui_backend_capabilities, ui_backend_caps_t

contains

subroutine ui_init(backend, width, height, title, target_fps, vsync, stat)
    !! Start FortUI with an explicitly named backend ("headless", "tui", "gui",
    !! or "auto"). An unavailable backend is an error (stat /= 0), not a fallback.
    !! target_fps = 0 means unlimited (useful for benchmarks with vsync off).
    character(*), intent(in) :: backend
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in), optional :: target_fps
    logical, intent(in), optional :: vsync
    integer, intent(out), optional :: stat

    type(fortui_context_t), pointer :: ctx
    class(ui_backend_t), allocatable :: chosen
    integer :: fps
    logical :: use_vsync, ok

    if (present(stat)) stat = 0

    ctx => get_default_context()
    if (associated(ctx)) call ui_shutdown()

    call create_backend(backend, chosen)
    if (.not. allocated(chosen)) then
        call report_error("fortui_core", "ui_init", "requested backend is unavailable")
        if (present(stat)) stat = 1
        return
    end if

    fps = 60
    if (present(target_fps)) fps = max(0, target_fps)
    use_vsync = .true.
    if (present(vsync)) use_vsync = vsync

    ctx => create_context()
    call move_alloc(chosen, ctx%backend)
    ctx%backend_name = ctx%backend%name()
    ctx%window_width = max(1, width)
    ctx%window_height = max(1, height)
    ctx%window_title = trim(title)
    ctx%target_fps = fps
    ctx%vsync = use_vsync

    ok = ctx%backend%init(ctx%window_width, ctx%window_height, trim(ctx%window_title), &
        ctx%target_fps, ctx%vsync)
    if (.not. ok) then
        call report_error("fortui_core", "ui_init", "backend initialization failed")
        call destroy_context(ctx)
        if (present(stat)) stat = 2
        return
    end if
    call ctx%backend%install_text_metrics()

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
    call ctx%backend%poll(ctx%input, ctx%window_width, ctx%window_height, ctx%ui_scale, &
        timeout_ms)
    ! Synthetic events (automation/tests) are normalized input for any backend.
    call apply_injected(ctx)

    call input_route(ctx%input, ctx%previous_frame)
    if (ctx%input%key == KEY_ESCAPE) then
        ! Escape leaves a focused text field first; otherwise it requests quit.
        if (focused_kind(ctx) == UI_TEXT_INPUT) then
            ctx%input%focus_id = ""
        else
            ctx%should_quit = .true.
        end if
    end if
    ctx%had_events = input_has_events(ctx%input)

    call ctx%current_frame%reset()
    ctx%canvas_node = 0
    call layout_reset(real(ctx%window_width), real(ctx%window_height))
    ctx%frame_count = ctx%frame_count + 1
    ctx%in_frame = .true.
end subroutine ui_frame_begin

subroutine ui_present()
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx) .or. .not. ctx%initialized) return
    if (.not. ctx%in_frame) return

    call ctx%canvas%collect(ctx%frame_count)
    call ctx%collect_states()
    ! Idle wait unless the application asked for frames or input arrived (one
    ! settle frame after input lets inline state changes become visible).
    ctx%last_present_waits = .not. (ctx%continuous .or. ctx%frame_requested .or. &
        ctx%had_events)
    if (ctx%last_present_waits) ctx%waiting_presents = ctx%waiting_presents + 1
    ctx%frame_requested = .false.
    call ctx%backend%present(ctx%current_frame, ctx%canvas, ctx%last_present_waits)
    ctx%previous_frame = ctx%current_frame
    ctx%in_frame = .false.
end subroutine ui_present

subroutine ui_request_frame()
    !! Present the next frame without waiting for input (one-shot).
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

subroutine ui_window_size(width, height)
    !! Current window size in logical units.
    real, intent(out) :: width, height
    type(fortui_context_t), pointer :: ctx

    width = 0.0
    height = 0.0
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    width = real(ctx%window_width)
    height = real(ctx%window_height)
end subroutine ui_window_size

real function ui_scale()
    !! Framebuffer pixels per logical unit (high-DPI factor).
    type(fortui_context_t), pointer :: ctx
    ui_scale = 1.0
    ctx => get_default_context()
    if (associated(ctx)) ui_scale = ctx%ui_scale
end function ui_scale

function ui_stats() result(stats)
    type(ui_stats_t) :: stats
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) return
    stats%frames = ctx%frame_count
    stats%waiting_presents = ctx%waiting_presents
    stats%last_present_waits = ctx%last_present_waits
    stats%vertex_uploads = ctx%canvas%vertex_uploads
    stats%index_uploads = ctx%canvas%index_uploads
    stats%active_layers = ctx%canvas%active_layers()
end function ui_stats

subroutine ui_canvas_layer_uploads(canvas_id, key, vertex_uploads, index_uploads)
    !! Realization counters of one retained layer (-1 when it does not exist).
    character(*), intent(in) :: canvas_id, key
    integer, intent(out) :: vertex_uploads, index_uploads
    type(fortui_context_t), pointer :: ctx
    integer :: slot

    vertex_uploads = -1
    index_uploads = -1
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    slot = ctx%canvas%lookup(trim(canvas_id) // "/" // trim(key))
    if (slot == 0) return
    vertex_uploads = ctx%canvas%layers(slot)%vertex_uploads
    index_uploads = ctx%canvas%layers(slot)%index_uploads
end subroutine ui_canvas_layer_uploads

subroutine ui_set_font(regular, bold)
    !! Use TTF files instead of the bundled DejaVu Sans subset. Call before ui_init.
    character(*), intent(in) :: regular
    character(*), intent(in), optional :: bold
    call text_set_font_files(regular, bold)
end subroutine ui_set_font

subroutine ui_inject_pointer(x, y, down)
    !! Headless: pointer state seen by the next ui_frame_begin.
    real, intent(in) :: x, y
    logical, intent(in) :: down
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    ctx%inject_pointer = .true.
    ctx%inject_x = x
    ctx%inject_y = y
    ctx%inject_down = down
end subroutine ui_inject_pointer

subroutine ui_inject_wheel(steps)
    real, intent(in) :: steps
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (associated(ctx)) ctx%inject_wheel = ctx%inject_wheel + steps
end subroutine ui_inject_wheel

subroutine ui_inject_key(key)
    integer, intent(in) :: key
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    if (ctx%inject_key_count >= size(ctx%inject_keys)) return
    ctx%inject_key_count = ctx%inject_key_count + 1
    ctx%inject_keys(ctx%inject_key_count) = key
end subroutine ui_inject_key

subroutine ui_inject_text(utf8)
    character(*), intent(in) :: utf8
    type(fortui_context_t), pointer :: ctx
    integer :: n
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    n = min(len(utf8), len(ctx%inject_text) - ctx%inject_text_len)
    if (n <= 0) return
    ctx%inject_text(ctx%inject_text_len + 1:ctx%inject_text_len + n) = utf8(1:n)
    ctx%inject_text_len = ctx%inject_text_len + n
end subroutine ui_inject_text

subroutine ui_inject_time(seconds)
    double precision, intent(in) :: seconds
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (associated(ctx)) ctx%inject_time = seconds
end subroutine ui_inject_time

subroutine ui_inject_resize(width, height)
    integer, intent(in) :: width, height
    type(fortui_context_t), pointer :: ctx
    ctx => get_default_context()
    if (.not. associated(ctx)) return
    ctx%window_width = max(1, width)
    ctx%window_height = max(1, height)
    ctx%inject_resize = .true.
end subroutine ui_inject_resize

subroutine apply_injected(ctx)
    type(fortui_context_t), intent(inout) :: ctx
    integer :: k

    if (ctx%inject_time >= 0.0d0) call input_set_time(ctx%input, ctx%inject_time)
    if (ctx%inject_pointer) call input_update_pointer(ctx%input, ctx%inject_x, &
        ctx%inject_y, ctx%inject_down)
    if (abs(ctx%inject_wheel) > 0.0) call input_scroll(ctx%input, &
        nint(sign(1.0, ctx%inject_wheel)), ctx%inject_wheel)
    do k = 1, ctx%inject_key_count
        call input_set_key(ctx%input, ctx%inject_keys(k))
    end do
    if (ctx%inject_text_len > 0) call input_type_text(ctx%input, &
        ctx%inject_text(1:ctx%inject_text_len))
    ctx%input%resized = ctx%inject_resize
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
    i = ctx%previous_frame%find(trim(ctx%input%focus_id))
    if (i > 0) kind = ctx%previous_frame%nodes(i)%kind
end function focused_kind

logical function ui_should_close()
    type(fortui_context_t), pointer :: ctx

    ctx => get_default_context()
    if (.not. associated(ctx)) then
        ui_should_close = .true.
        return
    end if
    if (.not. ctx%initialized) then
        ui_should_close = .true.
        return
    end if
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
