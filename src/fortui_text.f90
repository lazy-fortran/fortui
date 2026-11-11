module fortui_text
    !! Backend-neutral UTF-8 handling, text metrics and wrapping in logical units.
    !!
    !! Widgets measure through the active metric table. Headless uses fixed metrics
    !! (advance = factor * size per code point); a graphical backend installs a
    !! measured per-code-point advance table for the font it actually draws with.
    use iso_fortran_env, only: int64, real64
    implicit none
    private

    integer, parameter, public :: TEXT_STYLE_REGULAR = 1
    integer, parameter, public :: TEXT_STYLE_BOLD = 2
    integer, parameter, public :: TEXT_STYLE_MONO = 3
    integer, parameter, public :: TEXT_MAX_CODEPOINT = 12287
    real, parameter, public :: TEXT_DEFAULT_SIZE = 20.0
    integer, parameter :: REPLACEMENT = 65533

    type, public :: text_line_t
        !! One wrapped visual line: byte range [first, last] of the source string.
        integer :: first = 1
        integer :: last = 0
        real :: y = 0.0
        real :: size = TEXT_DEFAULT_SIZE
        integer :: style = TEXT_STYLE_REGULAR
    end type text_line_t

    logical, save :: fixed_metrics = .true.
    real, save :: fixed_advance = 0.5
    real, save :: line_factor = 1.25
    real, save :: advance_table(0:TEXT_MAX_CODEPOINT, 2) = 0.5
    real, save :: fallback_advance(2) = 0.5
    ! Advance of every code point in monospaced text, per unit size.
    real, save :: mono_advance = 0.6
    ! Character-cell metrics (terminals): every code point and line has the size of
    ! one cell whatever the requested text size (0 = off).
    real, save :: cell_advance = 0.0
    real, save :: cell_height = 0.0

    public :: utf8_decode, utf8_encode, utf8_length, utf8_prev, utf8_next
    public :: utf8_boundary
    public :: text_use_fixed_metrics, text_set_metrics, text_metrics_fixed, text_set_mono_metrics
    public :: text_use_cell_metrics
    public :: text_advance, text_width, text_line_height, text_caret_from_x
    public :: text_wrap, text_fit, ui_str

    interface ui_str
        !! Decimal text of a number for labels: ui_str(42), ui_str(3.14159, 2).
        module procedure str_int, str_real
    end interface ui_str

