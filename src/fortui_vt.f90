module fortui_vt
    !! A VT/xterm terminal engine in Fortran: the escape-sequence parser and the
    !! screen. The screen and the scrollback are one ring of lines, so scrolling
    !! the whole screen moves an index and copies no cells; runs of printable
    !! text are written straight into cells with colours resolved once, so
    !! drawing needs no conversion. Strings for the host (OSC, DCS, APC) end
    !! vt_feed so that the host handles them in stream order.
    use iso_fortran_env, only: int8, int32
    implicit none
    private

    public :: vt_t, vt_open, vt_resize, vt_feed, vt_line, vt_key, vt_paste, vt_mouse
    public :: vt_take_output, vt_set_colors, char_width

    integer, parameter, public :: VT_EV_NONE = 0, VT_EV_OSC = 1, VT_EV_DCS = 2, VT_EV_APC = 3
    integer, parameter, public :: VT_BOLD = 1, VT_ITALIC = 2, VT_UNDERLINE = 4, VT_STRIKE = 8, &
        VT_WIDE = 16, VT_CONT = 32, VT_DIM = 64

    integer, parameter :: GROUND = 0, ESCAPE = 1, CSI_ENTRY = 2, CSI_PARAM = 3, &
        OSC_STR = 4, DCS_STR = 5, APC_STR = 6, STR_ESC = 7, ESC_INTER = 8, IGNORE_STR = 9
    integer, parameter :: MAX_PARAMS = 32

    type :: vt_t
        integer :: rows = 24, cols = 80
        ! Main screen and scrollback: nlines = rows + sb_max lines in a ring;
        ! screen row r is line modulo(top + r, nlines).
        integer :: sb_max = 10000, nlines = 0, top = 0, sb_count = 0
        integer(int32), allocatable :: cp(:, :), fg(:, :), bg(:, :), attr(:, :)
        ! The alternate screen (no scrollback).
        integer(int32), allocatable :: acp(:, :), afg(:, :), abg(:, :), aattr(:, :)
        logical :: alt = .false.
        ! Lines scrolled into the scrollback since the host last looked, and
        ! the first screen row erased by an erase in display (-1: none).
        integer :: scrolled = 0, erased_from = -1
        ! Cursor (0-based), the deferred wrap at the right margin, saved cursor.
        integer :: cr = 0, cc = 0
        logical :: wrap_next = .false.
        integer :: saved(2) = 0
        integer(int32) :: saved_pen(4) = 0
        ! Scroll region rows (inclusive) and modes.
        integer :: stop = 0, sbot = 23
        logical :: autowrap = .true., origin = .false., insert = .false., newline = .false.
        logical :: app_cursor = .false., app_keypad = .false., paste_brackets = .false.
        logical :: cursor_visible = .true., focus_events = .false.
        ! Synchronized output (mode 2026): the program is between two frames.
        logical :: sync = .false.
        integer :: mouse = 0 ! 0, 9, 1000, 1002, 1003
        logical :: mouse_sgr = .false.
        integer :: cursor_style = 0 ! DECSCUSR: 0/1/2 block, 3/4 underline, 5/6 bar
        logical, allocatable :: tabs(:)
        logical :: line_drawing = .false.
        ! Pen: attributes, colour indices (-1 default, 0..255 palette, -2 RGB).
        integer(int32) :: pen_attr = 0
        integer :: fg_index = -1, bg_index = -1
        integer(int32) :: fg_rgb = 0, bg_rgb = 0
        logical :: reverse = .false., conceal = .false.
        ! Resolved colours the pen writes (ui_rgba; background 0 = default).
        integer(int32) :: wfg = 0, wbg = 0, wattr = 0
        integer(int32) :: default_fg = int(z'FFAAAAAA', int32), default_bg = int(z'FF000000', int32)
        integer(int32) :: palette(0:255) = 0
        logical :: bold_bright = .true.
        ! Parser.
        integer :: state = GROUND
        integer :: params(MAX_PARAMS) = 0, nparams = 0
        logical :: param_given = .false., colon = .false.
        character :: private = " ", inter = " "
        integer :: utf8_need = 0, utf8_cp = 0
        integer :: last_cp = 32
        ! The string in progress (OSC, DCS, APC) and the finished one.
        character(len=:), allocatable :: str
        integer :: nstr = 0
        character(len=:), allocatable :: dcs_head
        integer :: ndcs_head = 0
        ! Replies to the program.
        character(len=:), allocatable :: out
        integer :: nout = 0
        ! Window and cell size in pixels, for size reports.
        integer :: cell_px_w = 8, cell_px_h = 16
        character(len=:), allocatable :: title
        logical :: dirty = .true.
    end type vt_t

