module fortui_icons
    !! Symbols for icons and buttons, drawn from strokes in a 24 x 24 box with
    !! round caps and joins, so every host draws the same shapes: browsers as
    !! SVG paths, painted hosts as thick lines, terminals as one character.
    !!
    !! A symbol is path text of commands with coordinates in the box:
    !! "M x y" moves, "L x y" draws a line, "Z" closes the figure and
    !! "O cx cy r" draws a circle.
    implicit none
    private

    public :: icon_path, icon_svg, icon_polylines, icon_glyph, icon_names

    ! Names, each with its path and the character terminals show.
    integer, parameter :: N_ICONS = 40
    character(len=*), parameter :: NAMES(N_ICONS) = [character(len=14) :: &
        'check', 'close', 'add', 'remove', 'chevron-down', 'chevron-up', 'chevron-left', &
        'chevron-right', 'search', 'menu', 'more', 'filter', 'arrow-up', 'arrow-down', &
        'arrow-left', 'arrow-right', 'undo', 'redo', 'info', 'warning', 'error', 'send', &
        'pen', 'eraser', 'eye', 'lock', 'person', 'people', 'chat', 'globe', 'branch', &
        'merge', 'refresh', 'delete', 'settings', 'home', 'star', 'cube', 'gate', 'translate']
    character(len=*), parameter :: GLYPHS(N_ICONS) = [character(len=4) :: &
        '✓', '✕', '+', '−', '▾', '▴', '‹', '›', '⌕', '≡', '⋯', '⏷', '↑', '↓', '←', '→', &
        '↶', '↷', 'ⓘ', '⚠', '⊗', '➤', '✎', '⌫', '◉', '⚿', '☺', '☻', '✉', '◍', '⑂', '⑃', &
        '⟳', '⌦', '⚙', '⌂', '★', '◫', '⛩', '文']

