module fortui_tb
    !! The terminal of the TUI backend: raw mode and the alternate screen, a cell
    !! grid sent to the terminal as differences from the last frame, and keys,
    !! mouse reports and window size changes decoded from the input bytes.
    !!
    !! The calls and constants are those of the termbox2 subset FortUI used
    !! before, so cells carry attributes as in termbox2 with 32-bit attributes:
    !! a colour in the low 24 bits (0 = the terminal's default, TB_HI_BLACK for
    !! black) and style bits above. The device itself is in src/c/fortui_tty.c.
    use iso_c_binding, only: c_int, c_long, c_char
    use iso_fortran_env, only: int32
    use fortui_text, only: utf8_encode
    use fortui_vt, only: char_width
    implicit none
    private

    public :: tb_event, tb_grid_t
    public :: tb_init, tb_shutdown, tb_width, tb_height, tb_clear, tb_present, &
        tb_hide_cursor, tb_set_cell, tb_peek_event, tb_poll_event, tb_set_clear_attrs, &
        tb_set_input_mode, tb_set_output_mode
    public :: tb_grid_resize, tb_grid_clear, tb_grid_set, tb_render, tb_decode

    integer, parameter, public :: TB_OK = 0, TB_ERR = -1, TB_ERR_NO_EVENT = -6
    integer, parameter, public :: TB_KEY_CTRL_C = 3
    integer, parameter, public :: TB_KEY_BACKSPACE = 8, TB_KEY_TAB = 9, TB_KEY_ENTER = 13
    integer, parameter, public :: TB_KEY_ESC = 27, TB_KEY_BACKSPACE2 = 127
    integer, parameter, public :: TB_KEY_F1 = 65535, TB_KEY_F12 = 65535 - 11
    integer, parameter, public :: TB_KEY_INSERT = 65535 - 12, TB_KEY_DELETE = 65535 - 13
    integer, parameter, public :: TB_KEY_HOME = 65535 - 14, TB_KEY_END = 65535 - 15
    integer, parameter, public :: TB_KEY_PGUP = 65535 - 16, TB_KEY_PGDN = 65535 - 17
    integer, parameter, public :: TB_KEY_ARROW_UP = 65535 - 18, TB_KEY_ARROW_DOWN = 65535 - 19
    integer, parameter, public :: TB_KEY_ARROW_LEFT = 65535 - 20, &
        TB_KEY_ARROW_RIGHT = 65535 - 21
    integer, parameter, public :: TB_KEY_MOUSE_LEFT = 65535 - 23, &
        TB_KEY_MOUSE_RIGHT = 65535 - 24, TB_KEY_MOUSE_MIDDLE = 65535 - 25, &
        TB_KEY_MOUSE_RELEASE = 65535 - 26, TB_KEY_MOUSE_WHEEL_UP = 65535 - 27, &
        TB_KEY_MOUSE_WHEEL_DOWN = 65535 - 28
    integer, parameter, public :: TB_MOD_MOTION = 8
    integer, parameter, public :: TB_EVENT_KEY = 1, TB_EVENT_RESIZE = 2, TB_EVENT_MOUSE = 3
    integer, parameter, public :: TB_INPUT_ESC = 1, TB_INPUT_MOUSE = 4
    integer, parameter, public :: TB_OUTPUT_256 = 2, TB_OUTPUT_TRUECOLOR = 5
    integer, parameter, public :: TB_BOLD = int(z'01000000'), TB_UNDERLINE = int(z'02000000'), &
        TB_REVERSE = int(z'04000000'), TB_ITALIC = int(z'08000000'), &
        TB_HI_BLACK = int(z'20000000')

    character(len=*), parameter :: ESC = achar(27)
    integer, parameter :: COLOUR_BITS = int(z'FFFFFF')
    ! An escape sequence still incomplete after this long is taken as typed.
    integer, parameter :: ESC_WAIT_MS = 25
    integer, parameter :: READ_CHUNK = 4096

    type :: tb_event
        integer :: type = 0, mod = 0, key = 0, ch = 0
        integer :: w = 0, h = 0, x = 0, y = 0
    end type tb_event

    type :: tb_grid_t
        !! Cells by (column, row), 1-based: code point, foreground, background.
        integer :: w = 0, h = 0
        integer(int32), allocatable :: ch(:, :), fg(:, :), bg(:, :)
    end type tb_grid_t

    type :: tb_state_t
        logical :: active = .false.
        integer :: output_mode = TB_OUTPUT_256
        integer(int32) :: clear_fg = 0, clear_bg = 0
        type(tb_grid_t) :: back, front
        ! Input bytes not decoded yet.
        character(len=:), allocatable :: pending
        logical :: clear_screen = .true.
    end type tb_state_t

    type(tb_state_t), save :: tb

    interface
        integer(c_int) function fortui_tty_open() bind(C, name="fortui_tty_open")
            import :: c_int
        end function fortui_tty_open
        integer(c_int) function fortui_tty_close() bind(C, name="fortui_tty_close")
            import :: c_int
        end function fortui_tty_close
        integer(c_long) function fortui_tty_read(buf, cap, timeout_ms) &
                bind(C, name="fortui_tty_read")
            import :: c_long, c_int, c_char
            character(kind=c_char), intent(out) :: buf(*)
            integer(c_long), value :: cap
            integer(c_int), value :: timeout_ms
        end function fortui_tty_read
        integer(c_int) function fortui_tty_write(buf, n) bind(C, name="fortui_tty_write")
            import :: c_int, c_long, c_char
            character(kind=c_char), intent(in) :: buf(*)
            integer(c_long), value :: n
        end function fortui_tty_write
        integer(c_int) function fortui_tty_size(cols, rows, xpixel, ypixel) &
                bind(C, name="fortui_tty_size")
            import :: c_int
            integer(c_int), intent(out) :: cols, rows, xpixel, ypixel
        end function fortui_tty_size
    end interface

