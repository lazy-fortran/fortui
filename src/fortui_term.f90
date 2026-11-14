module fortui_term
    !! Terminal emulator: a program on a pseudo-terminal, its screen kept by
    !! the Fortran engine fortui_vt, with scrollback, the window title, and
    !! images from the kitty graphics protocol and from sixel strings anchored
    !! to the cells they cover. A reader thread drains the program's output
    !! into a ring buffer, so the program never waits while the host draws.
    !! Built with -DENABLE_TERM=1 (POSIX pseudo-terminals); without it
    !! term_open reports that terminals are unavailable.
    use iso_c_binding
    use iso_fortran_env, only: int8, int32, int64
    use fortui_error, only: report_error
    use fortui_input, only: key_press_t, KEY_NONE, KEY_ENTER, KEY_ESCAPE, KEY_TAB, &
        KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, &
        KEY_ARROW_UP, KEY_ARROW_DOWN, KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_SPACE, KEY_INSERT, &
        KEY_F1, KEY_F12, MOD_CTRL, MOD_ALT, MOD_SHIFT
    use fortui_inflate, only: zlib_decompress, png_decode, base64_decode
    use fortui_sixel, only: sixel_decode
    use fortui_vt, only: vt_t, vt_open, vt_resize, vt_feed, vt_line, vt_key, vt_paste, &
        vt_mouse, vt_take_output, vt_set_colors, VT_EV_NONE, VT_EV_OSC, VT_EV_DCS, VT_EV_APC
    implicit none
    private

    public :: term_t, term_image_t, term_place_t
    public :: term_open, term_close, term_pump, term_key, term_paste, term_resize, term_write
    public :: term_available, term_set_colors, term_mouse, term_row
    integer, parameter, public :: CURSOR_BLOCK = 1, CURSOR_BAR = 2, CURSOR_UNDERLINE = 3

    integer, parameter :: MAX_IMAGES = 64, MAX_PLACES = 256

    type :: term_image_t
        integer :: id = 0
        integer :: width = 0, height = 0
        ! Changes whenever new pixels arrive under this slot.
        integer :: generation = 0
        integer(int32), allocatable :: rgba(:, :)
    end type term_image_t

    type :: term_place_t
        !! An image shown from `row` (screen row, negative once in the
        !! scrollback) and `col` over `rows` x `cols` cells.
        integer :: image = 0
        integer :: row = 0, col = 0, rows = 1, cols = 1
        integer :: z = 0
        integer :: serial = 0
    end type term_place_t

    type :: term_t
        type(vt_t) :: vt
        type(c_ptr) :: watch = c_null_ptr
        integer :: fd = -1, pid = -1
        integer :: rows = 24, cols = 80, cell_px_w = 8, cell_px_h = 16
        logical :: alive = .false.
        integer :: exit_status = -1
        logical :: bell = .false.
        integer :: generation = 0
        character(len=:), allocatable :: title
        integer :: cursor_row = 0, cursor_col = 0
        logical :: cursor_visible = .true.
        logical :: altscreen = .false.
        ! Mouse reporting the program asked for (0 = none).
        integer :: mouse_mode = 0
        integer(int32) :: default_fg = int(z'FFD4D4D4', int32)
        integer(int32) :: default_bg = int(z'FF000000', int32)
        ! The 16 ANSI colours (ui_rgba) when `own_palette`, else xterm's.
        integer(int32) :: palette(16) = 0
        logical :: own_palette = .false.
        ! Bold text in the first eight colours shows the bright eight, as VTE
        ! and xterm do by default (ls draws directories in bold blue).
        logical :: bold_bright = .true.
        ! Cursor colour (ui_rgba; 0: the text colour) and shape (CURSOR_*);
        ! a program's DECSCUSR overrides the shape until it resets it.
        integer(int32) :: cursor_color = 0
        integer :: cursor_shape = CURSOR_BLOCK
        ! The screen, row by row from the top (ui_rgba colours, CELL_* bits).
        integer(int32), allocatable :: cp(:), fg(:), bg(:), attr(:)
        integer :: sb_count = 0
        ! Images and where they are shown.
        type(term_image_t) :: images(MAX_IMAGES)
        type(term_place_t), allocatable :: places(:)
        integer :: nplaces = 0, place_serial = 0, image_serial = 0
        ! Cursor motion owed after an image.
        character(len=:), allocatable :: motion
        ! Kitty transmission in chunks (m=1).
        character(len=:), allocatable :: chunk_keys, chunk_data
        logical :: chunking = .false.
        logical :: dirty = .true.
        character(kind=c_char, len=:), allocatable :: buf
        ! Text a program put on the clipboard (OSC 52; "c" clipboard, "p"
        ! primary) for the host to hand to the desktop.
        character(len=:), allocatable :: clipboard_out
        character :: clipboard_target = "c"
        logical :: clipboard_pending = .false.
        ! When synchronized output began (the screen shown waits for its end).
        integer(int64) :: sync_since = 0
    end type term_t

