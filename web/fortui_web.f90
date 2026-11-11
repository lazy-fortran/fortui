module fortui_web
    !! Browser backend. The application runs as WebAssembly; the browser lays
    !! out ordinary controls itself: containers become flex boxes and controls
    !! native elements, created and updated by the JavaScript host
    !! `fortui_web.js`. Native elements report what happened to them (activated,
    !! focused, edited, submitted), so no pointer routing or text measuring is
    !! needed; only canvases get pointer coordinates.
    !!
    !! The browser drives the frames: `ui_run` returns at once, and the host
    !! calls `fortui_web_step` when there is something to show.
    use, intrinsic :: iso_c_binding, only: c_int, c_float, c_double, c_char
    use fortui_backend, only: ui_backend_t, ui_backend_caps_t
    use fortui_frame, only: ui_frame_t, ui_node_t
    use fortui_input, only: input_state_t, input_update_pointer, input_scroll, &
        input_set_time, input_host_event, input_widget_key, input_host_key, &
        input_claims, KEY_ESCAPE
    use fortui_context, only: fortui_context_t, get_default_context
    use fortui_canvas, only: canvas_store_t
    use fortui_text, only: text_use_fixed_metrics, ui_str
    use fortui_core, only: ui_run_step
    implicit none
    private

    public :: web_backend_t

    integer, parameter :: MAX_EVENTS = 256
    integer, parameter :: TEXT_CAP = 65536
    integer, parameter :: EV_POINTER = 1, EV_KEY = 2, EV_WHEEL = 3, EV_RESIZE = 4, &
        EV_HOST = 5
    character(len=1), parameter :: RS = achar(30), US = achar(31)

    type, extends(ui_backend_t) :: web_backend_t
        !! Element that hosts the application, by DOM id; empty means the page body.
        character(len=128) :: root_id = ""
        logical :: active = .false.
        !! Serialized last frame, so an unchanged frame touches no DOM.
        character(len=:), allocatable :: last
    contains
        procedure :: name => web_name
        procedure :: init => web_init
        procedure :: shutdown => web_shutdown
        procedure :: poll => web_poll
        procedure :: present => web_present
        procedure :: should_close => web_should_close
        procedure :: install_text_metrics => web_metrics
        procedure :: capabilities => web_caps
        procedure :: hand_over => web_hand_over
    end type web_backend_t

    interface
        integer(c_int) function js_init(root, nroot) bind(C, name="fortui_web_init")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: root(*)
            integer(c_int), value :: nroot
        end function js_init

        subroutine js_shutdown() bind(C, name="fortui_web_shutdown")
        end subroutine js_shutdown

        subroutine js_exit_live() bind(C, name="emscripten_exit_with_live_runtime")
        end subroutine js_exit_live

        integer(c_int) function js_events(ev, cap, text, text_cap) &
                bind(C, name="fortui_web_events")
            import :: c_int, c_float, c_char
            real(c_float), intent(out) :: ev(4, *)
            integer(c_int), value :: cap
            character(kind=c_char), intent(out) :: text(*)
            integer(c_int), value :: text_cap
        end function js_events

        real(c_double) function js_now() bind(C, name="fortui_web_now")
            import :: c_double
        end function js_now

        subroutine js_wake_after(ms) bind(C, name="fortui_web_wake_after")
            import :: c_int
            integer(c_int), value :: ms
        end subroutine js_wake_after

        subroutine js_present(frame, n) bind(C, name="fortui_web_present")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: frame(*)
            integer(c_int), value :: n
        end subroutine js_present
    end interface

