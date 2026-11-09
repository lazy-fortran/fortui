module fortui_web
    !! Browser backend. The application runs as WebAssembly; ordinary controls are
    !! realized as DOM elements by the JavaScript host `fortui_web.js`, which also
    !! measures text and queues browser events.
    !!
    !! The application keeps its ordinary frame loop: `poll` yields to the browser
    !! (Asyncify) until the next animation frame, or with `wait` until the next
    !! event, so the page stays responsive between frames.
    !!
    !! Only `c_int`, `c_float` and `c_double` cross the JavaScript boundary: the
    !! size of `c_long` and `c_size_t` depends on the compiler's wasm32 support.
    use, intrinsic :: iso_c_binding, only: c_int, c_float, c_double, c_char
    use fortui_backend, only: ui_backend_t, ui_backend_caps_t
    use fortui_frame, only: ui_frame_t, ui_node_t
    use fortui_input, only: input_state_t, input_update_pointer, input_scroll, &
        input_set_key, input_type_text, input_set_time
    use fortui_canvas, only: canvas_store_t
    use fortui_text, only: text_set_metrics, TEXT_MAX_CODEPOINT
    implicit none
    private

    public :: web_backend_t

    integer, parameter :: MAX_EVENTS = 256
    integer, parameter :: TEXT_CAP = 1024
    integer, parameter :: EV_POINTER = 1, EV_KEY = 2, EV_WHEEL = 3, EV_RESIZE = 4, &
        EV_TEXT = 5
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
    end type web_backend_t

    interface
        integer(c_int) function js_init(root, nroot) bind(C, name="fortui_web_init")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: root(*)
            integer(c_int), value :: nroot
        end function js_init

        subroutine js_shutdown() bind(C, name="fortui_web_shutdown")
        end subroutine js_shutdown

        subroutine js_wait(for_event) bind(C, name="fortui_web_wait")
            import :: c_int
            integer(c_int), value :: for_event
        end subroutine js_wait

        integer(c_int) function js_events(ev, cap, text, text_cap) &
                bind(C, name="fortui_web_events")
            import :: c_int, c_float, c_char
            real(c_float), intent(out) :: ev(4, *)
            integer(c_int), value :: cap
            character(kind=c_char), intent(out) :: text(*)
            integer(c_int), value :: text_cap
        end function js_events

        integer(c_int) function js_metrics_changed() bind(C, name="fortui_web_metrics_changed")
            import :: c_int
        end function js_metrics_changed

        real(c_double) function js_now() bind(C, name="fortui_web_now")
            import :: c_double
        end function js_now

        subroutine js_present(frame, n) bind(C, name="fortui_web_present")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: frame(*)
            integer(c_int), value :: n
        end subroutine js_present

        subroutine js_measure(advances, ncodepoints, fallback, line_factor) &
                bind(C, name="fortui_web_measure")
            import :: c_int, c_float
            real(c_float), intent(out) :: advances(*)
            integer(c_int), value :: ncodepoints
            real(c_float), intent(out) :: fallback(2), line_factor
        end subroutine js_measure
    end interface

