module fortui_core
    !! FortUI lifecycle, frame transactions and idle scheduling. The core knows only
    !! the abstract backend interface; applications inject a backend value.
    use iso_fortran_env, only: int32, int64
    use fortui_context, only: fortui_context_t, create_context, destroy_context, &
        get_default_context, set_default_context
    use fortui_input, only: input_begin_frame, input_route, input_update_pointer, input_pointer_event, &
        input_scroll, input_set_key, input_type_text, input_set_time, input_key_arrived, &
        KEY_ESCAPE, input_apply_host, input_host_event, input_key_press, &
        input_sort_presses, input_shortcut, input_commit_chords, input_presses_wait, FOCUS_PLAIN, &
        FOCUS_CONTROL, FOCUS_RANGE, FOCUS_FIELD, FOCUS_EDITOR, FOCUS_TERMINAL
    use fortui_layout, only: layout_reset, layout_check_balance, layout_boxes
    use fortui_frame, only: UI_TEXT_INPUT, UI_TEXT_AREA, UI_NONE, UI_SLIDER, &
        UI_SCROLL_TEXT, UI_LIST_BOX, style_weight
    use fortui_backend, only: ui_backend_t, ui_backend_caps_t, ui_window_config_t
    use fortui_text, only: text_use_fixed_metrics, text_width
    use fortui_error, only: report_error
    use fortui_theme, only: theme, theme_select, theme_requested, theme_set, theme_plain, &
        theme_refresh, theme_follows_desktop
    use iso_c_binding, only: c_funptr, c_null_funptr
    implicit none
    private

    interface ui_init
        !! Start FortUI with an injected backend (see also fortui_backends).
        module procedure ui_init_backend
    end interface ui_init

    public :: ui_init, ui_init_backend, ui_shutdown, ui_frame_begin, ui_present
    public :: ui_should_close, ui_request_quit, ui_is_initialized, ui_get_backend
    public :: ui_request_frame, ui_set_continuous, ui_window_size, ui_scale
    public :: ui_time, ui_wake_after
    public :: ui_clipboard_set, ui_clipboard_text, ui_set_title, ui_waker, ui_set_window_margin
    public :: ui_set_window_size, ui_set_window_visible, ui_maximize_window, ui_open_url, ui_offer_file
    public :: ui_set_window_background
    public :: ui_primary_set, ui_primary_text
    public :: ui_key_pressed, ui_text_width, ui_backend_capabilities, ui_backend_caps_t
    public :: ui_shortcut, ui_set_theme, ui_theme_name
    public :: ui_backend_description, ui_run, ui_run_step, ui_frame_proc
    public :: ui_locale, ui_url_param, ui_width_class, ui_appearance_changed
    public :: ui_set_url_param, ui_location, ui_store_get, ui_store_set, ui_store_use
    !> Window width classes (as in Material 3): phones, tablets and folded
    !! windows, laptops, wide desktops.
    integer, parameter, public :: UI_COMPACT = 1, UI_MEDIUM = 2, UI_EXPANDED = 3, UI_LARGE = 4

    abstract interface
        subroutine ui_frame_proc()
            !! Composes one frame: the body of the frame loop.
        end subroutine ui_frame_proc
    end interface

    ! The application's frame procedure while a host drives the frames.
    procedure(ui_frame_proc), pointer, save :: driven_frame => null()
    double precision, save :: appearance_checked = -1d9