#ifdef ENABLE_TERM
    interface
        integer(c_int) function fortui_pty_spawn(args, nargs, cwd, rows, cols, xpix, ypix, &
                pid) bind(C, name="fortui_pty_spawn")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: args(*), cwd(*)
            integer(c_int), value :: nargs, rows, cols, xpix, ypix
            integer(c_int), intent(out) :: pid
        end function
        integer(c_int) function fortui_pty_resize(fd, rows, cols, xpix, ypix) &
                bind(C, name="fortui_pty_resize")
            import :: c_int
            integer(c_int), value :: fd, rows, cols, xpix, ypix
        end function
        integer(c_int) function fortui_pty_exited(pid) bind(C, name="fortui_pty_exited")
            import :: c_int
            integer(c_int), value :: pid
        end function
        type(c_ptr) function fortui_pty_watch(fd, wake) bind(C, name="fortui_pty_watch")
            import :: c_ptr, c_int, c_funptr
            integer(c_int), value :: fd
            type(c_funptr), value :: wake
        end function
        integer(c_long) function fortui_pty_take(w, dst, max) bind(C, name="fortui_pty_take")
            import :: c_ptr, c_long, c_char
            type(c_ptr), value :: w
            character(kind=c_char), intent(out) :: dst(*)
            integer(c_long), value :: max
        end function
        subroutine fortui_pty_rearm(w) bind(C, name="fortui_pty_rearm")
            import :: c_ptr
            type(c_ptr), value :: w
        end subroutine
        subroutine fortui_pty_unwatch(w) bind(C, name="fortui_pty_unwatch")
            import :: c_ptr
            type(c_ptr), value :: w
        end subroutine
        integer(c_long) function c_read(fd, buf, n) bind(C, name="read")
            import :: c_int, c_long, c_size_t, c_char
            integer(c_int), value :: fd
            character(kind=c_char), intent(out) :: buf(*)
            integer(c_size_t), value :: n
        end function
        integer(c_long) function c_write(fd, buf, n) bind(C, name="write")
            import :: c_int, c_long, c_size_t, c_ptr
            integer(c_int), value :: fd
            type(c_ptr), value :: buf
            integer(c_size_t), value :: n
        end function
        integer(c_int) function c_close(fd) bind(C, name="close")
            import :: c_int
            integer(c_int), value :: fd
        end function
        integer(c_int) function c_poll(fds, n, timeout) bind(C, name="poll")
            import :: c_int, c_long
            integer(c_int), intent(inout) :: fds(2)
            integer(c_long), value :: n
            integer(c_int), value :: timeout
        end function
        integer(c_int) function c_kill(pid, sig) bind(C, name="kill")
            import :: c_int
            integer(c_int), value :: pid, sig
        end function
    end interface
#endif

contains

    logical function term_available()
        !! Whether this build has the terminal emulator.
#ifdef ENABLE_TERM
        term_available = .true.
#else
        term_available = .false.
