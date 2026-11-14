module fortui_terminal
    !! The `terminal` widget: a terminal emulator (fortui_term) on a canvas of
    !! character cells, sized to the space it gets. It takes every key while
    !! focused, keeps a scrollback the wheel and Shift+Page Up/Down move
    !! through, selects with the pointer, copies with Ctrl+Shift+C and pastes
    !! with Ctrl+Shift+V, forwards the pointer to programs that ask for mouse
    !! reports, and shows the program's images over their cells.
    use iso_c_binding, only: c_funptr, c_associated
    use iso_fortran_env, only: int32
    use fortui_core, only: ui_scale, ui_waker, ui_wake_after, ui_clipboard_set, &
        ui_clipboard_text, ui_request_frame, ui_open_url, ui_primary_set, ui_primary_text
    use fortui_widgets, only: canvas_begin, canvas_end, canvas_cells, canvas_image, &
        canvas_keys, ui_cell_metrics
    use fortui_canvas, only: canvas_view_t, canvas_events_t
    use fortui_input, only: key_press_t, KEY_NONE, KEY_PAGE_UP, KEY_PAGE_DOWN, MOD_CTRL, MOD_ALT, &
        MOD_SHIFT
    use fortui_frame, only: CELL_UNDERLINE, CELL_CONT, CELL_CURSOR, CELL_BAR
    use fortui_term, only: term_t, term_open, term_pump, term_key, term_paste, term_resize, &
        term_mouse, term_row, CURSOR_BAR, CURSOR_UNDERLINE
    implicit none
    private

    public :: terminal, terminal_view_t, terminal_selection, url_at

    type :: terminal_view_t
        !! What one terminal widget shows: how far it is scrolled back, the
        !! selection (rows counted from the top of the screen, negative in the
        !! scrollback), and whether its program was started.
        integer :: back = 0
        logical :: selected = .false., selecting = .false.
        integer :: anchor(2) = 0, head(2) = 0
        logical :: started = .false.
        logical :: failed = .false.
        integer :: generation = 0
        integer :: cols = 0, rows = 0
        real :: cell_w = 0.0, cell_h = 0.0
        ! The URL under the pointer: line and columns of its start and end
        ! (it may continue on the next line), underlined while hovered.
        logical :: url_shown = .false.
        integer :: url_from(2) = 0, url_to(2) = 0
        ! The cell the pointer was last reported in (motion reports).
        integer :: last_cell(2) = -1
    end type terminal_view_t

