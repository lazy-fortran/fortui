module fortui_tui
!! Terminal platform + renderer backend using termbox2. One terminal cell is
!! CELL_W_DP x CELL_H_DP logical units; layout uses matching fixed metrics.
!!
!! Canvas layers are rasterized in Fortran (fortui_raster) and realized either
!! as braille cells (2x4 dots per cell, per-cell colour; any UTF-8 terminal,
!! also through ssh and tmux) or as pixels with the kitty graphics protocol.
!! Capabilities are detected in-band (queries answered by the terminal, which
!! works over ssh) and can be set explicitly:
!!
!!   FORTUI_TUI_GRAPHICS = auto | braille | kitty | sixel (sixel: unsupported)
!!   FORTUI_TUI_COLOR    = auto | truecolor | 256
!!
!! An explicit choice the backend cannot honour fails `init` with a reason; an
!! automatic choice is reported by `describe` (e.g. "256 colours: no truecolor
!! reply"), never silently assumed.
use iso_c_binding, only: c_int, c_int8_t, c_int16_t, c_int32_t, c_long, c_char
use iso_fortran_env, only: int32, int64
use fortui_frame, only: ui_frame_t, ui_node_t, UI_TEXT, UI_BUTTON, UI_LINK, UI_SLIDER, &
    UI_CHECKBOX, UI_TAB, UI_CANVAS, UI_SCROLL_TEXT, UI_TEXT_INPUT, UI_CAPTION, &
    UI_HEADING, UI_TITLE, SCROLL_PADDING
use fortui_input, only: input_state_t, input_update_pointer, input_scroll, &
    input_set_key, input_type_text, KEY_NONE, KEY_ENTER, KEY_ESCAPE, KEY_TAB, &
    KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, &
    KEY_ARROW_UP, KEY_ARROW_DOWN, KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_INSERT, KEY_SPACE
use fortui_text, only: utf8_decode, utf8_encode, utf8_length, text_use_cell_metrics
use fortui_error, only: report_error
use fortui_backend, only: ui_backend_t, ui_backend_caps_t
use fortui_canvas, only: canvas_store_t
use fortui_raster, only: raster_t, raster_map_t, raster_resize, raster_canvas, &
    raster_braille, rgb_of_rgba, rgb_to_xterm256
use fortui_kitty, only: kitty_encoder_t, kitty_encode_image, kitty_delete, &
    KITTY_QUERY
implicit none
private

real, parameter, public :: CELL_W_DP = 8.0
real, parameter, public :: CELL_H_DP = 16.0

integer, parameter, public :: TUI_COLOR_256 = 1, TUI_COLOR_TRUE = 2
integer, parameter, public :: TUI_GRAPHICS_BRAILLE = 1, TUI_GRAPHICS_KITTY = 2

! Braille: a dot is set when its pixel differs from the canvas background by
! at least this much in some channel (0..255).
integer, parameter :: DOT_THRESHOLD = 10
! Kitty images larger than this (pixels per side) are not sent.
integer, parameter :: MAX_IMAGE_SIDE = 8192
integer, parameter :: QUERY_TIMEOUT_MS = 1500

! termbox2.h constants (termbox2 v2, TB_OPT_ATTR_W 32 as compiled in src/c).
integer, parameter :: TB_OK = 0
integer, parameter :: TB_KEY_CTRL_C = 3
integer, parameter :: TB_KEY_BACKSPACE = 8, TB_KEY_TAB = 9, TB_KEY_ENTER = 13
integer, parameter :: TB_KEY_ESC = 27, TB_KEY_BACKSPACE2 = 127
integer, parameter :: TB_KEY_INSERT = 65535 - 12, TB_KEY_DELETE = 65535 - 13
integer, parameter :: TB_KEY_HOME = 65535 - 14, TB_KEY_END = 65535 - 15
integer, parameter :: TB_KEY_PGUP = 65535 - 16, TB_KEY_PGDN = 65535 - 17
integer, parameter :: TB_KEY_ARROW_UP = 65535 - 18, TB_KEY_ARROW_DOWN = 65535 - 19
integer, parameter :: TB_KEY_ARROW_LEFT = 65535 - 20, TB_KEY_ARROW_RIGHT = 65535 - 21
integer, parameter :: TB_KEY_MOUSE_LEFT = 65535 - 23, TB_KEY_MOUSE_RIGHT = 65535 - 24
integer, parameter :: TB_KEY_MOUSE_MIDDLE = 65535 - 25
integer, parameter :: TB_KEY_MOUSE_RELEASE = 65535 - 26
integer, parameter :: TB_KEY_MOUSE_WHEEL_UP = 65535 - 27
integer, parameter :: TB_KEY_MOUSE_WHEEL_DOWN = 65535 - 28
integer, parameter :: TB_MOD_MOTION = 8
integer, parameter :: TB_EVENT_KEY = 1, TB_EVENT_RESIZE = 2, TB_EVENT_MOUSE = 3
integer(c_int), parameter :: TB_INPUT_ESC = 1, TB_INPUT_MOUSE = 4
integer(c_int), parameter :: TB_OUTPUT_256 = 2, TB_OUTPUT_TRUECOLOR = 5
integer, parameter :: ATTR_BITS = 32
integer, parameter :: TB_BOLD = 16777216, TB_REVERSE = 67108864
integer, parameter :: TB_HI_BLACK = 536870912

! Presentation colours (0x00RRGGBB); the 256-colour mode uses the nearest
! palette entries.
integer, parameter :: RGB_TEXT = 14212326, RGB_DISABLED = 7368816
integer, parameter :: RGB_HOVER = 8378088, RGB_FOCUS = 15782000
integer, parameter :: RGB_ACTIVE_BG = 14212326, RGB_ACTIVE_FG = 1052688
integer, parameter :: RGB_CHECK = 8446080, RGB_CAPTION = 9414848
integer, parameter :: RGB_TRACK = 8378088
! Screen background: every cell gets an explicit colour, so the theme does not
! depend on the terminal's default colours (light or dark).
integer, parameter :: RGB_BACKGROUND = 1580063

character(len=*), parameter :: ESC = achar(27)

type, bind(C) :: tb_event
    integer(c_int8_t) :: type
    integer(c_int8_t) :: mod
    integer(c_int16_t) :: key
    integer(c_int32_t) :: ch
    integer(c_int32_t) :: w, h, x, y
end type tb_event

interface
    integer(c_int) function tb_init() bind(C, name="tb_init")
        import :: c_int
    end function tb_init
    integer(c_int) function tb_shutdown() bind(C, name="tb_shutdown")
        import :: c_int
    end function tb_shutdown
    integer(c_int) function tb_width() bind(C, name="tb_width")
        import :: c_int
    end function tb_width
    integer(c_int) function tb_height() bind(C, name="tb_height")
        import :: c_int
    end function tb_height
    integer(c_int) function tb_clear() bind(C, name="tb_clear")
        import :: c_int
    end function tb_clear
    integer(c_int) function tb_present() bind(C, name="tb_present")
        import :: c_int
    end function tb_present
    integer(c_int) function tb_hide_cursor() bind(C, name="tb_hide_cursor")
        import :: c_int
    end function tb_hide_cursor
    integer(c_int) function tb_attr_width() bind(C, name="tb_attr_width")
        import :: c_int
    end function tb_attr_width
    integer(c_int) function tb_set_cell(x, y, ch, fg, bg) bind(C, name="tb_set_cell")
        !! uintattr_t is uint32_t for TB_OPT_ATTR_W 32 (checked at init).
        import :: c_int, c_int32_t
        integer(c_int), value :: x, y
        integer(c_int32_t), value :: ch
        integer(c_int32_t), value :: fg, bg
    end function tb_set_cell
    integer(c_int) function tb_peek_event(event, timeout) bind(C, name="tb_peek_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
        integer(c_int), value :: timeout
    end function tb_peek_event
    integer(c_int) function tb_poll_event(event) bind(C, name="tb_poll_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
    end function tb_poll_event
    integer(c_int) function tb_set_clear_attrs(fg, bg) &
        bind(C, name="tb_set_clear_attrs")
        import :: c_int, c_int32_t
        integer(c_int32_t), value :: fg, bg
    end function tb_set_clear_attrs
    integer(c_int) function tb_set_input_mode(mode) bind(C, name="tb_set_input_mode")
        import :: c_int
        integer(c_int), value :: mode
    end function tb_set_input_mode
    integer(c_int) function tb_set_output_mode(mode) bind(C, name="tb_set_output_mode")
        import :: c_int
        integer(c_int), value :: mode
    end function tb_set_output_mode
    integer(c_int) function fortui_tty_write(buf, n) bind(C, name="fortui_tty_write")
        import :: c_int, c_long, c_char
        character(kind=c_char), intent(in) :: buf(*)
        integer(c_long), value :: n
    end function fortui_tty_write
    integer(c_long) function fortui_tty_query(query, nquery, reply, cap, timeout_ms) &
        bind(C, name="fortui_tty_query")
        import :: c_int, c_long, c_char
        character(kind=c_char), intent(in) :: query(*)
        integer(c_long), value :: nquery
        character(kind=c_char), intent(inout) :: reply(*)
        integer(c_long), value :: cap
        integer(c_int), value :: timeout_ms
    end function fortui_tty_query
    integer(c_int) function fortui_tty_size(cols, rows, xpixel, ypixel) &
        bind(C, name="fortui_tty_size")
        import :: c_int
        integer(c_int), intent(out) :: cols, rows, xpixel, ypixel
    end function fortui_tty_size
end interface

type, public :: tui_replies_t
    !! Capabilities a terminal reported in reply to the init queries.
    logical :: kitty_graphics = .false.
    logical :: truecolor = .false.
    logical :: pixel_mouse = .false.
    logical :: device_attributes = .false.
    integer :: cell_px_w = 0
    integer :: cell_px_h = 0
end type tui_replies_t

type :: tui_canvas_t
    !! Realization of one canvas node (keyed by node id).
    character(len=96) :: id = ""
    logical :: seen = .false.
    logical :: pending = .false.
    integer :: image_id = 0
    logical :: placed = .false.
    integer :: cx = 0, cy = 0, cols = 0, rows = 0
    integer(int32) :: background = 0
    integer, allocatable :: signature(:)
    type(raster_t) :: raster = raster_t()
    integer, allocatable :: glyph(:)
    integer(int32), allocatable :: fg(:)
end type tui_canvas_t

type, extends(ui_backend_t), public :: tui_backend_t
    !! termbox2 terminal backend: widgets as cells, canvases as braille or pixels.
    logical :: active = .false.
    logical :: quit_requested = .false.
    logical :: draw_failed = .false.
    integer :: cols = 0
    integer :: rows = 0
    integer :: color_mode = TUI_COLOR_256
    integer :: graphics = TUI_GRAPHICS_BRAILLE
    logical :: pixel_mouse = .false.
    integer :: cell_px_w = 0
    integer :: cell_px_h = 0
    character(len=96) :: color_note = ""
    character(len=96) :: graphics_note = ""
    type(tui_canvas_t), allocatable :: canvases(:)
    integer :: next_image = 0
    type(kitty_encoder_t) :: kitty = kitty_encoder_t()
    !! Measurements of the last canvas realization (milliseconds, bytes).
    real :: raster_ms = 0.0
    real :: encode_ms = 0.0
    real :: raster_ms_total = 0.0
    real :: encode_ms_total = 0.0
    real :: raster_ms_max = 0.0
    real :: encode_ms_max = 0.0
    integer :: rasters = 0
    integer :: images_sent = 0
    integer(int64) :: image_bytes = 0
contains
    procedure :: name => tui_name
    procedure :: describe => tui_describe
    procedure :: init => tui_init
    procedure :: shutdown => tui_shutdown
    procedure :: poll => tui_poll
    procedure :: present => tui_present
    procedure :: should_close => tui_should_close
    procedure :: install_text_metrics => tui_metrics
    procedure :: capabilities => tui_caps
end type tui_backend_t

public :: tui_is_available, tui_map_key, tui_parse_replies, tui_cell_to_logical
public :: tui_pixel_to_logical, tui_canvas_map

contains

function tui_name(self) result(name)
    class(tui_backend_t), intent(in) :: self
    character(len=:), allocatable :: name
    name = "tui"
end function tui_name

function tui_describe(self) result(text)
    !! Realization choices, e.g. "tui: kitty pixels, truecolor, pixel mouse".
    class(tui_backend_t), intent(in) :: self
    character(len=:), allocatable :: text

    text = "tui: " // trim(self%graphics_note) // ", " // trim(self%color_note)
    if (self%pixel_mouse) then
        text = text // ", pixel mouse"
    else
        text = text // ", cell mouse"
    end if
end function tui_describe

pure subroutine tui_cell_to_logical(col, row, x, y)
    !! Logical position of a pointer reported as a terminal cell: its centre.
    integer, intent(in) :: col, row
    real, intent(out) :: x, y
    x = (real(col) + 0.5) * CELL_W_DP
    y = (real(row) + 0.5) * CELL_H_DP
end subroutine tui_cell_to_logical

pure subroutine tui_pixel_to_logical(px, py, cell_px_w, cell_px_h, x, y)
    !! Logical position of a pointer reported in pixels (SGR-pixel mode 1016).
    integer, intent(in) :: px, py, cell_px_w, cell_px_h
    real, intent(out) :: x, y
    x = (real(px) + 0.5) * CELL_W_DP / real(max(1, cell_px_w))
    y = (real(py) + 0.5) * CELL_H_DP / real(max(1, cell_px_h))
end subroutine tui_pixel_to_logical

pure function tui_canvas_map(col, row, dots_x, dots_y) result(map)
    !! Raster mapping for a canvas whose top-left cell is (col, row) with
    !! dots_x x dots_y raster pixels per cell (2x4 braille, cell pixels kitty).
    integer, intent(in) :: col, row, dots_x, dots_y
    type(raster_map_t) :: map
    map%origin_x = real(col) * CELL_W_DP
    map%origin_y = real(row) * CELL_H_DP
    map%scale_x = real(dots_x) / CELL_W_DP
    map%scale_y = real(dots_y) / CELL_H_DP
end function tui_canvas_map

pure function tui_parse_replies(reply) result(r)
    !! Capabilities in the terminal's replies to the init queries: kitty graphics
    !! (`ESC _G i=31;OK`), cell size (`CSI 6;h;w t`), SGR-pixel mouse
    !! (DECRPM `CSI ? 1016;1|2 $ y`), truecolor (DECRQSS reply echoing
    !! 38;2;1;2;3 or 38:2::1:2:3, or XTGETTCAP knowing `RGB`) and device
    !! attributes (`CSI ? ... c`).
    character(*), intent(in) :: reply
    type(tui_replies_t) :: r
    integer :: p, q, v(3), nv

    r%kitty_graphics = index(reply, ESC // "_Gi=31;OK") > 0
    p = index(reply, ESC // "[6;")
    if (p > 0) then
        call read_numbers(reply, p + 2, "t", v, nv)
        if (nv == 3) then
            r%cell_px_h = v(2)
            r%cell_px_w = v(3)
        end if
    end if
    r%pixel_mouse = index(reply, ESC // "[?1016;1$y") > 0 .or. &
        index(reply, ESC // "[?1016;2$y") > 0
    p = index(reply, ESC // "P1$r")
    if (p > 0) then
        q = index(reply(p:), ESC // "\")
        if (q > 0) r%truecolor = index(reply(p:p + q), "2;1;2;3") > 0 .or. &
            index(reply(p:p + q), ":1:2:3") > 0
    end if
    ! XTGETTCAP: the terminfo capability RGB is known.
    if (index(reply, ESC // "P1+r524742") > 0) r%truecolor = .true.
    p = index(reply, ESC // "[?")
    do while (p > 0)
        q = p + 3
        do while (q <= len(reply))
            if (verify(reply(q:q), "0123456789;") /= 0) exit
            q = q + 1
        end do
        if (q <= len(reply)) then
            if (reply(q:q) == "c") r%device_attributes = .true.
        end if
        if (q > len(reply)) exit
        p = index(reply(q:), ESC // "[?")
        if (p > 0) p = p + q - 1
    end do
end function tui_parse_replies

pure subroutine read_numbers(s, start, final, v, nv)
    !! Up to three ';'-separated integers from s(start:) ending at `final`.
    character(*), intent(in) :: s
    integer, intent(in) :: start
    character, intent(in) :: final
    integer, intent(out) :: v(3), nv
    integer :: i, d

    v = 0
    nv = 0
    i = start
    do while (i <= len(s))
        d = index("0123456789", s(i:i)) - 1
        if (d >= 0) then
            if (nv == 0) nv = 1
            v(nv) = 10 * v(nv) + d
        else if (s(i:i) == ";") then
            if (nv >= 3) then
                nv = 0
                return
            end if
            nv = nv + 1
        else if (s(i:i) == final) then
            return
        else
            nv = 0
            return
        end if
        i = i + 1
    end do
    nv = 0
end subroutine read_numbers

logical function tui_init(self)
    !! The terminal decides the window size; the requested size is ignored.
    class(tui_backend_t), intent(inout) :: self
    character(len=32) :: want_graphics, want_color
    character(len=:), allocatable :: query
    type(tui_replies_t) :: replies
    logical :: in_tmux, colorterm
    integer :: status
    integer(c_int) :: mode

    tui_init = .false.
    if (.not. tui_is_available()) then
        call report_error("fortui_tui", "init", "no terminal (TERM unset or headless)")
        return
    end if
    want_graphics = env_lower("FORTUI_TUI_GRAPHICS", "auto")
    want_color = env_lower("FORTUI_TUI_COLOR", "auto")
    select case (trim(want_graphics))
    case ("auto", "braille", "kitty")
    case ("sixel")
        call report_error("fortui_tui", "init", "FORTUI_TUI_GRAPHICS=sixel is not " // &
            "implemented; use braille, kitty or auto")
        return
    case default
        call report_error("fortui_tui", "init", "FORTUI_TUI_GRAPHICS='" // &
            trim(want_graphics) // "' is not one of auto, braille, kitty, sixel")
        return
    end select
    select case (trim(want_color))
    case ("auto", "truecolor", "24bit", "256")
    case default
        call report_error("fortui_tui", "init", "FORTUI_TUI_COLOR='" // &
            trim(want_color) // "' is not one of auto, truecolor, 256")
        return
    end select
    in_tmux = len_trim(env_lower("TMUX", "")) > 0
    if (trim(want_graphics) == "kitty" .and. in_tmux) then
        call report_error("fortui_tui", "init", "kitty graphics are not supported " // &
            "inside tmux (no image placement passthrough); use braille")
        return
    end if

    status = tb_init()
    if (status /= TB_OK) then
        call report_error("fortui_tui", "init", &
            "termbox2 could not initialize a terminal")
        return
    end if
    self%active = .true.
    if (tb_attr_width() /= ATTR_BITS) then
        call report_error("fortui_tui", "init", "termbox2 attribute width differs " // &
            "from the 32-bit binding")
        call tui_shutdown(self)
        return
    end if

    ! In-band queries, terminated by a device-attributes request that every
    ! terminal answers.
    query = ESC // "[16t" // ESC // "[?1016$p"
    if (trim(want_graphics) == "auto" .and. .not. in_tmux) query = KITTY_QUERY // query
    colorterm = env_lower("COLORTERM", "") == "truecolor" .or. &
        env_lower("COLORTERM", "") == "24bit"
    if (trim(want_color) == "auto" .and. .not. colorterm) query = query // ESC // &
        "[38;2;1;2;3m" // ESC // "P$qm" // ESC // "\" // ESC // "[0m" // ESC // &
        "P+q524742" // ESC // "\"
    replies = query_terminal(query // ESC // "[c")

    select case (trim(want_color))
    case ("truecolor", "24bit")
        self%color_mode = TUI_COLOR_TRUE
        self%color_note = "truecolor (FORTUI_TUI_COLOR)"
    case ("256")
        self%color_mode = TUI_COLOR_256
        self%color_note = "256 colours (FORTUI_TUI_COLOR)"
    case default
        if (colorterm) then
            self%color_mode = TUI_COLOR_TRUE
            self%color_note = "truecolor (COLORTERM)"
        else if (replies%truecolor) then
            self%color_mode = TUI_COLOR_TRUE
            self%color_note = "truecolor (terminal reply)"
        else
            self%color_mode = TUI_COLOR_256
            self%color_note = "256 colours: no truecolor reply " // &
                "(set FORTUI_TUI_COLOR=truecolor to force)"
        end if
    end select
    call update_cell_pixels(self, replies)
    select case (trim(want_graphics))
    case ("braille")
        self%graphics = TUI_GRAPHICS_BRAILLE
        self%graphics_note = "braille (FORTUI_TUI_GRAPHICS)"
    case ("kitty")
        self%graphics = TUI_GRAPHICS_KITTY
        self%graphics_note = "kitty pixels (FORTUI_TUI_GRAPHICS)"
    case default
        if (replies%kitty_graphics .and. self%cell_px_w > 0 .and. &
            self%cell_px_h > 0) then
            self%graphics = TUI_GRAPHICS_KITTY
            self%graphics_note = "kitty pixels (terminal reply)"
        else
            self%graphics = TUI_GRAPHICS_BRAILLE
            if (in_tmux) then
                self%graphics_note = "braille (inside tmux)"
            else if (.not. replies%device_attributes) then
                self%graphics_note = "braille (terminal did not answer queries)"
            else
                self%graphics_note = "braille (no kitty graphics reply)"
            end if
        end if
    end select
    if (self%graphics == TUI_GRAPHICS_KITTY .and. &
        (self%cell_px_w <= 0 .or. self%cell_px_h <= 0)) then
        call report_error("fortui_tui", "init", "kitty graphics need the cell " // &
            "size in pixels, which the terminal did not report")
        call tui_shutdown(self)
        return
    end if
    self%pixel_mouse = replies%pixel_mouse .and. self%cell_px_w > 0 .and. &
        self%cell_px_h > 0

    mode = TB_OUTPUT_256
    if (self%color_mode == TUI_COLOR_TRUE) mode = TB_OUTPUT_TRUECOLOR
    if (tb_set_output_mode(mode) < 0 .or. &
        tb_set_input_mode(TB_INPUT_ESC + TB_INPUT_MOUSE) < 0 .or. &
        tb_hide_cursor() /= TB_OK .or. &
        tb_set_clear_attrs(int(colour(self, RGB_TEXT), c_int32_t), &
        int(colour(self, RGB_BACKGROUND), c_int32_t)) /= TB_OK) then
        call report_error("fortui_tui", "init", "termbox2 terminal setup failed")
        call tui_shutdown(self)
        return
    end if
    ! Hover (any-motion tracking) and, when supported, pixel mouse positions.
    call tty_send(ESC // "[?1003h")
    if (self%pixel_mouse) call tty_send(ESC // "[?1016h")
    self%quit_requested = .false.
    tui_init = .true.
end function tui_init

function query_terminal(query) result(replies)
    character(*), intent(in) :: query
    type(tui_replies_t) :: replies
    character(kind=c_char, len=4096) :: buf
    integer(c_long) :: n

    n = fortui_tty_query(query, int(len(query), c_long), buf, &
        int(len(buf), c_long), int(QUERY_TIMEOUT_MS, c_int))
    if (n <= 0) return
    replies = tui_parse_replies(buf(1:int(n)))
end function query_terminal

subroutine update_cell_pixels(self, replies)
    !! Cell size in pixels: TIOCGWINSZ when it reports pixels, else the CSI 16t
    !! reply, else the previous value (resize without pixel information).
    type(tui_backend_t), intent(inout) :: self
    type(tui_replies_t), intent(in) :: replies
    integer(c_int) :: c, r, xp, yp

    if (replies%cell_px_w > 0 .and. replies%cell_px_h > 0) then
        self%cell_px_w = replies%cell_px_w
        self%cell_px_h = replies%cell_px_h
    end if
    if (fortui_tty_size(c, r, xp, yp) /= 0) return
    if (c > 0 .and. r > 0 .and. xp >= c .and. yp >= r) then
        self%cell_px_w = int(xp) / int(c)
        self%cell_px_h = int(yp) / int(r)
    end if
end subroutine update_cell_pixels

subroutine tty_send(s)
    character(*), intent(in) :: s
    if (fortui_tty_write(s, int(len(s), c_long)) /= 0) &
        call report_error("fortui_tui", "tty", "writing to the terminal failed")
end subroutine tty_send

function env_lower(name, default) result(value)
    character(*), intent(in) :: name, default
    character(len=:), allocatable :: value
    character(len=256) :: buf
    integer :: status, i, code

    call get_environment_variable(name, buf, status=status)
    if (status /= 0 .or. len_trim(buf) == 0) then
        value = default
        return
    end if
    do i = 1, len_trim(buf)
        code = iachar(buf(i:i))
        if (code >= iachar('A') .and. code <= iachar('Z')) buf(i:i) = achar(code + 32)
    end do
    value = trim(buf)
end function env_lower

subroutine tui_shutdown(self)
    class(tui_backend_t), intent(inout) :: self
    integer :: i

    if (.not. self%active) return
    if (allocated(self%canvases)) then
        do i = 1, size(self%canvases)
            if (self%canvases(i)%placed) &
                call tty_send(kitty_delete(self%canvases(i)%image_id))
        end do
        deallocate(self%canvases)
    end if
    if (self%pixel_mouse) call tty_send(ESC // "[?1016l")
    call tty_send(ESC // "[?1003l")
    if (tb_shutdown() /= TB_OK) &
        call report_error("fortui_tui", "shutdown", "termbox2 shutdown failed")
    self%active = .false.
    call write_stats(self)
end subroutine tui_shutdown

subroutine write_stats(self)
    !! With FORTUI_TUI_STATS=file, append the canvas realization measurements.
    type(tui_backend_t), intent(in) :: self
    character(len=512) :: path
    integer :: status, u

    call get_environment_variable("FORTUI_TUI_STATS", path, status=status)
    if (status /= 0 .or. len_trim(path) == 0) return
    open(newunit=u, file=trim(path), position="append", action="write", &
        iostat=status)
    if (status /= 0) return
    write(u, '(a,a,a,i0,a,i0,a,f0.3,a,f0.3,a,i0,a,f0.3,a,f0.3,a,f0.1,a,i0,a,i0)') &
        "describe='", trim(tui_describe(self)), "' presents=", self%presents, &
        " rasters=", self%rasters, " raster_ms_mean=", &
        self%raster_ms_total / real(max(1, self%rasters)), " raster_ms_max=", &
        self%raster_ms_max, " images=", self%images_sent, " encode_ms_mean=", &
        self%encode_ms_total / real(max(1, self%images_sent)), " encode_ms_max=", &
        self%encode_ms_max, " image_kib_mean=", &
        real(self%image_bytes) / 1024.0 / real(max(1, self%images_sent)), &
        " cell_px=", self%cell_px_w, "x", self%cell_px_h
    close(u)
end subroutine write_stats

subroutine tui_poll(self, input, wait)
    !! Terminal events; with `wait`, block until one arrives (keys, mouse, resize).
    !! A mouse release ends the batch so that each click gets its own frame.
    class(tui_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    logical, intent(in) :: wait
    type(tb_event) :: event
    integer :: status
    logical :: stop

    if (.not. self%active) return
    call report_size(self, input)
    stop = .false.
    if (wait) then
        self%waits = self%waits + 1
        if (self%wake_in >= 0.0) then
            ! A timer is due: wait for input at most until then.
            status = tb_peek_event(event, int(ceiling(1000.0 * self%wake_in), c_int))
        else
            status = tb_poll_event(event)
        end if
        if (status == TB_OK) call process_event(self, input, event, stop)
    end if
    do while (.not. stop)
        status = tb_peek_event(event, 0_c_int)
        if (status /= TB_OK) exit
        call process_event(self, input, event, stop)
    end do
end subroutine tui_poll

subroutine report_size(self, input)
    type(tui_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    integer :: w, h

    w = max(1, nint(real(tb_width()) * CELL_W_DP))
    h = max(1, nint(real(tb_height()) * CELL_H_DP))
    if (w /= input%width .or. h /= input%height) input%resized = .true.
    input%width = w
    input%height = h
    input%scale = 1.0
    if (self%pixel_mouse) then
        input%pointer_slop = 0.5 * CELL_H_DP / real(max(1, self%cell_px_h))
    else
        input%pointer_slop = 0.5 * CELL_H_DP
    end if
end subroutine report_size

subroutine process_event(self, input, event, stop)
    type(tui_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    type(tb_event), intent(in) :: event
    logical, intent(inout) :: stop
    integer :: key
    logical :: motion
    real :: px, py
    type(tui_replies_t) :: none

    key = iand(int(event%key), 65535)
    select case (int(event%type))
    case (TB_EVENT_KEY)
        if (key == TB_KEY_CTRL_C) self%quit_requested = .true.
        if (event%ch > 0) then
            ! Space is typed text and also the activation key.
            if (event%ch == 32) call input_set_key(input, KEY_SPACE)
            call input_type_text(input, utf8_encode(int(event%ch)))
        else
            call input_set_key(input, tui_map_key(key))
        end if
    case (TB_EVENT_RESIZE)
        if (self%graphics == TUI_GRAPHICS_KITTY .or. self%pixel_mouse) &
            call update_cell_pixels(self, none)
        call report_size(self, input)
        input%resized = .true.
    case (TB_EVENT_MOUSE)
        if (self%pixel_mouse) then
            call tui_pixel_to_logical(int(event%x), int(event%y), self%cell_px_w, &
                self%cell_px_h, px, py)
        else
            call tui_cell_to_logical(int(event%x), int(event%y), px, py)
        end if
        motion = iand(int(event%mod), TB_MOD_MOTION) /= 0
        select case (key)
        case (TB_KEY_MOUSE_LEFT)
            if (motion .and. input%pointer_down) then
                call input_update_pointer(input, px, py, .true.)
            else
                call input_update_pointer(input, px, py, .true., .true.)
            end if
        case (TB_KEY_MOUSE_RELEASE)
            ! Without a button, motion reports arrive as releases (hover).
            if (motion) then
                call input_update_pointer(input, px, py, .false.)
            else
                call input_update_pointer(input, px, py, .false.)
                stop = .true.
            end if
        case (TB_KEY_MOUSE_WHEEL_UP)
            call input_update_pointer(input, px, py, input%pointer_down)
            call input_scroll(input, 1)
        case (TB_KEY_MOUSE_WHEEL_DOWN)
            call input_update_pointer(input, px, py, input%pointer_down)
            call input_scroll(input, -1)
        case (TB_KEY_MOUSE_RIGHT, TB_KEY_MOUSE_MIDDLE)
            call input_update_pointer(input, px, py, input%pointer_down)
        end select
    end select
end subroutine process_event

pure integer function tui_map_key(tb_key) result(key)
    !! Backend-neutral KEY_* for a termbox2 key code (KEY_NONE if unnamed).
    integer, intent(in) :: tb_key
    select case (tb_key)
    case (TB_KEY_ENTER); key = KEY_ENTER
    case (TB_KEY_ESC); key = KEY_ESCAPE
    case (TB_KEY_TAB); key = KEY_TAB
    case (TB_KEY_BACKSPACE, TB_KEY_BACKSPACE2); key = KEY_BACKSPACE
    case (TB_KEY_DELETE); key = KEY_DELETE
    case (TB_KEY_INSERT); key = KEY_INSERT
    case (TB_KEY_HOME); key = KEY_HOME
    case (TB_KEY_END); key = KEY_END
    case (TB_KEY_PGUP); key = KEY_PAGE_UP
    case (TB_KEY_PGDN); key = KEY_PAGE_DOWN
    case (TB_KEY_ARROW_UP); key = KEY_ARROW_UP
    case (TB_KEY_ARROW_DOWN); key = KEY_ARROW_DOWN
    case (TB_KEY_ARROW_LEFT); key = KEY_ARROW_LEFT
    case (TB_KEY_ARROW_RIGHT); key = KEY_ARROW_RIGHT
    case default; key = KEY_NONE
    end select
end function tui_map_key

subroutine tui_present(self, frame, store)
    class(tui_backend_t), intent(inout) :: self
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(in), target :: store
    integer :: i

    call self%canvas%realize_frame(store, frame)
    self%presents = self%presents + 1
    if (.not. self%active) return
    self%cols = int(tb_width())
    self%rows = int(tb_height())
    if (allocated(self%canvases)) self%canvases(:)%seen = .false.
    if (tb_clear() /= TB_OK) call draw_failure(self)
    do i = 1, frame%count
        if (frame%nodes(i)%kind == UI_CANVAS) then
            call draw_canvas(self, frame, store, frame%nodes(i))
        else
            call draw_node(self, frame%nodes(i))
        end if
    end do
    if (tb_present() /= TB_OK) call draw_failure(self)
    if (self%graphics == TUI_GRAPHICS_KITTY) call send_images(self)
end subroutine tui_present

subroutine send_images(self)
    !! Transmit changed canvas images after the cells (cursor saved/restored, so
    !! termbox2's cursor tracking stays valid) and delete images of removed
    !! canvases.
    type(tui_backend_t), intent(inout) :: self
    integer :: i
    integer(int64) :: t0, t1, rate
    character(len=32) :: move

    if (.not. allocated(self%canvases)) return
    do i = 1, size(self%canvases)
        associate(c => self%canvases(i))
            if (len_trim(c%id) == 0) cycle
            if (.not. c%seen) then
                if (c%placed) call tty_send(kitty_delete(c%image_id))
                c = tui_canvas_t()
                cycle
            end if
            if (.not. c%pending) cycle
            c%pending = .false.
            if (c%raster%width <= 0 .or. c%raster%height <= 0) cycle
            call system_clock(t0, rate)
            call kitty_encode_image(self%kitty, c%raster%rgb, c%raster%width, &
                c%raster%height, c%image_id, c%cols, c%rows)
            call system_clock(t1)
            self%encode_ms = real(t1 - t0) * 1000.0 / real(rate)
            self%encode_ms_total = self%encode_ms_total + self%encode_ms
            self%encode_ms_max = max(self%encode_ms_max, self%encode_ms)
            write(move, '(a,i0,a,i0,a)') ESC // "7" // ESC // "[", c%cy + 1, ";", &
                c%cx + 1, "H"
            call tty_send(trim(move) // self%kitty%out(1:self%kitty%out_len) // &
                ESC // "8")
            c%placed = .true.
            self%images_sent = self%images_sent + 1
            self%image_bytes = self%image_bytes + self%kitty%out_len
        end associate
    end do
end subroutine send_images

integer function canvas_index(self, id) result(k)
    !! State of canvas `id`, created on first use.
    type(tui_backend_t), intent(inout) :: self
    character(*), intent(in) :: id
    type(tui_canvas_t), allocatable :: grown(:)
    integer :: i, free

    if (.not. allocated(self%canvases)) allocate(self%canvases(2))
    free = 0
    do i = 1, size(self%canvases)
        if (len_trim(self%canvases(i)%id) == 0) then
            if (free == 0) free = i
        else if (self%canvases(i)%id == id) then
            k = i
            return
        end if
    end do
    if (free == 0) then
        allocate(grown(2 * size(self%canvases)))
        grown(1:size(self%canvases)) = self%canvases
        free = size(self%canvases) + 1
        call move_alloc(grown, self%canvases)
    end if
    k = free
    self%next_image = self%next_image + 1
    self%canvases(k)%id = id
    self%canvases(k)%image_id = 7000 + self%next_image
end function canvas_index

subroutine canvas_signature(frame, node, cx, cy, cols, rows, dx, dy, sig, n)
    !! Everything the raster depends on: geometry, resolution, fill, view and the
    !! data versions of every layer.
    type(ui_frame_t), intent(in) :: frame
    type(ui_node_t), intent(in) :: node
    integer, intent(in) :: cx, cy, cols, rows, dx, dy
    integer, allocatable, intent(inout) :: sig(:)
    integer, intent(out) :: n
    integer :: j

    n = 10 + 6 * node%layer_count
    if (allocated(sig)) then
        if (size(sig) < n) deallocate(sig)
    end if
    if (.not. allocated(sig)) allocate(sig(n))
    sig(1:10) = [cx, cy, cols, rows, dx, dy, int(node%fill), &
        transfer(node%canvas_view%zoom, 0), transfer(node%canvas_view%pan_x, 0), &
        transfer(node%canvas_view%pan_y, 0)]
    do j = 1, node%layer_count
        associate(ref => frame%layers(node%layer_first + j - 1))
            sig(5 + 6 * j:10 + 6 * j) = [ref%slot, ref%serial, ref%version, &
                ref%index_version, ref%vertex_version, ref%vertex_serial]
        end associate
    end do
end subroutine canvas_signature

subroutine draw_canvas(self, frame, store, node)
    !! Realize a canvas node: raster when anything it depends on changed, then
    !! braille cells (or background cells under a kitty image) and text labels.
    type(tui_backend_t), intent(inout) :: self
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(in) :: store
    type(ui_node_t), intent(in) :: node
    integer, allocatable :: sig(:)
    type(raster_map_t) :: map
    integer :: k, cx, cy, cols, rows, dx, dy, n, nsig, i, j, bg
    logical :: changed
    integer(int64) :: t0, t1, rate

    cx = max(0, nint(node%x / CELL_W_DP))
    cy = max(0, nint(node%y / CELL_H_DP))
    cols = min(max(1, nint(node%width / CELL_W_DP)), self%cols - cx)
    rows = min(max(1, nint(node%height / CELL_H_DP)), self%rows - cy)
    if (cols <= 0 .or. rows <= 0) return
    if (self%graphics == TUI_GRAPHICS_KITTY) then
        dx = self%cell_px_w
        dy = self%cell_px_h
        if (cols * dx > MAX_IMAGE_SIDE .or. rows * dy > MAX_IMAGE_SIDE) return
    else
        dx = 2
        dy = 4
    end if
    k = canvas_index(self, trim(node%id))
    associate(c => self%canvases(k))
        c%seen = .true.
        call canvas_signature(frame, node, cx, cy, cols, rows, dx, dy, sig, nsig)
        changed = .not. allocated(c%signature)
        if (.not. changed) changed = size(c%signature) /= nsig
        if (.not. changed) changed = any(c%signature /= sig(1:nsig))
        if (changed) then
            call system_clock(t0, rate)
            c%cx = cx
            c%cy = cy
            c%cols = cols
            c%rows = rows
            c%signature = sig(1:nsig)
            call raster_resize(c%raster, cols * dx, rows * dy)
            map = tui_canvas_map(cx, cy, dx, dy)
            ! Braille: large discs as one-dot rings, so overlaps stay readable.
            if (self%graphics == TUI_GRAPHICS_BRAILLE) map%outline = 1.0
            call raster_canvas(c%raster, store, frame, node, map)
            c%background = c%raster%background
            if (self%graphics == TUI_GRAPHICS_BRAILLE) then
                n = cols * rows
                if (allocated(c%glyph)) then
                    if (size(c%glyph) < n) deallocate(c%glyph, c%fg)
                end if
                if (.not. allocated(c%glyph)) allocate(c%glyph(n), c%fg(n))
                call raster_braille(c%raster, cols, rows, DOT_THRESHOLD, .true., &
                    c%glyph, c%fg)
            else
                c%pending = .true.
            end if
            call system_clock(t1)
            self%raster_ms = real(t1 - t0) * 1000.0 / real(rate)
            self%raster_ms_total = self%raster_ms_total + self%raster_ms
            self%raster_ms_max = max(self%raster_ms_max, self%raster_ms)
            self%rasters = self%rasters + 1
        end if
        bg = colour(self, c%background)
        do j = 0, rows - 1
            do i = 0, cols - 1
                if (self%graphics == TUI_GRAPHICS_BRAILLE) then
                    call put_cell(self, cx + i, cy + j, c%glyph(i + j * cols + 1), &
                        colour(self, c%fg(i + j * cols + 1)), bg)
                else
                    call put_cell(self, cx + i, cy + j, 32, bg, bg)
                end if
            end do
        end do
        call draw_labels(self, frame, node, cx, cy, cols, rows, bg)
    end associate
end subroutine draw_canvas

subroutine draw_labels(self, frame, node, cx, cy, cols, rows, bg)
    !! Canvas labels as text cells centred under their anchor, clipped to the
    !! canvas.
    type(tui_backend_t), intent(inout) :: self
    type(ui_frame_t), intent(in) :: frame
    type(ui_node_t), intent(in) :: node
    integer, intent(in) :: cx, cy, cols, rows, bg
    integer :: j, n, col, row, pos, cp, nb, fg
    real :: sx, sy

    do j = node%label_first, node%label_first + node%label_count - 1
        associate(lab => frame%labels(j))
            if (.not. allocated(lab%text)) cycle
            sx = node%x + lab%x * node%canvas_view%zoom + node%canvas_view%pan_x
            sy = node%y + lab%y * node%canvas_view%zoom + node%canvas_view%pan_y
            n = utf8_length(lab%text)
            col = nint(sx / CELL_W_DP - 0.5 * real(n))
            row = int(floor((sy + 2.0) / CELL_H_DP))
            if (row < cy .or. row >= cy + rows) cycle
            fg = colour(self, rgb_of_rgba(lab%rgba))
            pos = 1
            do while (pos <= len(lab%text))
                call utf8_decode(lab%text, pos, cp, nb)
                pos = pos + nb
                if (col >= cx .and. col < cx + cols) &
                    call put_cell(self, col, row, cp, fg, bg)
                col = col + 1
            end do
        end associate
    end do
end subroutine draw_labels

integer function colour(self, rgb) result(attr)
    !! termbox2 attribute of a 0x00RRGGBB colour in the active output mode.
    type(tui_backend_t), intent(in) :: self
    integer(int32), intent(in) :: rgb
    integer :: idx

    if (self%color_mode == TUI_COLOR_TRUE) then
        attr = int(iand(rgb, 16777215_int32))
        if (attr == 0) attr = TB_HI_BLACK
    else
        idx = rgb_to_xterm256(rgb)
        attr = idx
        if (idx == 0) attr = TB_HI_BLACK
    end if
end function colour

subroutine draw_failure(self)
    type(tui_backend_t), intent(inout) :: self
    if (self%draw_failed) return
    self%draw_failed = .true.
    call report_error("fortui_tui", "present", "termbox2 drawing failed")
end subroutine draw_failure

logical function tui_should_close(self)
    class(tui_backend_t), intent(in) :: self
    tui_should_close = self%quit_requested
end function tui_should_close

subroutine tui_metrics(self)
    !! Every code point and text line occupies one terminal cell, whatever the
    !! text size (sizes and styles adapt to bold/colour, not to pixels).
    class(tui_backend_t), intent(inout) :: self
    call text_use_cell_metrics(CELL_W_DP, CELL_H_DP)
end subroutine tui_metrics

function tui_caps(self) result(caps)
    class(tui_backend_t), intent(in) :: self
    type(ui_backend_caps_t) :: caps
    caps%pointer = .true.
    caps%text_entry = .true.
    caps%event_waiting = .true.
    caps%canvas_layers = .true.
end function tui_caps

subroutine draw_node(self, node)
    type(tui_backend_t), intent(inout) :: self
    type(ui_node_t), intent(in) :: node
    integer :: x, y, w, h, fg, bg, knob, track, i
    real :: fraction

    x = max(0, nint(node%x / CELL_W_DP))
    y = max(0, nint(node%y / CELL_H_DP))
    w = max(1, nint(node%width / CELL_W_DP))
    h = max(1, nint(node%height / CELL_H_DP))

    fg = colour(self, RGB_TEXT)
    bg = colour(self, RGB_BACKGROUND)
    if (node%disabled) fg = colour(self, RGB_DISABLED)
    if (node%hovered) fg = colour(self, RGB_HOVER) + TB_BOLD
    if (node%focused) fg = colour(self, RGB_FOCUS) + TB_BOLD
    if (node%active) then
        fg = colour(self, RGB_ACTIVE_FG) + TB_BOLD
        bg = colour(self, RGB_ACTIVE_BG)
    end if

    select case (node%kind)
    case (UI_TEXT, UI_LINK)
        if (node%style == UI_HEADING .or. node%style == UI_TITLE) fg = fg + TB_BOLD
        if (node%style == UI_CAPTION) fg = colour(self, RGB_CAPTION)
        call draw_string(self, x, y, trim(node%text), fg, bg, w, node%ellipsis)
    case (UI_BUTTON)
        call put_cell(self, x, y, iachar('['), fg, bg)
        call draw_string(self, x + 1, y, trim(node%text), fg, bg, max(0, w - 2), &
            node%ellipsis)
        call put_cell(self, x + w - 1, y, iachar(']'), fg, bg)
    case (UI_TAB)
        if (node%checked) fg = fg + TB_REVERSE
        call draw_string(self, x, y, " " // trim(node%text) // " ", fg, bg, w, .true.)
    case (UI_CHECKBOX)
        call put_cell(self, x, y, iachar('['), fg, bg)
        if (node%checked) then
            call put_cell(self, x + 1, y, iachar('x'), &
                colour(self, RGB_CHECK) + TB_BOLD, bg)
        else
            call put_cell(self, x + 1, y, iachar(' '), fg, bg)
        end if
        call put_cell(self, x + 2, y, iachar(']'), fg, bg)
        if (len_trim(node%text) > 0) call draw_string(self, x + 4, y, trim(node%text), &
            fg, bg, max(0, w - 4), .true.)
    case (UI_SLIDER)
        if (node%max_value > node%min_value) then
            fraction = (node%value - node%min_value) / (node%max_value - node%min_value)
        else
            fraction = 0.0
        end if
        fraction = max(0.0, min(1.0, fraction))
        track = max(1, w - 2)
        knob = nint(fraction * real(max(0, track - 1)))
        call put_cell(self, x, y, iachar('['), fg, bg)
        do i = 0, track - 1
            if (i < knob) then
                call put_cell(self, x + 1 + i, y, iachar('='), &
                    colour(self, RGB_TRACK), bg)
            else if (i == knob) then
                call put_cell(self, x + 1 + i, y, iachar('|'), &
                    colour(self, RGB_TEXT) + TB_BOLD, bg)
            else
                call put_cell(self, x + 1 + i, y, iachar('-'), fg, bg)
            end if
        end do
        call put_cell(self, x + w - 1, y, iachar(']'), fg, bg)
    case (UI_SCROLL_TEXT)
        call draw_scroll_text(self, node, x, y, w, h, fg, bg)
    case (UI_TEXT_INPUT)
        call put_cell(self, x, y, iachar('['), fg, bg)
        if (allocated(node%body)) then
            if (len(node%body) > 0) then
                call draw_string(self, x + 1, y, node%body, fg, bg, max(0, w - 2), &
                    .false.)
            else
                call draw_string(self, x + 1, y, trim(node%text), &
                    colour(self, RGB_DISABLED), bg, max(0, w - 2), .false.)
            end if
        end if
        call put_cell(self, x + w - 1, y, iachar(']'), fg, bg)
    end select
end subroutine draw_node

subroutine draw_scroll_text(self, node, x, y, w, h, fg, bg)
    type(tui_backend_t), intent(inout) :: self
    type(ui_node_t), intent(in) :: node
    integer, intent(in) :: x, y, w, h, fg, bg
    integer :: i, row

    if (.not. allocated(node%body) .or. .not. allocated(node%lines)) return
    do i = 1, node%line_count
        row = nint((SCROLL_PADDING + node%lines(i)%y - node%scroll) / CELL_H_DP)
        if (row < 0) cycle
        if (row >= h) exit
        if (node%lines(i)%last >= node%lines(i)%first) call draw_string(self, x, &
            y + row, node%body(node%lines(i)%first:node%lines(i)%last), fg, bg, w, .false.)
    end do
end subroutine draw_scroll_text

subroutine draw_string(self, x, y, value, fg, bg, limit, ellipsis)
    !! Draw UTF-8 text, one code point per cell (no wide-character evidence yet);
    !! with `ellipsis`, a clipped string ends in U+2026.
    type(tui_backend_t), intent(inout) :: self
    integer, intent(in) :: x, y, fg, bg, limit
    character(*), intent(in) :: value
    logical, intent(in) :: ellipsis
    integer :: pos, col, cp, nb

    pos = 1
    col = 0
    do while (pos <= len_trim(value) .and. col < limit)
        call utf8_decode(value, pos, cp, nb)
        pos = pos + nb
        if (ellipsis .and. col == limit - 1 .and. pos <= len_trim(value)) cp = 8230
        call put_cell(self, x + col, y, cp, fg, bg)
        col = col + 1
    end do
end subroutine draw_string

subroutine put_cell(self, x, y, ch, fg, bg)
    type(tui_backend_t), intent(inout) :: self
    integer, intent(in) :: x, y, ch, fg, bg
    if (x < 0 .or. y < 0 .or. x >= self%cols .or. y >= self%rows) return
    if (tb_set_cell(int(x, c_int), int(y, c_int), int(ch, c_int32_t), &
        int(fg, c_int32_t), int(bg, c_int32_t)) /= TB_OK) call draw_failure(self)
end subroutine put_cell

logical function tui_is_available()
    character(len=256) :: value
    integer :: status

    call get_environment_variable("FORTUI_HEADLESS", value, status=status)
    if (status == 0 .and. trim(value) == "1") then
        tui_is_available = .false.
        return
    end if
    call get_environment_variable("TERM", value, status=status)
    tui_is_available = status == 0 .and. len_trim(value) > 0
end function tui_is_available

end module fortui_tui