contains

    subroutine ui_init_backend(backend, width, height, title, target_fps, vsync, stat, &
            theme_name, hidden)
        !! Start FortUI with `backend`, a backend value such as `headless_backend_t()`.
        !! The runtime keeps its own copy and creates the platform resources; a host
        !! that is unavailable is an error (stat /= 0), never a fallback.
        !! target_fps = 0 means unlimited (useful for benchmarks with vsync off).
        !! Desktop backends use the theme the user asked for (FORTUI_THEME, else
        !! `theme =` in ~/.config/fortui/config), else `theme_name`, else
        !! "fluent"; the browser uses `theme_name` only (else the page's own
        !! look); headless and terminal backends use the plain metrics.
        class(ui_backend_t), intent(in) :: backend
        integer, intent(in) :: width, height
        character(*), intent(in) :: title
        integer, intent(in), optional :: target_fps
        logical, intent(in), optional :: vsync
        integer, intent(out), optional :: stat
        character(*), intent(in), optional :: theme_name
        !! Create the window hidden (ui_set_window_visible shows it), so a
        !! program can start ahead of time and appear at once later.
        logical, intent(in), optional :: hidden
        character(len=:), allocatable :: wanted
        logical :: ok
        type(ui_backend_caps_t) :: caps

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
        if (present(hidden)) config%hidden = hidden

        caps = backend%capabilities()
        if (caps%host_driven) then
            ! The browser: a theme only when the application asks for one; else the
            ! page keeps its own look.
            ok = .false.
            if (present(theme_name)) call theme_select(theme_name, ok)
            if (.not. ok) call theme_set(theme_plain())
        else if (caps%graphical) then
            wanted = "fluent"
            if (present(theme_name)) wanted = theme_name
            wanted = theme_requested(wanted)
            call theme_select(wanted, ok)
            if (.not. ok) then
                write (0, '(a)') "fortui: unknown theme '" // wanted // "' (fluent, " // &
                    "fluent-dark, classic); using fluent"
                call theme_select("fluent", ok)
            end if
        else
            call theme_set(theme_plain())
        end if
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
        appearance_checked = -1d9
        ctx%initialized = .true.
        call set_default_context(ctx)
        call ctx%backend%network(ctx%net)
    end subroutine ui_init_backend

    subroutine ui_set_theme(name, stat)
        !! Switch to the built-in theme `name` at run time (fluent, fluent-dark,
        !! classic); the next frame is drawn with it.
        character(*), intent(in) :: name
        integer, intent(out), optional :: stat
        type(fortui_context_t), pointer :: ctx
        logical :: ok
        call theme_select(name, ok)
        if (present(stat)) stat = merge(0, 1, ok)
        if (.not. ok) return
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. allocated(ctx%backend)) return
        call ctx%backend%install_text_metrics()
        call ui_request_frame()
    end subroutine ui_set_theme

    function ui_theme_name() result(name)
        !! Name of the current theme.
        character(len=:), allocatable :: name
        name = trim(theme%name)
    end function ui_theme_name

    subroutine ui_frame_begin()
        !! Start one composition: poll the host (blocking only when the previous
        !! present allowed idle waiting), route input against the previous frame.
        type(fortui_context_t), pointer :: ctx
        double precision :: press_time
        integer :: focus_level

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

        call input_apply_host(ctx%input)
        call input_route(ctx%input, ctx%previous_frame)
        ctx%text_focused = focused_kind(ctx) == UI_TEXT_INPUT .or. &
            focused_kind(ctx) == UI_TEXT_AREA
        ! Shortcuts: what the focused control does with keys itself.
        if (focused_keyboard(ctx)) then
            focus_level = FOCUS_TERMINAL
        else
            select case (focused_kind(ctx))
            case (UI_NONE); focus_level = FOCUS_PLAIN
            case (UI_TEXT_INPUT); focus_level = FOCUS_FIELD
            case (UI_TEXT_AREA); focus_level = FOCUS_EDITOR
            case (UI_SLIDER, UI_SCROLL_TEXT, UI_LIST_BOX); focus_level = FOCUS_RANGE
            case default; focus_level = FOCUS_CONTROL
            end select
        end if
        press_time = ui_time()
        if (ctx%inject_time >= 0.0d0) press_time = ctx%inject_time
        call input_sort_presses(ctx%input, focus_level, press_time)
        ! A chord pressed again before this frame is pressed in the next one.
        if (input_presses_wait(ctx%input)) ctx%followup = .true.
        ! Escape leaves a focused text field; otherwise it is an ordinary key.
        if (ctx%text_focused .and. input_key_arrived(ctx%input, KEY_ESCAPE)) &
            ctx%input%focus_id = ""

        if (theme_follows_desktop()) then
            if (ui_time() - appearance_checked >= 2d0) then
                if (theme_refresh()) call ctx%backend%install_text_metrics()
                appearance_checked = ui_time()
            end if
        end if
        call ctx%current_frame%reset()
        ctx%canvas_node = 0
        if (ctx%window_margin >= 0.0) then
            call layout_reset(real(ctx%input%width), real(ctx%input%height), ctx%window_margin)
        else
            call layout_reset(real(ctx%input%width), real(ctx%input%height), theme%margin)
        end if
        ! Counters wrap explicitly (only compared for equality), so months of
        ! frames never overflow.
        ctx%frame_count = modulo(ctx%frame_count + 1, 2**30)
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
        if (associated(ctx%overlays)) call ctx%overlays()
        call layout_boxes(ctx%current_frame%boxes, ctx%current_frame%box_count)
        call apply_requests(ctx)
        call input_commit_chords(ctx%input)
        call ctx%canvas%collect(ctx%frame_count)
        call ctx%collect_states()
        ctx%wait_next = .not. (ctx%continuous .or. ctx%frame_requested .or. ctx%followup)
        ! A due timer makes the next frame come without input; a later one bounds
        ! the wait for input.
        ctx%backend%wake_in = -1.0
        if (ctx%wake_at >= 0d0) then
            if (ui_time() >= ctx%wake_at) then
                ctx%wake_at = -1d0
                ctx%wait_next = .false.
            else if (ctx%wait_next) then
                ctx%backend%wake_in = real(ctx%wake_at - ui_time())
            end if
        end if
        if (ctx%wait_next .and. theme_follows_desktop()) then
            if (ctx%backend%wake_in < 0.0) then
                ctx%backend%wake_in = real(max(0d0, appearance_checked + 2d0 - ui_time()))
            else
                ctx%backend%wake_in = min(ctx%backend%wake_in, &
                    real(max(0d0, appearance_checked + 2d0 - ui_time())))
            end if
        end if
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

    double precision function ui_time() result(seconds)
        !! Seconds on a monotonic clock, for timers and animations.
        integer(int64) :: count, rate
        call system_clock(count, rate)
        seconds = real(count, kind(seconds)) / real(max(rate, 1_int64), kind(seconds))
    end function ui_time

    subroutine ui_wake_after(seconds)
        !! A frame after `seconds` without input (one-shot; the earliest request
        !! wins), for clocks, countdowns and retries. The host waits for it
        !! without polling.
        real, intent(in) :: seconds
        type(fortui_context_t), pointer :: ctx
        double precision :: at
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        at = ui_time() + max(0.0, seconds)
        if (ctx%wake_at < 0d0 .or. at < ctx%wake_at) ctx%wake_at = at
    end subroutine ui_wake_after

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

    logical function ui_shortcut(chord, repeat, label) result(pressed)
        !! Keyboard shortcut: asks for `chord` in this frame and is true in the
        !! frame in which it was pressed (which schedules a follow-up frame).
        !!
        !! A chord is a key with optional modifiers, "j", "?", "Enter", "Escape",
        !! "mod+k", "ctrl+shift+ArrowUp", or two keys pressed within a second,
        !! "g o". Modifiers: mod (Cmd on macOS, Ctrl elsewhere), ctrl, alt, shift,
        !! meta. Keys: one character, or Enter, Escape, Tab, Space, Backspace,
        !! Delete, Insert, Home, End, PageUp, PageDown, ArrowLeft, ArrowRight,
        !! ArrowUp, ArrowDown. A character alone is the character typed ("?" and
        !! "G" need no shift); with ctrl, alt, meta or mod a letter ignores case
        !! and shift is written out ("mod+shift+p"). A chord that cannot be read
        !! is never pressed.
        !!
        !! Keys the control with the focus uses itself are not shortcuts: a text
        !! field keeps everything typed into it and gives up only ArrowUp,
        !! ArrowDown, Enter and Escape, a field of several lines only Escape; a
        !! button keeps Enter and Space, a slider also the navigation keys. A
        !! chord with ctrl, meta or mod is pressed wherever the focus is.
        !!
        !! A chord pressed several times before a frame is pressed in as many
        !! frames, one after the other, so no press is lost.
        !! Key repeats count only with `repeat`. A key that completes a chord of
        !! two keys is not also that key alone. In the browser the page's own
        !! reaction to a key (scrolling, quick find, the address bar) is
        !! suppressed exactly for the chords of the last frame; hosts that do
        !! not report modifiers or repeats (a terminal knows Ctrl with a letter
        !! only) cannot press such chords.
        !! `label` names the action for hosts that list shortcuts, such as the
        !! terminal's function key line ("ctrl+s" with label "Save" shows
        !! "Ctrl+S=Save").
        character(*), intent(in) :: chord
        logical, intent(in), optional :: repeat
        character(*), intent(in), optional :: label
        type(fortui_context_t), pointer :: ctx
        integer :: k

        pressed = .false.
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. ctx%in_frame) return
        if (present(label)) then
            associate(f => ctx%current_frame)
                if (f%hint_count < size(f%hint_keys) .and. .not. any(f%hint_keys(1:f%hint_count) &
                    == chord)) then
                    k = f%hint_count + 1
                    f%hint_keys(k) = chord
                    f%hint_labels(k) = label
                    f%hint_count = k
                end if
            end associate
        end if
        pressed = input_shortcut(ctx%input, chord, repeat)
        if (pressed) ctx%followup = .true.
    end function ui_shortcut

    subroutine apply_requests(ctx)
        !! Focus and reveal asked for during composition, wherever the control
        !! was composed: the presented frame already shows them.
        type(fortui_context_t), intent(inout) :: ctx
        integer :: i, k

        if (len_trim(ctx%focus_request) > 0) then
            i = resolve(ctx, ctx%focus_request, ctx%focus_name)
            if (i > 0) then
                if (ctx%current_frame%nodes(i)%focusable .and. &
                    .not. ctx%current_frame%nodes(i)%disabled) then
                    ctx%input%focus_id = ctx%current_frame%nodes(i)%id
                    do k = 1, ctx%current_frame%count
                        ctx%current_frame%nodes(k)%focused = k == i
                    end do
                end if
            end if
            ctx%focus_request = ""
            ctx%focus_name = ""
        end if
        if (len_trim(ctx%reveal_request) > 0) then
            i = resolve(ctx, ctx%reveal_request, ctx%reveal_name)
            if (i > 0) ctx%current_frame%nodes(i)%reveal = .true.
            ctx%reveal_request = ""
            ctx%reveal_name = ""
        end if
    end subroutine apply_requests

    integer function resolve(ctx, scoped, name) result(found)
        !! The node with the scoped identity, else the one node whose identity is
        !! `name` or ends in "/" // name; 0 when there is none or several.
        type(fortui_context_t), intent(in) :: ctx
        character(*), intent(in) :: scoped, name
        integer :: k, n
        character(len=:), allocatable :: tail, nid
        found = ctx%current_frame%find(trim(scoped))
        if (found > 0 .or. len_trim(name) == 0) return
        tail = "/" // trim(name)
        n = 0
        do k = 1, ctx%current_frame%count
            nid = trim(ctx%current_frame%nodes(k)%id)
            if (nid == trim(name)) then
                n = n + 1
                found = k
            else if (len(nid) > len(tail)) then
                if (nid(len(nid) - len(tail) + 1:) == tail) then
                    n = n + 1
                    found = k
                end if
            end if
        end do
        if (n /= 1) found = 0
    end function resolve

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
        do k = 1, ctx%inject_events
            associate (e => ctx%inject_event(:, k))
                call input_pointer_event(ctx%input, e(1), e(2), e(3) > 0.5, nint(e(4)), e(5), &
                    e(6), e(7), nint(e(8)))
            end associate
        end do
        ctx%inject_events = 0
        if (abs(ctx%inject_wheel) > 0.0) call input_scroll(ctx%input, &
            nint(sign(1.0, ctx%inject_wheel)), ctx%inject_wheel)
        do k = 1, ctx%inject_key_count
            call input_set_key(ctx%input, ctx%inject_keys(k))
        end do
        if (ctx%inject_text_len > 0) call input_type_text(ctx%input, &
            ctx%inject_text(1:ctx%inject_text_len))
        do k = 1, ctx%inject_press_count
            associate (p => ctx%inject_presses(k))
                call input_key_press(ctx%input, p%key, p%code, p%mods, repeat=p%repeat, &
                    focus=p%focus, mac=p%mac)
            end associate
        end do
        ctx%inject_press_count = 0
        do k = 1, ctx%inject_host_count
            call input_host_event(ctx%input, ctx%inject_host(k)%kind, &
                trim(ctx%inject_host(k)%id), ctx%inject_host(k)%value)
        end do
        ctx%inject_host_count = 0
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

    logical function focused_keyboard(ctx) result(yes)
        type(fortui_context_t), intent(in) :: ctx
        integer :: i
        yes = .false.
        if (len_trim(ctx%input%focus_id) == 0) return
        i = ctx%previous_frame%find(ctx%input%focus_id)
        if (i > 0) yes = ctx%previous_frame%nodes(i)%keyboard
    end function focused_keyboard

    subroutine ui_set_window_margin(margin)
        !! Free space around the window's content in logical units, instead of
        !! the theme's (0 for content that fills the window, such as a
        !! terminal); a negative margin returns to the theme's.
        real, intent(in) :: margin
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (associated(ctx)) ctx%window_margin = margin
    end subroutine ui_set_window_margin

    subroutine ui_clipboard_set(text)
        !! Put UTF-8 `text` on the system clipboard.
        character(*), intent(in) :: text
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%clipboard_set(text)
    end subroutine ui_clipboard_set

    function ui_clipboard_text() result(text)
        !! The clipboard's text ("" when empty or the host has no clipboard).
        character(len=:), allocatable :: text
        type(fortui_context_t), pointer :: ctx
        text = ""
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%clipboard_get(text)
    end function ui_clipboard_text

    subroutine ui_set_window_size(width, height)
        !! Resize the window to width x height logical units.
        integer, intent(in) :: width, height
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%set_window_size(width, height)
    end subroutine ui_set_window_size

    subroutine ui_primary_set(text)
        !! Make `text` the primary selection (X11: what middle-click pastes).
        character(*), intent(in) :: text
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%primary_set(text)
    end subroutine ui_primary_set

    function ui_primary_text() result(text)
        !! The primary selection ("" when empty or the host has none).
        character(len=:), allocatable :: text
        type(fortui_context_t), pointer :: ctx
        text = ""
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%primary_get(text)
    end function ui_primary_text

    subroutine ui_offer_file(path)
        !! Offers a file the application wrote (file_write) to the person: a
        !! download in the browser, nothing more on the desktop.
        character(*), intent(in) :: path
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%offer_file(path)
    end subroutine ui_offer_file

    subroutine ui_open_url(url)
        !! Open `url` with the desktop's handler (the default browser).
        character(*), intent(in) :: url
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%open_url(url)
    end subroutine ui_open_url

    subroutine ui_set_window_background(colour)
        !! The window's background (ui_rgba) in place of the theme's: what shows
        !! where nothing is drawn and before the first frame, so that an
        !! application drawn over in another colour (a terminal) never shows the
        !! theme's. Call it after ui_init, before the first frame.
        integer(int32), intent(in) :: colour
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. ctx%initialized) return
        ctx%backend%own_background = .true.
        ctx%backend%background = colour
    end subroutine ui_set_window_background

    subroutine ui_maximize_window()
        !! Fill the screen's work area with the window.
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%maximize_window()
    end subroutine ui_maximize_window

    subroutine ui_set_window_visible(visible)
        !! Show (and raise) or hide the window.
        logical, intent(in) :: visible
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%set_window_visible(visible)
    end subroutine ui_set_window_visible

    subroutine ui_set_title(title)
        !! The window title (the terminal's title on a terminal host).
        character(*), intent(in) :: title
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%set_title(title)
    end subroutine ui_set_title

    function ui_waker() result(fn)
        !! A C function any thread may call to wake the event loop (a null
        !! pointer when the host has none; then wake with ui_wake_after).
        type(c_funptr) :: fn
        type(fortui_context_t), pointer :: ctx
        fn = c_null_funptr
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) fn = ctx%backend%waker()
    end function ui_waker

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
        ! A host-driven application keeps running after ui_run returned.
        if (associated(driven_frame)) return

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

    subroutine ui_appearance_changed()
        !! The host reports that the desktop's light or dark preference changed:
        !! a theme that follows it is looked at again in the next frame.
        appearance_checked = -1d9
        call ui_request_frame()
    end subroutine ui_appearance_changed

    integer function ui_width_class() result(class)
        !! UI_COMPACT below 600 logical units of window width, UI_MEDIUM below
        !! 840, UI_EXPANDED below 1200, else UI_LARGE: the breakpoints for
        !! layouts that adapt from phone to desktop.
        real :: w, h
        call ui_window_size(w, h)
        if (w < 600.0) then
            class = UI_COMPACT
        else if (w < 840.0) then
            class = UI_MEDIUM
        else if (w < 1200.0) then
            class = UI_EXPANDED
        else
            class = UI_LARGE
        end if
    end function ui_width_class

    function ui_locale() result(tag)
        !! The user's language as a BCP 47 tag ("zh-CN", "en-US"), "" when unknown.
        character(len=:), allocatable :: tag
        type(fortui_context_t), pointer :: ctx
        tag = ""
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) tag = ctx%backend%locale()
    end function ui_locale

    function ui_url_param(name) result(value)
        !! A parameter of the address the application was opened with ("?site=cn"
        !! gives "cn" for "site"); "" when absent or on hosts without one.
        character(*), intent(in) :: name
        character(len=:), allocatable :: value
        type(fortui_context_t), pointer :: ctx
        value = ""
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) value = ctx%backend%url_param(name)
    end function ui_url_param

    subroutine ui_set_url_param(name, value, push)
        !! Put a parameter into the address, so it can be shared and reopened
        !! ("" removes it). With `push`, Back returns to the address before;
        !! an application that keeps its view in the address reads it with
        !! ui_url_param in every frame and so follows Back and Forward too.
        character(*), intent(in) :: name, value
        logical, intent(in), optional :: push
        type(fortui_context_t), pointer :: ctx
        logical :: step
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (.not. ctx%initialized) return
        step = .false.
        if (present(push)) step = push
        if (ctx%backend%url_param(name) == value) return
        call ctx%backend%set_url_param(name, value, step)
    end subroutine ui_set_url_param

    function ui_location() result(where)
        !! The address of what is shown, to share: the page's address in a
        !! browser, "?name=value&..." elsewhere.
        character(len=:), allocatable :: where
        type(fortui_context_t), pointer :: ctx
        where = ""
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) where = ctx%backend%location()
    end function ui_location

    function ui_store_get(key) result(value)
        !! A value kept between runs (local storage in a browser, a file
        !! elsewhere, see fortui_store); "" when there is none.
        character(*), intent(in) :: key
        character(len=:), allocatable :: value
        type(fortui_context_t), pointer :: ctx
        value = ""
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) value = ctx%backend%store_get(key)
    end function ui_store_get

    subroutine ui_store_set(key, value)
        !! Keep `value` under `key` between runs ("" removes it).
        character(*), intent(in) :: key, value
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%store_set(key, value)
    end subroutine ui_store_set

    subroutine ui_store_use(path)
        !! Keep the values of ui_store_set in file `path` on hosts that keep
        !! them in files ("" for memory only); browsers keep local storage.
        character(*), intent(in) :: path
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (ctx%initialized) call ctx%backend%store%use_file(path)
    end subroutine ui_store_use

    function ui_backend_description() result(text)
        !! How the active backend realizes the UI (e.g. terminal graphics and
        !! colour mode), empty when not initialized.
        character(len=:), allocatable :: text
        type(fortui_context_t), pointer :: ctx
        text = ""
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        if (allocated(ctx%backend)) text = ctx%backend%describe()
    end function ui_backend_description


    subroutine ui_run(frame)
        !! Runs the application: `frame` composes one frame (widgets only, between
        !! the frame begin and present that ui_run supplies). Native hosts loop
        !! here until the application quits. A browser host calls the frame itself
        !! when there is something to show, so ui_run returns at once and the
        !! program must not shut FortUI down after it.
        procedure(ui_frame_proc) :: frame
        type(fortui_context_t), pointer :: ctx
        type(ui_backend_caps_t) :: caps

        ctx => get_default_context()
        if (.not. associated(ctx)) then
            call report_error("fortui_core", "ui_run", "FortUI is not initialized")
            return
        end if
        caps = ctx%backend%capabilities()
        if (caps%host_driven) then
            driven_frame => frame
            call ctx%backend%hand_over()
            return
        end if
        do while (.not. ui_should_close())
            call ui_frame_begin()
            call frame()
            call ui_present()
        end do
    end subroutine ui_run

    logical function ui_run_step() result(again)
        !! One frame for a host that drives the frames; true when the next frame
        !! should follow without waiting for input.
        type(fortui_context_t), pointer :: ctx

        again = .false.
        ctx => get_default_context()
        if (.not. associated(ctx) .or. .not. associated(driven_frame)) return
        call ui_frame_begin()
        call driven_frame()
        call ui_present()
        again = .not. ctx%wait_next
    end function ui_run_step

end module fortui_core