contains

    pure function icon_names() result(list)
        !! Every symbol name, in a fixed order.
        character(len=14) :: list(N_ICONS)
        list = NAMES
    end function icon_names

    function icon_path(name) result(path)
        !! Path text of the symbol `name`; empty when there is none.
        character(*), intent(in) :: name
        character(len=:), allocatable :: path
        select case (trim(name))
        case ('check'); path = 'M5 12.5 L10 17.5 L19 7'
        case ('close'); path = 'M6 6 L18 18 M18 6 L6 18'
        case ('add'); path = 'M12 5 L12 19 M5 12 L19 12'
        case ('remove'); path = 'M5 12 L19 12'
        case ('chevron-down'); path = 'M6 9 L12 15 L18 9'
        case ('chevron-up'); path = 'M6 15 L12 9 L18 15'
        case ('chevron-left'); path = 'M15 6 L9 12 L15 18'
        case ('chevron-right'); path = 'M9 6 L15 12 L9 18'
        case ('search'); path = 'O10.5 10.5 6.5 M15.5 15.5 L20 20'
        case ('menu'); path = 'M4 6 L20 6 M4 12 L20 12 M4 18 L20 18'
        case ('more'); path = 'O5 12 1 O12 12 1 O19 12 1'
        case ('filter'); path = 'M4 5 L20 5 L14 12.5 L14 19 L10 17 L10 12.5 Z'
        case ('arrow-up'); path = 'M12 19 L12 5 M6 11 L12 5 L18 11'
        case ('arrow-down'); path = 'M12 5 L12 19 M6 13 L12 19 L18 13'
        case ('arrow-left'); path = 'M19 12 L5 12 M11 6 L5 12 L11 18'
        case ('arrow-right'); path = 'M5 12 L19 12 M13 6 L19 12 L13 18'
        case ('undo')
            path = 'M9 14 L4 9 L9 4 M4 9 L14.5 9 L16.6 9.4 L18.4 10.6 L19.6 12.4 L20 14.5 ' // &
                'L19.6 16.6 L18.4 18.4 L16.6 19.6 L14.5 20 L11 20'
        case ('redo')
            path = 'M15 14 L20 9 L15 4 M20 9 L9.5 9 L7.4 9.4 L5.6 10.6 L4.4 12.4 L4 14.5 ' // &
                'L4.4 16.6 L5.6 18.4 L7.4 19.6 L9.5 20 L13 20'
        case ('info'); path = 'O12 12 9 M12 11 L12 16.5 M12 7.6 L12 7.8'
        case ('warning'); path = 'M12 3.5 L21.5 20 L2.5 20 Z M12 9.5 L12 14 M12 17 L12 17.2'
        case ('error'); path = 'O12 12 9 M9 9 L15 15 M15 9 L9 15'
        case ('send'); path = 'M21 3 L10.5 13.5 M21 3 L14.5 21 L10.5 13.5 L3 9.5 Z'
        case ('pen'); path = 'M16.5 3.5 L20.5 7.5 L8 20 L3.5 20.5 L4 16 Z M14 6 L18 10'
        case ('eraser'); path = 'M8 20 L20 8 L14.5 2.5 L3 14 L9 20 Z M9 20 L21 20 M8.5 8.5 L14.5 14.5'
        case ('eye')
            path = 'M2 12 L4.5 8.3 L8 5.8 L12 5 L16 5.8 L19.5 8.3 L22 12 L19.5 15.7 L16 18.2 ' // &
                'L12 19 L8 18.2 L4.5 15.7 Z O12 12 3'
        case ('lock'); path = 'M5 11 L19 11 L19 21 L5 21 Z M8 11 L8 7.5 L9.2 4.8 L12 3.5 L14.8 4.8 L16 7.5 L16 11'
        case ('person'); path = 'O12 8 4 M4.5 21 L5.5 17.5 L8 15.3 L12 14.5 L16 15.3 L18.5 17.5 L19.5 21'
        case ('people')
            path = 'O9 8 3.5 M2.5 20 L3.3 17 L5.5 15.2 L9 14.5 L12.5 15.2 L14.7 17 L15.5 20 ' // &
                'M15.5 4.8 L17.5 5.5 L18.5 8 L17.5 10.5 L15.5 11.2 M17.5 14.6 L20 15.8 L21.5 20'
        case ('chat'); path = 'M4 5 L20 5 L20 16 L11 16 L6 20 L6 16 L4 16 Z'
        case ('globe')
            path = 'O12 12 9 M3 12 L21 12 M12 3 L9.5 7 L8.6 12 L9.5 17 L12 21 L14.5 17 L15.4 12 ' // &
                'L14.5 7 Z'
        case ('branch'); path = 'O6 5.5 2.5 O6 18.5 2.5 O18 7 2.5 M6 8 L6 16 M18 9.5 L18 11 L16.8 13 L6 16'
        case ('merge'); path = 'O6 5.5 2.5 O6 18.5 2.5 O18 18.5 2.5 M6 8 L6 16 M6 8 L7.5 12 L11 15.5 L15.5 18.5'
        case ('refresh')
            path = 'M20 5 L20 10 L15 10 M20 10 L18.2 7.2 L15.6 5.3 L12.4 4.5 L9.3 5 L6.6 6.6 ' // &
                'L4.7 9.1 L4 12 L4.5 15.1 L6.1 17.8 L8.6 19.6 L11.6 20.4 L14.7 20 L17.4 18.4 L19.3 16'
        case ('delete'); path = 'M4 6.5 L20 6.5 M9 6.5 L9.5 3.5 L14.5 3.5 L15 6.5 M6 6.5 L7 21 L17 21 L18 6.5 M10 10.5 L10 17 M14 10.5 L14 17'
        case ('settings'); path = 'M4 6 L20 6 M4 12 L20 12 M4 18 L20 18 O9 6 2 O15 12 2 O7 18 2'
        case ('home'); path = 'M3.5 11 L12 3.5 L20.5 11 M6 9 L6 20.5 L18 20.5 L18 9 M10 20.5 L10 14.5 L14 14.5 L14 20.5'
        case ('star')
            path = 'M12 3 L14.6 8.8 L21 9.4 L16.2 13.6 L17.6 20 L12 16.6 L6.4 20 L7.8 13.6 L3 9.4 ' // &
                'L9.4 8.8 Z'
        case ('cube'); path = 'M12 2.5 L20.5 7.2 L20.5 16.8 L12 21.5 L3.5 16.8 L3.5 7.2 Z M3.5 7.2 L12 12 L20.5 7.2 M12 12 L12 21.5'
        case ('gate'); path = 'M3 6 L21 6 M5 10 L19 10 M6 6 L6 21 M18 6 L18 21 M12 6 L12 10'
        case ('translate'); path = 'M3 5 L13 5 M8 3 L8 5 M5 9 L8 13 L11 9 M6 5 L10 15 M12 21 L16.5 11 L21 21 M13.5 18 L19.5 18'
        case default; path = ''
        end select
    end function icon_path

    function icon_glyph(name) result(glyph)
        !! The character a terminal shows for `name`.
        character(*), intent(in) :: name
        character(len=:), allocatable :: glyph
        integer :: k
        glyph = '·'
        do k = 1, N_ICONS
            if (trim(NAMES(k)) == trim(name)) then
                glyph = trim(GLYPHS(k))
                return
            end if
        end do
    end function icon_glyph

    function icon_svg(path) result(d)
        !! The SVG path data of path text (circles as two arcs).
        character(*), intent(in) :: path
        character(len=:), allocatable :: d, tok
        integer :: at
        real :: v(3)
        character :: op
        d = ''
        at = 1
        do
            call next_command(path, at, op, v)
            select case (op)
            case ('M', 'L')
                d = d // op // fmt(v(1)) // ' ' // fmt(v(2)) // ' '
            case ('Z')
                d = d // 'Z '
            case ('O')
                tok = fmt(v(3))
                d = d // 'M' // fmt(v(1) - v(3)) // ' ' // fmt(v(2)) // ' a' // tok // ' ' // tok // &
                    ' 0 1 0 ' // fmt(2 * v(3)) // ' 0 a' // tok // ' ' // tok // ' 0 1 0 ' // &
                    fmt(-2 * v(3)) // ' 0 '
            case default
                exit
            end select
        end do
        d = trim(d)
    end function icon_svg

    subroutine icon_polylines(path, xy, starts, count)
        !! Path text as polylines in box coordinates: polyline k runs through
        !! points starts(k) to starts(k + 1) - 1 of xy(2, :); circles become
        !! 24 segments, and a closed figure repeats its first point.
        character(*), intent(in) :: path
        real, allocatable, intent(out) :: xy(:, :)
        integer, allocatable, intent(out) :: starts(:)
        integer, intent(out) :: count
        integer :: at, n, k, first
        real :: v(3), t
        character :: op
        real, parameter :: TAU = 6.2831853
        allocate (xy(2, 64), starts(17))
        n = 0
        count = 0
        first = 0
        at = 1
        do
            call next_command(path, at, op, v)
            select case (op)
            case ('M')
                call open_line()
                call put(v(1), v(2))
            case ('L')
                if (count == 0) call open_line()
                call put(v(1), v(2))
            case ('Z')
                if (count > 0 .and. n >= first) call put(xy(1, first), xy(2, first))
            case ('O')
                call open_line()
                do k = 0, 24
                    t = TAU * real(k) / 24.0
                    call put(v(1) + v(3) * cos(t), v(2) + v(3) * sin(t))
                end do
            case default
                exit
            end select
        end do
        starts(count + 1) = n + 1

    contains

        subroutine open_line()
            integer, allocatable :: more(:)
            if (count + 1 >= size(starts)) then
                allocate (more(2 * size(starts)))
                more = 0
                more(1:size(starts)) = starts
                call move_alloc(more, starts)
            end if
            count = count + 1
            starts(count) = n + 1
            first = n + 1
        end subroutine open_line

        subroutine put(x, y)
            real, intent(in) :: x, y
            real, allocatable :: bigger(:, :)
            if (n >= size(xy, 2)) then
                allocate (bigger(2, 2 * size(xy, 2)))
                bigger(:, 1:n) = xy(:, 1:n)
                call move_alloc(bigger, xy)
            end if
            n = n + 1
            xy(:, n) = [x, y]
        end subroutine put

    end subroutine icon_polylines

    subroutine next_command(path, at, op, v)
        !! The command at `at` and its numbers; op is ' ' at the end.
        character(*), intent(in) :: path
        integer, intent(inout) :: at
        character, intent(out) :: op
        real, intent(out) :: v(3)
        integer :: k, need
        op = ' '
        v = 0.0
        do while (at <= len(path))
            if (path(at:at) /= ' ') exit
            at = at + 1
        end do
        if (at > len(path)) return
        op = path(at:at)
        at = at + 1
        select case (op)
        case ('M', 'L'); need = 2
        case ('O'); need = 3
        case ('Z'); need = 0
        case default
            op = ' '
            return
        end select
        do k = 1, need
            v(k) = number(path, at)
        end do
    end subroutine next_command

    real function number(s, at) result(v)
        !! The decimal number at `at` ("-12.5"), skipping spaces; `at` moves past it.
        character(*), intent(in) :: s
        integer, intent(inout) :: at
        real :: sign, scale
        v = 0.0
        sign = 1.0
        scale = 0.0
        do while (at <= len(s))
            if (s(at:at) /= ' ') exit
            at = at + 1
        end do
        if (at <= len(s)) then
            if (s(at:at) == '-') then
                sign = -1.0
                at = at + 1
            end if
        end if
        do while (at <= len(s))
            select case (s(at:at))
            case ('0':'9')
                if (scale > 0.0) then
                    v = v + scale * real(iachar(s(at:at)) - 48)
                    scale = scale * 0.1
                else
                    v = 10.0 * v + real(iachar(s(at:at)) - 48)
                end if
            case ('.')
                scale = 0.1
            case default
                exit
            end select
            at = at + 1
        end do
        v = sign * v
    end function number

    function fmt(x) result(s)
        !! A coordinate with at most two decimals, without trailing zeros.
        real, intent(in) :: x
        character(len=:), allocatable :: s
        integer :: c, whole, frac
        character(len=16) :: b
        c = nint(abs(x) * 100.0)
        whole = c / 100
        frac = mod(c, 100)
        write (b, '(i0)') whole
        s = trim(b)
        if (frac /= 0) then
            if (mod(frac, 10) == 0) then
                write (b, '(i0)') frac / 10
            else
                write (b, '(i2.2)') frac
            end if
            s = s // '.' // trim(b)
        end if
        if (x < 0.0 .and. c /= 0) s = '-' // s
    end function fmt

end module fortui_icons
