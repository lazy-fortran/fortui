module fortui_gui
    !! Graphical backend in Fortran: an X11 window and its input from fortwin,
    !! drawing through fortgfx (Vulkan; the CPU renderer for offscreen frames
    !! without a GPU), text from fortfont with fonts found by fortui_fonts.
    !!
    !! The frame is painted by the current theme's painter (fortui_paint) into a
    !! display list in physical pixels: rectangles, lines and points become
    !! instances of one signed-distance shader (exact pixels for square edges,
    !! antialiased for rounded ones), text and images become textured quads drawn
    !! 1:1 with nearest sampling for glyphs, so text stays sharp. Glyphs come from
    !! atlas textures; a character the face lacks comes from a fallback font set on
    !! the face's own baseline. Canvas point and line layers stay on the GPU and
    !! are drawn with the view as a transform.
    use iso_c_binding
    use iso_fortran_env, only: int8, int32, int64
    use fortui_backend, only: ui_backend_t, ui_backend_caps_t
    use fortui_frame, only: ui_frame_t, ui_layer_ref_t, LAYER_POINTS, LAYER_IMAGE, LAYER_CELLS, &
        CELL_UNDERLINE, CELL_STRIKE, CELL_CONT, CELL_WIDE, CELL_CURSOR, CELL_BAR
    use fortui_canvas, only: canvas_layer_t, canvas_store_t
    use fortui_input, only: input_state_t, input_update_pointer, input_scroll, &
        input_type_text, input_set_time, input_key_press, KEY_NONE, &
        KEY_ENTER, KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, &
        KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN, KEY_PAGE_UP, &
        KEY_PAGE_DOWN, KEY_SPACE, KEY_INSERT, KEY_F1, MOD_CTRL, MOD_ALT, MOD_SHIFT, MOD_META
    use fortui_paint, only: paint_list_t, paint_frame, paint_face, PAINT_RECT, PAINT_LINE, &
        PAINT_TEXT, PAINT_CLIP, PAINT_UNCLIP, PAINT_CANVAS, PATTERN_CHECKER
    use fortui_theme, only: theme, FACE_REGULAR, FACE_MONO, FACE_CELL, cell_font_family
    use fortui_text, only: text_use_measurement, text_use_cell_measure
    use fortui_fonts, only: font_for, font_lookup
    use fortui_error, only: report_error
    use fortwin, only: window_t, win_event_t, win_open, win_close, win_next_event, win_wait, &
        win_wake, win_set_title, win_set_size, win_set_visible, win_set_background, &
        win_maximize, &
        win_clipboard_set, win_clipboard_get, win_primary_set, win_primary_get, win_flush, &
        win_mods_down, win_time, WIN_EV_CLOSE, WIN_EV_RESIZE, WIN_EV_EXPOSE, WIN_EV_MOTION, &
        WIN_EV_BUTTON_DOWN, WIN_EV_BUTTON_UP, WIN_EV_WHEEL, WIN_EV_KEY_DOWN, WIN_EV_TEXT, &
        WIN_EV_LEAVE, WIN_MOD_SHIFT, WIN_MOD_CTRL, WIN_MOD_ALT, WIN_MOD_META
    use fortwin_keys, only: WIN_KEY_NONE, WIN_KEY_ENTER, WIN_KEY_ESCAPE, WIN_KEY_BACKSPACE, &
        WIN_KEY_TAB, WIN_KEY_SPACE, WIN_KEY_DELETE, WIN_KEY_RIGHT, WIN_KEY_LEFT, WIN_KEY_DOWN, &
        WIN_KEY_UP, WIN_KEY_HOME, WIN_KEY_END, WIN_KEY_PAGE_UP, WIN_KEY_PAGE_DOWN, &
        WIN_KEY_INSERT, WIN_KEY_F1
    use fortgfx_list, only: gfx_list_t, gfx_list_reset, gfx_add_shape, gfx_add_quad, &
        gfx_add_layer
    use fortgfx_gpu, only: gfx_gpu_t, gpu_open_window, gpu_open_offscreen, gpu_close, &
        gpu_resize, gpu_render, gpu_read, gpu_texture_create, gpu_texture_update, &
        gpu_texture_release, gpu_layer_set, gpu_layer_release
    use fortgfx_cpu, only: gfx_cpu_t, cpu_render, cpu_texture_create, cpu_texture_update, &
        cpu_texture_release, cpu_layer_set, cpu_layer_release
    use fortfont, only: font_t, glyph_t, font_open_file, font_set_hinting, font_has, font_glyph, &
        font_advance, font_advance26, font_glyph_box
    implicit none
    private

    public :: gui_backend_t, gui_is_available, gui_read_pixels, gui_inject

    integer, parameter :: ATLAS = 1024 ! side of an atlas page in pixels
    character(len=*), parameter :: FALLBACK_FAMILIES(3) = [character(len=20) :: &
        "DejaVu Sans Mono", "Noto Sans Symbols 2", "Noto Color Emoji"]

    type :: face_slot_t
        !! A theme face at a pixel size: its font, the fallbacks, metrics.
        integer :: face = 0, px = 0
        type(font_t) :: font
        type(font_t) :: fallback(3)
        logical :: has_fallback(3) = .false.
        logical :: mono = .false. ! monochrome (pixel designs)
        logical :: light = .false. ! light hinting: fractional advances (as SDL_ttf)
        integer :: height = 0, ascent = 0
        logical :: ok = .false.
        ! Layout metrics of code points 0..255: advance (26.6), ink left and width.
        logical :: known(0:255) = .false.
        integer :: adv26(0:255) = 0, ink_left(0:255) = 0, ink_width(0:255) = 0
    end type face_slot_t

    type :: glyph_entry_t
        !! A glyph placed in an atlas page (key: slot and code point).
        integer :: slot = 0, cp = -1
        integer :: page = 0, x = 0, y = 0, w = 0, h = 0
        integer :: left = 0, top = 0
        logical :: colour = .false.
    end type glyph_entry_t

    type :: page_t
        integer :: texture = 0, shelf_y = 0, shelf_h = 0, cursor_x = 0
    end type page_t

    type :: gpu_layer_t
        integer :: serial = 0, version = -1, index_version = -1, vertex_version = -1
        integer :: count = 0, width = 0, height = 0, texture = 0
        real(c_float), allocatable :: data(:, :)
    end type gpu_layer_t

    type, extends(ui_backend_t) :: gui_backend_t
        !! `offscreen` renders frames of the configured size without a window
        !! (tests read them with gui_read_pixels); on the GPU when there is one.
        logical :: offscreen = .false.
        !! The window is shown once a frame was drawn, never empty; until then it
        !! has the frame's background colour, which the X server paints.
        logical :: show_pending = .false., drawn = .false.
        real :: window_bg(3) = -1.0
        logical :: active = .false., close_requested = .false., gpu = .false.
        type(window_t) :: win
        type(gfx_gpu_t) :: dev
        type(gfx_cpu_t) :: cpu
        type(gfx_list_t) :: list
        type(paint_list_t) :: paint
        integer :: pw = 1, ph = 1
        real :: scale = 1.0
        integer :: frame_no = 0
        integer :: clip(4) = 0
        integer :: clip_stack(4, 32) = 0
        integer :: clip_depth = 0
        type(gpu_layer_t), allocatable :: layers(:)
        type(glyph_entry_t), allocatable :: glyphs(:)
        integer :: nglyphs = 0
        type(page_t), allocatable :: pages(:)
        integer :: npages = 0
        type(win_event_t), allocatable :: queue(:)
        integer :: nqueue = 0
        logical :: pointer_down = .false.
        logical :: redraw = .false.
    contains
        procedure :: name => gb_name
        procedure :: init => gb_init
        procedure :: shutdown => gb_shutdown
        procedure :: poll => gb_poll
        procedure :: present => gb_present
        procedure :: should_close => gb_should_close
        procedure :: install_text_metrics => gb_metrics
        procedure :: capabilities => gb_caps
        procedure :: clipboard_set => gb_clipboard_set
        procedure :: clipboard_get => gb_clipboard_get
        procedure :: set_title => gb_set_title
        procedure :: waker => gb_waker
        procedure :: set_window_size => gb_set_window_size
        procedure :: set_window_visible => gb_set_window_visible
        procedure :: maximize_window => gb_maximize_window
        procedure :: open_url => gb_open_url
        procedure :: primary_set => gb_primary_set
        procedure :: primary_get => gb_primary_get
    end type gui_backend_t

    ! Fonts, shared with text measurement (one backend at a time).
    type(face_slot_t), save, target :: slots(48)
    integer, save :: nslots = 0
    character(len=192), save :: slots_theme = ""
    real, save :: px_scale = 1.0
    logical, save :: measuring = .false.