contains

    subroutine terminal(id, t, v, font_size, width, height, command, cwd, changed)
        !! Show terminal `t` (started on first use with `command`, default the
        !! user's shell, in `cwd`) with the monospace face at logical
        !! `font_size`.
        !! `changed` reports that the screen changed in this frame.
        character(*), intent(in) :: id
        type(term_t), intent(inout), target :: t
        type(terminal_view_t), intent(inout) :: v
        real, intent(in) :: font_size
        real, intent(in), optional :: width, height
        character(*), intent(in), optional :: command(:), cwd
        logical, intent(out), optional :: changed
        type(canvas_events_t) :: ev
        type(key_press_t), allocatable :: presses(:)
        type(c_funptr) :: wake
        integer(int32), allocatable :: cp(:), fg(:), bg(:), attr(:)
        real :: cw, ch, scale
        integer :: cols, rows, n, k, cwp, chp, r, c
        logical :: ok, moved, behind

        if (present(changed)) changed = .false.
        scale = max(0.25, ui_scale())
        call ui_cell_metrics(font_size, cw, ch)
        cwp = max(1, nint(cw * scale))
        chp = max(1, nint(ch * scale))
        cw = real(cwp) / scale
        ch = real(chp) / scale
        call canvas_begin(id, canvas_view_t(), ev, width, height, fill=opaque(t%default_bg), &
            keyboard=.true.)
        cols = max(2, int(ev%width / cw))
        rows = max(1, int(ev%height / ch))
        v%cols = cols
        v%rows = rows
        v%cell_w = cw
        v%cell_h = ch
        if (.not. v%started) then
            v%started = .true.
            wake = ui_waker()
            if (c_associated(wake)) then
                call term_open(t, rows, cols, cwp, chp, command, cwd, wake, ok)
            else
                call term_open(t, rows, cols, cwp, chp, command, cwd, ok=ok)
            end if
            v%failed = .not. ok
        else
            call term_resize(t, rows, cols, cwp, chp)
        end if

        call canvas_keys(presses, n)
        do k = 1, n
            call key(presses(k))
        end do
        call pointer()

        moved = term_pump(t, more=behind)
        if (t%clipboard_pending) then
            if (t%clipboard_target == "p") then
                call ui_primary_set(t%clipboard_out)
            else
                call ui_clipboard_set(t%clipboard_out)
            end if
            t%clipboard_pending = .false.
        end if
        if (present(changed)) changed = moved
        ! Output still waiting: draw this frame and continue at once. Without a
        ! waker the program's output is fetched on a timer.
        if (behind) then
            call ui_request_frame()
        else if (t%alive .and. .not. c_associated(ui_waker())) then
            call ui_wake_after(1.0 / 60.0)
        else if (.not. t%alive .and. t%pid > 0 .and. t%exit_status < 0) then
            ! The output ended before the program's exit status could be
            ! collected: look again shortly.
            call ui_wake_after(0.05)
        end if
        v%back = max(0, min(v%back, t%sb_count))

        call compose()
        v%generation = modulo(v%generation + 1, 2**30)
        ! Images with a negative z-index lie between the cell backgrounds and the
        ! text (kitty's rule; fortui draws canvas labels over its images so):
        ! backgrounds, those images, the text, then the other images.
        if (any(t%places(1:t%nplaces)%z < 0)) then
            call canvas_cells("cells", v%generation, cols, rows, spread(32_int32, 1, cols * rows), &
                fg, bg, spread(0_int32, 1, cols * rows), 0.0, 0.0, real(cols) * cw, &
                real(rows) * ch, font_size, extend_edges=.true.)
            call images(.true.)
            call canvas_cells("text", v%generation, cols, rows, cp, fg, &
                spread(0_int32, 1, cols * rows), attr, 0.0, 0.0, real(cols) * cw, &
                real(rows) * ch, font_size)
        else
            call canvas_cells("cells", v%generation, cols, rows, cp, fg, bg, attr, 0.0, 0.0, &
                real(cols) * cw, real(rows) * ch, font_size, extend_edges=.true.)
        end if
        call images(.false.)
        call canvas_end()
    contains
        subroutine images(below)
            !! The visible images below the text (z < 0) or above it.
            logical, intent(in) :: below
            integer :: j, rr
            do j = 1, t%nplaces
                associate(p => t%places(j))
                    if ((p%z < 0) .neqv. below) cycle
                    rr = p%row + v%back
                    if (rr + p%rows <= 0 .or. rr >= rows) cycle
                    if (.not. allocated(t%images(p%image)%rgba)) cycle
                    call canvas_image("image" // itoa(p%serial), &
                        t%images(p%image)%generation, t%images(p%image)%rgba, &
                        real(p%col) * cw, real(rr) * ch, real(p%cols) * cw, real(p%rows) * ch)
                end associate
            end do
        end subroutine images

        subroutine key(p)
            type(key_press_t), intent(in) :: p
            if (iand(p%mods, MOD_CTRL + MOD_SHIFT) == MOD_CTRL + MOD_SHIFT .and. &
                p%key == KEY_NONE) then
                select case (achar(p%code))
                case ("c", "C")
                    if (v%selected) call ui_clipboard_set(terminal_selection(t, v))
                case ("v", "V")
                    call term_paste(t, ui_clipboard_text())
                    v%back = 0
                end select
                return
            end if
            if (iand(p%mods, MOD_SHIFT) /= 0 .and. iand(p%mods, MOD_CTRL) == 0) then
                if (p%key == KEY_PAGE_UP) then
                    v%back = v%back + max(1, rows - 1)
                    return
                else if (p%key == KEY_PAGE_DOWN) then
                    v%back = max(0, v%back - max(1, rows - 1))
                    return
                end if
            end if
            call term_key(t, p)
            v%back = 0
            v%selected = .false.
        end subroutine key

        subroutine pointer()
            !! Pointer: URLs (underlined, Ctrl+click opens), reports to a program
            !! that takes the mouse (Shift keeps selecting in the terminal, as in
            !! xterm and VTE), else selection, scrollback and middle-click paste.
            integer :: row, col, steps, i, m
            character(len=:), allocatable :: url
            v%url_shown = .false.
            if (.not. ev%hovered .and. .not. ev%captured .and. .not. ev%released) return
            col = max(0, min(cols - 1, int(ev%local_x / cw)))
            row = max(0, min(rows - 1, int(ev%local_y / ch)))
            if (ev%hovered) then
                call url_at(t, row - v%back, col, url, v%url_from, v%url_to)
                v%url_shown = len(url) > 0
                if (v%url_shown .and. ev%pressed .and. iand(ev%mods, MOD_CTRL) /= 0) then
                    call ui_open_url(url)
                    return
                end if
            end if
            m = iand(ev%mods, MOD_CTRL + MOD_ALT)
            if (t%mouse_mode > 0 .and. v%back == 0 .and. iand(ev%mods, MOD_SHIFT) == 0) then
                if (ev%pressed) call term_mouse(t, row, col, 1, .true., .false., m)
                if (ev%released) call term_mouse(t, row, col, 1, .false., .false., m)
                if (ev%middle_pressed) call term_mouse(t, row, col, 2, .true., .false., m)
                if (ev%middle_released) call term_mouse(t, row, col, 2, .false., .false., m)
                if (any([row, col] /= v%last_cell)) then
                    ! Motion: with the button held (1002, 1003), or any (1003,
                    ! which tmux's focus-follows-mouse needs).
                    if (ev%captured) then
                        call term_mouse(t, row, col, 1, .true., .true., m)
                    else if (t%mouse_mode == 1003) then
                        call term_mouse(t, row, col, 0, .false., .true., m)
                    end if
                end if
                v%last_cell = [row, col]
                if (ev%wheel /= 0.0) then
                    do i = 1, max(1, nint(abs(ev%wheel)))
                        call term_mouse(t, row, col, merge(4, 5, ev%wheel > 0.0), .true., &
                            .false., m)
                    end do
                end if
                return
            end if
            v%last_cell = [row, col]
            if (ev%middle_pressed) then
                ! X11: middle-click pastes the primary selection.
                call term_paste(t, ui_primary_text())
                v%back = 0
            end if
            if (ev%wheel /= 0.0) then
                steps = nint(3.0 * ev%wheel)
                if (steps == 0) steps = merge(1, -1, ev%wheel > 0.0)
                v%back = max(0, min(t%sb_count, v%back + steps))
            end if
            if (ev%pressed) then
                v%anchor = [row - v%back, col]
                v%head = v%anchor
                v%selecting = .true.
                v%selected = .false.
            else if (ev%dragging .and. v%selecting) then
                v%head = [row - v%back, col]
                v%selected = any(v%head /= v%anchor)
            end if
            if (ev%released .and. v%selecting) then
                v%selecting = .false.
                ! The selection becomes the primary selection, as in X11.
                if (v%selected) call ui_primary_set(terminal_selection(t, v))
            end if
            if (ev%double_clicked) v%selected = .false.
        end subroutine pointer

        subroutine compose()
            !! The visible cells: screen rows, or scrollback rows above them,
            !! with the cursor and the selection drawn in.
            integer :: line, i, kk, lo(2), hi(2), w
            allocate(cp(cols * rows), fg(cols * rows), bg(cols * rows), attr(cols * rows))
            cp = 32
            fg = t%default_fg
            bg = 0
            attr = 0
            do r = 0, rows - 1
                line = r - v%back
                i = r * cols
                if (line >= 0) then
                    if (.not. allocated(t%cp) .or. line >= t%rows) cycle
                    w = min(cols, t%cols)
                    cp(i + 1:i + w) = t%cp(line * t%cols + 1:line * t%cols + w)
                    fg(i + 1:i + w) = t%fg(line * t%cols + 1:line * t%cols + w)
                    bg(i + 1:i + w) = t%bg(line * t%cols + 1:line * t%cols + w)
                    attr(i + 1:i + w) = t%attr(line * t%cols + 1:line * t%cols + w)
                else if (-line <= t%sb_count) then
                    w = min(cols, t%cols)
                    call term_row(t, line, cp(i + 1:i + w), fg(i + 1:i + w), bg(i + 1:i + w), &
                        attr(i + 1:i + w))
                end if
            end do
            if (v%failed) call message("The terminal could not start a program.")
            if (.not. t%alive .and. v%started .and. .not. v%failed .and. t%exit_status >= 0) &
                call message("[process exited " // itoa(t%exit_status) // "]")
            if (v%selected) then
                call ordered(v%anchor, v%head, lo, hi)
                do r = 0, rows - 1
                    line = r - v%back
                    if (line < lo(1) .or. line > hi(1)) cycle
                    do c = 0, cols - 1
                        if (line == lo(1) .and. c < lo(2)) cycle
                        if (line == hi(1) .and. c > hi(2)) cycle
                        i = r * cols + c + 1
                        call invert(i)
                    end do
                end do
            end if
            if (v%url_shown) then
                do r = 0, rows - 1
                    line = r - v%back
                    if (line < v%url_from(1) .or. line > v%url_to(1)) cycle
                    do c = 0, cols - 1
                        if (line == v%url_from(1) .and. c < v%url_from(2)) cycle
                        if (line == v%url_to(1) .and. c > v%url_to(2)) cycle
                        attr(r * cols + c + 1) = ior(attr(r * cols + c + 1), CELL_UNDERLINE)
                    end do
                end do
            end if
            if (t%alive .and. t%cursor_visible .and. v%back == 0 .and. &
                t%cursor_row < rows .and. t%cursor_col < cols) then
                i = t%cursor_row * cols + t%cursor_col + 1
                attr(i) = ior(attr(i), CELL_CURSOR)
                if (.not. ev%focused) then
                    attr(i) = ior(attr(i), CELL_UNDERLINE)
                else if (t%cursor_shape == CURSOR_BAR) then
                    attr(i) = ior(attr(i), CELL_BAR)
                    if (t%cursor_color /= 0) fg(i) = t%cursor_color
                else if (t%cursor_shape == CURSOR_UNDERLINE) then
                    attr(i) = ior(attr(i), CELL_UNDERLINE)
                    if (t%cursor_color /= 0) fg(i) = t%cursor_color
                else
                    ! A block in the cursor colour (else the text colour), its
                    ! character in whichever of the cell's background and the
                    ! default colours stands out most against the block (a
                    ! reverse-video cell, such as readline's search match, would
                    ! otherwise come out grey on grey).
                    call invert(i)
                    if (t%cursor_color /= 0) bg(i) = opaque(t%cursor_color)
                    fg(i) = contrasting(bg(i), [fg(i), opaque(t%default_bg), &
                        opaque(t%default_fg)])
                end if
            end if
        end subroutine compose

        subroutine invert(i)
            integer, intent(in) :: i
            integer(int32) :: tmp
            tmp = fg(i)
            fg(i) = opaque(merge(t%default_bg, bg(i), iand(ishft(bg(i), -24), 255_int32) == 0))
            bg(i) = tmp
        end subroutine invert

        subroutine message(text)
            character(*), intent(in) :: text
            integer :: j, row
            row = min(rows - 1, max(t%cursor_row + 1, 0))
            if (v%failed) row = 0
            do j = 1, min(len(text), cols)
                cp(row * cols + j) = iachar(text(j:j))
                fg(row * cols + j) = t%default_fg
                attr(row * cols + j) = 0
            end do
        end subroutine message
    end subroutine terminal

    function terminal_selection(t, v) result(text)
        !! The selected text, lines joined by newlines, trailing blanks dropped.
        type(term_t), intent(in) :: t
        type(terminal_view_t), intent(in) :: v
        character(len=:), allocatable :: text, line_text
        integer :: lo(2), hi(2), line, c, c0, c1, cpv, k
        integer(int32) :: rcp(t%cols), rfg(t%cols), rbg(t%cols), rattr(t%cols)
        text = ""
        if (.not. v%selected) return
        call ordered(v%anchor, v%head, lo, hi)
        do line = lo(1), hi(1)
            c0 = 0
            c1 = t%cols - 1
            if (line == lo(1)) c0 = lo(2)
            if (line == hi(1)) c1 = hi(2)
            line_text = ""
            if (line < 0) call term_row(t, line, rcp, rfg, rbg, rattr)
            do c = c0, c1
                cpv = 32
                if (line >= 0 .and. line < t%rows) then
                    k = line * t%cols + c + 1
                    if (iand(t%attr(k), CELL_CONT) /= 0) cycle
                    cpv = t%cp(k)
                else if (line < 0 .and. -line <= t%sb_count) then
                    if (iand(rattr(c + 1), CELL_CONT) /= 0) cycle
                    cpv = rcp(c + 1)
                end if
                line_text = line_text // utf8(cpv)
            end do
            text = text // trim(line_text)
            if (line < hi(1)) text = text // new_line("a")
        end do
    end function terminal_selection

    subroutine url_at(t, line, col, url, from, to)
        !! The URL through cell (line, col): a run of URL characters starting
        !! with a scheme (http, https, ftp, file, mailto) or "www.", carried
        !! on to the next line when it reaches the last column; trailing
        !! punctuation and an unmatched closing parenthesis are not part of
        !! it. `url` is "" when there is none.
        type(term_t), intent(in) :: t
        integer, intent(in) :: line, col
        character(len=:), allocatable, intent(out) :: url
        integer, intent(out) :: from(2), to(2)
        integer(int32) :: cp(t%cols), fg(t%cols), bg(t%cols), attr(t%cols)
        character(len=:), allocatable :: s, nxt
        integer :: a, b, k, start, n, cut, opened
        character(len=*), parameter :: SCHEMES(6) = [character(len=8) :: "https://", &
            "http://", "ftp://", "file://", "mailto:", "www."]
        character(len=*), parameter :: TRAILING = ".,;:!?'" // achar(34)
        url = ""
        from = 0
        to = 0
        call term_row(t, line, cp, fg, bg, attr)
        s = ascii(cp)
        if (col + 1 > len(s)) return
        if (.not. url_char(s(col + 1:col + 1))) return
        a = col + 1
        do while (a > 1)
            if (.not. url_char(s(a - 1:a - 1))) exit
            a = a - 1
        end do
        b = col + 1
        do while (b < len(s))
            if (.not. url_char(s(b + 1:b + 1))) exit
            b = b + 1
        end do
        start = 0
        do k = 1, size(SCHEMES)
            n = index(s(a:b), trim(SCHEMES(k)))
            if (n > 0 .and. (start == 0 .or. a + n - 1 < start)) start = a + n - 1
        end do
        if (start == 0 .or. start > col + 1) return
        url = s(start:b)
        from = [line, start - 1]
        to = [line, b - 1]
        ! Wrapped onto the next line.
        if (b == t%cols .and. line + 1 < t%rows) then
            call term_row(t, line + 1, cp, fg, bg, attr)
            nxt = ascii(cp)
            n = 0
            do while (n < len(nxt))
                if (.not. url_char(nxt(n + 1:n + 1))) exit
                n = n + 1
            end do
            if (n > 0) then
                url = url // nxt(1:n)
                to = [line + 1, n - 1]
            end if
        end if
        ! Trailing punctuation, and ")" without its "(".
        do
            cut = len(url)
            if (cut == 0) exit
            if (index(TRAILING, url(cut:cut)) > 0) then
                url = url(1:cut - 1)
            else if (url(cut:cut) == ")") then
                opened = count([(url(k:k) == "(", k = 1, cut)]) - &
                    count([(url(k:k) == ")", k = 1, cut)])
                if (opened >= 0) exit
                url = url(1:cut - 1)
            else
                exit
            end if
            if (to(2) > 0) then
                to(2) = to(2) - 1
            else if (to(1) > from(1)) then
                to = [from(1), t%cols - 1]
            end if
        end do
        if (len(url) < 8) then
            if (url(1:min(4, len(url))) /= "www.") url = ""
        end if
        if (len(url) >= 4) then
            if (url(1:4) == "www.") url = "https://" // url
        end if
    contains
        pure logical function url_char(c)
            character, intent(in) :: c
            url_char = index("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789" // &
                "-._~:/?#[]@!$&'()*+,;=%", c) > 0
        end function url_char
        pure function ascii(cells) result(text)
            integer(int32), intent(in) :: cells(:)
            character(len=size(cells)) :: text
            integer :: j
            do j = 1, size(cells)
                if (cells(j) > 32 .and. cells(j) < 127) then
                    text(j:j) = achar(cells(j))
                else
                    text(j:j) = " "
                end if
            end do
        end function ascii
    end subroutine url_at

    pure subroutine ordered(a, b, lo, hi)
        integer, intent(in) :: a(2), b(2)
        integer, intent(out) :: lo(2), hi(2)
        if (a(1) < b(1) .or. (a(1) == b(1) .and. a(2) <= b(2))) then
            lo = a
            hi = b
        else
            lo = b
            hi = a
        end if
    end subroutine ordered

    pure integer(int32) function contrasting(block, choices) result(best)
        !! The colour in `choices` farthest in luminance from `block`.
        integer(int32), intent(in) :: block, choices(:)
        real :: d, dmax
        integer :: k
        best = choices(1)
        dmax = -1.0
        do k = 1, size(choices)
            d = abs(luma(choices(k)) - luma(block))
            if (d > dmax + 1.0) then
                dmax = d
                best = choices(k)
            end if
        end do
    end function contrasting

    pure real function luma(rgba)
        integer(int32), intent(in) :: rgba
        luma = 0.2126 * real(iand(rgba, 255_int32)) + 0.7152 * &
            real(iand(ishft(rgba, -8), 255_int32)) + 0.0722 * real(iand(ishft(rgba, -16), 255_int32))
    end function luma

    pure integer(int32) function opaque(rgba)
        integer(int32), intent(in) :: rgba
        opaque = ior(iand(rgba, int(z'00FFFFFF', int32)), ishft(-1_int32, 24))
    end function opaque

    pure function utf8(cp) result(s)
        integer(int32), intent(in) :: cp
        character(len=:), allocatable :: s
        integer :: c
        c = int(cp)
        if (c < 128) then
            s = achar(c)
        else if (c < 2048) then
            s = achar(ior(192, ishft(c, -6))) // achar(ior(128, iand(c, 63)))
        else if (c < 65536) then
            s = achar(ior(224, ishft(c, -12))) // achar(ior(128, iand(ishft(c, -6), 63))) // &
                achar(ior(128, iand(c, 63)))
        else
            s = achar(ior(240, ishft(c, -18))) // achar(ior(128, iand(ishft(c, -12), 63))) // &
                achar(ior(128, iand(ishft(c, -6), 63))) // achar(ior(128, iand(c, 63)))
        end if
    end function utf8

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: buf
        write (buf, '(i0)') i
        s = trim(buf)
    end function itoa

end module fortui_terminal