contains

    pure subroutine utf8_decode(s, pos, cp, nbytes)
        !! Decode the code point starting at byte `pos`; malformed input yields U+FFFD.
        character(*), intent(in) :: s
        integer, intent(in) :: pos
        integer, intent(out) :: cp, nbytes
        integer :: b0, i, need, b

        cp = REPLACEMENT
        nbytes = 1
        if (pos < 1 .or. pos > len(s)) return
        b0 = iachar(s(pos:pos))
        if (b0 < 128) then
            cp = b0
            return
        else if (b0 >= 192 .and. b0 < 224) then
            need = 1
            cp = iand(b0, 31)
        else if (b0 >= 224 .and. b0 < 240) then
            need = 2
            cp = iand(b0, 15)
        else if (b0 >= 240 .and. b0 < 248) then
            need = 3
            cp = iand(b0, 7)
        else
            cp = REPLACEMENT
            return
        end if
        if (pos + need > len(s)) then
            cp = REPLACEMENT
            return
        end if
        do i = 1, need
            b = iachar(s(pos + i:pos + i))
            if (b < 128 .or. b >= 192) then
                cp = REPLACEMENT
                return
            end if
            cp = cp * 64 + iand(b, 63)
        end do
        nbytes = need + 1
    end subroutine utf8_decode

    pure function utf8_encode(cp) result(out)
        integer, intent(in) :: cp
        character(len=:), allocatable :: out
        integer :: c

        c = cp
        if (c < 0 .or. c > 1114111) c = REPLACEMENT
        if (c < 128) then
            out = achar(c)
        else if (c < 2048) then
            out = achar(192 + c / 64) // achar(128 + iand(c, 63))
        else if (c < 65536) then
            out = achar(224 + c / 4096) // achar(128 + iand(c / 64, 63)) // &
                achar(128 + iand(c, 63))
        else
            out = achar(240 + c / 262144) // achar(128 + iand(c / 4096, 63)) // &
                achar(128 + iand(c / 64, 63)) // achar(128 + iand(c, 63))
        end if
    end function utf8_encode

    pure integer function utf8_length(s) result(n)
        character(*), intent(in) :: s
        integer :: pos, cp, nb

        n = 0
        pos = 1
        do while (pos <= len(s))
            call utf8_decode(s, pos, cp, nb)
            pos = pos + nb
            n = n + 1
        end do
    end function utf8_length

    pure logical function is_continuation(s, pos)
        character(*), intent(in) :: s
        integer, intent(in) :: pos
        integer :: b

        is_continuation = .false.
        if (pos < 1 .or. pos > len(s)) return
        b = iachar(s(pos:pos))
        is_continuation = b >= 128 .and. b < 192
    end function is_continuation

    pure integer function utf8_boundary(s, caret) result(c)
        !! Clamp a caret (byte offset 0..len) back onto a code point boundary.
        character(*), intent(in) :: s
        integer, intent(in) :: caret

        c = max(0, min(len(s), caret))
        do while (c > 0)
            if (.not. is_continuation(s, c + 1)) exit
            c = c - 1
        end do
    end function utf8_boundary

    pure integer function utf8_prev(s, caret) result(c)
        !! Caret offset of the code point boundary before `caret`.
        character(*), intent(in) :: s
        integer, intent(in) :: caret

        c = max(0, min(len(s), caret))
        if (c == 0) return
        c = c - 1
        do while (c > 0)
            if (.not. is_continuation(s, c + 1)) exit
            c = c - 1
        end do
    end function utf8_prev

    pure integer function utf8_next(s, caret) result(c)
        !! Caret offset of the code point boundary after `caret`.
        character(*), intent(in) :: s
        integer, intent(in) :: caret
        integer :: cp, nb

        c = max(0, min(len(s), caret))
        if (c >= len(s)) return
        call utf8_decode(s, c + 1, cp, nb)
        c = min(len(s), c + nb)
    end function utf8_next

    subroutine text_use_fixed_metrics(advance_factor, height_factor)
        !! Deterministic metrics: every code point advances `advance_factor * size`.
        real, intent(in), optional :: advance_factor, height_factor

        fixed_metrics = .true.
        cell_advance = 0.0
        cell_height = 0.0
        fixed_advance = 0.5
        line_factor = 1.25
        if (present(advance_factor)) fixed_advance = advance_factor
        if (present(height_factor)) line_factor = height_factor
    end subroutine text_use_fixed_metrics

    subroutine text_use_cell_metrics(advance, height)
        !! Character-cell metrics: every code point advances `advance` and every
        !! line is `height` logical units, independent of the text size (a terminal
        !! shows all text sizes in the same cells).
        real, intent(in) :: advance, height

        fixed_metrics = .true.
        cell_advance = advance
        cell_height = height
    end subroutine text_use_cell_metrics

    subroutine text_set_metrics(advances, fallback, height_factor)
        !! Install measured advances per unit font size, indexed (code point, style).
        real, intent(in) :: advances(0:, :)
        real, intent(in) :: fallback(2)
        real, intent(in) :: height_factor
        integer :: n, s

        fixed_metrics = .false.
        cell_advance = 0.0
        cell_height = 0.0
        n = min(ubound(advances, 1), TEXT_MAX_CODEPOINT)
        do s = 1, 2
            advance_table(:, s) = fallback(s)
            advance_table(0:n, s) = advances(0:n, min(s, size(advances, 2)))
        end do
        fallback_advance = fallback
        line_factor = height_factor
    end subroutine text_set_metrics

    subroutine text_set_mono_metrics(advance)
        !! Install the advance of monospaced text per unit font size.
        real, intent(in) :: advance
        mono_advance = max(0.05, advance)
    end subroutine text_set_mono_metrics

    logical function text_metrics_fixed()
        text_metrics_fixed = fixed_metrics
    end function text_metrics_fixed

    real function text_advance(cp, size, style) result(adv)
        integer, intent(in) :: cp
        real, intent(in) :: size
        integer, intent(in), optional :: style
        integer :: st

        if (cell_advance > 0.0) then
            adv = cell_advance
            return
        end if
        if (fixed_metrics) then
            adv = fixed_advance * size
            return
        end if
        st = TEXT_STYLE_REGULAR
        if (present(style)) st = style
        if (st == TEXT_STYLE_MONO) then
            adv = mono_advance * size
            return
        end if
        st = max(1, min(2, st))
        if (cp >= 0 .and. cp <= TEXT_MAX_CODEPOINT) then
            adv = advance_table(cp, st) * size
        else
            adv = fallback_advance(st) * size
        end if
    end function text_advance

    real function text_width(s, size, style) result(w)
        character(*), intent(in) :: s
        real, intent(in) :: size
        integer, intent(in), optional :: style
        integer :: pos, cp, nb

        w = 0.0
        pos = 1
        do while (pos <= len(s))
            call utf8_decode(s, pos, cp, nb)
            w = w + text_advance(cp, size, style)
            pos = pos + nb
        end do
    end function text_width

    real function text_line_height(size) result(h)
        real, intent(in) :: size
        if (cell_height > 0.0) then
            h = cell_height
        else
            h = line_factor * size
        end if
    end function text_line_height

    integer function text_caret_from_x(s, size, x) result(caret)
        !! Byte caret nearest to logical offset `x` from the start of `s`.
        character(*), intent(in) :: s
        real, intent(in) :: size, x
        integer :: pos, cp, nb
        real :: w, adv

        caret = 0
        w = 0.0
        pos = 1
        do while (pos <= len(s))
            call utf8_decode(s, pos, cp, nb)
            adv = text_advance(cp, size)
            if (x < w + 0.5 * adv) return
            w = w + adv
            pos = pos + nb
            caret = pos - 1
        end do
    end function text_caret_from_x

    subroutine text_wrap(s, max_width, size, markdown, lines, count, height)
        !! Greedy word wrap at spaces; LF separates paragraphs, CR is ignored.
        !! With `markdown`, lines starting with `#` become bold, larger headings and
        !! the heading marker is excluded from the line range.
        character(*), intent(in) :: s
        real, intent(in) :: max_width, size
        logical, intent(in) :: markdown
        type(text_line_t), allocatable, intent(inout) :: lines(:)
        integer, intent(out) :: count
        real, intent(out) :: height

        integer :: pstart, pend, nl
        real :: y

        count = 0
        y = 0.0
        if (.not. allocated(lines)) allocate(lines(64))
        pstart = 1
        do
            nl = index(s(pstart:), achar(10))
            if (nl == 0) then
                pend = len(s)
            else
                pend = pstart + nl - 2
            end if
            call wrap_paragraph(s, pstart, pend, max_width, size, markdown, lines, count, y)
            if (nl == 0) exit
            pstart = pend + 2
            if (pstart > len(s)) then
                call push_line(lines, count, text_line_t(first=pstart, last=pstart - 1, &
                    y=y, size=size))
                y = y + text_line_height(size)
                exit
            end if
        end do
        height = y
    end subroutine text_wrap

    subroutine wrap_paragraph(s, pstart, pend_in, max_width, base_size, markdown, &
            lines, count, y)
        character(*), intent(in) :: s
        integer, intent(in) :: pstart, pend_in
        real, intent(in) :: max_width, base_size
        logical, intent(in) :: markdown
        type(text_line_t), allocatable, intent(inout) :: lines(:)
        integer, intent(inout) :: count
        real, intent(inout) :: y

        integer :: pend, first, pos, cp, nb, line_start, last_break, level, style
        real :: size, width, width_at_break, adv, lh

        pend = pend_in
        if (pend >= pstart) then
            if (s(pend:pend) == achar(13)) pend = pend - 1
        end if
        first = pstart
        size = base_size
        style = TEXT_STYLE_REGULAR
        if (markdown .and. pend >= pstart) then
            level = 0
            do while (first + level <= pend)
                if (s(first + level:first + level) /= '#') exit
                level = level + 1
            end do
            if (level >= 1 .and. level <= 6 .and. first + level <= pend) then
                if (s(first + level:first + level) == ' ') then
                    style = TEXT_STYLE_BOLD
                    select case (level)
                    case (1); size = 1.5 * base_size
                    case (2); size = 1.3 * base_size
                    case default; size = 1.15 * base_size
                    end select
                    first = first + level + 1
                end if
            end if
        end if
        lh = text_line_height(size)

        line_start = first
        last_break = 0
        width = 0.0
        width_at_break = 0.0
        pos = first
        do while (pos <= pend)
            call utf8_decode(s(1:pend), pos, cp, nb)
            adv = text_advance(cp, size, style)
            if (max_width > 0.0 .and. width + adv > max_width .and. pos > line_start &
                .and. cp /= 32) then
                if (last_break > line_start) then
                    call emit(line_start, last_break - 1)
                    line_start = last_break
                    width = width - width_at_break
                else
                    call emit(line_start, pos - 1)
                    line_start = pos
                    width = 0.0
                end if
                last_break = 0
                width_at_break = 0.0
            end if
            width = width + adv
            pos = pos + nb
            if (cp == 32) then
                last_break = pos
                width_at_break = width
            end if
        end do
        call emit(line_start, pend)

    contains

        subroutine emit(a, b)
            integer, intent(in) :: a, b
            integer :: e
            e = b
            do while (e >= a)
                if (s(e:e) /= ' ') exit
                e = e - 1
            end do
            call push_line(lines, count, text_line_t(first=a, last=e, y=y, size=size, &
                style=style))
            y = y + lh
        end subroutine emit

    end subroutine wrap_paragraph

    subroutine push_line(lines, count, line)
        type(text_line_t), allocatable, intent(inout) :: lines(:)
        integer, intent(inout) :: count
        type(text_line_t), intent(in) :: line
        type(text_line_t), allocatable :: grown(:)

        if (count >= size(lines)) then
            allocate(grown(2 * size(lines)))
            grown(1:count) = lines(1:count)
            call move_alloc(grown, lines)
        end if
        count = count + 1
        lines(count) = line
    end subroutine push_line


    function text_fit(s, size, max_width, style) result(r)
        !! `s` unchanged when it fits `max_width`; otherwise the longest code point
        !! prefix followed by an ellipsis that fits (only the ellipsis if none does).
        character(*), intent(in) :: s
        real, intent(in) :: size, max_width
        integer, intent(in), optional :: style
        character(len=:), allocatable :: r
        character(len=*), parameter :: ELLIPSIS = char(226) // char(128) // char(166)
        real :: avail, w
        integer :: pos, cp, nb, last

        if (text_width(s, size, style) <= max_width) then
            r = s
            return
        end if
        avail = max_width - text_width(ELLIPSIS, size, style)
        w = 0.0
        last = 0
        pos = 1
        do while (pos <= len(s))
            call utf8_decode(s, pos, cp, nb)
            w = w + text_advance(cp, size, style)
            if (w > avail) exit
            pos = pos + nb
            last = pos - 1
        end do
        r = s(1:last) // ELLIPSIS
    end function text_fit

    pure function str_int(value) result(s)
        !! Decimal digits, written out so that no formatted I/O is linked in.
        integer, intent(in) :: value
        character(len=:), allocatable :: s

        s = digits_of(abs(int(value, int64)))
        if (value < 0) s = '-' // s
    end function str_int

    pure function digits_of(v) result(s)
        integer(int64), intent(in) :: v
        character(len=:), allocatable :: s
        character(len=20) :: buf
        integer(int64) :: r
        integer :: p

        r = v
        p = len(buf)
        do
            buf(p:p) = achar(48 + int(mod(r, 10_int64)))
            r = r / 10_int64
            if (r == 0) exit
            p = p - 1
        end do
        s = buf(p:)
    end function digits_of

    pure function str_real(value, decimals) result(s)
        !! Fixed-point text with `decimals` digits after the point (default 2).
        real, intent(in) :: value
        integer, intent(in), optional :: decimals
        character(len=:), allocatable :: s
        integer(int64) :: scaled, unit
        character(len=:), allocatable :: frac
        integer :: d
        real(real64) :: v

        d = 2
        if (present(decimals)) d = max(0, min(12, decimals))
        if (value /= value) then
            s = 'NaN'
            return
        end if
        if (abs(value) > huge(value)) then
            s = 'Infinity'
            if (value < 0.0) s = '-' // s
            return
        end if
        unit = 10_int64**d
        v = abs(real(value, real64)) * real(unit, real64)
        if (v >= 9.0e18_real64) then
            ! Beyond 64-bit integers: the digits before the point only.
            s = digits_of(int(abs(real(value, real64)) / 1.0e9_real64, int64)) // '000000000'
        else
            scaled = nint(v, int64)
            s = digits_of(scaled / unit)
            if (d > 0) then
                frac = digits_of(mod(scaled, unit))
                s = s // '.' // repeat('0', d - len(frac)) // frac
            end if
        end if
        if (value < 0.0) s = '-' // s
    end function str_real

end module fortui_text