contains

    ! --- identity -----------------------------------------------------------------------

    function gb_name(self) result(name)
        class(gui_backend_t), intent(in) :: self
        character(len=:), allocatable :: name
        name = "gui"
        if (self%offscreen) name = "gui-offscreen"
    end function gb_name

    function gb_caps(self) result(caps)
        class(gui_backend_t), intent(in) :: self
        type(ui_backend_caps_t) :: caps
        caps%graphical = .true.
        caps%canvas_layers = .true.
        caps%proportional_text = .true.
        caps%event_waiting = .not. self%offscreen
        caps%high_dpi = .true.
        caps%pointer = .true.
        caps%text_entry = .true.
    end function gb_caps

    logical function gui_is_available()
        !! An X display is named (unless headless tests ask for none with
        !! FORTUI_HEADLESS=1). Opening it and the GPU is left to init.
        character(len=256) :: v
        integer :: n, st
        gui_is_available = .false.
        call get_environment_variable("FORTUI_HEADLESS", v, n, st)
        if (st == 0 .and. trim(v) == "1") return
        call get_environment_variable("DISPLAY", v, n, st)
        gui_is_available = st == 0 .and. n > 0
    end function gui_is_available

    ! --- life cycle -----------------------------------------------------------------------------

    logical function gb_init(self)
        class(gui_backend_t), intent(inout) :: self
        gb_init = .false.
        if (self%offscreen) then
            self%pw = max(1, self%config%width)
            self%ph = max(1, self%config%height)
            self%scale = 1.0
            self%gpu = gpu_open_offscreen(self%dev, self%pw, self%ph)
        else
            if (.not. win_open(self%win, trim(self%config%title), self%config%width, &
                self%config%height, visible=.false., class=program_name())) then
                call report_error("fortui_gui", "init", "cannot open a window on the X display")
                return
            end if
            self%show_pending = .not. self%config%hidden
            self%pw = self%win%width
            self%ph = self%win%height
            self%scale = self%win%scale
            self%gpu = gpu_open_window(self%dev, self%win%conn, self%win%id, self%pw, self%ph)
            if (.not. self%gpu) then
                call report_error("fortui_gui", "init", "no Vulkan device can draw the window")
                call win_close(self%win)
                return
            end if
        end if
        px_scale = self%scale
        allocate (self%layers(8), self%glyphs(4096), self%pages(4), self%queue(256))
        call gfx_list_reset(self%list, self%pw, self%ph, [0.0, 0.0, 0.0, 1.0])
        self%active = .true.
        gb_init = .true.
    end function gb_init

    function program_name() result(name)
        character(len=:), allocatable :: name
        character(len=1024) :: exe
        integer :: k
        call get_command_argument(0, exe)
        k = index(exe, "/", back=.true.)
        name = trim(exe(k + 1:))
        if (len(name) == 0) name = "fortui"
    end function program_name

    subroutine gb_shutdown(self)
        class(gui_backend_t), intent(inout) :: self
        if (.not. self%active) return
        if (self%gpu) call gpu_close(self%dev)
        if (.not. self%offscreen) call win_close(self%win)
        self%active = .false.
        nslots = 0
        measuring = .false.
    end subroutine gb_shutdown

    logical function gb_should_close(self)
        class(gui_backend_t), intent(in) :: self
        gb_should_close = self%close_requested
    end function gb_should_close

    ! --- platform services --------------------------------------------------------------------------

    subroutine gb_clipboard_set(self, text)
        class(gui_backend_t), intent(inout) :: self
        character(*), intent(in) :: text
        if (.not. self%active .or. self%offscreen) return
        call win_clipboard_set(self%win, text)
    end subroutine gb_clipboard_set

    subroutine gb_clipboard_get(self, text)
        class(gui_backend_t), intent(inout) :: self
        character(len=:), allocatable, intent(out) :: text
        text = ""
        if (.not. self%active .or. self%offscreen) return
        text = win_clipboard_get(self%win)
    end subroutine gb_clipboard_get

    subroutine gb_primary_set(self, text)
        class(gui_backend_t), intent(inout) :: self
        character(*), intent(in) :: text
        if (.not. self%active .or. self%offscreen) return
        call win_primary_set(self%win, text)
    end subroutine gb_primary_set

    subroutine gb_primary_get(self, text)
        class(gui_backend_t), intent(inout) :: self
        character(len=:), allocatable, intent(out) :: text
        text = ""
        if (.not. self%active .or. self%offscreen) return
        text = win_primary_get(self%win)
    end subroutine gb_primary_get

    subroutine gb_set_title(self, title)
        class(gui_backend_t), intent(inout) :: self
        character(*), intent(in) :: title
        if (.not. self%active .or. self%offscreen) return
        call win_set_title(self%win, title)
    end subroutine gb_set_title

    subroutine gb_set_window_size(self, width, height)
        !! Logical units to pixels.
        class(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: width, height
        if (.not. self%active .or. self%offscreen) return
        call win_set_size(self%win, nint(real(width) * self%scale), nint(real(height) * self%scale))
    end subroutine gb_set_window_size

    subroutine gb_set_window_visible(self, visible)
        class(gui_backend_t), intent(inout) :: self
        logical, intent(in) :: visible
        if (.not. self%active .or. self%offscreen) return
        self%show_pending = visible .and. .not. self%drawn
        if (self%show_pending) return
        call win_set_visible(self%win, visible)
    end subroutine gb_set_window_visible

    subroutine gb_maximize_window(self)
        class(gui_backend_t), intent(inout) :: self
        if (.not. self%active .or. self%offscreen) return
        call win_maximize(self%win)
    end subroutine gb_maximize_window

    subroutine gb_open_url(self, url)
        !! The desktop's handler (xdg-open), not waited for.
        class(gui_backend_t), intent(inout) :: self
        character(*), intent(in) :: url
        integer :: st
        if (self%offscreen) return
        if (index(url, "'") > 0) return
        call execute_command_line("xdg-open '" // url // "' >/dev/null 2>&1 &", wait=.false., &
            exitstat=st)
    end subroutine gb_open_url

    function gb_waker(self) result(fn)
        class(gui_backend_t), intent(in) :: self
        type(c_funptr) :: fn
        fn = c_null_funptr
        if (self%active .and. .not. self%offscreen) fn = c_funloc(win_wake)
    end function gb_waker

    ! --- input --------------------------------------------------------------------------------------------

    subroutine gb_poll(self, input, wait)
        !! Give the queued events to the frame; block for the next one when the
        !! runtime allows idle waiting and nothing is queued.
        class(gui_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        logical, intent(in) :: wait
        type(win_event_t) :: ev
        if (.not. self%active) return
        call input_set_time(input, real(win_time(), kind(1.0d0)))
        if (.not. self%offscreen) then
            do while (win_next_event(self%win, ev))
                call enqueue(self, ev)
            end do
            if (wait .and. self%nqueue == 0 .and. .not. self%close_requested .and. &
                .not. self%redraw) then
                self%waits = self%waits + 1
                call win_wait(self%win, self%wake_in)
                do while (win_next_event(self%win, ev))
                    call enqueue(self, ev)
                end do
                call input_set_time(input, real(win_time(), kind(1.0d0)))
            end if
        end if
        call apply_events(self, input)
        if (self%redraw) then
            input%resized = .true.
            self%redraw = .false.
        end if
        input%mods_down = 0
        if (.not. self%offscreen) input%mods_down = mods_of(win_mods_down(self%win))
        input%width = max(1, nint(real(self%pw) / self%scale))
        input%height = max(1, nint(real(self%ph) / self%scale))
        input%scale = self%scale
    end subroutine gb_poll

    subroutine enqueue(self, ev)
        type(gui_backend_t), intent(inout) :: self
        type(win_event_t), intent(in) :: ev
        if (self%nqueue == size(self%queue)) then
            ! Full: drop the oldest event.
            self%queue(1:self%nqueue - 1) = self%queue(2:self%nqueue)
            self%nqueue = self%nqueue - 1
        end if
        self%nqueue = self%nqueue + 1
        self%queue(self%nqueue) = ev
    end subroutine enqueue

    subroutine apply_events(self, input)
        type(gui_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        integer :: k
        do k = 1, self%nqueue
            associate (ev => self%queue(k))
                select case (ev%kind)
                case (WIN_EV_CLOSE)
                    self%close_requested = .true.
                case (WIN_EV_RESIZE)
                    self%pw = max(1, self%win%width)
                    self%ph = max(1, self%win%height)
                    call gpu_resize(self%dev, self%pw, self%ph)
                    input%resized = .true.
                case (WIN_EV_EXPOSE)
                    input%resized = .true.
                case (WIN_EV_MOTION)
                    call input_update_pointer(input, ev%x / self%scale, ev%y / self%scale, &
                        self%pointer_down)
                case (WIN_EV_BUTTON_DOWN, WIN_EV_BUTTON_UP)
                    ! Only the left button drives widgets; the middle one is reported.
                    if (ev%button == 2) then
                        if (ev%kind == WIN_EV_BUTTON_DOWN) input%middle_pressed = .true.
                        if (ev%kind == WIN_EV_BUTTON_UP) input%middle_released = .true.
                    end if
                    if (ev%button == 1) then
                        self%pointer_down = ev%kind == WIN_EV_BUTTON_DOWN
                        call input_update_pointer(input, ev%x / self%scale, ev%y / self%scale, &
                            self%pointer_down)
                    end if
                case (WIN_EV_LEAVE)
                    if (.not. self%pointer_down) call input_update_pointer(input, -1.0, -1.0, &
                        .false.)
                case (WIN_EV_WHEEL)
                    if (abs(ev%wheel_y) > 0.0) call input_scroll(input, nint(sign(1.0, &
                        ev%wheel_y)), ev%wheel_y)
                case (WIN_EV_KEY_DOWN)
                    call key_event(input, ev)
                case (WIN_EV_TEXT)
                    if (allocated(ev%text)) call input_type_text(input, ev%text)
                end select
            end associate
        end do
        self%nqueue = 0
    end subroutine apply_events

    pure integer function mods_of(m)
        integer, intent(in) :: m
        mods_of = 0
        if (iand(m, WIN_MOD_CTRL) /= 0) mods_of = ior(mods_of, MOD_CTRL)
        if (iand(m, WIN_MOD_SHIFT) /= 0) mods_of = ior(mods_of, MOD_SHIFT)
        if (iand(m, WIN_MOD_ALT) /= 0) mods_of = ior(mods_of, MOD_ALT)
        if (iand(m, WIN_MOD_META) /= 0) mods_of = ior(mods_of, MOD_META)
    end function mods_of

    subroutine key_event(input, ev)
        type(input_state_t), intent(inout) :: input
        type(win_event_t), intent(in) :: ev
        integer :: key, mods
        mods = mods_of(ev%mods)
        select case (ev%key)
        case (WIN_KEY_ENTER)
            key = KEY_ENTER
        case (WIN_KEY_ESCAPE)
            key = KEY_ESCAPE
        case (WIN_KEY_BACKSPACE)
            key = KEY_BACKSPACE
        case (WIN_KEY_TAB)
            key = KEY_TAB
        case (WIN_KEY_SPACE)
            key = KEY_SPACE
        case (WIN_KEY_DELETE)
            key = KEY_DELETE
        case (WIN_KEY_RIGHT)
            key = KEY_ARROW_RIGHT
        case (WIN_KEY_LEFT)
            key = KEY_ARROW_LEFT
        case (WIN_KEY_DOWN)
            key = KEY_ARROW_DOWN
        case (WIN_KEY_UP)
            key = KEY_ARROW_UP
        case (WIN_KEY_HOME)
            key = KEY_HOME
        case (WIN_KEY_END)
            key = KEY_END
        case (WIN_KEY_PAGE_UP)
            key = KEY_PAGE_UP
        case (WIN_KEY_PAGE_DOWN)
            key = KEY_PAGE_DOWN
        case (WIN_KEY_INSERT)
            key = KEY_INSERT
        case (WIN_KEY_F1:WIN_KEY_F1 + 11)
            key = KEY_F1 + ev%key - WIN_KEY_F1
        case default
            key = KEY_NONE
        end select
        if (key /= KEY_NONE) then
            call input_key_press(input, key, 0, mods, repeat=ev%repeat, widgets=.true.)
        else if (ev%codepoint > 32 .and. iand(mods, MOD_CTRL + MOD_ALT + MOD_META) /= 0) then
            call input_key_press(input, KEY_NONE, ev%codepoint, mods, repeat=ev%repeat)
        end if
    end subroutine key_event

    ! --- fonts -----------------------------------------------------------------------------------------------

    integer function face_px(face, size) result(px)
        !! Pixel size for a logical size: pixel fonts snap to their design grid.
        integer, intent(in) :: face
        real, intent(in) :: size
        real :: grid
        px = max(1, nint(size))
        ! A named cell font is drawn at the size asked for, as terminals do.
        if (face == FACE_CELL .and. len_trim(cell_font_family) > 0) return
        grid = theme%fonts(min(face, FACE_MONO))%grid
        if (theme%fonts(min(face, FACE_MONO))%pixel .and. grid > 0.0) &
            px = nint(grid) * max(1, nint(size / grid))
    end function face_px

    function slots_key() result(key)
        character(len=192) :: key
        key = trim(theme%name) // "|" // trim(cell_font_family)
    end function slots_key

    integer function font_slot(face, px) result(k)
        !! The fonts of a theme face at `px` pixels (opened once, kept).
        integer, intent(in) :: face, px
        character(len=:), allocatable :: path
        logical :: pixel
        integer :: size_px, idx, j
        if (slots_theme /= slots_key()) then
            nslots = 0
            slots_theme = slots_key()
        end if
        size_px = max(1, px)
        do j = 1, nslots
            if (slots(j)%face == face .and. slots(j)%px == size_px) then
                k = j
                if (.not. slots(j)%ok) k = 0
                return
            end if
        end do
        if (nslots == size(slots)) nslots = 0
        pixel = .false.
        path = ""
        idx = 0
        if (face == FACE_CELL .and. len_trim(cell_font_family) > 0) then
            call font_lookup(trim(cell_font_family), "", 0, path, index=idx)
            if (len(path) == 0) call report_error("fortui_gui", "font", "cell font '" // &
                trim(cell_font_family) // "' is not installed; using the theme's")
            ! A pixel design at a whole multiple of its grid is drawn crisp.
            pixel = any(theme%fonts(FACE_MONO)%families == cell_font_family) .and. &
                theme%fonts(FACE_MONO)%pixel .and. theme%fonts(FACE_MONO)%grid > 0.0
            if (pixel) pixel = modulo(size_px, nint(theme%fonts(FACE_MONO)%grid)) == 0
        end if
        if (len(path) == 0) call font_for(theme%fonts(min(face, FACE_MONO)), min(face, FACE_MONO), &
            size_px, theme%name, path, pixel, idx)
        k = nslots + 1
        nslots = k
        slots(k) = face_slot_t(face=face, px=size_px)
        slots(k)%ok = len(path) > 0
        if (slots(k)%ok) slots(k)%ok = font_open_file(slots(k)%font, path, size_px, idx)
        if (.not. slots(k)%ok) then
            call report_error("fortui_gui", "font", "cannot open '" // path // "'")
            k = 0
            return
        end if
        ! The fonts' own hinting, as FreeType applies it for the desktop's text.
        call font_set_hinting(slots(k)%font, .true.)
        slots(k)%mono = pixel .or. (theme%fonts(min(face, FACE_MONO))%pixel .and. .not. &
            (face == FACE_CELL .and. len_trim(cell_font_family) > 0))
        ! A named cell font is hinted fully (whole-pixel advances), others lightly.
        slots(k)%light = .not. slots(k)%mono .and. .not. (face == FACE_CELL .and. &
            len_trim(cell_font_family) > 0)
        slots(k)%height = slots(k)%font%height
        slots(k)%ascent = slots(k)%font%ascent
        do j = 1, size(FALLBACK_FAMILIES)
            call font_lookup(trim(FALLBACK_FAMILIES(j)), "", 0, path, index=idx)
            if (len(path) == 0) cycle
            slots(k)%has_fallback(j) = font_open_file(slots(k)%fallback(j), path, size_px, idx)
            if (slots(k)%has_fallback(j)) call font_set_hinting(slots(k)%fallback(j), .true.)
        end do
    end function font_slot

    subroutine pick(slot, cp, which)
        !! Which font draws a code point: 0 the face, 1..3 a fallback (the face's
        !! own glyph for missing characters when no font has it).
        integer, intent(in) :: slot, cp
        integer, intent(out) :: which
        integer :: j
        which = 0
        if (font_has(slots(slot)%font, cp)) return
        do j = 1, size(FALLBACK_FAMILIES)
            if (.not. slots(slot)%has_fallback(j)) cycle
            if (font_has(slots(slot)%fallback(j), cp)) then
                which = j
                return
            end if
        end do
    end subroutine pick

    integer function advance_of(slot, cp) result(adv)
        integer, intent(in) :: slot, cp
        integer :: which
        call pick(slot, cp, which)
        if (which == 0) then
            adv = font_advance(slots(slot)%font, cp)
        else
            adv = font_advance(slots(slot)%fallback(which), cp)
        end if
    end function advance_of

    subroutine layout_metrics(slot, cp, adv26, left, width)
        !! A code point's advance (26.6) and ink box in the font that draws it.
        integer, intent(in) :: slot, cp
        integer, intent(out) :: adv26, left, width
        integer :: which
        if (cp >= 0 .and. cp <= 255) then
            if (slots(slot)%known(cp)) then
                adv26 = slots(slot)%adv26(cp)
                left = slots(slot)%ink_left(cp)
                width = slots(slot)%ink_width(cp)
                return
            end if
        end if
        call pick(slot, cp, which)
        if (which == 0) then
            adv26 = font_advance26(slots(slot)%font, cp, slots(slot)%light)
            call font_glyph_box(slots(slot)%font, cp, left, width)
        else
            adv26 = font_advance26(slots(slot)%fallback(which), cp, slots(slot)%light)
            call font_glyph_box(slots(slot)%fallback(which), cp, left, width)
        end if
        if (cp >= 0 .and. cp <= 255) then
            slots(slot)%known(cp) = .true.
            slots(slot)%adv26(cp) = adv26
            slots(slot)%ink_left(cp) = left
            slots(slot)%ink_width(cp) = width
        end if
    end subroutine layout_metrics

    subroutine line_extent(slot, s, width, xstart)
        !! SDL_ttf's measure of a line: from the leftmost ink (at most the origin)
        !! to the rightmost ink or the pen's end, and the shift that keeps ink
        !! left of the origin visible.
        integer, intent(in) :: slot
        character(*), intent(in) :: s
        integer, intent(out) :: width, xstart
        integer :: pos, cp, pen26, adv26, left, w, x, minx, maxx
        minx = 0
        maxx = 0
        pen26 = 0
        pos = 1
        do while (pos <= len(s))
            cp = next_codepoint(s, pos)
            call layout_metrics(slot, cp, adv26, left, w)
            x = floor26(pen26) + left
            minx = min(minx, x)
            maxx = max(maxx, x + w)
            pen26 = pen26 + adv26
        end do
        maxx = max(maxx, floor26(pen26))
        width = maxx - minx
        xstart = max(0, -minx)
    end subroutine line_extent

    pure integer function floor26(v)
        integer, intent(in) :: v
        floor26 = (v - modulo(v, 64)) / 64
    end function floor26

    subroutine gb_metrics(self)
        class(gui_backend_t), intent(inout) :: self
        measuring = .true.
        px_scale = self%scale
        nslots = 0
        self%nglyphs = 0
        call release_pages(self)
        call text_use_measurement(measure_width, measure_advance, theme%line_factor)
        call text_use_cell_measure(measure_cell)
    end subroutine gb_metrics

    subroutine measure_cell(size, width, height)
        !! The cell font's advance of "M" and its line height (ascent plus descent).
        real, intent(in) :: size
        real, intent(out) :: width, height
        integer :: k
        width = 0.5 * size
        height = 1.25 * size
        if (.not. measuring) return
        k = font_slot(FACE_CELL, face_px(FACE_CELL, size * px_scale))
        if (k == 0) return
        width = real(font_advance(slots(k)%font, iachar("M"))) / px_scale
        height = real(slots(k)%height) / px_scale
    end subroutine measure_cell

    real function measure_width(s, size, style) result(w)
        character(*), intent(in) :: s
        real, intent(in) :: size
        integer, intent(in) :: style
        integer :: k, face, width, xstart
        w = 0.0
        if (.not. measuring .or. len(s) == 0) return
        face = paint_face(style)
        k = font_slot(face, face_px(face, size * px_scale))
        if (k == 0) return
        call line_extent(k, s, width, xstart)
        w = real(width) / px_scale
    end function measure_width

    real function measure_advance(cp, size, style) result(adv)
        integer, intent(in) :: cp, style
        real, intent(in) :: size
        integer :: k, face
        adv = 0.0
        if (.not. measuring) return
        face = paint_face(style)
        k = font_slot(face, face_px(face, size * px_scale))
        if (k == 0) return
        adv = real(advance_of(k, cp)) / px_scale
    end function measure_advance

    integer function next_codepoint(s, pos) result(cp)
        !! The UTF-8 character at s(pos:), advancing pos (bad bytes count as one).
        character(*), intent(in) :: s
        integer, intent(inout) :: pos
        integer :: b, n, k
        b = iachar(s(pos:pos))
        if (b < 128) then
            cp = b
            n = 1
        else if (b >= 240) then
            cp = iand(b, 7)
            n = 4
        else if (b >= 224) then
            cp = iand(b, 15)
            n = 3
        else if (b >= 192) then
            cp = iand(b, 31)
            n = 2
        else
            cp = 65533
            pos = pos + 1
            return
        end if
        if (pos + n - 1 > len(s)) then
            cp = 65533
            pos = len(s) + 1
            return
        end if
        do k = 1, n - 1
            cp = ior(ishft(cp, 6), iand(iachar(s(pos + k:pos + k)), 63))
        end do
        pos = pos + n
    end function next_codepoint

    ! --- glyph atlas ------------------------------------------------------------------------------------

    integer function glyph_index(self, slot, cp) result(g)
        !! The atlas entry of a glyph, rendered and placed when first drawn.
        type(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: slot, cp
        type(glyph_entry_t), allocatable :: grown(:)
        type(glyph_t) :: gl
        integer(int8), allocatable :: rgba(:, :, :)
        integer :: which, page, x, y
        logical :: found
        do g = self%nglyphs, 1, -1
            if (self%glyphs(g)%cp == cp .and. self%glyphs(g)%slot == slot) return
        end do
        call pick(slot, cp, which)
        if (which == 0) then
            found = font_glyph(slots(slot)%font, cp, gl)
        else
            found = font_glyph(slots(slot)%fallback(which), cp, gl)
        end if
        if (self%nglyphs == size(self%glyphs)) then
            allocate (grown(2 * size(self%glyphs)))
            grown(1:self%nglyphs) = self%glyphs(1:self%nglyphs)
            call move_alloc(grown, self%glyphs)
        end if
        g = self%nglyphs + 1
        self%nglyphs = g
        self%glyphs(g) = glyph_entry_t(slot=slot, cp=cp, w=gl%width, h=gl%height, &
            left=gl%left, top=gl%top, colour=gl%colour)
        if (gl%width == 0 .or. gl%height == 0) return
        call place(self, gl%width, gl%height, page, x, y)
        if (page == 0) return
        self%glyphs(g)%page = page
        self%glyphs(g)%x = x
        self%glyphs(g)%y = y
        allocate (rgba(4, gl%width, gl%height))
        if (gl%colour) then
            rgba = gl%rgba
        else
            rgba(1:3, :, :) = -1_int8
            if (slots(slot)%mono) then
                rgba(4, :, :) = merge(-1_int8, 0_int8, iand(int(gl%alpha), 255) >= 128)
            else
                rgba(4, :, :) = gl%alpha
            end if
        end if
        call texture_update(self, self%pages(page)%texture, x, y, rgba)
    end function glyph_index

    subroutine place(self, w, h, page, x, y)
        !! Shelf packing over atlas pages, a new page when the last is full.
        type(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: w, h
        integer, intent(out) :: page, x, y
        type(page_t), allocatable :: grown(:)
        page = 0
        if (w + 2 > ATLAS .or. h + 2 > ATLAS) return
        if (self%npages > 0) then
            associate (p => self%pages(self%npages))
                if (p%cursor_x + w + 1 > ATLAS) then
                    p%shelf_y = p%shelf_y + p%shelf_h + 1
                    p%shelf_h = 0
                    p%cursor_x = 0
                end if
                if (p%shelf_y + h + 1 <= ATLAS) then
                    page = self%npages
                    x = p%cursor_x
                    y = p%shelf_y
                    p%cursor_x = p%cursor_x + w + 1
                    p%shelf_h = max(p%shelf_h, h)
                    return
                end if
            end associate
        end if
        if (self%npages == size(self%pages)) then
            allocate (grown(2 * size(self%pages)))
            grown(1:self%npages) = self%pages(1:self%npages)
            call move_alloc(grown, self%pages)
        end if
        self%npages = self%npages + 1
        page = self%npages
        self%pages(page) = page_t(texture=texture_create(self, ATLAS, ATLAS))
        x = 0
        y = 0
        self%pages(page)%cursor_x = w + 1
        self%pages(page)%shelf_h = h
    end subroutine place

    subroutine release_pages(self)
        type(gui_backend_t), intent(inout) :: self
        integer :: k
        if (.not. allocated(self%pages)) return
        do k = 1, self%npages
            call texture_release(self, self%pages(k)%texture)
        end do
        self%npages = 0
        self%nglyphs = 0
    end subroutine release_pages

    ! --- renderer resources (GPU, else CPU) --------------------------------------------------------------

    integer function texture_create(self, w, h) result(id)
        type(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: w, h
        if (self%gpu) then
            id = gpu_texture_create(self%dev, w, h)
        else
            id = cpu_texture_create(self%cpu, w, h)
        end if
    end function texture_create

    subroutine texture_update(self, id, x, y, rgba)
        type(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: id, x, y
        integer(int8), intent(in) :: rgba(:, :, :)
        if (id == 0) return
        if (self%gpu) then
            call gpu_texture_update(self%dev, id, x, y, rgba)
        else
            call cpu_texture_update(self%cpu, id, x, y, rgba)
        end if
    end subroutine texture_update

    subroutine texture_release(self, id)
        type(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: id
        if (id == 0) return
        if (self%gpu) then
            call gpu_texture_release(self%dev, id)
        else
            call cpu_texture_release(self%cpu, id)
        end if
    end subroutine texture_release

    subroutine layer_set(self, id, data, count)
        type(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: id, count
        real(c_float), intent(in) :: data(:, :)
        if (self%gpu) then
            call gpu_layer_set(self%dev, id, data, count)
        else
            call cpu_layer_set(self%cpu, id, data, count)
        end if
    end subroutine layer_set

    subroutine layer_release(self, id)
        type(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: id
        if (self%gpu) then
            call gpu_layer_release(self%dev, id)
        else
            call cpu_layer_release(self%cpu, id)
        end if
    end subroutine layer_release

    ! --- frame -----------------------------------------------------------------------------------------------

    subroutine gb_present(self, frame, store)
        class(gui_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        real :: bg(4)
        integer :: k
        self%presents = self%presents + 1
        if (.not. self%active) return
        self%frame_no = modulo(self%frame_no + 1, 2**30)
        measuring = .true.
        call self%canvas%sync(store)
        call sync_layers(self, store)
        if (self%own_background) then
            call paint_frame(frame, self%scale, real(self%pw), real(self%ph), self%paint, &
                self%background)
        else
            call paint_frame(frame, self%scale, real(self%pw), real(self%ph), self%paint)
        end if
        call unpack(self%paint%background, bg)
        if (.not. self%offscreen) then
            if (any(abs(bg(1:3) - self%window_bg) > 1.0e-3)) then
                call win_set_background(self%win, bg(1:3))
                self%window_bg = bg(1:3)
            end if
        end if
        call gfx_list_reset(self%list, self%pw, self%ph, bg)
        self%clip = [0, 0, self%pw, self%ph]
        self%clip_depth = 0
        do k = 1, self%paint%n
            call record(self, frame, store, k)
        end do
        if (self%gpu) then
            if (.not. gpu_render(self%dev, self%list)) self%redraw = .true.
        else
            call cpu_render(self%cpu, self%list)
        end if
        if (.not. self%offscreen) then
            self%drawn = .true.
            if (self%show_pending) then
                self%show_pending = .false.
                call win_set_visible(self%win, .true.)
            end if
            call win_flush(self%win)
        end if
    end subroutine gb_present

    subroutine record(self, frame, store, k)
        !! One display-list command into the frame's batches.
        type(gui_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        integer, intent(in) :: k
        real :: c(4), d(4)
        associate (cm => self%paint%cmds(k))
            select case (cm%kind)
            case (PAINT_RECT)
                call unpack(cm%fill, c)
                call unpack(cm%stroke, d)
                call gfx_add_shape(self%list, self%clip, [cm%x, cm%y, cm%w, cm%h], c, d, &
                    [cm%radius, cm%border, 0.0, merge(1.0, 0.0, cm%pattern == PATTERN_CHECKER)])
            case (PAINT_LINE)
                call unpack(cm%fill, c)
                call gfx_add_shape(self%list, self%clip, [cm%x, cm%y, cm%w, cm%h], c, c, &
                    [0.0, cm%border, 1.0, 0.0])
            case (PAINT_TEXT)
                call add_text(self, self%paint%text_of(k), cm%x, cm%y, cm%h, cm%face, cm%size, &
                    cm%fill)
            case (PAINT_CLIP)
                if (self%clip_depth < size(self%clip_stack, 2)) then
                    self%clip_depth = self%clip_depth + 1
                    self%clip_stack(:, self%clip_depth) = self%clip
                end if
                self%clip = intersect(self%clip, [nint(cm%x), nint(cm%y), nint(cm%w), nint(cm%h)])
            case (PAINT_UNCLIP)
                if (self%clip_depth > 0) then
                    self%clip = self%clip_stack(:, self%clip_depth)
                    self%clip_depth = self%clip_depth - 1
                end if
            case (PAINT_CANVAS)
                call record_canvas(self, frame, store, cm%node, cm%x, cm%y, cm%w, cm%h, cm%fill)
            end select
        end associate
    end subroutine record

    pure function intersect(a, b) result(r)
        integer, intent(in) :: a(4), b(4)
        integer :: r(4), x0, y0, x1, y1
        x0 = max(a(1), b(1))
        y0 = max(a(2), b(2))
        x1 = min(a(1) + a(3), b(1) + b(3))
        y1 = min(a(2) + a(4), b(2) + b(4))
        r = [x0, y0, max(0, x1 - x0), max(0, y1 - y0)]
    end function intersect

    pure subroutine unpack(c, out)
        !! ui_rgba to 0..1 floats.
        integer(int32), intent(in) :: c
        real, intent(out) :: out(4)
        integer :: k
        do k = 1, 4
            out(k) = real(iand(ishft(c, -8 * (k - 1)), 255_int32)) / 255.0
        end do
    end subroutine unpack

    subroutine add_text(self, str, x, y, line_h, face, size_px, colour)
        !! Glyph quads of `str` with its line box at (x, y), whole pixels, drawn
        !! 1:1 from the atlas; every glyph sits on the face's baseline.
        type(gui_backend_t), intent(inout) :: self
        character(*), intent(in) :: str
        real, intent(in) :: x, y, line_h, size_px
        integer, intent(in) :: face
        integer(int32), intent(in) :: colour
        integer :: slot, pos, cp, g, pen, base, pen26, adv26, left, w, width, xstart
        real :: c(4), x0, y0, x1, y1, u0, v0, u1, v1, white(4)
        slot = font_slot(face, face_px(face, size_px))
        if (slot == 0) return
        call unpack(colour, c)
        white = [1.0, 1.0, 1.0, c(4)]
        base = nint(y + 0.5 * (line_h - real(slots(slot)%height))) + slots(slot)%ascent
        call line_extent(slot, str, width, xstart)
        pen26 = 0
        pos = 1
        do while (pos <= len(str))
            cp = next_codepoint(str, pos)
            g = glyph_index(self, slot, cp)
            call layout_metrics(slot, cp, adv26, left, w)
            pen = nint(x) + xstart + floor26(pen26)
            associate (e => self%glyphs(g))
                if (e%page > 0) then
                    x0 = real(pen + e%left)
                    y0 = real(base - e%top)
                    x1 = x0 + real(e%w)
                    y1 = y0 + real(e%h)
                    u0 = real(e%x) / ATLAS
                    v0 = real(e%y) / ATLAS
                    u1 = real(e%x + e%w) / ATLAS
                    v1 = real(e%y + e%h) / ATLAS
                    call gfx_add_quad(self%list, self%clip, self%pages(e%page)%texture, .false., &
                        reshape([x0, y0, x1, y0, x1, y1, x0, y1], [2, 4]), &
                        reshape([u0, v0, u1, v0, u1, v1, u0, v1], [2, 4]), &
                        merge(white, c, e%colour))
                end if
            end associate
            pen26 = pen26 + adv26
        end do
    end subroutine add_text

    ! --- canvas ------------------------------------------------------------------------------------------------

    subroutine sync_layers(self, store)
        !! GPU resources follow the store slots (released or reassigned slots).
        type(gui_backend_t), intent(inout) :: self
        type(canvas_store_t), intent(in) :: store
        type(gpu_layer_t), allocatable :: grown(:)
        integer :: k, n
        n = 0
        if (allocated(store%layers)) n = size(store%layers)
        if (size(self%layers) < n) then
            allocate (grown(n))
            grown(1:size(self%layers)) = self%layers
            call move_alloc(grown, self%layers)
        end if
        do k = 1, size(self%layers)
            if (self%layers(k)%serial == 0) cycle
            if (k > n) then
                call free_layer(self, k)
            else if (.not. store%layers(k)%in_use .or. &
                    store%layers(k)%serial /= self%layers(k)%serial) then
                call free_layer(self, k)
            end if
        end do
    end subroutine sync_layers

    subroutine free_layer(self, k)
        type(gui_backend_t), intent(inout) :: self
        integer, intent(in) :: k
        if (self%layers(k)%texture /= 0) call texture_release(self, self%layers(k)%texture)
        if (self%layers(k)%count > 0) call layer_release(self, k)
        self%layers(k) = gpu_layer_t()
    end subroutine free_layer

    subroutine record_canvas(self, frame, store, index, x, y, w, h, fill)
        !! A canvas: fill, then its layers in order (images as textured quads,
        !! points and lines from their retained buffers), then its labels.
        type(gui_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
        integer, intent(in) :: index
        real, intent(in) :: x, y, w, h
        integer(int32), intent(in) :: fill
        integer :: j, saved(4)
        real :: c(4), z, ox, oy, sx, sy, sw, sh
        logical :: fresh, attributes, indices, upload
        saved = self%clip
        self%clip = intersect(self%clip, [nint(x), nint(y), nint(w), nint(h)])
        if (fill /= 0) then
            call unpack(fill, c)
            call gfx_add_shape(self%list, self%clip, [x, y, w, h], c, c, [0.0, 0.0, 0.0, 0.0])
        end if
        associate (node => frame%nodes(index))
            z = node%canvas_view%zoom * self%scale
            ox = (node%x + node%canvas_view%pan_x) * self%scale
            oy = (node%y + node%canvas_view%pan_y) * self%scale
            do j = node%layer_first, node%layer_first + node%layer_count - 1
                associate (ref => frame%layers(j))
                    if (ref%vertex_slot > 0) upload = self%canvas%vertices(store, &
                        ref%vertex_slot, .false.)
                    fresh = self%layers(ref%slot)%serial /= ref%serial
                    call self%canvas%layer(ref, fresh, attributes, indices)
                    if (ref%kind == LAYER_CELLS) then
                        call record_cells(self, store%layers(ref%slot), ox, oy, z)
                        cycle
                    end if
                    call prepare_layer(self, store, ref)
                    if (ref%kind == LAYER_IMAGE) then
                        associate (l => store%layers(ref%slot))
                            sx = ox + l%rect(1) * z
                            sy = oy + l%rect(2) * z
                            sw = l%rect(3) * z
                            sh = l%rect(4) * z
                        end associate
                        if (self%layers(ref%slot)%texture /= 0) call gfx_add_quad(self%list, &
                            self%clip, self%layers(ref%slot)%texture, .true., reshape([sx, sy, &
                            sx + sw, sy, sx + sw, sy + sh, sx, sy + sh], [2, 4]), &
                            reshape([0.0, 0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 1.0], [2, 4]), &
                            [1.0, 1.0, 1.0, 1.0])
                    else if (self%layers(ref%slot)%count > 0) then
                        call gfx_add_layer(self%list, self%clip, ref%slot, &
                            self%layers(ref%slot)%count, real([real(self%pw), real(self%ph), &
                            0.0, 0.0, z, ox, oy, z, store%layers(ref%slot)%min_pixels * &
                            self%scale, self%scale, 0.0, 0.0], c_float))
                    end if
                end associate
            end do
            do j = node%label_first, node%label_first + node%label_count - 1
                associate (lab => frame%labels(j))
                    call add_label(self, lab%text, ox + lab%x * z, oy + lab%y * z, lab%size, &
                        lab%rgba, fill)
                end associate
            end do
        end associate
        self%clip = saved
    end subroutine record_canvas

    subroutine prepare_layer(self, store, ref)
        !! Rebuild the instances (or image) of a layer whose data changed.
        type(gui_backend_t), intent(inout) :: self
        type(canvas_store_t), intent(in), target :: store
        type(ui_layer_ref_t), intent(in) :: ref
        integer :: i, n, ia, ib, vs
        real :: c(4), d(4)
        integer(int8), allocatable :: rgba(:, :, :)
        associate (g => self%layers(ref%slot), l => store%layers(ref%slot))
            if (g%serial == ref%serial .and. g%version == ref%version .and. &
                g%index_version == ref%index_version .and. &
                g%vertex_version == ref%vertex_version .and. ref%kind /= LAYER_IMAGE) return
            if (ref%kind == LAYER_IMAGE .and. g%serial == ref%serial .and. &
                g%version == ref%version) return
            if (g%serial /= ref%serial) call free_layer(self, ref%slot)
            g%serial = ref%serial
            g%version = ref%version
            g%index_version = ref%index_version
            g%vertex_version = ref%vertex_version
            if (ref%kind == LAYER_IMAGE) then
                if (g%texture /= 0 .and. (g%width /= l%image_width .or. &
                    g%height /= l%image_height)) then
                    call texture_release(self, g%texture)
                    g%texture = 0
                end if
                g%width = l%image_width
                g%height = l%image_height
                if (g%width <= 0 .or. g%height <= 0) return
                if (g%texture == 0) g%texture = texture_create(self, g%width, g%height)
                rgba = reshape(transfer(l%rgba(1:g%width * g%height), 0_int8, &
                    4 * g%width * g%height), [4, g%width, g%height])
                call texture_update(self, g%texture, 0, 0, rgba)
                return
            end if
            vs = ref%vertex_slot
            if (ref%kind == LAYER_POINTS) then
                n = min(ref%vertex_count, size(l%rgba), size(l%sizes))
                call ensure_data(g, n)
                do i = 1, n
                    call unpack(l%rgba(i), c)
                    g%data(:, i) = real([store%layers(vs)%xy(1, i), store%layers(vs)%xy(2, i), &
                        l%sizes(i), 0.0, c, c, 0.0, 0.0, 2.0, merge(1.0, 0.0, l%world_size)], &
                        c_float)
                end do
            else
                n = min(l%index_count, size(l%indices)) / 2
                call ensure_data(g, n)
                do i = 1, n
                    ia = int(l%indices(2 * i - 1)) + 1
                    ib = int(l%indices(2 * i)) + 1
                    call unpack(l%rgba(ia), c)
                    call unpack(l%rgba(ib), d)
                    g%data(:, i) = real([store%layers(vs)%xy(:, ia), store%layers(vs)%xy(:, ib), &
                        c, d, 0.0, l%line_width, 1.0, 1.0], c_float)
                end do
            end if
            g%count = n
            call layer_set(self, ref%slot, g%data, n)
        end associate
    end subroutine prepare_layer

    subroutine ensure_data(g, n)
        type(gpu_layer_t), intent(inout) :: g
        integer, intent(in) :: n
        if (allocated(g%data)) then
            if (size(g%data, 2) >= n) return
            deallocate (g%data)
        end if
        allocate (g%data(16, max(16, n + n / 4)))
    end subroutine ensure_data

    subroutine record_cells(self, l, ox, oy, z)
        !! A cell grid: background runs, then one glyph per cell (whole cells, so
        !! the grid stays exact whatever the font's advances), then underlines
        !! and strike-throughs.
        type(gui_backend_t), intent(inout) :: self
        type(canvas_layer_t), intent(in) :: l
        real, intent(in) :: ox, oy, z
        real :: x0, y0, cw, ch, px, c(4), t
        integer :: r, col, k, first, cp, nb
        character(len=4) :: buf
        if (l%cols <= 0 .or. l%rows <= 0 .or. .not. allocated(l%cp)) return
        x0 = ox + l%rect(1) * z
        y0 = oy + l%rect(2) * z
        cw = l%rect(3) * z / real(l%cols)
        ch = l%rect(4) * z / real(l%rows)
        px = l%cell_size * self%scale
        do r = 0, l%rows - 1
            k = r * l%cols
            first = 0
            do col = 1, l%cols
                if (col < l%cols) then
                    if (l%bg(k + col + 1) == l%bg(k + first + 1)) cycle
                end if
                if (alpha(l%bg(k + first + 1)) > 0) then
                    call unpack(l%bg(k + first + 1), c)
                    call gfx_add_shape(self%list, self%clip, [x0 + real(first) * cw, &
                        y0 + real(r) * ch, real(col - first) * cw, ch], c, c, [0.0, 0.0, 0.0, 0.0])
                end if
                first = col
            end do
        end do
        if (l%extend_edges) call edges()
        do r = 0, l%rows - 1
            do col = 0, l%cols - 1
                k = r * l%cols + col + 1
                cp = l%cp(k)
                if (cp <= 32 .or. iand(l%attr(k), CELL_CONT) /= 0) cycle
                call encode(cp, buf, nb)
                call add_text(self, buf(1:nb), real(nint(x0 + real(col) * cw)), &
                    y0 + real(r) * ch, ch, FACE_CELL, px, l%fg(k))
            end do
        end do
        t = max(1.0, real(nint(self%scale)))
        do k = 1, l%cols * l%rows
            if (iand(l%attr(k), CELL_BAR) /= 0) then
                call unpack(l%fg(k), c)
                call gfx_add_shape(self%list, self%clip, [x0 + real(modulo(k - 1, l%cols)) * cw, &
                    y0 + real((k - 1) / l%cols) * ch, 2.0 * t, ch], c, c, [0.0, 0.0, 0.0, 0.0])
            end if
            if (iand(l%attr(k), CELL_UNDERLINE + CELL_STRIKE) == 0) cycle
            r = (k - 1) / l%cols
            col = modulo(k - 1, l%cols)
            call unpack(l%fg(k), c)
            px = cw
            if (iand(l%attr(k), CELL_WIDE) /= 0) px = 2.0 * cw
            if (iand(l%attr(k), CELL_UNDERLINE) /= 0) call gfx_add_shape(self%list, self%clip, &
                [x0 + real(col) * cw, real(nint(y0 + real(r + 1) * ch - 2.0 * t)), px, t], c, c, &
                [0.0, 0.0, 0.0, 0.0])
            if (iand(l%attr(k), CELL_STRIKE) /= 0) call gfx_add_shape(self%list, self%clip, &
                [x0 + real(col) * cw, real(nint(y0 + (real(r) + 0.5) * ch)), px, t], c, c, &
                [0.0, 0.0, 0.0, 0.0])
        end do
    contains
        subroutine edges()
            !! The last column's backgrounds out to the right edge of the clip, so
            !! a full-width bar (tmux's status line) reaches the window edge. The
            !! strip below the last row is no row and keeps the canvas fill, the
            !! terminal's default background.
            real :: xr, right
            integer :: j
            xr = x0 + real(l%cols) * cw
            right = real(self%clip(1) + self%clip(3))
            if (right <= xr) return
            do j = 0, l%rows - 1
                k = j * l%cols + l%cols
                if (alpha(l%bg(k)) == 0 .or. iand(l%attr(k), CELL_CURSOR) /= 0) cycle
                call unpack(l%bg(k), c)
                call gfx_add_shape(self%list, self%clip, [xr, y0 + real(j) * ch, right - xr, &
                    ch], c, c, [0.0, 0.0, 0.0, 0.0])
            end do
        end subroutine edges
        pure integer function alpha(rgba)
            integer(int32), intent(in) :: rgba
            alpha = iand(ishft(rgba, -24), 255_int32)
        end function alpha
        pure subroutine encode(cp, out, n)
            integer, intent(in) :: cp
            character(len=4), intent(out) :: out
            integer, intent(out) :: n
            if (cp < 128) then
                out(1:1) = achar(cp)
                n = 1
            else if (cp < 2048) then
                out(1:1) = achar(ior(192, ishft(cp, -6)))
                out(2:2) = achar(ior(128, iand(cp, 63)))
                n = 2
            else if (cp < 65536) then
                out(1:1) = achar(ior(224, ishft(cp, -12)))
                out(2:2) = achar(ior(128, iand(ishft(cp, -6), 63)))
                out(3:3) = achar(ior(128, iand(cp, 63)))
                n = 3
            else
                out(1:1) = achar(ior(240, ishft(cp, -18)))
                out(2:2) = achar(ior(128, iand(ishft(cp, -12), 63)))
                out(3:3) = achar(ior(128, iand(ishft(cp, -6), 63)))
                out(4:4) = achar(ior(128, iand(cp, 63)))
                n = 4
            end if
        end subroutine encode
    end subroutine record_cells

    subroutine add_label(self, str, cx, y, size, rgba, fill)
        !! Canvas label centred below its anchor; without a colour of its own it
        !! contrasts with the canvas fill.
        type(gui_backend_t), intent(inout) :: self
        character(*), intent(in) :: str
        real, intent(in) :: cx, y, size
        integer(int32), intent(in) :: rgba, fill
        integer :: slot, face, width, xstart
        real :: px
        face = FACE_REGULAR
        px = size * self%scale
        slot = font_slot(face, face_px(face, px))
        if (slot == 0) return
        call line_extent(slot, str, width, xstart)
        call add_text(self, str, real(nint(cx - 0.5 * real(width))), y + 2.0 * self%scale, &
            real(slots(slot)%height), face, px, merge(rgba, contrast(fill), rgba /= -1))
    end subroutine add_label

    integer(int32) function contrast(fill) result(c)
        !! Near-black on light fills, near-white on dark ones (the theme's text
        !! colour where the canvas has no fill).
        integer(int32), intent(in) :: fill
        real :: f(4), lum
        if (fill == 0) then
            c = theme%on_surface
            return
        end if
        call unpack(fill, f)
        lum = 0.2126 * f(1) + 0.7152 * f(2) + 0.0722 * f(3)
        c = merge(int(z'FF202020', int32), int(z'FFF0F0F0', int32), lum > 0.5)
    end function contrast

    ! --- tests ------------------------------------------------------------------------------------------------

    subroutine gui_read_pixels(backend, rgba, width, height)
        !! The last frame of an offscreen backend as RGBA bytes (tests).
        class(ui_backend_t), intent(inout) :: backend
        integer(int8), allocatable, intent(out) :: rgba(:, :, :)
        integer, intent(out) :: width, height
        width = 0
        height = 0
        select type (self => backend)
        type is (gui_backend_t)
            if (.not. self%offscreen .or. .not. self%active) return
            if (self%gpu) then
                call gpu_read(self%dev, rgba)
            else
                rgba = self%cpu%rgba
            end if
            width = self%pw
            height = self%ph
        end select
    end subroutine gui_read_pixels

    subroutine gui_inject(backend, ev)
        !! A window event as if the window had sent it (tests, scripted input).
        class(ui_backend_t), intent(inout) :: backend
        type(win_event_t), intent(in) :: ev
        select type (self => backend)
        type is (gui_backend_t)
            if (self%active) call enqueue(self, ev)
        end select
    end subroutine gui_inject

end module fortui_gui