contains

    ! --- setup -------------------------------------------------------------------

    subroutine vt_open(vt, rows, cols, scrollback)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: rows, cols
        integer, intent(in), optional :: scrollback
        vt%rows = max(1, rows)
        vt%cols = max(1, cols)
        if (present(scrollback)) vt%sb_max = max(0, scrollback)
        vt%nlines = vt%rows + vt%sb_max
        if (allocated(vt%cp)) deallocate(vt%cp, vt%fg, vt%bg, vt%attr)
        allocate(vt%cp(vt%cols, 0:vt%nlines - 1), vt%fg(vt%cols, 0:vt%nlines - 1), &
            vt%bg(vt%cols, 0:vt%nlines - 1), vt%attr(vt%cols, 0:vt%nlines - 1))
        if (allocated(vt%acp)) deallocate(vt%acp, vt%afg, vt%abg, vt%aattr)
        allocate(vt%acp(vt%cols, 0:vt%rows - 1), vt%afg(vt%cols, 0:vt%rows - 1), &
            vt%abg(vt%cols, 0:vt%rows - 1), vt%aattr(vt%cols, 0:vt%rows - 1))
        if (.not. allocated(vt%str)) allocate(character(len=4096) :: vt%str)
        if (.not. allocated(vt%out)) allocate(character(len=1024) :: vt%out)
        if (.not. allocated(vt%dcs_head)) allocate(character(len=64) :: vt%dcs_head)
        vt%title = ""
        call default_palette(vt)
        call reset(vt)
    end subroutine vt_open

    subroutine reset(vt)
        type(vt_t), intent(inout) :: vt
        integer :: k
        vt%top = 0
        vt%sb_count = 0
        vt%alt = .false.
        vt%cr = 0
        vt%cc = 0
        vt%wrap_next = .false.
        vt%stop = 0
        vt%sbot = vt%rows - 1
        vt%autowrap = .true.
        vt%origin = .false.
        vt%insert = .false.
        vt%newline = .false.
        vt%app_cursor = .false.
        vt%app_keypad = .false.
        vt%paste_brackets = .false.
        vt%cursor_visible = .true.
        vt%mouse = 0
        vt%mouse_sgr = .false.
        vt%line_drawing = .false.
        vt%state = GROUND
        call sgr_reset(vt)
        vt%cp = 32
        vt%fg = vt%default_fg
        vt%bg = 0
        vt%attr = 0
        vt%acp = 32
        vt%afg = vt%default_fg
        vt%abg = 0
        vt%aattr = 0
        if (allocated(vt%tabs)) deallocate(vt%tabs)
        allocate(vt%tabs(0:vt%cols - 1))
        vt%tabs = [(modulo(k, 8) == 0, k = 0, vt%cols - 1)]
        vt%dirty = .true.
    end subroutine reset

    subroutine default_palette(vt)
        !! xterm's 256 colours.
        type(vt_t), intent(inout) :: vt
        integer, parameter :: base(3, 0:15) = reshape([0, 0, 0, 205, 0, 0, 0, 205, 0, &
            205, 205, 0, 0, 0, 238, 205, 0, 205, 0, 205, 205, 229, 229, 229, 127, 127, 127, &
            255, 0, 0, 0, 255, 0, 255, 255, 0, 92, 92, 255, 255, 0, 255, 0, 255, 255, &
            255, 255, 255], [3, 16])
        integer :: k, r, g, b, lv(0:5)
        lv = [0, 95, 135, 175, 215, 255]
        do k = 0, 15
            vt%palette(k) = rgb(base(1, k), base(2, k), base(3, k))
        end do
        do k = 16, 231
            r = (k - 16) / 36
            g = modulo((k - 16) / 6, 6)
            b = modulo(k - 16, 6)
            vt%palette(k) = rgb(lv(r), lv(g), lv(b))
        end do
        do k = 232, 255
            vt%palette(k) = rgb(8 + 10 * (k - 232), 8 + 10 * (k - 232), 8 + 10 * (k - 232))
        end do
    end subroutine default_palette

    subroutine vt_set_colors(vt, fg, bg, palette)
        !! Default colours and optionally the 16 ANSI colours (ui_rgba).
        type(vt_t), intent(inout) :: vt
        integer(int32), intent(in) :: fg, bg
        integer(int32), intent(in), optional :: palette(16)
        vt%default_fg = fg
        vt%default_bg = bg
        if (present(palette)) vt%palette(0:15) = palette
        call resolve_pen(vt)
    end subroutine vt_set_colors

    subroutine vt_resize(vt, rows, cols)
        !! New size: lines keep their text (cut or padded on the right). A
        !! shorter screen drops blank lines below the cursor first and then
        !! moves lines above it into the scrollback; a taller one adds blank
        !! lines below.
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: rows, cols
        integer(int32), allocatable :: ncp(:, :), nfg(:, :), nbg(:, :), nattr(:, :)
        integer :: nr, nc, k, nl, src, w, last, first, s0
        logical, allocatable :: ntabs(:)
        nr = max(1, rows)
        nc = max(1, cols)
        if (nr == vt%rows .and. nc == vt%cols) return
        w = min(nc, vt%cols)
        ! Old line indices relative to the old top: -sb_count .. rows-1.
        last = max(vt%cr, min(vt%rows - 1, nr - 1))
        s0 = max(0, last - (nr - 1))
        nl = nr + vt%sb_max
        first = max(-vt%sb_count, s0 - vt%sb_max)
        allocate(ncp(nc, 0:nl - 1), nfg(nc, 0:nl - 1), nbg(nc, 0:nl - 1), nattr(nc, 0:nl - 1))
        ncp = 32
        nfg = vt%default_fg
        nbg = 0
        nattr = 0
        do k = first, last
            src = modulo(vt%top + k, vt%nlines)
            ncp(1:w, k - first) = vt%cp(1:w, src)
            nfg(1:w, k - first) = vt%fg(1:w, src)
            nbg(1:w, k - first) = vt%bg(1:w, src)
            nattr(1:w, k - first) = vt%attr(1:w, src)
        end do
        call move_alloc(ncp, vt%cp)
        call move_alloc(nfg, vt%fg)
        call move_alloc(nbg, vt%bg)
        call move_alloc(nattr, vt%attr)
        vt%nlines = nl
        vt%top = s0 - first
        vt%sb_count = s0 - first
        vt%scrolled = vt%scrolled + s0
        vt%cr = vt%cr - s0
        ! The alternate screen: cut or padded.
        allocate(ncp(nc, 0:nr - 1), nfg(nc, 0:nr - 1), nbg(nc, 0:nr - 1), nattr(nc, 0:nr - 1))
        ncp = 32
        nfg = vt%default_fg
        nbg = 0
        nattr = 0
        do k = 0, min(nr, vt%rows) - 1
            ncp(1:w, k) = vt%acp(1:w, k)
            nfg(1:w, k) = vt%afg(1:w, k)
            nbg(1:w, k) = vt%abg(1:w, k)
            nattr(1:w, k) = vt%aattr(1:w, k)
        end do
        call move_alloc(ncp, vt%acp)
        call move_alloc(nfg, vt%afg)
        call move_alloc(nbg, vt%abg)
        call move_alloc(nattr, vt%aattr)
        allocate(ntabs(0:nc - 1))
        ntabs = [(modulo(k, 8) == 0, k = 0, nc - 1)]
        ntabs(0:w - 1) = vt%tabs(0:w - 1)
        call move_alloc(ntabs, vt%tabs)
        vt%rows = nr
        vt%cols = nc
        if (vt%alt) vt%cr = min(vt%cr + s0, nr - 1)
        vt%cr = max(0, min(nr - 1, vt%cr))
        vt%cc = min(vt%cc, nc - 1)
        vt%stop = 0
        vt%sbot = nr - 1
        vt%wrap_next = .false.
        vt%dirty = .true.
    end subroutine vt_resize

    ! --- access --------------------------------------------------------------------

    pure integer function vt_line(vt, row) result(line)
        !! The line index of screen row `row` (negative: the scrollback, -1 the
        !! newest) in the main arrays, or of the alternate screen when shown.
        type(vt_t), intent(in) :: vt
        integer, intent(in) :: row
        if (vt%alt .and. row >= 0) then
            line = row
        else
            line = modulo(vt%top + row, vt%nlines)
        end if
    end function vt_line

    ! --- feeding -------------------------------------------------------------------

    subroutine vt_feed(vt, bytes, pos, event)
        !! Process bytes(pos:) until its end or until a string for the host is
        !! complete (`event`, the string in vt%str(1:vt%nstr)); `pos` then is
        !! the next byte to process.
        type(vt_t), intent(inout) :: vt
        character(*), intent(in) :: bytes
        integer, intent(inout) :: pos
        integer, intent(out) :: event
        integer :: b, n, run

        event = VT_EV_NONE
        n = len(bytes)
        vt%dirty = .true.
        do while (pos <= n)
            b = iachar(bytes(pos:pos))
            if (vt%state == GROUND) then
                if (b >= 32 .and. b < 127 .and. vt%utf8_need == 0 .and. .not. vt%line_drawing) then
                    ! The fast path: printable ASCII straight into the cells.
                    call print_run(vt, bytes, pos)
                    cycle
                end if
                if (b >= 128) then
                    call utf8_byte(vt, b)
                else if (b == 127) then
                    continue
                else if (b >= 32) then
                    call put_char(vt, map_char(vt, b))
                else
                    vt%utf8_need = 0
                    call control(vt, b)
                end if
                pos = pos + 1
                cycle
            end if
            call parse(vt, b, event)
            pos = pos + 1
            if (event /= VT_EV_NONE) return
        end do
    end subroutine vt_feed

    subroutine utf8_byte(vt, b)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: b
        if (vt%utf8_need > 0 .and. b >= 128 .and. b < 192) then
            vt%utf8_cp = ior(ishft(vt%utf8_cp, 6), iand(b, 63))
            vt%utf8_need = vt%utf8_need - 1
            if (vt%utf8_need == 0) call put_char(vt, vt%utf8_cp)
            return
        end if
        vt%utf8_need = 0
        if (b >= 240 .and. b < 248) then
            vt%utf8_cp = iand(b, 7)
            vt%utf8_need = 3
        else if (b >= 224) then
            vt%utf8_cp = iand(b, 15)
            vt%utf8_need = 2
        else if (b >= 192) then
            vt%utf8_cp = iand(b, 31)
            vt%utf8_need = 1
        else
            call put_char(vt, 65533)
        end if
    end subroutine utf8_byte

    pure integer function map_char(vt, b) result(cp)
        !! DEC special graphics (ESC ( 0): box drawing.
        type(vt_t), intent(in) :: vt
        integer, intent(in) :: b
        integer, parameter :: dec(0:31) = [9670, 9618, 9225, 9228, 9229, 9226, 176, 177, &
            9252, 9227, 9496, 9488, 9484, 9492, 9532, 9146, 9147, 9472, 9148, 9149, 9500, &
            9508, 9524, 9516, 9474, 8804, 8805, 960, 8800, 163, 183, 32]
        cp = b
        if (vt%line_drawing .and. b >= 96 .and. b <= 126) cp = dec(b - 96)
    end function map_char

    ! --- printing ------------------------------------------------------------------

    subroutine print_run(vt, s, pos)
        !! Printable ASCII from s(pos:), up to the next other byte: each byte is
        !! read once and written into its cell; colours and attributes are set
        !! for the whole stretch up to the right margin.
        type(vt_t), intent(inout) :: vt
        character(*), intent(in) :: s
        integer, intent(inout) :: pos
        integer :: line, c0, j, m, b, n
        n = len(s)
        do
            ! The deferred wrap happens only when a character is printed: text
            ! that ends exactly at the right margin, followed by a control or
            ! escape, must not scroll (tmux draws its status line so).
            if (pos > n) return
            b = iachar(s(pos:pos))
            if (b < 32 .or. b > 126) return
            if (vt%wrap_next) call wrap_line(vt)
            m = vt%cols - vt%cc
            c0 = vt%cc + 1
            if (vt%insert) then
                ! Rare: insert one cell per character.
                call insert_cells(vt, 1)
                m = 1
            end if
            j = 0
            if (vt%alt) then
                line = vt%cr
                do while (j < m .and. pos + j <= n)
                    b = iachar(s(pos + j:pos + j))
                    if (b < 32 .or. b > 126) exit
                    vt%acp(c0 + j, line) = b
                    j = j + 1
                end do
                vt%afg(c0:c0 + j - 1, line) = vt%wfg
                vt%abg(c0:c0 + j - 1, line) = vt%wbg
                vt%aattr(c0:c0 + j - 1, line) = vt%wattr
            else
                line = modulo(vt%top + vt%cr, vt%nlines)
                do while (j < m .and. pos + j <= n)
                    b = iachar(s(pos + j:pos + j))
                    if (b < 32 .or. b > 126) exit
                    vt%cp(c0 + j, line) = b
                    j = j + 1
                end do
                vt%fg(c0:c0 + j - 1, line) = vt%wfg
                vt%bg(c0:c0 + j - 1, line) = vt%wbg
                vt%attr(c0:c0 + j - 1, line) = vt%wattr
            end if
            if (j == 0) return
            vt%last_cp = iachar(s(pos + j - 1:pos + j - 1))
            pos = pos + j
            vt%cc = vt%cc + j
            if (vt%cc >= vt%cols) then
                vt%cc = vt%cols - 1
                if (vt%autowrap) vt%wrap_next = .true.
            end if
            if (j < m .or. pos > n) return
        end do
    end subroutine print_run

    subroutine put_char(vt, cp)
        !! One code point: wide ones take two cells, combining marks none.
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: cp
        integer :: w
        w = char_width(cp)
        if (w == 0) return
        if (vt%wrap_next) call wrap_line(vt)
        if (w == 2 .and. vt%cc == vt%cols - 1) then
            if (vt%autowrap) then
                call set_cell(vt, vt%cc, 32, 0)
                call wrap_line(vt)
            else
                return
            end if
        end if
        if (vt%insert) call insert_cells(vt, w)
        call set_cell(vt, vt%cc, cp, merge(VT_WIDE, 0, w == 2))
        if (w == 2) call set_cell(vt, vt%cc + 1, 32, VT_CONT)
        vt%last_cp = cp
        vt%cc = vt%cc + w
        if (vt%cc >= vt%cols) then
            vt%cc = vt%cols - 1
            if (vt%autowrap) vt%wrap_next = .true.
        end if
    end subroutine put_char

    subroutine set_cell(vt, col, cp, extra)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: col, cp, extra
        integer :: line
        if (col < 0 .or. col >= vt%cols) return
        if (vt%alt) then
            vt%acp(col + 1, vt%cr) = cp
            vt%afg(col + 1, vt%cr) = vt%wfg
            vt%abg(col + 1, vt%cr) = vt%wbg
            vt%aattr(col + 1, vt%cr) = ior(vt%wattr, extra)
        else
            line = modulo(vt%top + vt%cr, vt%nlines)
            vt%cp(col + 1, line) = cp
            vt%fg(col + 1, line) = vt%wfg
            vt%bg(col + 1, line) = vt%wbg
            vt%attr(col + 1, line) = ior(vt%wattr, extra)
        end if
    end subroutine set_cell

    subroutine wrap_line(vt)
        type(vt_t), intent(inout) :: vt
        vt%wrap_next = .false.
        vt%cc = 0
        call index_down(vt)
    end subroutine wrap_line

    pure integer function char_width(cp) result(w)
        !! Cells a code point takes (Unicode East Asian Wide/Fullwidth and
        !! emoji: 2; combining marks and zero-width characters: 0).
        integer, intent(in) :: cp
        w = 1
        if (cp < 768) return
        if ((cp >= 768 .and. cp <= 879) .or. (cp >= 1155 .and. cp <= 1161) .or. &
            (cp >= 1425 .and. cp <= 1469) .or. (cp >= 6832 .and. cp <= 6911) .or. &
            (cp >= 7616 .and. cp <= 7679) .or. (cp >= 8203 .and. cp <= 8207) .or. &
            (cp >= 8400 .and. cp <= 8447) .or. (cp >= 65024 .and. cp <= 65039) .or. &
            (cp >= 65056 .and. cp <= 65071) .or. cp == 65279 .or. &
            (cp >= 917760 .and. cp <= 917999)) then
            w = 0
        else if ((cp >= 4352 .and. cp <= 4447) .or. (cp >= 11904 .and. cp <= 42191) .or. &
                (cp >= 44032 .and. cp <= 55203) .or. (cp >= 63744 .and. cp <= 64255) .or. &
                (cp >= 65040 .and. cp <= 65049) .or. (cp >= 65072 .and. cp <= 65135) .or. &
                (cp >= 65280 .and. cp <= 65376) .or. (cp >= 65504 .and. cp <= 65510) .or. &
                (cp >= 127744 .and. cp <= 128591) .or. (cp >= 128640 .and. cp <= 128767) .or. &
                (cp >= 129280 .and. cp <= 129791) .or. (cp >= 131072 .and. cp <= 262141)) then
            w = 2
        end if
    end function char_width

    ! --- lines and scrolling ---------------------------------------------------------

    subroutine index_down(vt)
        !! Line feed: down one row, scrolling at the bottom of the region.
        type(vt_t), intent(inout) :: vt
        if (vt%cr == vt%sbot) then
            call scroll_up(vt, vt%stop, vt%sbot, 1)
        else if (vt%cr < vt%rows - 1) then
            vt%cr = vt%cr + 1
        end if
    end subroutine index_down

    subroutine scroll_up(vt, top, bot, n)
        !! Rows top..bot move up n; the whole main screen scrolls into the
        !! scrollback by moving the ring's start.
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: top, bot, n
        integer :: k, m, line
        m = min(n, bot - top + 1)
        if (m <= 0) return
        if (.not. vt%alt .and. top == 0 .and. bot == vt%rows - 1) then
            do k = 1, m
                vt%top = modulo(vt%top + 1, vt%nlines)
                line = modulo(vt%top + vt%rows - 1, vt%nlines)
                vt%cp(:, line) = 32
                vt%fg(:, line) = vt%default_fg
                vt%bg(:, line) = vt%wbg
                vt%attr(:, line) = 0
            end do
            vt%sb_count = min(vt%sb_max, vt%sb_count + m)
            vt%scrolled = vt%scrolled + m
            return
        end if
        do k = top, bot - m
            call copy_row(vt, k + m, k)
        end do
        do k = bot - m + 1, bot
            call clear_row(vt, k)
        end do
    end subroutine scroll_up

    subroutine scroll_down(vt, top, bot, n)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: top, bot, n
        integer :: k, m
        m = min(n, bot - top + 1)
        if (m <= 0) return
        do k = bot, top + m, -1
            call copy_row(vt, k - m, k)
        end do
        do k = top, top + m - 1
            call clear_row(vt, k)
        end do
    end subroutine scroll_down

    subroutine copy_row(vt, from, to)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: from, to
        integer :: a, b
        if (vt%alt) then
            vt%acp(:, to) = vt%acp(:, from)
            vt%afg(:, to) = vt%afg(:, from)
            vt%abg(:, to) = vt%abg(:, from)
            vt%aattr(:, to) = vt%aattr(:, from)
        else
            a = modulo(vt%top + from, vt%nlines)
            b = modulo(vt%top + to, vt%nlines)
            vt%cp(:, b) = vt%cp(:, a)
            vt%fg(:, b) = vt%fg(:, a)
            vt%bg(:, b) = vt%bg(:, a)
            vt%attr(:, b) = vt%attr(:, a)
        end if
    end subroutine copy_row

    subroutine clear_row(vt, row)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: row
        call clear_cells(vt, row, 0, vt%cols - 1)
    end subroutine clear_row

    subroutine clear_cells(vt, row, c0, c1)
        !! Erase cells c0..c1 of a screen row in the current background.
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: row, c0, c1
        integer :: a, b, line
        a = max(0, c0) + 1
        b = min(vt%cols - 1, c1) + 1
        if (b < a) return
        if (vt%alt) then
            vt%acp(a:b, row) = 32
            vt%afg(a:b, row) = vt%default_fg
            vt%abg(a:b, row) = vt%wbg
            vt%aattr(a:b, row) = 0
        else
            line = modulo(vt%top + row, vt%nlines)
            vt%cp(a:b, line) = 32
            vt%fg(a:b, line) = vt%default_fg
            vt%bg(a:b, line) = vt%wbg
            vt%attr(a:b, line) = 0
        end if
    end subroutine clear_cells

    subroutine insert_cells(vt, n)
        !! Shift the rest of the row right by n from the cursor.
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: n
        integer :: a, line, m
        a = vt%cc + 1
        m = min(n, vt%cols - vt%cc)
        if (m <= 0) return
        if (vt%alt) then
            vt%acp(a + m:vt%cols, vt%cr) = vt%acp(a:vt%cols - m, vt%cr)
            vt%afg(a + m:vt%cols, vt%cr) = vt%afg(a:vt%cols - m, vt%cr)
            vt%abg(a + m:vt%cols, vt%cr) = vt%abg(a:vt%cols - m, vt%cr)
            vt%aattr(a + m:vt%cols, vt%cr) = vt%aattr(a:vt%cols - m, vt%cr)
        else
            line = modulo(vt%top + vt%cr, vt%nlines)
            vt%cp(a + m:vt%cols, line) = vt%cp(a:vt%cols - m, line)
            vt%fg(a + m:vt%cols, line) = vt%fg(a:vt%cols - m, line)
            vt%bg(a + m:vt%cols, line) = vt%bg(a:vt%cols - m, line)
            vt%attr(a + m:vt%cols, line) = vt%attr(a:vt%cols - m, line)
        end if
        call clear_cells(vt, vt%cr, vt%cc, vt%cc + m - 1)
    end subroutine insert_cells

    subroutine delete_cells(vt, n)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: n
        integer :: a, line, m
        a = vt%cc + 1
        m = min(n, vt%cols - vt%cc)
        if (m <= 0) return
        if (vt%alt) then
            vt%acp(a:vt%cols - m, vt%cr) = vt%acp(a + m:vt%cols, vt%cr)
            vt%afg(a:vt%cols - m, vt%cr) = vt%afg(a + m:vt%cols, vt%cr)
            vt%abg(a:vt%cols - m, vt%cr) = vt%abg(a + m:vt%cols, vt%cr)
            vt%aattr(a:vt%cols - m, vt%cr) = vt%aattr(a + m:vt%cols, vt%cr)
        else
            line = modulo(vt%top + vt%cr, vt%nlines)
            vt%cp(a:vt%cols - m, line) = vt%cp(a + m:vt%cols, line)
            vt%fg(a:vt%cols - m, line) = vt%fg(a + m:vt%cols, line)
            vt%bg(a:vt%cols - m, line) = vt%bg(a + m:vt%cols, line)
            vt%attr(a:vt%cols - m, line) = vt%attr(a + m:vt%cols, line)
        end if
        call clear_cells(vt, vt%cr, vt%cols - m, vt%cols - 1)
    end subroutine delete_cells

    ! --- control characters and escapes ------------------------------------------------

    subroutine control(vt, b)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: b
        integer :: k
        select case (b)
        case (7)
            continue
        case (8)
            if (vt%cc > 0) vt%cc = vt%cc - 1
            vt%wrap_next = .false.
        case (9)
            do k = vt%cc + 1, vt%cols - 1
                if (vt%tabs(k)) exit
            end do
            vt%cc = min(k, vt%cols - 1)
            vt%wrap_next = .false.
        case (10, 11, 12)
            call index_down(vt)
            if (vt%newline) vt%cc = 0
            vt%wrap_next = .false.
        case (13)
            vt%cc = 0
            vt%wrap_next = .false.
        case (14)
            vt%line_drawing = .true.
        case (15)
            vt%line_drawing = .false.
        case (27)
            vt%state = ESCAPE
            vt%inter = " "
        end select
    end subroutine control

    subroutine parse(vt, b, event)
        !! Every state but ground, one byte.
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: b
        integer, intent(out) :: event
        event = VT_EV_NONE
        select case (vt%state)
        case (ESCAPE)
            call escape_byte(vt, b)
        case (ESC_INTER)
            call escape_final(vt, b)
        case (CSI_ENTRY, CSI_PARAM)
            call csi_byte(vt, b)
        case (OSC_STR, DCS_STR, APC_STR, IGNORE_STR)
            if (b == 7 .and. vt%state == OSC_STR) then
                vt%state = GROUND
                event = VT_EV_OSC
            else if (b == 27) then
                vt%inter = achar(vt%state)
                vt%state = STR_ESC
            else if (b == 24 .or. b == 26) then
                vt%state = GROUND
            else if (vt%state /= IGNORE_STR) then
                call str_add(vt, achar(b))
            end if
        case (STR_ESC)
            ! ESC \ ends the string; any other byte after ESC starts an escape.
            vt%state = GROUND
            if (b == 92) then
                select case (iachar(vt%inter))
                case (OSC_STR); event = VT_EV_OSC
                case (DCS_STR); event = VT_EV_DCS
                case (APC_STR); event = VT_EV_APC
                end select
            else
                vt%state = ESCAPE
                call escape_byte(vt, b)
            end if
        end select
    end subroutine parse

    subroutine str_add(vt, c)
        type(vt_t), intent(inout) :: vt
        character, intent(in) :: c
        character(len=:), allocatable :: grown
        if (vt%nstr >= 128 * 1024 * 1024) return
        if (vt%nstr == len(vt%str)) then
            allocate(character(len=2 * len(vt%str)) :: grown)
            grown(1:vt%nstr) = vt%str(1:vt%nstr)
            call move_alloc(grown, vt%str)
        end if
        vt%nstr = vt%nstr + 1
        vt%str(vt%nstr:vt%nstr) = c
    end subroutine str_add

    subroutine escape_byte(vt, b)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: b
        vt%state = GROUND
        select case (b)
        case (91) ! [
            vt%state = CSI_ENTRY
            vt%nparams = 0
            vt%params = 0
            vt%param_given = .false.
            vt%colon = .false.
            vt%private = " "
            vt%inter = " "
        case (93) ! ]
            vt%state = OSC_STR
            vt%nstr = 0
        case (80) ! P
            vt%state = DCS_STR
            vt%nstr = 0
        case (95) ! _
            vt%state = APC_STR
            vt%nstr = 0
        case (94, 88) ! ^ PM, X SOS
            vt%state = IGNORE_STR
        case (32:47)
            vt%inter = achar(b)
            vt%state = ESC_INTER
        case (55) ! 7
            call save_cursor(vt)
        case (56) ! 8
            call restore_cursor(vt)
        case (68) ! D
            call index_down(vt)
        case (69) ! E
            vt%cc = 0
            call index_down(vt)
        case (72) ! H
            vt%tabs(vt%cc) = .true.
        case (77) ! M reverse index
            if (vt%cr == vt%stop) then
                call scroll_down(vt, vt%stop, vt%sbot, 1)
            else if (vt%cr > 0) then
                vt%cr = vt%cr - 1
            end if
        case (99) ! c
            call reset(vt)
        case (61) ! =
            vt%app_keypad = .true.
        case (62) ! >
            vt%app_keypad = .false.
        end select
        vt%wrap_next = vt%wrap_next .and. (b == 91 .or. b == 93 .or. b == 80 .or. b == 95)
    end subroutine escape_byte

    subroutine escape_final(vt, b)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: b
        vt%state = GROUND
        if (vt%inter == "(") vt%line_drawing = b == 48
        if (vt%inter == "#" .and. b == 56) then
            ! DECALN: the screen full of E.
            call fill_e(vt)
        end if
    end subroutine escape_final

    subroutine fill_e(vt)
        type(vt_t), intent(inout) :: vt
        integer :: r
        do r = 0, vt%rows - 1
            call clear_row(vt, r)
            if (vt%alt) then
                vt%acp(:, r) = 69
            else
                vt%cp(:, modulo(vt%top + r, vt%nlines)) = 69
            end if
        end do
    end subroutine fill_e

    subroutine save_cursor(vt)
        type(vt_t), intent(inout) :: vt
        vt%saved = [vt%cr, vt%cc]
        vt%saved_pen = [vt%pen_attr, int(vt%fg_index, int32), int(vt%bg_index, int32), &
            merge(1_int32, 0_int32, vt%line_drawing)]
    end subroutine save_cursor

    subroutine restore_cursor(vt)
        type(vt_t), intent(inout) :: vt
        vt%cr = min(vt%rows - 1, vt%saved(1))
        vt%cc = min(vt%cols - 1, vt%saved(2))
        vt%pen_attr = vt%saved_pen(1)
        vt%fg_index = int(vt%saved_pen(2))
        vt%bg_index = int(vt%saved_pen(3))
        vt%line_drawing = vt%saved_pen(4) /= 0
        vt%wrap_next = .false.
        call resolve_pen(vt)
    end subroutine restore_cursor

    ! --- CSI -------------------------------------------------------------------------

    subroutine csi_byte(vt, b)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: b
        select case (b)
        case (48:57)
            if (vt%nparams == 0) vt%nparams = 1
            vt%params(vt%nparams) = min(65535, 10 * vt%params(vt%nparams) + b - 48)
            vt%param_given = .true.
            vt%state = CSI_PARAM
        case (59, 58) ! ; and : (sub-parameters are taken as parameters)
            if (b == 58) vt%colon = .true.
            if (vt%nparams == 0) vt%nparams = 1
            if (vt%nparams < MAX_PARAMS) vt%nparams = vt%nparams + 1
            vt%params(vt%nparams) = 0
            vt%state = CSI_PARAM
        case (60:63) ! < = > ?
            vt%private = achar(b)
        case (32:47)
            vt%inter = achar(b)
        case (64:126)
            vt%state = GROUND
            call csi_dispatch(vt, achar(b))
        case (24, 26)
            vt%state = GROUND
        case (27)
            vt%state = ESCAPE
        case (0:23, 25, 28:31)
            call control(vt, b)
        end select
    end subroutine csi_byte

    integer function p(vt, k, default)
        !! Parameter k (missing or 0 -> default).
        type(vt_t), intent(in) :: vt
        integer, intent(in) :: k, default
        p = default
        if (k <= vt%nparams) then
            if (vt%params(k) > 0) p = vt%params(k)
        end if
    end function p

    subroutine csi_dispatch(vt, f)
        type(vt_t), intent(inout) :: vt
        character, intent(in) :: f
        integer :: n, k, top, bot
        if (vt%private == "?") then
            select case (f)
            case ("h", "l")
                do k = 1, max(1, vt%nparams)
                    call private_mode(vt, vt%params(k), f == "h")
                end do
            end select
            if (f == "p" .and. vt%inter == "$") call reply(vt, achar(27) // "[?" // &
                itoa(vt%params(1)) // ";0$y")
            return
        end if
        if (vt%private == ">") then
            if (f == "c") call reply(vt, achar(27) // "[>1;10;0c")
            if (f == "q") call reply(vt, achar(27) // "P>|fortterm" // achar(27) // "\")
            return
        end if
        if (vt%private /= " ") return
        if (vt%inter == " " .and. f /= "q") vt%wrap_next = .false.
        select case (f)
        case ("@")
            call insert_cells(vt, p(vt, 1, 1))
        case ("A")
            vt%cr = max(merge(vt%stop, 0, vt%cr >= vt%stop), vt%cr - p(vt, 1, 1))
        case ("B", "e")
            vt%cr = min(merge(vt%sbot, vt%rows - 1, vt%cr <= vt%sbot), vt%cr + p(vt, 1, 1))
        case ("C", "a")
            vt%cc = min(vt%cols - 1, vt%cc + p(vt, 1, 1))
        case ("D")
            vt%cc = max(0, vt%cc - p(vt, 1, 1))
        case ("E")
            vt%cr = min(vt%rows - 1, vt%cr + p(vt, 1, 1))
            vt%cc = 0
        case ("F")
            vt%cr = max(0, vt%cr - p(vt, 1, 1))
            vt%cc = 0
        case ("G", "`")
            vt%cc = min(vt%cols - 1, p(vt, 1, 1) - 1)
        case ("H", "f")
            call move_to(vt, p(vt, 1, 1) - 1, p(vt, 2, 1) - 1)
        case ("I")
            do k = 1, p(vt, 1, 1)
                call control(vt, 9)
            end do
        case ("J")
            call erase_display(vt, vt%params(1))
        case ("K")
            select case (vt%params(1))
            case (0); call clear_cells(vt, vt%cr, vt%cc, vt%cols - 1)
            case (1); call clear_cells(vt, vt%cr, 0, vt%cc)
            case (2); call clear_row(vt, vt%cr)
            end select
        case ("L")
            if (vt%cr >= vt%stop .and. vt%cr <= vt%sbot) call scroll_down(vt, vt%cr, vt%sbot, &
                p(vt, 1, 1))
        case ("M")
            if (vt%cr >= vt%stop .and. vt%cr <= vt%sbot) call scroll_up_region(vt, vt%cr, &
                vt%sbot, p(vt, 1, 1))
        case ("P")
            call delete_cells(vt, p(vt, 1, 1))
        case ("S")
            call scroll_up(vt, vt%stop, vt%sbot, p(vt, 1, 1))
        case ("T")
            call scroll_down(vt, vt%stop, vt%sbot, p(vt, 1, 1))
        case ("X")
            call clear_cells(vt, vt%cr, vt%cc, vt%cc + p(vt, 1, 1) - 1)
        case ("Z")
            do k = 1, p(vt, 1, 1)
                do while (vt%cc > 0)
                    vt%cc = vt%cc - 1
                    if (vt%tabs(vt%cc)) exit
                end do
            end do
        case ("b")
            do k = 1, min(65535, p(vt, 1, 1))
                call put_char(vt, vt%last_cp)
            end do
        case ("c")
            ! VT220 with sixel graphics (4) and ANSI colour (22).
            call reply(vt, achar(27) // "[?62;4;22c")
        case ("d")
            call move_to(vt, p(vt, 1, 1) - 1, vt%cc)
        case ("g")
            if (vt%params(1) == 0) vt%tabs(vt%cc) = .false.
            if (vt%params(1) == 3) vt%tabs = .false.
        case ("h", "l")
            do k = 1, max(1, vt%nparams)
                if (vt%params(k) == 4) vt%insert = f == "h"
                if (vt%params(k) == 20) vt%newline = f == "h"
            end do
        case ("m")
            call sgr(vt)
        case ("n")
            if (vt%params(1) == 5) call reply(vt, achar(27) // "[0n")
            if (vt%params(1) == 6) call reply(vt, achar(27) // "[" // itoa(vt%cr + 1) // ";" // &
                itoa(vt%cc + 1) // "R")
        case ("q")
            if (vt%inter == " ") vt%cursor_style = vt%params(1)
        case ("r")
            top = p(vt, 1, 1) - 1
            bot = p(vt, 2, vt%rows) - 1
            if (bot > top .and. bot < vt%rows) then
                vt%stop = top
                vt%sbot = bot
                call move_to(vt, 0, 0)
            end if
        case ("s")
            call save_cursor(vt)
        case ("u")
            call restore_cursor(vt)
        case ("t")
            n = vt%params(1)
            if (n == 14) call reply(vt, achar(27) // "[4;" // itoa(vt%rows * vt%cell_px_h) // &
                ";" // itoa(vt%cols * vt%cell_px_w) // "t")
            if (n == 16) call reply(vt, achar(27) // "[6;" // itoa(vt%cell_px_h) // ";" // &
                itoa(vt%cell_px_w) // "t")
            if (n == 18) call reply(vt, achar(27) // "[8;" // itoa(vt%rows) // ";" // &
                itoa(vt%cols) // "t")
        end select
    end subroutine csi_dispatch

    subroutine scroll_up_region(vt, top, bot, n)
        !! Delete lines: a region that is the whole screen still must not feed
        !! the scrollback, so it is copied.
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: top, bot, n
        integer :: k, m
        m = min(n, bot - top + 1)
        do k = top, bot - m
            call copy_row(vt, k + m, k)
        end do
        do k = bot - m + 1, bot
            call clear_row(vt, k)
        end do
    end subroutine scroll_up_region

    subroutine move_to(vt, row, col)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: row, col
        if (vt%origin) then
            vt%cr = max(vt%stop, min(vt%sbot, row + vt%stop))
        else
            vt%cr = max(0, min(vt%rows - 1, row))
        end if
        vt%cc = max(0, min(vt%cols - 1, col))
        vt%wrap_next = .false.
    end subroutine move_to

    subroutine erase_display(vt, mode)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: mode
        integer :: r
        if (mode == 0) vt%erased_from = max(vt%erased_from, vt%cr)
        if (mode == 2 .or. mode == 3) vt%erased_from = 0
        select case (mode)
        case (0)
            call clear_cells(vt, vt%cr, vt%cc, vt%cols - 1)
            do r = vt%cr + 1, vt%rows - 1
                call clear_row(vt, r)
            end do
        case (1)
            call clear_cells(vt, vt%cr, 0, vt%cc)
            do r = 0, vt%cr - 1
                call clear_row(vt, r)
            end do
        case (2)
            do r = 0, vt%rows - 1
                call clear_row(vt, r)
            end do
        case (3)
            vt%sb_count = 0
        end select
    end subroutine erase_display

    subroutine private_mode(vt, mode, on)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: mode
        logical, intent(in) :: on
        select case (mode)
        case (1); vt%app_cursor = on
        case (6)
            vt%origin = on
            call move_to(vt, 0, 0)
        case (7); vt%autowrap = on
        case (25); vt%cursor_visible = on
        case (9, 1000, 1002, 1003)
            vt%mouse = merge(mode, 0, on)
        case (1004); vt%focus_events = on
        case (2026); vt%sync = on
        case (1006); vt%mouse_sgr = on
        case (2004); vt%paste_brackets = on
        case (47, 1047)
            call alternate(vt, on, .false.)
        case (1049)
            call alternate(vt, on, .true.)
        case (1048)
            if (on) then
                call save_cursor(vt)
            else
                call restore_cursor(vt)
            end if
        end select
    end subroutine private_mode

    subroutine alternate(vt, on, cursor)
        type(vt_t), intent(inout) :: vt
        logical, intent(in) :: on, cursor
        if (on .eqv. vt%alt) return
        if (on) then
            if (cursor) call save_cursor(vt)
            vt%alt = .true.
            vt%acp = 32
            vt%afg = vt%default_fg
            vt%abg = 0
            vt%aattr = 0
        else
            vt%alt = .false.
            if (cursor) call restore_cursor(vt)
        end if
        vt%dirty = .true.
    end subroutine alternate

    ! --- SGR ---------------------------------------------------------------------------

    subroutine sgr_reset(vt)
        type(vt_t), intent(inout) :: vt
        vt%pen_attr = 0
        vt%fg_index = -1
        vt%bg_index = -1
        vt%reverse = .false.
        vt%conceal = .false.
        call resolve_pen(vt)
    end subroutine sgr_reset

    subroutine sgr(vt)
        type(vt_t), intent(inout) :: vt
        integer :: k, v
        if (vt%nparams == 0) then
            call sgr_reset(vt)
            return
        end if
        k = 1
        do while (k <= vt%nparams)
            v = vt%params(k)
            select case (v)
            case (0); call sgr_reset(vt)
            case (1); vt%pen_attr = ior(vt%pen_attr, VT_BOLD)
            case (2); vt%pen_attr = ior(vt%pen_attr, VT_DIM)
            case (3); vt%pen_attr = ior(vt%pen_attr, VT_ITALIC)
            case (4); vt%pen_attr = ior(vt%pen_attr, VT_UNDERLINE)
            case (7); vt%reverse = .true.
            case (8); vt%conceal = .true.
            case (9); vt%pen_attr = ior(vt%pen_attr, VT_STRIKE)
            case (21, 22); vt%pen_attr = iand(vt%pen_attr, not(VT_BOLD + VT_DIM))
            case (23); vt%pen_attr = iand(vt%pen_attr, not(VT_ITALIC))
            case (24); vt%pen_attr = iand(vt%pen_attr, not(VT_UNDERLINE))
            case (27); vt%reverse = .false.
            case (28); vt%conceal = .false.
            case (29); vt%pen_attr = iand(vt%pen_attr, not(VT_STRIKE))
            case (30:37); vt%fg_index = v - 30
            case (38); call extended(vt%fg_index, vt%fg_rgb)
            case (39); vt%fg_index = -1
            case (40:47); vt%bg_index = v - 40
            case (48); call extended(vt%bg_index, vt%bg_rgb)
            case (49); vt%bg_index = -1
            case (90:97); vt%fg_index = v - 90 + 8
            case (100:107); vt%bg_index = v - 100 + 8
            end select
            k = k + 1
        end do
        call resolve_pen(vt)
    contains
        subroutine extended(index, colour)
            !! 38;5;n (palette) or 38;2;r;g;b (RGB, also 38:2::r:g:b).
            integer, intent(inout) :: index
            integer(int32), intent(inout) :: colour
            if (k + 1 > vt%nparams) return
            if (vt%params(k + 1) == 5 .and. k + 2 <= vt%nparams) then
                index = min(255, vt%params(k + 2))
                k = k + 2
            else if (vt%params(k + 1) == 2) then
                ! 38:2::r:g:b carries an (empty) colour space before r.
                if (vt%colon .and. k + 5 <= vt%nparams) k = k + 1
                if (k + 4 <= vt%nparams) then
                    index = -2
                    colour = rgb(vt%params(k + 2), vt%params(k + 3), vt%params(k + 4))
                    k = k + 4
                end if
            end if
        end subroutine extended
    end subroutine sgr

    subroutine resolve_pen(vt)
        !! The colours the pen writes: palette, bold-is-bright, faint, reverse
        !! and conceal applied once here instead of at every frame.
        type(vt_t), intent(inout) :: vt
        integer(int32) :: f, b, swap
        integer :: fi
        fi = vt%fg_index
        if (vt%bold_bright .and. iand(vt%pen_attr, VT_BOLD) /= 0 .and. fi >= 0 .and. fi < 8) &
            fi = fi + 8
        select case (fi)
        case (-1); f = vt%default_fg
        case (-2); f = vt%fg_rgb
        case default; f = vt%palette(fi)
        end select
        select case (vt%bg_index)
        case (-1); b = 0
        case (-2); b = vt%bg_rgb
        case default; b = vt%palette(vt%bg_index)
        end select
        if (iand(vt%pen_attr, VT_DIM) /= 0) then
            if (b == 0) then
                f = blend(f, vt%default_bg)
            else
                f = blend(f, b)
            end if
        end if
        if (vt%reverse) then
            swap = f
            f = b
            if (f == 0) f = vt%default_bg
            b = swap
        end if
        if (vt%conceal) f = merge(vt%default_bg, b, b == 0)
        vt%wfg = f
        vt%wbg = b
        vt%wattr = vt%pen_attr
    end subroutine resolve_pen

    pure integer(int32) function blend(a, b) result(c)
        integer(int32), intent(in) :: a, b
        integer :: k, v
        c = ishft(-1_int32, 24)
        do k = 0, 2
            v = (int(iand(ishft(a, -8 * k), 255_int32)) + int(iand(ishft(b, -8 * k), 255_int32))) / 2
            c = ior(c, ishft(int(v, int32), 8 * k))
        end do
    end function blend

    pure integer(int32) function rgb(r, g, b) result(c)
        integer, intent(in) :: r, g, b
        c = int(iand(r, 255), int32) + ishft(int(iand(g, 255), int32), 8) + &
            ishft(int(iand(b, 255), int32), 16) + ishft(-1_int32, 24)
    end function rgb

    ! --- replies and input --------------------------------------------------------------

    subroutine reply(vt, s)
        type(vt_t), intent(inout) :: vt
        character(*), intent(in) :: s
        character(len=:), allocatable :: grown
        if (vt%nout + len(s) > len(vt%out)) then
            allocate(character(len=2 * (vt%nout + len(s))) :: grown)
            grown(1:vt%nout) = vt%out(1:vt%nout)
            call move_alloc(grown, vt%out)
        end if
        vt%out(vt%nout + 1:vt%nout + len(s)) = s
        vt%nout = vt%nout + len(s)
    end subroutine reply

    subroutine vt_take_output(vt, s)
        !! What the terminal answers or encodes for the program, since the last
        !! call.
        type(vt_t), intent(inout) :: vt
        character(len=:), allocatable, intent(out) :: s
        s = vt%out(1:vt%nout)
        vt%nout = 0
    end subroutine vt_take_output

    subroutine vt_key(vt, key, code, shift, alt, ctrl)
        !! A key as xterm encodes it: `key` 0 for a character (`code`), else
        !! 1 Enter, 2 Tab, 3 Backspace, 4 Escape, 5-8 Up/Down/Left/Right,
        !! 9 Insert, 10 Delete, 11 Home, 12 End, 13 Page Up, 14 Page Down,
        !! 100+n F n.
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: key, code
        logical, intent(in) :: shift, alt, ctrl
        integer :: m, c
        character(len=:), allocatable :: s
        character(len=*), parameter :: E = achar(27)
        integer, parameter :: FKEYS(8) = [15, 17, 18, 19, 20, 21, 23, 24]
        character(len=*), parameter :: DIRS = "ABDC", PQRS = "PQRS"
        m = 1 + merge(1, 0, shift) + merge(2, 0, alt) + merge(4, 0, ctrl)
        select case (key)
        case (0)
            c = code
            if (ctrl) then
                if (c >= 97 .and. c <= 122) then
                    c = c - 96
                else if (c >= 64 .and. c <= 95) then
                    c = c - 64
                else if (c == 32 .or. c == 50) then
                    c = 0
                else if (c >= 51 .and. c <= 55) then
                    c = c - 24
                else if (c == 56) then
                    c = 127
                else if (c == 47) then
                    c = 31
                end if
            end if
            s = utf8(c)
            if (alt) s = E // s
        case (1)
            s = achar(13)
            if (vt%newline) s = achar(13) // achar(10)
            if (alt) s = E // s
        case (2)
            s = achar(9)
            if (shift) s = E // "[Z"
        case (3)
            s = achar(127)
            if (ctrl) s = achar(8)
            if (alt) s = E // s
        case (4)
            s = E
        case (5:8)
            s = arrow(DIRS(key - 4:key - 4))
        case (11)
            s = arrow("H")
        case (12)
            s = arrow("F")
        case (9); s = tilde(2)
        case (10); s = tilde(3)
        case (13); s = tilde(5)
        case (14); s = tilde(6)
        case (101:104)
            if (m == 1) then
                s = E // "O" // PQRS(key - 100:key - 100)
            else
                s = E // "[1;" // itoa(m) // PQRS(key - 100:key - 100)
            end if
        case (105:112)
            s = tilde(FKEYS(key - 104))
        case default
            return
        end select
        call reply(vt, s)
    contains
        function arrow(f) result(r)
            character, intent(in) :: f
            character(len=:), allocatable :: r
            if (m > 1) then
                r = E // "[1;" // itoa(m) // f
            else if (vt%app_cursor) then
                r = E // "O" // f
            else
                r = E // "[" // f
            end if
        end function arrow
        function tilde(n) result(r)
            integer, intent(in) :: n
            character(len=:), allocatable :: r
            if (m > 1) then
                r = E // "[" // itoa(n) // ";" // itoa(m) // "~"
            else
                r = E // "[" // itoa(n) // "~"
            end if
        end function tilde
    end subroutine vt_key

    subroutine vt_paste(vt, text)
        !! Pasted text (bracketed when the program asked; newlines become CR).
        type(vt_t), intent(inout) :: vt
        character(*), intent(in) :: text
        character(len=:), allocatable :: s
        integer :: k
        s = text
        do k = 1, len(s)
            if (s(k:k) == achar(10)) s(k:k) = achar(13)
        end do
        if (vt%paste_brackets) then
            call reply(vt, achar(27) // "[200~" // s // achar(27) // "[201~")
        else
            call reply(vt, s)
        end if
    end subroutine vt_paste

    subroutine vt_mouse(vt, row, col, button, pressed, moved, shift, alt, ctrl)
        !! A pointer event in the encoding the program asked for (button 0-2,
        !! 64/65 for the wheel).
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: row, col, button
        logical, intent(in) :: pressed, moved, shift, alt, ctrl
        integer :: b
        if (vt%mouse == 0) return
        if (moved .and. vt%mouse < 1002) return
        if (moved .and. vt%mouse == 1002 .and. (.not. pressed .or. button < 0)) return
        ! Motion with no button held reports button 3 (mode 1003).
        b = merge(3, button, button < 0) + merge(4, 0, shift) + merge(8, 0, alt) + &
            merge(16, 0, ctrl)
        if (moved) b = b + 32
        if (vt%mouse_sgr) then
            call reply(vt, achar(27) // "[<" // itoa(b) // ";" // itoa(col + 1) // ";" // &
                itoa(row + 1) // merge("M", "m", pressed .or. button >= 64))
        else
            if (.not. pressed .and. button < 64) b = 3 + b - button
            call reply(vt, achar(27) // "[M" // achar(min(255, 32 + b)) // &
                achar(min(255, 33 + col)) // achar(min(255, 33 + row)))
        end if
    end subroutine vt_mouse

    function utf8(cp) result(s)
        integer, intent(in) :: cp
        character(len=:), allocatable :: s
        if (cp < 128) then
            s = achar(cp)
        else if (cp < 2048) then
            s = achar(ior(192, ishft(cp, -6))) // achar(ior(128, iand(cp, 63)))
        else if (cp < 65536) then
            s = achar(ior(224, ishft(cp, -12))) // achar(ior(128, iand(ishft(cp, -6), 63))) // &
                achar(ior(128, iand(cp, 63)))
        else
            s = achar(ior(240, ishft(cp, -18))) // achar(ior(128, iand(ishft(cp, -12), 63))) // &
                achar(ior(128, iand(ishft(cp, -6), 63))) // achar(ior(128, iand(cp, 63)))
        end if
    end function utf8

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=12) :: buf
        write (buf, '(i0)') i
        s = trim(buf)
    end function itoa

end module fortui_vt