#endif
    end function term_available

    subroutine term_open(t, rows, cols, cell_px_w, cell_px_h, command, cwd, wake, ok)
        !! Start `command` (default: the user's shell) on a terminal of rows x
        !! cols cells, each cell_px_w x cell_px_h pixels (for programs that size
        !! images). With `wake` a reader thread takes the program's output and
        !! calls it (from that thread) when output arrives, so that a host
        !! sleeping in its event loop wakes; without it term_pump reads.
        type(term_t), intent(inout), target :: t
        integer, intent(in) :: rows, cols, cell_px_w, cell_px_h
        character(*), intent(in), optional :: command(:), cwd
        type(c_funptr), intent(in), optional :: wake
        logical, intent(out) :: ok
#ifdef ENABLE_TERM
        character(len=:), allocatable :: args, dir
        character(len=512) :: shell
        integer :: n, st, k
        integer(c_int) :: pid

        ok = .false.
        call term_close(t)
        t%rows = max(1, rows)
        t%cols = max(1, cols)
        t%cell_px_w = max(1, cell_px_w)
        t%cell_px_h = max(1, cell_px_h)
        n = 0
        if (present(command)) n = size(command)
        if (n > 0) then
            args = ""
            do k = 1, n
                args = args // trim(command(k)) // c_null_char
            end do
        else
            call get_environment_variable("SHELL", shell, status=st)
            if (st /= 0 .or. len_trim(shell) == 0) shell = "/bin/sh"
            args = trim(shell) // c_null_char
            n = 1
        end if
        dir = ""
        if (present(cwd)) dir = cwd
        t%vt%bold_bright = t%bold_bright
        call vt_open(t%vt, t%rows, t%cols)
        t%vt%cell_px_w = t%cell_px_w
        t%vt%cell_px_h = t%cell_px_h
        if (t%own_palette) then
            call vt_set_colors(t%vt, t%default_fg, t%default_bg, t%palette)
        else
            call vt_set_colors(t%vt, t%default_fg, t%default_bg)
        end if
        if (allocated(t%places)) deallocate(t%places)
        allocate(t%places(32))
        t%nplaces = 0
        t%sb_count = 0
        t%cursor_row = 0
        t%cursor_col = 0
        t%cursor_visible = .true.
        t%altscreen = .false.
        t%mouse_mode = 0
        t%bell = .false.
        t%chunking = .false.
        t%title = ""
        t%motion = ""
        t%chunk_keys = ""
        t%chunk_data = ""
        if (.not. allocated(t%buf)) allocate(character(kind=c_char, len=262144) :: t%buf)
        call snapshot(t)
        t%fd = fortui_pty_spawn(args, int(n, c_int), dir // c_null_char, int(t%rows, c_int), &
            int(t%cols, c_int), int(t%cols * t%cell_px_w, c_int), &
            int(t%rows * t%cell_px_h, c_int), pid)
        if (t%fd < 0) then
            call report_error("fortui_term", "term_open", "cannot start '" // &
                args(1:index(args, c_null_char) - 1) // "'")
            return
        end if
        t%pid = pid
        t%alive = .true.
        t%exit_status = -1
        if (present(wake)) then
            if (c_associated(wake)) t%watch = fortui_pty_watch(int(t%fd, c_int), wake)
        end if
        ok = .true.
#else
        ok = .false.
        if (present(command) .or. present(cwd) .or. present(wake)) continue
        t%rows = rows
        t%cols = cols
        t%cell_px_w = cell_px_w
        t%cell_px_h = cell_px_h
        call report_error("fortui_term", "term_open", &
            "built without the terminal emulator (-DENABLE_TERM=1)")
#endif
    end subroutine term_open

    subroutine term_close(t)
        !! End the program (SIGHUP, as when a terminal window closes).
        type(term_t), intent(inout) :: t
#ifdef ENABLE_TERM
        integer :: st
        if (c_associated(t%watch)) call fortui_pty_unwatch(t%watch)
        t%watch = c_null_ptr
        if (t%pid > 0 .and. t%alive) st = c_kill(int(t%pid, c_int), 1_c_int)
        if (t%fd >= 0) st = c_close(int(t%fd, c_int))
        if (t%pid > 0 .and. t%exit_status < 0) st = fortui_pty_exited(int(t%pid, c_int))
#endif
        t%fd = -1
        t%pid = -1
        t%alive = .false.
        t%nplaces = 0
    end subroutine term_close

    subroutine term_set_colors(t, fg, bg, palette)
        !! Default foreground and background (ui_rgba) and optionally the 16
        !! ANSI colours.
        type(term_t), intent(inout) :: t
        integer(int32), intent(in) :: fg, bg
        integer(int32), intent(in), optional :: palette(16)
        t%default_fg = fg
        t%default_bg = bg
        if (present(palette)) then
            t%palette = palette
            t%own_palette = .true.
            call vt_set_colors(t%vt, fg, bg, palette)
        else
            call vt_set_colors(t%vt, fg, bg)
        end if
        t%dirty = .true.
    end subroutine term_set_colors

    logical function term_pump(t, budget_ms, more) result(changed)
        !! Process the program's output for at most `budget_ms` milliseconds
        !! (default 25) and update the screen; `more` tells that output is
        !! still waiting (draw, then pump again without sleeping). True when
        !! the screen, cursor or title changed.
        type(term_t), intent(inout), target :: t
        real, intent(in), optional :: budget_ms
        logical, intent(out), optional :: more
#ifdef ENABLE_TERM
        integer(c_int) :: fds(2)
        integer(c_long) :: got
        integer(int64) :: t0, now, rate
        real :: budget
        integer :: st
        logical :: waiting

        changed = .false.
        waiting = .false.
        if (present(more)) more = .false.
        if (t%fd < 0 .and. .not. c_associated(t%watch)) return
        budget = 25.0
        if (present(budget_ms)) budget = budget_ms
        call system_clock(t0, rate)
        do while (t%alive)
            if (c_associated(t%watch)) then
                got = fortui_pty_take(t%watch, t%buf, int(len(t%buf), c_long))
                if (got == 0) then
                    call fortui_pty_rearm(t%watch)
                    got = fortui_pty_take(t%watch, t%buf, int(len(t%buf), c_long))
                    if (got == 0) exit
                end if
            else
                fds(1) = int(t%fd, c_int)
                fds(2) = 1_c_int ! POLLIN in the low half of the events/revents pair
                if (c_poll(fds, 1_c_long, 0_c_int) <= 0) exit
                got = c_read(int(t%fd, c_int), t%buf, int(len(t%buf), c_size_t))
                if (got == 0) got = -1
            end if
            if (got < 0) then
                ! The program and everything it started have ended.
                t%alive = .false.
                exit
            end if
            call feed(t, t%buf(1:int(got)))
            changed = .true.
            call system_clock(now)
            if (real(now - t0) * 1000.0 / real(rate) > budget) then
                waiting = .true.
                exit
            end if
        end do
        if (.not. t%alive .and. t%pid > 0 .and. t%exit_status < 0) then
            st = fortui_pty_exited(int(t%pid, c_int))
            if (st >= 0) t%exit_status = st
            changed = .true.
        end if
        ! During synchronized output the last complete frame stays (at most
        ! 150 ms, as other terminals do, in case the end never comes).
        if (t%vt%sync) then
            call system_clock(now, rate)
            if (t%sync_since == 0) t%sync_since = now
            if (real(now - t%sync_since) / real(rate) < 0.15) then
                if (present(more)) more = waiting .or. changed
                return
            end if
        end if
        t%sync_since = 0
        if (changed .or. t%dirty) then
            call snapshot(t)
            t%generation = modulo(t%generation + 1, 2**30)
            changed = .true.
            t%dirty = .false.
        end if
        if (present(more)) more = waiting
#else
        changed = .false.
        if (present(budget_ms) .and. present(more)) more = .false.
        if (t%alive) continue
#endif
    end function term_pump

    subroutine term_row(t, row, cp, fg, bg, attr)
        !! Cells of screen row `row` (negative: the scrollback, -1 the newest
        !! line), t%cols of them.
        type(term_t), intent(in) :: t
        integer, intent(in) :: row
        integer(int32), intent(out) :: cp(:), fg(:), bg(:), attr(:)
        integer :: line, w
        cp = 32
        fg = t%default_fg
        bg = 0
        attr = 0
        if (.not. allocated(t%vt%cp)) return
        if (row >= t%vt%rows .or. row < -t%vt%sb_count) return
        w = min(size(cp), t%vt%cols)
        line = vt_line(t%vt, row)
        if (t%vt%alt .and. row >= 0) then
            cp(1:w) = t%vt%acp(1:w, line)
            fg(1:w) = t%vt%afg(1:w, line)
            bg(1:w) = t%vt%abg(1:w, line)
            attr(1:w) = t%vt%aattr(1:w, line)
        else
            cp(1:w) = t%vt%cp(1:w, line)
            fg(1:w) = t%vt%fg(1:w, line)
            bg(1:w) = t%vt%bg(1:w, line)
            attr(1:w) = t%vt%attr(1:w, line)
        end if
    end subroutine term_row

    subroutine term_key(t, press)
        !! A key press as xterm sends it to the program.
        type(term_t), intent(inout) :: t
        type(key_press_t), intent(in) :: press
        integer :: k
        logical :: sh, al, ct
        sh = iand(press%mods, MOD_SHIFT) /= 0
        al = iand(press%mods, MOD_ALT) /= 0
        ct = iand(press%mods, MOD_CTRL) /= 0
        select case (press%key)
        case (KEY_NONE)
            if (press%code <= 0) return
            call vt_key(t%vt, 0, press%code, sh, al, ct)
            call flush_output(t)
            return
        case (KEY_SPACE)
            call vt_key(t%vt, 0, 32, sh, al, ct)
            call flush_output(t)
            return
        case (KEY_ENTER); k = 1
        case (KEY_TAB); k = 2
        case (KEY_BACKSPACE); k = 3
        case (KEY_ESCAPE); k = 4
        case (KEY_ARROW_UP); k = 5
        case (KEY_ARROW_DOWN); k = 6
        case (KEY_ARROW_LEFT); k = 7
        case (KEY_ARROW_RIGHT); k = 8
        case (KEY_INSERT); k = 9
        case (KEY_DELETE); k = 10
        case (KEY_HOME); k = 11
        case (KEY_END); k = 12
        case (KEY_PAGE_UP); k = 13
        case (KEY_PAGE_DOWN); k = 14
        case (KEY_F1:KEY_F12); k = 101 + press%key - KEY_F1
        case default; return
        end select
        call vt_key(t%vt, k, 0, sh, al, ct)
        call flush_output(t)
    end subroutine term_key

    subroutine term_paste(t, text)
        !! Pasted text, bracketed when the program asked for that.
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: text
        call vt_paste(t%vt, text)
        call flush_output(t)
    end subroutine term_paste

    subroutine term_mouse(t, row, col, button, pressed, moved, mods)
        !! Pointer events for a program that asked for mouse reports (button
        !! 1-3, 4/5 for the wheel; `moved` for motion only).
        type(term_t), intent(inout) :: t
        integer, intent(in) :: row, col, button, mods
        logical, intent(in) :: pressed, moved
        integer :: b
        b = button - 1
        if (button >= 4) b = 64 + button - 4
        call vt_mouse(t%vt, row, col, b, pressed, moved, iand(mods, MOD_SHIFT) /= 0, &
            iand(mods, MOD_ALT) /= 0, iand(mods, MOD_CTRL) /= 0)
        call flush_output(t)
    end subroutine term_mouse

    subroutine term_write(t, bytes)
        !! Bytes to the program as if typed.
        type(term_t), intent(inout) :: t
        character(*), intent(in), target :: bytes
#ifdef ENABLE_TERM
        call write_all(t%fd, bytes)
#else
        if (len(bytes) > 0 .or. t%alive) continue
#endif
    end subroutine term_write

    subroutine term_resize(t, rows, cols, cell_px_w, cell_px_h)
        !! New size in cells (and pixels per cell); the program gets SIGWINCH.
        type(term_t), intent(inout) :: t
        integer, intent(in) :: rows, cols, cell_px_w, cell_px_h
#ifdef ENABLE_TERM
        integer :: st, before
        if (rows == t%rows .and. cols == t%cols .and. cell_px_w == t%cell_px_w .and. &
            cell_px_h == t%cell_px_h) return
        t%cell_px_w = max(1, cell_px_w)
        t%cell_px_h = max(1, cell_px_h)
        t%vt%cell_px_w = t%cell_px_w
        t%vt%cell_px_h = t%cell_px_h
        if (rows /= t%rows .or. cols /= t%cols) then
            t%rows = max(1, rows)
            t%cols = max(1, cols)
            before = t%vt%scrolled
            if (allocated(t%vt%cp)) call vt_resize(t%vt, t%rows, t%cols)
            call follow_scroll(t)
            call snapshot(t)
        end if
        if (t%fd >= 0) st = fortui_pty_resize(int(t%fd, c_int), int(t%rows, c_int), &
            int(t%cols, c_int), int(t%cols * t%cell_px_w, c_int), &
            int(t%rows * t%cell_px_h, c_int))
        t%dirty = .true.
        if (before < 0) continue
#else
        t%rows = rows
        t%cols = cols
        t%cell_px_w = cell_px_w
        t%cell_px_h = cell_px_h
#endif
    end subroutine term_resize

    ! --- screen ----------------------------------------------------------------

    subroutine snapshot(t)
        !! The visible screen into t%cp/fg/bg/attr, and the cursor and modes.
        type(term_t), intent(inout) :: t
        integer :: n, r, line, c0
        n = t%rows * t%cols
        if (allocated(t%cp)) then
            if (size(t%cp) /= n) deallocate(t%cp, t%fg, t%bg, t%attr)
        end if
        if (.not. allocated(t%cp)) allocate(t%cp(n), t%fg(n), t%bg(n), t%attr(n))
        if (.not. allocated(t%vt%cp)) then
            t%cp = 32
            t%fg = t%default_fg
            t%bg = 0
            t%attr = 0
            return
        end if
        do r = 0, t%rows - 1
            c0 = r * t%cols
            line = vt_line(t%vt, r)
            if (t%vt%alt) then
                t%cp(c0 + 1:c0 + t%cols) = t%vt%acp(1:t%cols, line)
                t%fg(c0 + 1:c0 + t%cols) = t%vt%afg(1:t%cols, line)
                t%bg(c0 + 1:c0 + t%cols) = t%vt%abg(1:t%cols, line)
                t%attr(c0 + 1:c0 + t%cols) = t%vt%aattr(1:t%cols, line)
            else
                t%cp(c0 + 1:c0 + t%cols) = t%vt%cp(1:t%cols, line)
                t%fg(c0 + 1:c0 + t%cols) = t%vt%fg(1:t%cols, line)
                t%bg(c0 + 1:c0 + t%cols) = t%vt%bg(1:t%cols, line)
                t%attr(c0 + 1:c0 + t%cols) = t%vt%attr(1:t%cols, line)
            end if
        end do
        t%cursor_row = t%vt%cr
        t%cursor_col = t%vt%cc
        t%cursor_visible = t%vt%cursor_visible
        t%mouse_mode = t%vt%mouse
        t%sb_count = t%vt%sb_count
        if (allocated(t%vt%title)) t%title = t%vt%title
    end subroutine snapshot

    subroutine follow_scroll(t)
        !! Images move up with the lines that scrolled into the scrollback.
        type(term_t), intent(inout) :: t
        if (t%vt%scrolled == 0) return
        if (t%nplaces > 0) then
            t%places(1:t%nplaces)%row = t%places(1:t%nplaces)%row - t%vt%scrolled
            call drop_old_places(t)
        end if
        t%vt%scrolled = 0
    end subroutine follow_scroll

    ! --- program output ---------------------------------------------------------

#ifdef ENABLE_TERM
    subroutine feed(t, bytes)
        !! Program output through the engine; strings for the host (titles,
        !! colour queries, images) are handled in stream order.
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: bytes
        integer :: pos, ev
        logical :: was_alt
        pos = 1
        do while (pos <= len(bytes))
            was_alt = t%vt%alt
            call vt_feed(t%vt, bytes, pos, ev)
            call follow_scroll(t)
            if (t%vt%erased_from >= 0) then
                call erase_images(t, t%vt%erased_from)
                t%vt%erased_from = -1
            end if
            ! Images belong to the screen they were shown on.
            if (t%vt%alt .neqv. was_alt) t%nplaces = 0
            t%altscreen = t%vt%alt
            t%cursor_row = t%vt%cr
            t%cursor_col = t%vt%cc
            select case (ev)
            case (VT_EV_OSC); call osc(t, t%vt%str(1:t%vt%nstr))
            case (VT_EV_DCS); call dcs(t, t%vt%str(1:t%vt%nstr))
            case (VT_EV_APC)
                if (t%vt%nstr > 0) then
                    if (t%vt%str(1:1) == "G") call kitty_command(t, t%vt%str(2:t%vt%nstr))
                end if
            end select
            if (ev /= VT_EV_NONE) call owed_motion(t)
        end do
        call flush_output(t)
    end subroutine feed

    subroutine osc(t, s)
        !! Operating system commands: titles (0, 2), colour queries (10, 11).
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: s
        integer :: semi
        semi = index(s, ";")
        if (semi == 0) return
        select case (s(1:semi - 1))
        case ("0", "2")
            t%vt%title = s(semi + 1:)
        case ("52")
            call osc52(t, s(semi + 1:))
        case ("10", "11")
            if (s(semi + 1:) == "?") call t_reply(t, achar(27) // "]" // s(1:semi) // &
                xcolor(merge(t%default_fg, t%default_bg, s(1:semi - 1) == "10")) // &
                achar(27) // "\")
        end select
    end subroutine osc

    subroutine osc52(t, s)
        !! A program sets the clipboard ("c;BASE64" or "p;..."; tmux copies this
        !! way). Requests to read it ("?") are refused: they would hand the
        !! clipboard to any program.
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: s
        integer(int8), allocatable :: raw(:)
        integer :: semi, n
        semi = index(s, ";")
        if (semi == 0) return
        if (s(semi + 1:) == "?") return
        call base64_decode(s(semi + 1:), raw, n)
        if (n > 16 * 1024 * 1024) return
        t%clipboard_out = repeat(" ", n)
        if (n > 0) t%clipboard_out = transfer(raw(1:n), t%clipboard_out)
        t%clipboard_target = "c"
        if (semi > 1) then
            if (verify(s(1:semi - 1), "p") == 0) t%clipboard_target = "p"
        end if
        t%clipboard_pending = .true.
    end subroutine osc52

    subroutine dcs(t, s)
        !! Device control strings: "params q data" is a sixel image.
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: s
        integer :: q
        q = verify(s, "0123456789;")
        if (q == 0) return
        if (s(q:q) == "q") call show_sixel(t, s(1:q - 1), s(q + 1:))
    end subroutine dcs

    function xcolor(rgba) result(spec)
        integer(int32), intent(in) :: rgba
        character(len=:), allocatable :: spec
        character(len=32) :: buf
        write (buf, '(a,z2.2,z2.2,a,z2.2,z2.2,a,z2.2,z2.2)') "rgb:", &
            iand(rgba, 255_int32), iand(rgba, 255_int32), "/", &
            iand(ishft(rgba, -8), 255_int32), iand(ishft(rgba, -8), 255_int32), "/", &
            iand(ishft(rgba, -16), 255_int32), iand(ishft(rgba, -16), 255_int32)
        spec = trim(buf)
    end function xcolor

    subroutine t_reply(t, s)
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: s
        call write_all(t%fd, s)
    end subroutine t_reply

    subroutine flush_output(t)
        type(term_t), intent(inout) :: t
        character(len=:), allocatable :: s
        if (t%vt%nout == 0) return
        call vt_take_output(t%vt, s)
        call write_all(t%fd, s)
    end subroutine flush_output

    subroutine erase_images(t, from_row)
        !! Images shown on screen rows from `from_row` down are erased.
        type(term_t), intent(inout) :: t
        integer, intent(in) :: from_row
        integer :: k, m
        m = 0
        do k = 1, t%nplaces
            if (t%places(k)%row + t%places(k)%rows > 0 .and. t%places(k)%row >= from_row) cycle
            m = m + 1
            t%places(m) = t%places(k)
        end do
        if (m /= t%nplaces) t%dirty = .true.
        t%nplaces = m
    end subroutine erase_images

    subroutine owed_motion(t)
        type(term_t), intent(inout) :: t
        character(len=:), allocatable :: m
        integer :: pos, ev
        if (len(t%motion) == 0) return
        m = t%motion
        t%motion = ""
        pos = 1
        do while (pos <= len(m))
            call vt_feed(t%vt, m, pos, ev)
        end do
        call follow_scroll(t)
        t%cursor_row = t%vt%cr
        t%cursor_col = t%vt%cc
    end subroutine owed_motion

    subroutine write_all(fd, bytes)
        integer, intent(in) :: fd
        character(*), intent(in), target :: bytes
        integer(c_long) :: w
        integer :: done
        done = 0
        if (fd < 0) return
        do while (done < len(bytes))
            w = c_write(int(fd, c_int), c_loc(bytes(done + 1:done + 1)), &
                int(len(bytes) - done, c_size_t))
            if (w <= 0) return
            done = done + int(w)
        end do
    end subroutine write_all

    ! --- images --------------------------------------------------------------------

    subroutine show_sixel(t, params, data)
        !! A sixel image at the cursor. As in xterm, the cursor then goes down
        !! to the row holding the top of the image's last six-pixel band and
        !! keeps its column, scrolling as text would.
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: params, data
        integer(int32), allocatable :: rgba(:, :)
        logical :: ok
        integer :: slot, rows, cols
        call sixel_decode(params, data, rgba, ok)
        if (.not. ok) return
        slot = store_image(t, 0, rgba)
        rows = (size(rgba, 2) + t%cell_px_h - 1) / t%cell_px_h
        cols = (size(rgba, 1) + t%cell_px_w - 1) / t%cell_px_w
        call place(t, slot, t%cursor_row, t%cursor_col, rows, cols, 0)
        t%motion = repeat(achar(10), (6 * ((size(rgba, 2) - 1) / 6)) / t%cell_px_h)
    end subroutine show_sixel

    subroutine kitty_command(t, body)
        !! One kitty graphics command (keys, ";", base64 payload).
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: body
        character(len=:), allocatable :: keys, payload
        integer :: semi, id, number, more, quiet
        character :: action

        semi = index(body, ";")
        if (semi == 0) then
            keys = body
            payload = ""
        else
            keys = body(1:semi - 1)
            payload = body(semi + 1:)
        end if
        more = key_int(keys, "m", 0)
        if (t%chunking) then
            ! Later chunks carry only m (and maybe q); the first one's keys count.
            ! A transfer that never ends is dropped at 128 MB.
            if (len(t%chunk_data) + len(payload) > 128 * 1024 * 1024) then
                t%chunking = .false.
                t%chunk_data = ""
                return
            end if
            t%chunk_data = t%chunk_data // payload
            if (more == 1) return
            keys = t%chunk_keys
            payload = t%chunk_data
            t%chunking = .false.
            t%chunk_data = ""
        else if (more == 1) then
            t%chunking = .true.
            t%chunk_keys = keys
            t%chunk_data = payload
            return
        end if
        action = key_char(keys, "a", "t")
        id = key_int(keys, "i", 0)
        number = key_int(keys, "I", 0)
        quiet = key_int(keys, "q", 0)
        select case (action)
        case ("q")
            call reply(t, id, number, quiet, "OK", .true.)
        case ("t", "T")
            call kitty_transmit(t, keys, payload, id, number, quiet, action == "T")
        case ("p")
            call kitty_put(t, keys, find_image(t, id))
            if (id > 0) call reply(t, id, number, quiet, "OK", .true.)
        case ("d")
            call kitty_delete(t, keys, id)
        end select
    end subroutine kitty_command

    subroutine kitty_transmit(t, keys, payload, id, number, quiet, display)
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: keys, payload
        integer, intent(in) :: id, number, quiet
        logical, intent(in) :: display
        integer(int8), allocatable :: raw(:), data(:)
        integer(int32), allocatable :: rgba(:, :)
        integer :: n, nd, fmt, w, h, x, y, k, slot, image_id
        character :: medium
        logical :: ok

        call base64_decode(payload, raw, n)
        medium = key_char(keys, "t", "d")
        if (medium == "f" .or. medium == "t") then
            call read_file(transfer(raw(1:n), repeat(" ", n)), medium == "t", raw, n, ok)
            if (.not. ok) then
                call reply(t, id, number, quiet, "EBADF:cannot read file", .false.)
                return
            end if
        else if (medium /= "d") then
            call reply(t, id, number, quiet, "EINVAL:unsupported transmission medium", .false.)
            return
        end if
        if (key_char(keys, "o", " ") == "z") then
            call zlib_decompress(raw(1:n), data, nd, ok)
            if (.not. ok) then
                call reply(t, id, number, quiet, "EINVAL:bad zlib data", .false.)
                return
            end if
        else
            data = raw(1:n)
            nd = n
        end if
        fmt = key_int(keys, "f", 32)
        w = key_int(keys, "s", 0)
        h = key_int(keys, "v", 0)
        select case (fmt)
        case (100)
            call png_decode(data(1:nd), rgba, ok)
            if (.not. ok) then
                call reply(t, id, number, quiet, "EBADPNG:cannot decode", .false.)
                return
            end if
        case (24, 32)
            if (w <= 0 .or. h <= 0 .or. nd < w * h * fmt / 8) then
                call reply(t, id, number, quiet, "EINVAL:size does not match data", .false.)
                return
            end if
            allocate(rgba(w, h))
            k = 1
            do y = 1, h
                do x = 1, w
                    if (fmt == 24) then
                        rgba(x, y) = px(data(k), data(k + 1), data(k + 2), -1_int8)
                        k = k + 3
                    else
                        rgba(x, y) = px(data(k), data(k + 1), data(k + 2), data(k + 3))
                        k = k + 4
                    end if
                end do
            end do
        case default
            call reply(t, id, number, quiet, "EINVAL:unsupported format", .false.)
            return
        end select
        image_id = id
        if (image_id == 0 .and. number > 0) then
            t%image_serial = modulo(t%image_serial + 1, 2**30)
            image_id = 1000000 + t%image_serial
        end if
        slot = store_image(t, image_id, rgba)
        if (display) call kitty_put(t, keys, slot)
        if (image_id > 0) call reply(t, image_id, number, quiet, "OK", .true.)
    end subroutine kitty_transmit

    subroutine kitty_put(t, keys, slot)
        !! Show image `slot` at the cursor over c x r cells (default: its pixel
        !! size in cells); the cursor moves past it unless C=1. A virtual
        !! placement (U=1, for Unicode placeholders) is not drawn here.
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: keys
        integer, intent(in) :: slot
        integer :: rows, cols
        if (slot == 0) return
        if (key_int(keys, "U", 0) == 1) return
        cols = key_int(keys, "c", 0)
        rows = key_int(keys, "r", 0)
        associate(im => t%images(slot))
            if (cols <= 0 .and. rows <= 0) then
                cols = (im%width + t%cell_px_w - 1) / t%cell_px_w
                rows = (im%height + t%cell_px_h - 1) / t%cell_px_h
            else if (cols <= 0) then
                cols = max(1, nint(real(rows * t%cell_px_h) * real(im%width) / &
                    real(max(1, im%height)) / real(t%cell_px_w)))
            else if (rows <= 0) then
                rows = max(1, nint(real(cols * t%cell_px_w) * real(im%height) / &
                    real(max(1, im%width)) / real(t%cell_px_h)))
            end if
        end associate
        call place(t, slot, t%cursor_row, t%cursor_col, rows, cols, key_int(keys, "z", 0))
        if (key_int(keys, "C", 0) /= 1) then
            ! Cursor down (never scrolls) to the image's last row, then past its
            ! last column.
            t%motion = achar(27) // "[" // itoa(t%cursor_col + cols + 1) // "G"
            if (rows > 1) t%motion = achar(27) // "[" // itoa(rows - 1) // "B" // t%motion
        end if
    end subroutine kitty_put

    subroutine kitty_delete(t, keys, id)
        !! d=a/A: every placement (A also frees images), d=i/I: those of image
        !! `id`; other selectors remove the placements on the screen.
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: keys
        integer, intent(in) :: id
        character :: what
        integer :: k, n, slot
        what = key_char(keys, "d", "a")
        slot = 0
        if (what == "i" .or. what == "I") slot = find_image(t, id)
        n = 0
        do k = 1, t%nplaces
            if ((what == "i" .or. what == "I") .and. t%places(k)%image /= slot) then
                n = n + 1
                t%places(n) = t%places(k)
            end if
        end do
        t%nplaces = n
        if (what == "A") then
            do k = 1, MAX_IMAGES
                t%images(k)%id = 0
                if (allocated(t%images(k)%rgba)) deallocate(t%images(k)%rgba)
            end do
        else if (what == "I" .and. slot > 0) then
            t%images(slot)%id = 0
            if (allocated(t%images(slot)%rgba)) deallocate(t%images(slot)%rgba)
        end if
        t%dirty = .true.
    end subroutine kitty_delete

    integer function store_image(t, id, rgba) result(slot)
        !! Keep pixels under `id` (0: anonymous, as sixel images are); the
        !! oldest image not on screen makes room when all slots are taken.
        type(term_t), intent(inout) :: t
        integer, intent(in) :: id
        integer(int32), intent(in) :: rgba(:, :)
        integer :: k
        slot = 0
        if (id > 0) slot = find_image(t, id)
        if (slot == 0) then
            do k = 1, MAX_IMAGES
                if (.not. allocated(t%images(k)%rgba)) then
                    slot = k
                    exit
                end if
            end do
        end if
        if (slot == 0) then
            do k = 1, MAX_IMAGES
                if (.not. any(t%places(1:t%nplaces)%image == k)) then
                    slot = k
                    exit
                end if
            end do
        end if
        if (slot == 0) slot = 1
        t%images(slot)%id = id
        t%images(slot)%width = size(rgba, 1)
        t%images(slot)%height = size(rgba, 2)
        t%images(slot)%rgba = rgba
        t%image_serial = modulo(t%image_serial + 1, 2**30)
        t%images(slot)%generation = t%image_serial
    end function store_image

    integer function find_image(t, id) result(slot)
        type(term_t), intent(in) :: t
        integer, intent(in) :: id
        integer :: k
        slot = 0
        if (id <= 0) return
        do k = 1, MAX_IMAGES
            if (t%images(k)%id == id .and. allocated(t%images(k)%rgba)) then
                slot = k
                return
            end if
        end do
    end function find_image

    subroutine place(t, slot, row, col, rows, cols, z)
        type(term_t), intent(inout) :: t
        integer, intent(in) :: slot, row, col, rows, cols, z
        type(term_place_t), allocatable :: grown(:)
        integer :: k, n
        ! A new image over the same cells replaces the old one.
        n = 0
        do k = 1, t%nplaces
            if (t%places(k)%row == row .and. t%places(k)%col == col .and. &
                t%places(k)%z == z) cycle
            n = n + 1
            t%places(n) = t%places(k)
        end do
        t%nplaces = n
        if (t%nplaces == size(t%places)) then
            if (t%nplaces >= MAX_PLACES) then
                t%places(1:t%nplaces - 1) = t%places(2:t%nplaces)
                t%nplaces = t%nplaces - 1
            else
                allocate(grown(2 * size(t%places)))
                grown(1:t%nplaces) = t%places(1:t%nplaces)
                call move_alloc(grown, t%places)
            end if
        end if
        t%place_serial = modulo(t%place_serial + 1, 2**30)
        t%nplaces = t%nplaces + 1
        t%places(t%nplaces) = term_place_t(image=slot, row=row, col=col, rows=max(1, rows), &
            cols=max(1, cols), z=z, serial=t%place_serial)
        t%dirty = .true.
    end subroutine place

    subroutine drop_old_places(t)
        !! Placements that left the scrollback.
        type(term_t), intent(inout) :: t
        integer :: k, n
        n = 0
        do k = 1, t%nplaces
            if (t%places(k)%row + t%places(k)%rows <= -t%vt%sb_max) cycle
            n = n + 1
            t%places(n) = t%places(k)
        end do
        t%nplaces = n
    end subroutine drop_old_places

    subroutine reply(t, id, number, quiet, message, success)
        !! The kitty response (q=1 silences successes, q=2 everything).
        type(term_t), intent(inout) :: t
        integer, intent(in) :: id, number, quiet
        character(*), intent(in) :: message
        logical, intent(in) :: success
        character(len=:), allocatable :: head
        if (quiet >= 2 .or. (success .and. quiet == 1)) return
        if (id <= 0 .and. number <= 0) return
        head = achar(27) // "_G"
        if (id > 0) head = head // "i=" // itoa(id)
        if (number > 0) then
            if (id > 0) head = head // ","
            head = head // "I=" // itoa(number)
        end if
        call write_all(t%fd, head // ";" // message // achar(27) // "\")
    end subroutine reply

    subroutine read_file(path, temporary, raw, n, ok)
        !! Pixels sent as a file name; a temporary one (t=t) is removed after
        !! reading when its name says it is one, as the protocol requires.
        character(*), intent(in) :: path
        logical, intent(in) :: temporary
        integer(int8), allocatable, intent(out) :: raw(:)
        integer, intent(out) :: n
        logical, intent(out) :: ok
        integer :: u, ios, sz
        ok = .false.
        n = 0
        open (newunit=u, file=path, access="stream", form="unformatted", status="old", &
            action="read", iostat=ios)
        if (ios /= 0) return
        inquire (unit=u, size=sz)
        if (sz <= 0 .or. sz > 512 * 1024 * 1024) then
            close (u)
            return
        end if
        allocate(raw(sz))
        read (u, iostat=ios) raw
        if (temporary .and. index(path, "tty-graphics-protocol") > 0) then
            close (u, status="delete")
        else
            close (u)
        end if
        if (ios /= 0) return
        n = sz
        ok = .true.
    end subroutine read_file

    integer function key_int(keys, name, fallback) result(v)
        character(*), intent(in) :: keys, name
        integer, intent(in) :: fallback
        character(len=:), allocatable :: s
        integer :: ios
        s = key_value(keys, name)
        v = fallback
        if (len(s) == 0) return
        read (s, *, iostat=ios) v
        if (ios /= 0) v = fallback
    end function key_int

    character function key_char(keys, name, fallback) result(v)
        character(*), intent(in) :: keys, name
        character, intent(in) :: fallback
        character(len=:), allocatable :: s
        s = key_value(keys, name)
        v = fallback
        if (len(s) > 0) v = s(1:1)
    end function key_char

    function key_value(keys, name) result(v)
        !! The value of `name` in "a=T,f=100,...".
        character(*), intent(in) :: keys, name
        character(len=:), allocatable :: v
        integer :: a, b
        v = ""
        a = 1
        do while (a <= len(keys))
            b = index(keys(a:), ",")
            if (b == 0) then
                b = len(keys) + 1
            else
                b = a + b - 1
            end if
            if (b - a >= 2) then
                if (keys(a:a + len(name)) == name // "=") then
                    v = keys(a + len(name) + 1:b - 1)
                    return
                end if
            end if
            a = b + 1
        end do
    end function key_value

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=16) :: buf
        write (buf, '(i0)') i
        s = trim(buf)
    end function itoa

    pure integer(int32) function px(r, g, b, a) result(c)
        integer(int8), intent(in) :: r, g, b, a
        c = int(iand(int(r), 255), int32) + ishft(int(iand(int(g), 255), int32), 8) + &
            ishft(int(iand(int(b), 255), int32), 16) + ishft(int(a, int32), 24)
    end function px

    pure subroutine decode_utf8(s, pos, cp, nb)
        character(*), intent(in) :: s
        integer, intent(in) :: pos
        integer, intent(out) :: cp, nb
        integer :: c0, k
        c0 = iachar(s(pos:pos))
        if (c0 < 128) then
            cp = c0
            nb = 1
        else if (c0 >= 240) then
            cp = iand(c0, 7)
            nb = 4
        else if (c0 >= 224) then
            cp = iand(c0, 15)
            nb = 3
        else
            cp = iand(c0, 31)
            nb = 2
        end if
        if (pos + nb - 1 > len(s)) then
            cp = 65533
            nb = 1
            return
        end if
        do k = 1, nb - 1
            cp = ior(ishft(cp, 6), iand(iachar(s(pos + k:pos + k)), 63))
        end do
    end subroutine decode_utf8
#else
    subroutine feed(t, bytes)
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: bytes
        if (len(bytes) > 0 .or. t%alive) continue
    end subroutine feed

    subroutine flush_output(t)
        type(term_t), intent(inout) :: t
        if (t%alive) continue
    end subroutine flush_output

    subroutine drop_old_places(t)
        type(term_t), intent(inout) :: t
        if (t%alive) continue
    end subroutine drop_old_places
#endif

end module fortui_term
