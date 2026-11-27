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
    use, intrinsic :: iso_c_binding, only: c_int, c_float, c_double, c_char, c_null_char, &
        c_ptr, c_loc, c_null_ptr
    use fortui_backend, only: ui_backend_t, ui_backend_caps_t
    use fortui_frame, only: ui_frame_t, ui_node_t, ui_layer_ref_t, UI_CANVAS, LAYER_IMAGE, &
        LAYER_LINES, LAYER_POINTS, LAYER_MESH
    use fortui_input, only: input_state_t, input_update_pointer, input_pointer_event, input_scroll, &
        input_set_time, input_host_event, input_widget_key, input_host_key, &
        input_claims, KEY_ESCAPE
    use fortui_context, only: fortui_context_t, get_default_context
    use fortui_canvas, only: canvas_store_t
    use fortui_text, only: text_use_fixed_metrics, ui_str
    use fortui_theme, only: theme, STYLE_PLAIN
    use fortui_core, only: ui_run_step, ui_appearance_changed
    use fortui_net_transport, only: net_transport_t
    use fortui_web_net, only: web_transport_t
    use fortui_layout, only: layout_box_t
    use fortui_icons, only: icon_svg
    implicit none
    private

    public :: web_backend_t, fortui_web_layer_ptr

    ! The store of the last frame, read by the host while it draws canvases.
    type(canvas_store_t), pointer :: drawn => null()

    integer, parameter :: MAX_EVENTS = 256
    integer, parameter :: TEXT_CAP = 65536
    integer, parameter :: EV_POINTER = 1, EV_KEY = 2, EV_WHEEL = 3, EV_RESIZE = 4, &
        EV_HOST = 5, EV_APPEARANCE = 6
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
        procedure :: offer_file => web_offer_file
        procedure :: clipboard_set => web_clipboard_set
        procedure :: network => web_network
        procedure :: locale => web_locale
        procedure :: url_param => web_url_param
        procedure :: set_url_param => web_set_url_param
        procedure :: location => web_location
        procedure :: store_get => web_store_get
        procedure :: store_set => web_store_set
    end type web_backend_t

    interface
        integer(c_int) function js_init(root, nroot) bind(C, name="fortui_web_init")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: root(*)
            integer(c_int), value :: nroot
        end function js_init

        subroutine js_theme(name, n) bind(C, name="fortui_web_theme")
            import :: c_char, c_int
            character(kind=c_char), intent(in) :: name(*)
            integer(c_int), value :: n
        end subroutine
        subroutine js_shutdown() bind(C, name="fortui_web_shutdown")
        end subroutine js_shutdown

        subroutine js_exit_live() bind(C, name="emscripten_exit_with_live_runtime")
        end subroutine js_exit_live

        integer(c_int) function js_events(ev, cap, text, text_cap) &
                bind(C, name="fortui_web_events")
            import :: c_int, c_float, c_char
            real(c_float), intent(out) :: ev(9, *)
            integer(c_int), value :: cap
            character(kind=c_char), intent(out) :: text(*)
            integer(c_int), value :: text_cap
        end function js_events

        integer(c_int) function js_locale(buf, cap) bind(C, name="fortui_web_locale")
            import :: c_int, c_char
            character(kind=c_char), intent(out) :: buf(*)
            integer(c_int), value :: cap
        end function js_locale

        subroutine js_set_url_param(name, n, value, nv, push) bind(C, name="fortui_web_set_url_param")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: name(*), value(*)
            integer(c_int), value :: n, nv, push
        end subroutine js_set_url_param
        integer(c_int) function js_location(buf, cap) bind(C, name="fortui_web_location")
            import :: c_int, c_char
            character(kind=c_char), intent(out) :: buf(*)
            integer(c_int), value :: cap
        end function js_location
        integer(c_int) function js_store_get(key, n, buf, cap) bind(C, name="fortui_web_store_get")
            !! The value's length in bytes; up to cap - 1 of them copied into buf.
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: key(*)
            character(kind=c_char), intent(out) :: buf(*)
            integer(c_int), value :: n, cap
        end function js_store_get
        subroutine js_store_set(key, n, value, nv) bind(C, name="fortui_web_store_set")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: key(*), value(*)
            integer(c_int), value :: n, nv
        end subroutine js_store_set
        integer(c_int) function js_url_param(name, n, buf, cap) bind(C, name="fortui_web_url_param")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: name(*)
            integer(c_int), value :: n
            character(kind=c_char), intent(out) :: buf(*)
            integer(c_int), value :: cap
        end function js_url_param

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

    subroutine web_network(self, transport)
        !! fetch and EventSource.
        class(web_backend_t), intent(inout) :: self
        class(net_transport_t), allocatable, intent(out) :: transport
        allocate (web_transport_t :: transport)
        if (.not. self%active) deallocate (transport)
    end subroutine web_network

    function web_locale(self) result(tag)
        !! navigator.language.
        class(web_backend_t), intent(in) :: self
        character(len=:), allocatable :: tag
        character(len=64) :: buf
        integer :: n
        tag = ""
        if (.not. self%active) return
        n = int(js_locale(buf, int(len(buf), c_int)))
        tag = buf(1:n)
    end function web_locale

    function web_url_param(self, name) result(value)
        !! A parameter of the page's query string.
        class(web_backend_t), intent(inout) :: self
        character(*), intent(in) :: name
        character(len=:), allocatable :: value
        character(len=1024) :: buf
        integer :: n
        value = ""
        if (.not. self%active) return
        n = int(js_url_param(name, int(len(name), c_int), buf, int(len(buf), c_int)))
        value = buf(1:n)
    end function web_url_param

    subroutine web_clipboard_set(self, text)
        !! The browser's clipboard (asynchronous; the page must have been used
        !! a moment ago, as after a click).
        class(web_backend_t), intent(inout) :: self
        character(*), intent(in) :: text
        interface
            subroutine js_copy(t, n) bind(C, name="fortui_web_clipboard_set")
                import :: c_char, c_int
                character(kind=c_char), intent(in) :: t(*)
                integer(c_int), value :: n
            end subroutine js_copy
        end interface
        if (.not. self%active) return
        call js_copy(text, int(len(text), c_int))
    end subroutine web_clipboard_set

    subroutine web_set_url_param(self, name, value, push)
        !! The page's address with the parameter changed (history.replaceState,
        !! or pushState for a step Back returns from).
        class(web_backend_t), intent(inout) :: self
        character(*), intent(in) :: name, value
        logical, intent(in) :: push
        if (.not. self%active) return
        call js_set_url_param(name, int(len(name), c_int), value, int(len(value), c_int), &
            int(merge(1, 0, push), c_int))
    end subroutine web_set_url_param

    function web_location(self) result(where)
        class(web_backend_t), intent(inout) :: self
        character(len=:), allocatable :: where
        character(len=4096) :: buf
        integer :: n
        where = ""
        if (.not. self%active) return
        n = int(js_location(buf, int(len(buf), c_int)))
        where = buf(1:n)
    end function web_location

    function web_store_get(self, key) result(value)
        !! localStorage, under the key prefixed with "fortui:".
        class(web_backend_t), intent(inout) :: self
        character(*), intent(in) :: key
        character(len=:), allocatable :: value
        character(len=65536) :: buf
        integer :: n
        value = ""
        if (.not. self%active) return
        ! Values longer than the buffer are cut; keep drafts and settings short.
        n = int(js_store_get(key, int(len(key), c_int), buf, int(len(buf), c_int)))
        value = buf(1:max(0, min(n, len(buf) - 1)))
    end function web_store_get

    subroutine web_store_set(self, key, value)
        class(web_backend_t), intent(inout) :: self
        character(*), intent(in) :: key, value
        if (.not. self%active) return
        call js_store_set(key, int(len(key), c_int), value, int(len(value), c_int))
    end subroutine web_store_set

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

    subroutine web_offer_file(self, path)
        !! Downloads the file from the in-memory file system.
        class(web_backend_t), intent(inout) :: self
        character(*), intent(in) :: path
        interface
            subroutine offer(p) bind(C, name="fortui_web_offer_file")
                import c_char
                character(kind=c_char), intent(in) :: p(*)
            end subroutine offer
        end interface
        if (self%presents < 0) return
        call offer(path // c_null_char)
    end subroutine web_offer_file

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
        real(c_float) :: ev(9, MAX_EVENTS)
        character(kind=c_char), allocatable :: text(:)
        integer :: n, i, first, nbytes, sep

        if (.not. self%active) return
        if (wait) self%waits = self%waits + 1
        allocate (text(TEXT_CAP))
        n = int(js_events(ev, int(MAX_EVENTS, c_int), text, int(TEXT_CAP, c_int)))
        do i = 1, n
            select case (nint(ev(1, i)))
            case (EV_POINTER)
                call input_pointer_event(input, real(ev(2, i)), real(ev(3, i)), ev(4, i) > 0.5, &
                    nint(ev(5, i)), real(ev(6, i)), real(ev(7, i)), real(ev(8, i)), nint(ev(9, i)))
            case (EV_KEY)
                ! The press is with the shortcuts since fortui_web_key. Escape
                ! also goes to the widgets; the browser's own controls handle
                ! every other key themselves.
                if (nint(ev(2, i)) == KEY_ESCAPE) call input_widget_key(input, KEY_ESCAPE)
            case (EV_APPEARANCE)
                call ui_appearance_changed()
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
                    US//clean(trim(b%anchor))//US//trim(merge('1', '0', b%wrap))//US// &
                    ui_str(nint(b%viewport))//US//ui_str(nint(b%pad_before))//US// &
                    ui_str(nint(b%pad_after))//US//ui_str(merge(1, 0, b%stick) + &
                    merge(2, 0, b%reports))//US//label_of(b)//RS
            end associate
            call add(rec)
        end do
        do i = 1, frame%count
            call add(node_record(frame%nodes(i))//RS)
        end do
        drawn => store
        do i = 1, frame%count
            if (frame%nodes(i)%kind == UI_CANVAS) call canvas_records(frame, i)
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

        subroutine canvas_records(frame, i)
            !! 'V': node, view and fill; then per layer 'L': node, kind, store
            !! slot, data versions, sizes and placement. The host reads the
            !! arrays from memory with fortui_web_layer_ptr when a version changed.
            type(ui_frame_t), intent(in) :: frame
            integer, intent(in) :: i
            integer :: j, vs
            type(ui_layer_ref_t) :: ref
            associate (n => frame%nodes(i))
                call add('V'//US//ui_str(i)//US//ui_str(n%canvas_view%zoom, 6)//US// &
                    ui_str(n%canvas_view%pan_x, 3)//US//ui_str(n%canvas_view%pan_y, 3)//US// &
                    ui_str(n%fill)//RS)
                do j = n%layer_first, n%layer_first + n%layer_count - 1
                    ref = frame%layers(j)
                    associate (l => store%layers(ref%slot))
                        select case (ref%kind)
                        case (LAYER_IMAGE)
                            call add('L'//US//ui_str(i)//US//ui_str(ref%kind)//US//ui_str(ref%slot)// &
                                US//ui_str(l%serial)//'.'//ui_str(ref%version)//US// &
                                ui_str(l%image_width)//US//ui_str(l%image_height)//US// &
                                ui_str(l%rect(1), 3)//US//ui_str(l%rect(2), 3)//US// &
                                ui_str(l%rect(3), 3)//US//ui_str(l%rect(4), 3)//RS)
                        case (LAYER_MESH)
                            ! Node, kind, slot, version, vertices, index count,
                            ! light, then the camera matrix (column-major).
                            call add('L'//US//ui_str(i)//US//ui_str(ref%kind)//US//ui_str(ref%slot)// &
                                US//ui_str(l%serial)//'.'//ui_str(ref%version)//US// &
                                ui_str(ref%vertex_count)//US//ui_str(ref%index_count)//US// &
                                floats(l%light)//US//floats(l%camera)//RS)
                        case (LAYER_LINES, LAYER_POINTS)
                            vs = ref%vertex_slot
                            call add('L'//US//ui_str(i)//US//ui_str(ref%kind)//US//ui_str(ref%slot)// &
                                US//ui_str(l%serial)//'.'//ui_str(ref%version)//'.'// &
                                ui_str(ref%index_version)//'.'//ui_str(ref%vertex_version)//US// &
                                ui_str(vs)//US//ui_str(vertices(vs))//US// &
                                ui_str(arr_size(l%rgba))//US//ui_str(arr_size(l%indices))//US// &
                                ui_str(l%line_width, 3)//US//ui_str(real_size(l%sizes))//US// &
                                ui_str(merge(1, 0, l%world_size))//US//ui_str(l%min_pixels, 3)//RS)
                        end select
                    end associate
                end do
                ! 'T': labels, centred below their world point at a fixed size.
                do j = n%label_first, n%label_first + n%label_count - 1
                    associate (lab => frame%labels(j))
                        call add('T'//US//ui_str(i)//US//ui_str(lab%x, 2)//US//ui_str(lab%y, 2)//US// &
                            ui_str(lab%size, 1)//US//ui_str(lab%rgba)//US//clean(lab%text)//RS)
                    end associate
                end do
            end associate
        end subroutine canvas_records

        integer function vertices(slot)
            !! Positions in a vertex layer (x, y pairs).
            integer, intent(in) :: slot
            vertices = 0
            if (slot < 1 .or. slot > size(store%layers)) return
            if (allocated(store%layers(slot)%xy)) vertices = size(store%layers(slot)%xy, 2)
        end function vertices

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

    function floats(v) result(s)
        !! Numbers separated as fields.
        real, intent(in) :: v(:)
        character(len=:), allocatable :: s
        integer :: k
        s = ''
        do k = 1, size(v)
            if (k > 1) s = s//US
            s = s//ui_str(v(k), 7)
        end do
    end function floats

    integer function arr_size(a)
        integer, allocatable, intent(in) :: a(:)
        arr_size = 0
        if (allocated(a)) arr_size = size(a)
    end function arr_size

    integer function real_size(a)
        real, allocatable, intent(in) :: a(:)
        real_size = 0
        if (allocated(a)) real_size = size(a)
    end function real_size

    type(c_ptr) function fortui_web_layer_ptr(slot, which) bind(C, name="fortui_web_layer_ptr")
        !! Address of a layer array of the last frame: 1 positions (x, y
        !! pairs), 2 colours, 3 point sizes, 4 segment or triangle vertex indices
        !! (0-based), 5 mesh vertices (x, y, z triples), 6 their normals.
        integer(c_int), value :: slot, which
        fortui_web_layer_ptr = c_null_ptr
        if (.not. associated(drawn)) return
        if (slot < 1 .or. slot > size(drawn%layers)) return
        select case (which)
        case (1)
            if (allocated(drawn%layers(slot)%xy)) fortui_web_layer_ptr = c_loc(drawn%layers(slot)%xy)
        case (2)
            if (allocated(drawn%layers(slot)%rgba)) fortui_web_layer_ptr = c_loc(drawn%layers(slot)%rgba)
        case (3)
            if (allocated(drawn%layers(slot)%sizes)) fortui_web_layer_ptr = c_loc(drawn%layers(slot)%sizes)
        case (4)
            if (allocated(drawn%layers(slot)%indices)) fortui_web_layer_ptr = &
                c_loc(drawn%layers(slot)%indices)
        case (5)
            if (allocated(drawn%layers(slot)%xyz)) fortui_web_layer_ptr = c_loc(drawn%layers(slot)%xyz)
        case (6)
            if (allocated(drawn%layers(slot)%normals)) fortui_web_layer_ptr = &
                c_loc(drawn%layers(slot)%normals)
        end select
    end function fortui_web_layer_ptr

    function node_record(n) result(r)
        !! Kind, id, x, y, width, height (logical units), flags (1 focusable,
        !! 2 disabled, 8 focused, 32 checked, 64 ellipsis, 256 reveal, 512 toggle), value, min,
        !! max, style, text size, box, width mode, tone, text, body, runs, look,
        !! anchor, button emphasis, file types, tooltip, symbol (SVG path data),
        !! fill colour (people's avatars).
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
        if (n%toggle) flags = ior(flags, 512)
        r = ui_str(n%kind)//US//clean(trim(n%id))//US// &
            ui_str(nint(n%x))//US//ui_str(nint(n%y))//US//ui_str(nint(n%width))//US// &
            ui_str(nint(n%height))//US//ui_str(flags)//US//ui_str(n%value, 4)//US// &
            ui_str(n%min_value, 4)//US//ui_str(n%max_value, 4)//US//ui_str(n%style)//US// &
            ui_str(nint(n%text_size))//US//ui_str(n%box)//US//ui_str(n%width_mode)//US// &
            ui_str(n%tone)//US//clean(trim(n%text))//US
        if (allocated(n%body)) r = r//clean(n%body)
        r = r//US//runs(n)//US//clean(trim(n%look))//US//clean(trim(n%anchor))//US// &
            ui_str(n%emphasis) // US
        if (allocated(n%file_accept)) r = r // "1" // clean(n%file_accept)
        r = r//US
        if (allocated(n%tooltip)) r = r//clean(n%tooltip)
        r = r//US
        if (allocated(n%icon)) r = r//icon_svg(n%icon)
        r = r//US//ui_str(n%fill)
    end function node_record

    function label_of(b) result(s)
        type(layout_box_t), intent(in) :: b
        character(len=:), allocatable :: s
        s = ''
        if (allocated(b%label)) s = clean(b%label)
    end function label_of

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
        !! place canvases, so cheap fixed metrics suffice. A theme the
        !! application chose styles the page through data-theme on its root;
        !! without one the page keeps its own look.
        class(web_backend_t), intent(inout) :: self
        character(len=:), allocatable :: name
        call text_use_fixed_metrics(0.55, 1.25)
        name = ""
        if (theme%kind /= STYLE_PLAIN) name = trim(theme%name)
        if (self%active) call js_theme(name, int(len(name), c_int))
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