contains

    ! --- the device ----------------------------------------------------------------

    integer function tb_init() result(status)
        !! Raw mode, the alternate screen and application keypad, a cleared screen.
        integer(c_int) :: cols, rows, xp, yp
        status = TB_ERR
        if (tb%active) return
        if (fortui_tty_open() /= 0) return
        if (fortui_tty_size(cols, rows, xp, yp) /= 0) then
            status = fortui_tty_close()
            status = TB_ERR
            return
        end if
        tb%active = .true.
        tb%pending = ""
        call tb_grid_resize(tb%back, int(cols), int(rows))
        call tb_grid_resize(tb%front, int(cols), int(rows))
        call tb_grid_clear(tb%back, tb%clear_fg, tb%clear_bg)
        tb%front%ch = -1
        tb%clear_screen = .true.
        status = send(ESC // "[?1049h" // ESC // "[?1h" // ESC // "=" // ESC // "[H" // &
            ESC // "[2J")
    end function tb_init

    integer function tb_shutdown() result(status)
        !! The terminal as it was: cursor, colours, keypad, mouse and main screen.
        integer :: s
        status = TB_ERR
        if (.not. tb%active) return
        s = send(ESC // "[?25h" // ESC // "[m" // ESC // "[H" // ESC // "[2J" // &
            ESC // "[?1006l" // ESC // "[?1002l" // ESC // "[?1000l" // &
            ESC // "[?1l" // ESC // ">" // ESC // "[?1049l")
        status = TB_OK
        if (s /= TB_OK) status = TB_ERR
        if (fortui_tty_close() /= 0) status = TB_ERR
        tb%active = .false.
    end function tb_shutdown

    integer function tb_width()
        tb_width = tb%back%w
    end function tb_width

    integer function tb_height()
        tb_height = tb%back%h
    end function tb_height

    integer function tb_set_output_mode(mode) result(status)
        integer(c_int), intent(in) :: mode
        status = TB_ERR
        if (mode /= TB_OUTPUT_256 .and. mode /= TB_OUTPUT_TRUECOLOR) return
        tb%output_mode = mode
        tb%front%ch = -1
        status = TB_OK
    end function tb_set_output_mode

    integer function tb_set_input_mode(mode) result(status)
        !! Escape sequences are always decoded; the mouse reports buttons, drags
        !! and the wheel in SGR encoding.
        integer(c_int), intent(in) :: mode
        status = TB_OK
        if (iand(int(mode), TB_INPUT_MOUSE) /= 0) &
            status = send(ESC // "[?1000h" // ESC // "[?1002h" // ESC // "[?1006h")
    end function tb_set_input_mode

    integer function tb_hide_cursor() result(status)
        status = send(ESC // "[?25l")
    end function tb_hide_cursor

    integer function tb_set_clear_attrs(fg, bg) result(status)
        integer(int32), intent(in) :: fg, bg
        tb%clear_fg = fg
        tb%clear_bg = bg
        status = TB_OK
    end function tb_set_clear_attrs

    integer function tb_clear() result(status)
        call tb_grid_clear(tb%back, tb%clear_fg, tb%clear_bg)
        status = TB_OK
    end function tb_clear

    integer function tb_set_cell(x, y, ch, fg, bg) result(status)
        !! Cell (x, y), 0-based.
        integer(c_int), intent(in) :: x, y
        integer(int32), intent(in) :: ch, fg, bg
        status = TB_ERR
        if (x < 0 .or. y < 0 .or. x >= tb%back%w .or. y >= tb%back%h) return
        call tb_grid_set(tb%back, int(x) + 1, int(y) + 1, ch, fg, bg)
        status = TB_OK
    end function tb_set_cell

    integer function tb_present() result(status)
        character(len=:), allocatable :: out
        if (.not. tb%active) then
            status = TB_ERR
            return
        end if
        out = ""
        if (tb%clear_screen) then
            out = ESC // "[m" // ESC // "[H" // ESC // "[2J"
            tb%clear_screen = .false.
        end if
        call tb_render(tb%back, tb%front, tb%output_mode, out)
        status = TB_OK
        if (len(out) > 0) status = send(out)
    end function tb_present

    integer function tb_poll_event(event) result(status)
        type(tb_event), intent(out) :: event
        status = tb_peek_event(event, -1_c_int)
    end function tb_poll_event

    integer function tb_peek_event(event, timeout) result(status)
        !! The next event within `timeout` ms (negative: without limit); TB_OK
        !! with an event, TB_ERR_NO_EVENT when none came.
        type(tb_event), intent(out) :: event
        integer(c_int), intent(in) :: timeout
        character(kind=c_char) :: buf(READ_CHUNK)
        integer(c_long) :: n
        integer :: used, k
        logical :: partial

        status = TB_ERR
        if (.not. tb%active) return
        do
            call tb_decode(tb%pending, .false., event, used)
            partial = used == 0 .and. len(tb%pending) > 0
            if (used > 0) then
                tb%pending = tb%pending(used + 1:)
                if (event%type /= 0) then
                    status = TB_OK
                    return
                end if
                cycle
            end if
            if (partial) then
                n = fortui_tty_read(buf, int(READ_CHUNK, c_long), &
                    int(min(ESC_WAIT_MS, merge(ESC_WAIT_MS, int(timeout), timeout < 0)), c_int))
                if (n == 0) then
                    call tb_decode(tb%pending, .true., event, used)
                    tb%pending = tb%pending(max(used, 1) + 1:)
                    if (event%type /= 0) then
                        status = TB_OK
                        return
                    end if
                    cycle
                end if
            else
                n = fortui_tty_read(buf, int(READ_CHUNK, c_long), timeout)
                if (n == 0) then
                    status = TB_ERR_NO_EVENT
                    return
                end if
            end if
            if (n == -2) then
                call resized(event)
                status = TB_OK
                return
            end if
            if (n < 0) return
            do k = 1, int(n)
                tb%pending = tb%pending // buf(k)
            end do
        end do
    end function tb_peek_event

    subroutine resized(event)
        type(tb_event), intent(out) :: event
        integer(c_int) :: cols, rows, xp, yp
        if (fortui_tty_size(cols, rows, xp, yp) /= 0) then
            cols = int(tb%back%w, c_int)
            rows = int(tb%back%h, c_int)
        end if
        call tb_grid_resize(tb%back, int(cols), int(rows))
        call tb_grid_resize(tb%front, int(cols), int(rows))
        call tb_grid_clear(tb%back, tb%clear_fg, tb%clear_bg)
        tb%front%ch = -1
        tb%clear_screen = .true.
        event%type = TB_EVENT_RESIZE
        event%w = int(cols)
        event%h = int(rows)
    end subroutine resized

    integer function send(s) result(status)
        character(*), intent(in) :: s
        status = TB_OK
        if (len(s) == 0) return
        if (fortui_tty_write(s, int(len(s), c_long)) /= 0) status = TB_ERR
    end function send

    ! --- the grid and its output ---------------------------------------------------

    subroutine tb_grid_resize(g, w, h)
        type(tb_grid_t), intent(inout) :: g
        integer, intent(in) :: w, h
        g%w = max(0, w)
        g%h = max(0, h)
        if (allocated(g%ch)) deallocate(g%ch, g%fg, g%bg)
        allocate(g%ch(g%w, g%h), g%fg(g%w, g%h), g%bg(g%w, g%h))
        g%ch = 32
        g%fg = 0
        g%bg = 0
    end subroutine tb_grid_resize

    subroutine tb_grid_clear(g, fg, bg)
        type(tb_grid_t), intent(inout) :: g
        integer(int32), intent(in) :: fg, bg
        g%ch = 32
        g%fg = fg
        g%bg = bg
    end subroutine tb_grid_clear

    subroutine tb_grid_set(g, x, y, ch, fg, bg)
        !! Cell (x, y), 1-based.
        type(tb_grid_t), intent(inout) :: g
        integer, intent(in) :: x, y
        integer(int32), intent(in) :: ch, fg, bg
        g%ch(x, y) = ch
        g%fg(x, y) = fg
        g%bg(x, y) = bg
    end subroutine tb_grid_set

    subroutine tb_render(back, front, mode, out)
        !! Append to `out` what turns the screen showing `front` into `back`, and
        !! make `front` equal to `back`. A front cell of -1 is unknown. A wide
        !! character covers the next cell, whose own content is not drawn.
        type(tb_grid_t), intent(in) :: back
        type(tb_grid_t), intent(inout) :: front
        integer, intent(in) :: mode
        character(len=:), allocatable, intent(inout) :: out
        integer :: x, y, w, cx, cy
        integer(int32) :: cur_fg, cur_bg, ch
        logical :: pen_known

        pen_known = .false.
        cur_fg = 0
        cur_bg = 0
        cx = -1
        cy = -1
        do y = 1, back%h
            x = 1
            do while (x <= back%w)
                ch = back%ch(x, y)
                w = max(1, char_width(int(ch)))
                if (x + w - 1 > back%w) then
                    w = 1
                    ch = 32
                end if
                if (front%ch(x, y) == ch .and. front%fg(x, y) == back%fg(x, y) .and. &
                    front%bg(x, y) == back%bg(x, y) .and. &
                    (w == 1 .or. front%ch(min(x + 1, back%w), y) == -2)) then
                    x = x + w
                    cycle
                end if
                if (cx /= x .or. cy /= y) out = out // ESC // "[" // itoa(y) // ";" // &
                    itoa(x) // "H"
                if (.not. pen_known .or. cur_fg /= back%fg(x, y) .or. &
                    cur_bg /= back%bg(x, y)) then
                    out = out // sgr(back%fg(x, y), back%bg(x, y), mode)
                    cur_fg = back%fg(x, y)
                    cur_bg = back%bg(x, y)
                    pen_known = .true.
                end if
                if (ch < 32 .or. ch == 127) ch = 32
                out = out // utf8_encode(int(ch))
                front%ch(x, y) = ch
                front%fg(x, y) = back%fg(x, y)
                front%bg(x, y) = back%bg(x, y)
                ! The covered cell: -2 marks it as drawn by its left neighbour.
                if (w == 2) then
                    front%ch(x + 1, y) = -2
                    front%fg(x + 1, y) = back%fg(x, y)
                    front%bg(x + 1, y) = back%bg(x, y)
                end if
                x = x + w
                cx = x
                cy = y
                ! The terminal wraps or stays at the right margin: position anew.
                if (cx > back%w) cx = -1
            end do
        end do
    end subroutine tb_render

    function sgr(fg, bg, mode) result(s)
        integer(int32), intent(in) :: fg, bg
        integer, intent(in) :: mode
        character(len=:), allocatable :: s
        s = ESC // "[0"
        if (iand(fg, TB_BOLD) /= 0) s = s // ";1"
        if (iand(fg, TB_ITALIC) /= 0) s = s // ";3"
        if (iand(fg, TB_UNDERLINE) /= 0) s = s // ";4"
        if (iand(fg, TB_REVERSE) /= 0) s = s // ";7"
        s = s // colour_param(fg, mode, 38) // colour_param(bg, mode, 48) // "m"
    end function sgr

    function colour_param(attr, mode, base) result(s)
        integer(int32), intent(in) :: attr
        integer, intent(in) :: mode, base
        character(len=:), allocatable :: s
        integer :: c
        logical :: black
        black = iand(attr, TB_HI_BLACK) /= 0
        if (mode == TB_OUTPUT_TRUECOLOR) then
            c = iand(attr, COLOUR_BITS)
            if (c == 0 .and. .not. black) then
                s = ";" // itoa(base + 1)
            else
                s = ";" // itoa(base) // ";2;" // itoa(ishft(c, -16)) // ";" // &
                    itoa(iand(ishft(c, -8), 255)) // ";" // itoa(iand(c, 255))
            end if
        else
            c = iand(attr, 255)
            if (c == 0 .and. .not. black) then
                s = ";" // itoa(base + 1)
            else
                s = ";" // itoa(base) // ";5;" // itoa(c)
            end if
        end if
    end function colour_param

    pure function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=12) :: b
        write(b, '(i0)') i
        s = trim(b)
    end function itoa

    ! --- input ---------------------------------------------------------------------

    subroutine tb_decode(buf, final, event, used)
        !! The first event in `buf`: `used` bytes taken (0: an incomplete
        !! sequence, wait for more), event%type 0 when they carried no event
        !! (an unknown sequence or a terminal reply). With `final`, nothing more
        !! will arrive, so an incomplete escape sequence is the Escape key.
        character(*), intent(in) :: buf
        logical, intent(in) :: final
        type(tb_event), intent(out) :: event
        integer, intent(out) :: used
        integer :: b, n, need, cp, k

        used = 0
        n = len(buf)
        if (n == 0) return
        b = iachar(buf(1:1))
        if (b == 27) then
            call decode_escape(buf, final, event, used)
            return
        end if
        if (b < 32 .or. b == 127) then
            event%type = TB_EVENT_KEY
            event%key = b
            used = 1
            return
        end if
        need = 1
        if (b >= 240) then
            need = 4
        else if (b >= 224) then
            need = 3
        else if (b >= 192) then
            need = 2
        end if
        if (n < need) then
            if (final) used = n
            return
        end if
        if (need == 1) then
            cp = b
        else
            cp = iand(b, ishft(255, -(need + 1)))
            do k = 2, need
                cp = ior(ishft(cp, 6), iand(iachar(buf(k:k)), 63))
            end do
        end if
        event%type = TB_EVENT_KEY
        event%ch = cp
        used = need
    end subroutine tb_decode

    subroutine decode_escape(buf, final, event, used)
        character(*), intent(in) :: buf
        logical, intent(in) :: final
        type(tb_event), intent(inout) :: event
        integer, intent(out) :: used
        integer :: n, k, f

        n = len(buf)
        used = 0
        if (n == 1) then
            if (final) call escape_key(event, used)
            return
        end if
        select case (buf(2:2))
        case ("[")
            ! CSI: parameter bytes 0x30-0x3F, intermediates 0x20-0x2F, a final byte.
            k = 3
            do while (k <= n)
                f = iachar(buf(k:k))
                if (f >= 64 .and. f <= 126) exit
                if (f < 32 .or. f > 63) then
                    call escape_key(event, used)
                    return
                end if
                k = k + 1
            end do
            if (k > n) then
                if (final) call escape_key(event, used)
                return
            end if
            if (buf(3:k) == "M") then
                ! X10 mouse: three more bytes.
                if (n < k + 3) then
                    if (final) call escape_key(event, used)
                    return
                end if
                call x10_mouse(buf(k + 1:k + 3), event)
                used = k + 3
                return
            end if
            used = k
            call csi(buf(3:k - 1), buf(k:k), event)
        case ("O")
            if (n < 3) then
                if (final) call escape_key(event, used)
                return
            end if
            used = 3
            call ss3(buf(3:3), event)
        case ("]", "P", "_")
            ! OSC, DCS, APC (terminal replies): up to BEL or ESC \.
            do k = 3, n
                if (buf(k:k) == achar(7)) then
                    used = k
                    return
                end if
                if (k < n .and. buf(k:k) == ESC) then
                    if (buf(k + 1:k + 1) == "\") then
                        used = k + 1
                        return
                    end if
                end if
            end do
            if (final) call escape_key(event, used)
        case default
            call escape_key(event, used)
        end select
    end subroutine decode_escape

    subroutine escape_key(event, used)
        type(tb_event), intent(inout) :: event
        integer, intent(out) :: used
        event%type = TB_EVENT_KEY
        event%key = TB_KEY_ESC
        event%ch = 0
        used = 1
    end subroutine escape_key

    subroutine csi(params, final_byte, event)
        character(*), intent(in) :: params, final_byte
        type(tb_event), intent(inout) :: event
        integer :: p(3), np

        if (len(params) > 0) then
            if (params(1:1) == "<") then
                if (final_byte /= "M" .and. final_byte /= "m") return
                call numbers(params(2:), p, np)
                if (np == 3) call sgr_mouse(p, final_byte == "m", event)
                return
            end if
            ! Private replies (?), and other prefixes, carry no key.
            if (verify(params, "0123456789;") /= 0) return
        end if
        call numbers(params, p, np)
        select case (final_byte)
        case ("A", "B", "C", "D", "H", "F")
            call ss3(final_byte, event)
        case ("P", "Q", "R", "S")
            call ss3(final_byte, event)
        case ("~")
            if (np < 1) return
            select case (p(1))
            case (1, 7); call key(event, TB_KEY_HOME)
            case (2); call key(event, TB_KEY_INSERT)
            case (3); call key(event, TB_KEY_DELETE)
            case (4, 8); call key(event, TB_KEY_END)
            case (5); call key(event, TB_KEY_PGUP)
            case (6); call key(event, TB_KEY_PGDN)
            case (11:15); call key(event, TB_KEY_F1 - (p(1) - 11))
            case (17:21); call key(event, TB_KEY_F1 - (p(1) - 12))
            case (23, 24); call key(event, TB_KEY_F1 - (p(1) - 13))
            end select
        end select
    end subroutine csi

    subroutine ss3(c, event)
        character(*), intent(in) :: c
        type(tb_event), intent(inout) :: event
        select case (c)
        case ("A"); call key(event, TB_KEY_ARROW_UP)
        case ("B"); call key(event, TB_KEY_ARROW_DOWN)
        case ("C"); call key(event, TB_KEY_ARROW_RIGHT)
        case ("D"); call key(event, TB_KEY_ARROW_LEFT)
        case ("H"); call key(event, TB_KEY_HOME)
        case ("F"); call key(event, TB_KEY_END)
        case ("P", "Q", "R", "S"); call key(event, TB_KEY_F1 - (iachar(c) - iachar("P")))
        end select
    end subroutine ss3

    subroutine key(event, k)
        type(tb_event), intent(inout) :: event
        integer, intent(in) :: k
        event%type = TB_EVENT_KEY
        event%key = k
        event%ch = 0
    end subroutine key

    subroutine sgr_mouse(p, release, event)
        !! ESC [ < b ; x ; y M (press, drag, motion) or m (release), x and y from 1.
        integer, intent(in) :: p(3)
        logical, intent(in) :: release
        type(tb_event), intent(inout) :: event
        integer :: b
        b = p(1)
        if (iand(b, 64) /= 0) then
            if (iand(b, 2) /= 0) return
            event%key = merge(TB_KEY_MOUSE_WHEEL_DOWN, TB_KEY_MOUSE_WHEEL_UP, iand(b, 1) /= 0)
        else if (release) then
            event%key = TB_KEY_MOUSE_RELEASE
        else
            select case (iand(b, 3))
            case (0); event%key = TB_KEY_MOUSE_LEFT
            case (1); event%key = TB_KEY_MOUSE_MIDDLE
            case (2); event%key = TB_KEY_MOUSE_RIGHT
            case default; event%key = TB_KEY_MOUSE_RELEASE
            end select
        end if
        event%type = TB_EVENT_MOUSE
        if (iand(b, 32) /= 0) event%mod = TB_MOD_MOTION
        event%x = p(2) - 1
        event%y = p(3) - 1
    end subroutine sgr_mouse

    subroutine x10_mouse(b3, event)
        character(*), intent(in) :: b3
        type(tb_event), intent(inout) :: event
        integer :: p(3)
        p(1) = iachar(b3(1:1)) - 32
        p(2) = iachar(b3(2:2)) - 32
        p(3) = iachar(b3(3:3)) - 32
        call sgr_mouse(p, .false., event)
    end subroutine x10_mouse

    subroutine numbers(s, p, np)
        !! Up to three ';'-separated decimal numbers (empty ones are 1).
        character(*), intent(in) :: s
        integer, intent(out) :: p(3), np
        integer :: k, v
        logical :: any
        p = 1
        np = 0
        v = 0
        any = .false.
        do k = 1, len(s) + 1
            if (k > len(s)) then
                if (np < 3 .and. (any .or. np > 0)) then
                    np = np + 1
                    if (any) p(np) = v
                end if
                exit
            end if
            if (s(k:k) == ";") then
                if (np < 3) then
                    np = np + 1
                    if (any) p(np) = v
                end if
                v = 0
                any = .false.
            else
                v = 10 * v + iachar(s(k:k)) - 48
                any = .true.
            end if
        end do
    end subroutine numbers

end module fortui_tb