contains

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

    subroutine web_shutdown(self)
        class(web_backend_t), intent(inout) :: self
        if (self%active) call js_shutdown()
        self%active = .false.
    end subroutine web_shutdown

    subroutine web_poll(self, input, wait)
        !! Yield to the browser, then replay the queued events in arrival order.
        class(web_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        logical, intent(in) :: wait

        if (.not. self%active) return
        if (wait) then
            self%waits = self%waits + 1
            call js_wait(1_c_int)
        else
            call js_wait(0_c_int)
        end if
        call read_events(input)
        call input_set_time(input, real(js_now(), kind(1.0d0)))
        ! The full text metrics arrive after the first frames; lay out again.
        if (js_metrics_changed() /= 0) then
            call self%install_text_metrics()
            input%resized = .true.
        end if
    end subroutine web_poll

    subroutine read_events(input)
        type(input_state_t), intent(inout) :: input
        real(c_float) :: ev(4, MAX_EVENTS)
        character(kind=c_char) :: text(TEXT_CAP)
        character(len=TEXT_CAP) :: chunk
        integer :: n, i, k, first, nbytes

        n = int(js_events(ev, int(MAX_EVENTS, c_int), text, int(TEXT_CAP, c_int)))
        do i = 1, n
            select case (nint(ev(1, i)))
            case (EV_POINTER)
                call input_update_pointer(input, real(ev(2, i)), real(ev(3, i)), &
                    ev(4, i) > 0.5)
            case (EV_KEY)
                call input_set_key(input, nint(ev(2, i)))
            case (EV_WHEEL)
                call input_scroll(input, nint(ev(2, i)), real(ev(3, i)))
            case (EV_RESIZE)
                input%width = max(1, nint(ev(2, i)))
                input%height = max(1, nint(ev(3, i)))
                input%scale = max(real(ev(4, i)), 0.25)
                input%resized = .true.
            case (EV_TEXT)
                first = nint(ev(2, i))
                nbytes = nint(ev(3, i))
                if (first < 0 .or. nbytes <= 0 .or. first + nbytes > TEXT_CAP) cycle
                do k = 1, nbytes
                    chunk(k:k) = text(first + k)
                end do
                call input_type_text(input, chunk(1:nbytes))
            end select
        end do
    end subroutine read_events

    subroutine web_present(self, frame, store)
        !! Send the semantic frame as records of fields; the host reconciles DOM
        !! elements by node id. Canvas layers are not realized yet.
        class(web_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        character(len=:), allocatable :: buf
        integer :: i

        if (.not. self%active) return
        buf = ""
        do i = 1, frame%count
            buf = buf // node_record(frame%nodes(i)) // RS
        end do
        self%presents = self%presents + 1
        if (buf == self%last) return
        call js_present(buf, int(len(buf), c_int))
        self%last = buf
    end subroutine web_present

    function node_record(n) result(r)
        type(ui_node_t), intent(in) :: n
        character(len=:), allocatable :: r
        integer :: flags

        flags = 0
        if (n%focusable) flags = ior(flags, 1)
        if (n%disabled) flags = ior(flags, 2)
        if (n%hovered) flags = ior(flags, 4)
        if (n%focused) flags = ior(flags, 8)
        if (n%active) flags = ior(flags, 16)
        if (n%checked) flags = ior(flags, 32)
        if (n%ellipsis) flags = ior(flags, 64)
        if (n%markdown) flags = ior(flags, 128)
        r = itoa(n%kind) // US // clean(trim(n%id)) // US // &
            ftoa(n%x) // US // ftoa(n%y) // US // ftoa(n%width) // US // &
            ftoa(n%height) // US // itoa(flags) // US // ftoa(n%value) // US // &
            ftoa(n%min_value) // US // ftoa(n%max_value) // US // itoa(n%style) // US // &
            ftoa(n%text_size) // US // itoa(n%caret) // US // ftoa(n%scroll) // US // &
            clean(trim(n%text)) // US
        if (allocated(n%body)) r = r // clean(n%body)
    end function node_record

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

    function itoa(v) result(s)
        integer, intent(in) :: v
        character(len=:), allocatable :: s
        character(len=16) :: b

        write (b, "(i0)") v
        s = trim(b)
    end function itoa

    function ftoa(v) result(s)
        real, intent(in) :: v
        character(len=:), allocatable :: s
        character(len=24) :: b

        write (b, "(f0.2)") v
        s = trim(adjustl(b))
    end function ftoa

    logical function web_should_close(self)
        !! A page is closed by the browser, which ends the program with it.
        class(web_backend_t), intent(in) :: self
        web_should_close = .not. self%active
    end function web_should_close

    subroutine web_metrics(self)
        !! Advances measured by the browser in the font the DOM renders with.
        class(web_backend_t), intent(inout) :: self
        real(c_float), allocatable :: table(:, :)
        real(c_float) :: fallback(2), line_factor

        allocate (table(0:TEXT_MAX_CODEPOINT, 2))
        call js_measure(table, int(TEXT_MAX_CODEPOINT + 1, c_int), fallback, line_factor)
        call text_set_metrics(real(table), real(fallback), real(line_factor))
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
    end function web_caps

end module fortui_web