contains

    integer(c_int) function fortui_web_step() bind(C, name="fortui_web_step")
        !! One frame, called by the host; 1 when the next frame should follow
        !! without waiting for an event.
        fortui_web_step = 0
        if (ui_run_step()) fortui_web_step = 1
    end function fortui_web_step

    integer(c_int) function fortui_web_key(key, flags, code) bind(C, name="fortui_web_key")
        !! Asked by the host at a key press, before the browser's own action:
        !! 1 the application wants the press, 2 the browser's action must not
        !! happen (the arguments are those of input_host_key). The host asks
        !! for every key and sends an event for those the application wants.
        integer(c_int), value :: key, flags, code
        type(fortui_context_t), pointer :: ctx

        fortui_web_key = 0
        ctx => get_default_context()
        if (.not. associated(ctx)) return
        fortui_web_key = int(input_claims(ctx%input, input_host_key(int(key), int(flags), &
            int(code)), real(js_now(), kind(1.0d0))), c_int)
    end function fortui_web_key

    function web_name(self) result(name)
        class(web_backend_t), intent(in) :: self
        character(len=:), allocatable :: name
        name = "web"
    end function web_name

    logical function web_init(self)
        class(web_backend_t), intent(inout) :: self
        character(len=:), allocatable :: root

        root = trim(self%root_id)
        self%active = js_init(root, int(len(root), c_int)) == 0
        self%last = ""
        web_init = self%active
    end function web_init

    subroutine web_hand_over(self)
        !! Leaves main without ending the program: an ordinary return would run
        !! the program's end (deallocating module data) while the browser still
        !! calls the frames. The stack is unwound by an exception the runtime
        !! expects; nothing after this call runs.
        class(web_backend_t), intent(inout) :: self
        if (self%active) call js_exit_live()
    end subroutine web_hand_over

    subroutine web_shutdown(self)
        class(web_backend_t), intent(inout) :: self
        if (self%active) call js_shutdown()
        self%active = .false.
    end subroutine web_shutdown

    subroutine web_poll(self, input, wait)
        !! Replays the events the host queued since the last frame. Never waits:
        !! the host calls the next frame when there is something to do.
        class(web_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        logical, intent(in) :: wait
        real(c_float) :: ev(4, MAX_EVENTS)
        character(kind=c_char), allocatable :: text(:)
        integer :: n, i, first, nbytes, sep

        if (.not. self%active) return
        if (wait) self%waits = self%waits + 1
        allocate (text(TEXT_CAP))
        n = int(js_events(ev, int(MAX_EVENTS, c_int), text, int(TEXT_CAP, c_int)))
        do i = 1, n
            select case (nint(ev(1, i)))
            case (EV_POINTER)
                call input_update_pointer(input, real(ev(2, i)), real(ev(3, i)), &
                    ev(4, i) > 0.5)
            case (EV_KEY)
                ! The press is with the shortcuts since fortui_web_key. Escape
                ! also goes to the widgets; the browser's own controls handle
                ! every other key themselves.
                if (nint(ev(2, i)) == KEY_ESCAPE) call input_widget_key(input, KEY_ESCAPE)
            case (EV_WHEEL)
                call input_scroll(input, nint(ev(2, i)), real(ev(3, i)))
            case (EV_RESIZE)
                input%width = max(1, nint(ev(2, i)))
                input%height = max(1, nint(ev(3, i)))
                input%scale = max(real(ev(4, i)), 0.25)
                input%resized = .true.
            case (EV_HOST)
                ! Kind, then "id<US>value" in the text buffer.
                first = nint(ev(3, i))
                nbytes = nint(ev(4, i))
                if (first < 0 .or. nbytes < 0 .or. first + nbytes > TEXT_CAP) cycle
                block
                    character(len=nbytes) :: rec
                    integer :: k
                    do k = 1, nbytes
                        rec(k:k) = text(first + k)
                    end do
                    sep = index(rec, US)
                    if (sep == 0) then
                        call input_host_event(input, nint(ev(2, i)), rec)
                    else
                        call input_host_event(input, nint(ev(2, i)), rec(1:sep - 1), &
                            rec(sep + 1:))
                    end if
                end block
            end select
        end do
        call input_set_time(input, real(js_now(), kind(1.0d0)))
    end subroutine web_poll

    subroutine web_present(self, frame, store)
        !! Sends the containers, then the nodes, as records of fields; the host
        !! reconciles DOM elements by key and places them in their containers.
        class(web_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        character(len=:), allocatable :: buf, rec
        integer :: i, used

        if (.not. self%active) return
        ! A due timer: the host wakes the frame loop then (setTimeout), not by polling.
        if (self%wake_in >= 0.0) then
            call js_wake_after(int(ceiling(1000.0 * self%wake_in), c_int))
        else
            call js_wake_after(-1_c_int)
        end if
        ! Grows by doubling: a page of thousands of lines stays linear.
        allocate (character(len=65536) :: buf)
        used = 0
        do i = 1, frame%box_count
            associate (b => frame%boxes(i))
                rec = 'B'//US//ui_str(b%kind)//US//ui_str(b%parent)//US//ui_str(b%after)// &
                    US//ui_str(nint(b%gap))//US//ui_str(nint(b%cross))//US// &
                    ui_str(nint(b%width))//US//clean(trim(b%id))//US//clean(trim(b%look))// &
                    US//clean(trim(b%anchor))//RS
            end associate
            call add(rec)
        end do
        do i = 1, frame%count
            call add(node_record(frame%nodes(i))//RS)
        end do
        self%presents = self%presents + 1
        if (allocated(self%last)) then
            if (len(self%last) == used) then
                if (self%last == buf(1:used)) return
            end if
        end if
        call js_present(buf, int(used, c_int))
        self%last = buf(1:used)

    contains

        subroutine add(s)
            character(len=*), intent(in) :: s
            character(len=:), allocatable :: bigger

            if (used + len(s) > len(buf)) then
                allocate (character(len=max(used + len(s), 2 * len(buf))) :: bigger)
                bigger(1:used) = buf(1:used)
                call move_alloc(bigger, buf)
            end if
            buf(used + 1:used + len(s)) = s
            used = used + len(s)
        end subroutine add

    end subroutine web_present

    function node_record(n) result(r)
        !! Kind, id, x, y, width, height (logical units), flags (1 focusable,
        !! 2 disabled, 8 focused, 32 checked, 64 ellipsis, 256 reveal), value, min,
        !! max, style, text size, box, width mode, tone, text, body, runs, look,
        !! anchor.
        type(ui_node_t), intent(in) :: n
        character(len=:), allocatable :: r
        integer :: flags

        flags = 0
        if (n%focusable) flags = ior(flags, 1)
        if (n%disabled) flags = ior(flags, 2)
        if (n%focused) flags = ior(flags, 8)
        if (n%checked) flags = ior(flags, 32)
        if (n%ellipsis) flags = ior(flags, 64)
        if (n%markdown) flags = ior(flags, 128)
        if (n%reveal) flags = ior(flags, 256)
        r = ui_str(n%kind)//US//clean(trim(n%id))//US// &
            ui_str(nint(n%x))//US//ui_str(nint(n%y))//US//ui_str(nint(n%width))//US// &
            ui_str(nint(n%height))//US//ui_str(flags)//US//ui_str(n%value, 4)//US// &
            ui_str(n%min_value, 4)//US//ui_str(n%max_value, 4)//US//ui_str(n%style)//US// &
            ui_str(nint(n%text_size))//US//ui_str(n%box)//US//ui_str(n%width_mode)//US// &
            ui_str(n%tone)//US//clean(trim(n%text))//US
        if (allocated(n%body)) r = r//clean(n%body)
        r = r//US//runs(n)//US//clean(trim(n%look))//US//clean(trim(n%anchor))
    end function node_record

    function runs(n) result(s)
        !! "end:tone,end:tone" of rich text, or empty.
        type(ui_node_t), intent(in) :: n
        character(len=:), allocatable :: s
        integer :: k

        s = ''
        if (.not. allocated(n%run_end)) return
        do k = 1, size(n%run_end)
            if (k > 1) s = s//','
            s = s//ui_str(n%run_end(k))//':'//ui_str(n%run_tone(k))
        end do
    end function runs

    function clean(s) result(r)
        !! Separators cannot occur inside a field.
        character(len=*), intent(in) :: s
        character(len=len(s)) :: r
        integer :: i

        r = s
        do i = 1, len(r)
            if (r(i:i) == RS .or. r(i:i) == US) r(i:i) = " "
        end do
    end function clean

    logical function web_should_close(self)
        !! A page is closed by the browser, which ends the program with it.
        class(web_backend_t), intent(in) :: self
        web_should_close = .not. self%active
    end function web_should_close

    subroutine web_metrics(self)
        !! The browser lays text out itself; widths computed in Fortran only
        !! place canvases, so cheap fixed metrics suffice.
        class(web_backend_t), intent(inout) :: self
        call text_use_fixed_metrics(0.55, 1.25)
    end subroutine web_metrics

    function web_caps(self) result(caps)
        class(web_backend_t), intent(in) :: self
        type(ui_backend_caps_t) :: caps

        caps%graphical = .true.
        caps%proportional_text = .true.
        caps%event_waiting = .true.
        caps%high_dpi = .true.
        caps%pointer = .true.
        caps%text_entry = .true.
        caps%host_driven = .true.
    end function web_caps

end module fortui_web
