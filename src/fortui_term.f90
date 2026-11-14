module fortui_term
    !! Terminal emulator: a program on a pseudo-terminal whose output libvterm
    !! turns into a screen of cells, with scrollback, the window title, and
    !! images from the kitty graphics protocol and from sixel strings anchored
    !! to the cells they cover. Built with -DENABLE_TERM=1 (libvterm); without
    !! it term_open reports that terminals are unavailable.
    !!
    !! A term_t must stay where it is while it runs (libvterm keeps its
    !! address): a module variable, or an element of an array that is not
    !! reallocated.
    use iso_c_binding
    use iso_fortran_env, only: int8, int32, int64
    use fortui_error, only: report_error
    use fortui_input, only: key_press_t, KEY_NONE, KEY_ENTER, KEY_ESCAPE, KEY_TAB, &
        KEY_BACKSPACE, KEY_DELETE, KEY_HOME, KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, &
        KEY_ARROW_UP, KEY_ARROW_DOWN, KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_SPACE, KEY_INSERT, &
        KEY_F1, KEY_F12, MOD_CTRL, MOD_ALT, MOD_SHIFT
    use fortui_frame, only: CELL_BOLD, CELL_ITALIC, CELL_UNDERLINE, CELL_STRIKE, CELL_WIDE, &
        CELL_CONT, CELL_DIM
    use fortui_inflate, only: zlib_decompress, png_decode, base64_decode
    use fortui_sixel, only: sixel_decode
    implicit none
    private

    public :: term_t, term_image_t, term_place_t, term_line_t
    public :: term_open, term_close, term_pump, term_key, term_paste, term_resize, term_write
    public :: term_available, term_set_colors, term_mouse
    integer, parameter, public :: CURSOR_BLOCK = 1, CURSOR_BAR = 2, CURSOR_UNDERLINE = 3

    integer, parameter :: MAX_IMAGES = 64, MAX_PLACES = 256
    ! Erase in display: all, all with scrollback, below the cursor (two spellings).
    character(len=2), parameter :: ERASES(4) = [character(len=2) :: "2J", "3J", "J", "0J"]

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

    type :: term_line_t
        integer(int32), allocatable :: cp(:), fg(:), bg(:), attr(:)
    end type term_line_t

    type :: term_t
        type(c_ptr) :: vt = c_null_ptr, screen = c_null_ptr, state = c_null_ptr
        type(c_ptr) :: watch = c_null_ptr
        integer :: fd = -1, pid = -1
        integer :: rows = 24, cols = 80, cell_px_w = 8, cell_px_h = 16
        logical :: alive = .false.
        integer :: exit_status = -1
        logical :: dirty = .true.
        logical :: bell = .false.
        integer :: generation = 0
        character(len=:), allocatable :: title
        integer :: cursor_row = 0, cursor_col = 0
        logical :: cursor_visible = .true.
        logical :: altscreen = .false.
        ! Mouse reporting the program asked for (0 = none).
        integer :: mouse_mode = 0
        integer(int32) :: default_fg = int(z'FFD4D4D4', int32)
        integer(int32) :: default_bg = 0
        ! Cursor colour (ui_rgba; 0: the text colour) and shape (CURSOR_*).
        integer(int32) :: cursor_color = 0
        integer :: cursor_shape = 1
        ! The 16 ANSI colours (ui_rgba) when `own_palette`, else libvterm's.
        integer(int32) :: palette(16) = 0
        logical :: own_palette = .false.
        ! Bold text in the first eight colours shows the bright eight, as VTE
        ! and xterm do by default (ls draws directories in bold blue).
        logical :: bold_bright = .true.
        ! The screen, row by row from the top (ui_rgba colours, CELL_* bits).
        integer(int32), allocatable :: cp(:), fg(:), bg(:), attr(:)
        ! Scrollback ring: sb_count lines, the newest at sb_head.
        type(term_line_t), allocatable :: sb(:)
        integer :: sb_count = 0, sb_head = 0
        ! Images and where they are shown.
        type(term_image_t) :: images(MAX_IMAGES)
        type(term_place_t), allocatable :: places(:)
        integer :: nplaces = 0, place_serial = 0, image_serial = 0
        ! Escape strings in progress and cursor motion owed after an image.
        character(len=:), allocatable :: apc, dcs, dcs_command, title_part, motion
        integer :: napc = 0, ndcs = 0
        ! Kitty transmission in chunks (m=1).
        character(len=:), allocatable :: chunk_keys, chunk_data
        integer :: nchunk = 0
        logical :: chunking = .false.
    end type term_t

#ifdef ENABLE_TERM
    type, bind(C) :: vt_pos_t
        integer(c_int) :: row, col
    end type vt_pos_t

    type, bind(C) :: vt_rect_t
        integer(c_int) :: start_row, end_row, start_col, end_col
    end type vt_rect_t

    type, bind(C) :: vt_cell_t
        integer(c_int32_t) :: chars(6)
        integer(c_signed_char) :: width
        ! C bit-fields (bold 0, underline 1-2, italic 3, blink 4, reverse 5,
        ! conceal 6, strike 7, ...), allocated from the low bit on the
        ! little-endian ABIs this runs on.
        integer(c_int32_t) :: attrs
        integer(c_int8_t) :: fg(4), bg(4)
    end type vt_cell_t

    type, bind(C) :: vt_fragment_t
        type(c_ptr) :: str
        ! len : 30, initial : 1, final : 1
        integer(c_size_t) :: bits
    end type vt_fragment_t

    type, bind(C) :: vt_screen_callbacks_t
        type(c_funptr) :: damage, moverect, movecursor, settermprop, bell, resize, &
            sb_pushline, sb_popline, sb_clear
    end type vt_screen_callbacks_t

    type, bind(C) :: vt_fallbacks_t
        type(c_funptr) :: control, csi, osc, dcs, apc, pm, sos
    end type vt_fallbacks_t

    type(vt_screen_callbacks_t), target, save :: screen_cbs
    type(vt_fallbacks_t), target, save :: fallbacks

    integer(c_int), parameter :: PROP_CURSORVISIBLE = 1, PROP_ALTSCREEN = 3, &
        PROP_TITLE = 4, PROP_MOUSE = 8
    integer(c_int), parameter :: VK_ENTER = 1, VK_TAB = 2, VK_BACKSPACE = 3, VK_ESCAPE = 4, &
        VK_UP = 5, VK_DOWN = 6, VK_LEFT = 7, VK_RIGHT = 8, VK_INS = 9, VK_DEL = 10, &
        VK_HOME = 11, VK_END = 12, VK_PAGEUP = 13, VK_PAGEDOWN = 14, VK_FUNCTION_0 = 256

    interface
        type(c_ptr) function vterm_new(rows, cols) bind(C, name="vterm_new")
            import :: c_ptr, c_int
            integer(c_int), value :: rows, cols
        end function
        subroutine vterm_free(vt) bind(C, name="vterm_free")
            import :: c_ptr
            type(c_ptr), value :: vt
        end subroutine
        subroutine vterm_set_size(vt, rows, cols) bind(C, name="vterm_set_size")
            import :: c_ptr, c_int
            type(c_ptr), value :: vt
            integer(c_int), value :: rows, cols
        end subroutine
        subroutine vterm_set_utf8(vt, on) bind(C, name="vterm_set_utf8")
            import :: c_ptr, c_int
            type(c_ptr), value :: vt
            integer(c_int), value :: on
        end subroutine
        integer(c_size_t) function vterm_input_write(vt, bytes, n) &
                bind(C, name="vterm_input_write")
            import :: c_ptr, c_size_t, c_char
            type(c_ptr), value :: vt
            character(kind=c_char), intent(in) :: bytes(*)
            integer(c_size_t), value :: n
        end function
        subroutine vterm_output_set_callback(vt, fn, user) &
                bind(C, name="vterm_output_set_callback")
            import :: c_ptr, c_funptr
            type(c_ptr), value :: vt
            type(c_funptr), value :: fn
            type(c_ptr), value :: user
        end subroutine
        subroutine vterm_keyboard_unichar(vt, c, m) bind(C, name="vterm_keyboard_unichar")
            import :: c_ptr, c_int32_t, c_int
            type(c_ptr), value :: vt
            integer(c_int32_t), value :: c
            integer(c_int), value :: m
        end subroutine
        subroutine vterm_keyboard_key(vt, k, m) bind(C, name="vterm_keyboard_key")
            import :: c_ptr, c_int
            type(c_ptr), value :: vt
            integer(c_int), value :: k, m
        end subroutine
        subroutine vterm_keyboard_start_paste(vt) bind(C, name="vterm_keyboard_start_paste")
            import :: c_ptr
            type(c_ptr), value :: vt
        end subroutine
        subroutine vterm_keyboard_end_paste(vt) bind(C, name="vterm_keyboard_end_paste")
            import :: c_ptr
            type(c_ptr), value :: vt
        end subroutine
        subroutine vterm_mouse_move(vt, row, col, m) bind(C, name="vterm_mouse_move")
            import :: c_ptr, c_int
            type(c_ptr), value :: vt
            integer(c_int), value :: row, col, m
        end subroutine
        subroutine vterm_mouse_button(vt, button, pressed, m) &
                bind(C, name="vterm_mouse_button")
            import :: c_ptr, c_int, c_bool
            type(c_ptr), value :: vt
            integer(c_int), value :: button, m
            logical(c_bool), value :: pressed
        end subroutine
        type(c_ptr) function vterm_obtain_screen(vt) bind(C, name="vterm_obtain_screen")
            import :: c_ptr
            type(c_ptr), value :: vt
        end function
        type(c_ptr) function vterm_obtain_state(vt) bind(C, name="vterm_obtain_state")
            import :: c_ptr
            type(c_ptr), value :: vt
        end function
        subroutine vterm_screen_reset(screen, hard) bind(C, name="vterm_screen_reset")
            import :: c_ptr, c_int
            type(c_ptr), value :: screen
            integer(c_int), value :: hard
        end subroutine
        subroutine vterm_screen_enable_altscreen(screen, on) &
                bind(C, name="vterm_screen_enable_altscreen")
            import :: c_ptr, c_int
            type(c_ptr), value :: screen
            integer(c_int), value :: on
        end subroutine
        subroutine vterm_screen_enable_reflow(screen, on) &
                bind(C, name="vterm_screen_enable_reflow")
            import :: c_ptr, c_bool
            type(c_ptr), value :: screen
            logical(c_bool), value :: on
        end subroutine
        subroutine vterm_screen_set_damage_merge(screen, size) &
                bind(C, name="vterm_screen_set_damage_merge")
            import :: c_ptr, c_int
            type(c_ptr), value :: screen
            integer(c_int), value :: size
        end subroutine
        subroutine vterm_screen_flush_damage(screen) bind(C, name="vterm_screen_flush_damage")
            import :: c_ptr
            type(c_ptr), value :: screen
        end subroutine
        subroutine vterm_screen_set_callbacks(screen, cbs, user) &
                bind(C, name="vterm_screen_set_callbacks")
            import :: c_ptr
            type(c_ptr), value :: screen, cbs, user
        end subroutine
        subroutine vterm_screen_set_unrecognised_fallbacks(screen, fb, user) &
                bind(C, name="vterm_screen_set_unrecognised_fallbacks")
            import :: c_ptr
            type(c_ptr), value :: screen, fb, user
        end subroutine
        integer(c_int) function vterm_screen_get_cell(screen, pos, cell) &
                bind(C, name="vterm_screen_get_cell")
            import :: c_ptr, c_int, vt_pos_t, vt_cell_t
            type(c_ptr), value :: screen
            type(vt_pos_t), value :: pos
            type(vt_cell_t), intent(out) :: cell
        end function
        subroutine vterm_screen_convert_color_to_rgb(screen, col) &
                bind(C, name="vterm_screen_convert_color_to_rgb")
            import :: c_ptr, c_int8_t
            type(c_ptr), value :: screen
            integer(c_int8_t), intent(inout) :: col(4)
        end subroutine
        subroutine vterm_screen_set_default_colors(screen, fg, bg) &
                bind(C, name="vterm_screen_set_default_colors")
            import :: c_ptr, c_int8_t
            type(c_ptr), value :: screen
            integer(c_int8_t), intent(in) :: fg(4), bg(4)
        end subroutine
        subroutine vterm_state_set_bold_highbright(state, on) &
                bind(C, name="vterm_state_set_bold_highbright")
            import :: c_ptr, c_int
            type(c_ptr), value :: state
            integer(c_int), value :: on
        end subroutine
        subroutine vterm_state_set_palette_color(state, index, col) &
                bind(C, name="vterm_state_set_palette_color")
            import :: c_ptr, c_int, c_int8_t
            type(c_ptr), value :: state
            integer(c_int), value :: index
            integer(c_int8_t), intent(in) :: col(4)
        end subroutine

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
        type(c_ptr) function c_memcpy(dst, src, n) bind(C, name="memcpy")
            import :: c_ptr, c_size_t
            type(c_ptr), value :: dst, src
            integer(c_size_t), value :: n
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
        !! images). `wake` (optional) is called from another thread when the
        !! program writes, so that a host sleeping in its event loop wakes.
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
            do k = 1, size(command)
                args = args // trim(command(k)) // c_null_char
            end do
            n = size(command)
        else
            call get_environment_variable("SHELL", shell, status=st)
            if (st /= 0 .or. len_trim(shell) == 0) shell = "/bin/sh"
            args = trim(shell) // c_null_char
            n = 1
        end if
        dir = ""
        if (present(cwd)) dir = cwd
        t%vt = vterm_new(int(t%rows, c_int), int(t%cols, c_int))
        if (.not. c_associated(t%vt)) return
        call vterm_set_utf8(t%vt, 1_c_int)
        t%screen = vterm_obtain_screen(t%vt)
        t%state = vterm_obtain_state(t%vt)
        screen_cbs = vt_screen_callbacks_t(c_funloc(cb_damage), c_funloc(cb_moverect), &
            c_funloc(cb_movecursor), c_funloc(cb_settermprop), c_funloc(cb_bell), &
            c_null_funptr, c_funloc(cb_sb_pushline), c_null_funptr, c_funloc(cb_sb_clear))
        fallbacks = vt_fallbacks_t(c_null_funptr, c_null_funptr, c_null_funptr, &
            c_funloc(cb_dcs), c_funloc(cb_apc), c_null_funptr, c_null_funptr)
        call vterm_output_set_callback(t%vt, c_funloc(cb_output), c_loc(t))
        call vterm_screen_set_callbacks(t%screen, c_loc(screen_cbs), c_loc(t))
        call vterm_screen_set_unrecognised_fallbacks(t%screen, c_loc(fallbacks), c_loc(t))
        call vterm_screen_enable_altscreen(t%screen, 1_c_int)
        call vterm_state_set_bold_highbright(t%state, merge(1_c_int, 0_c_int, t%bold_bright))
        call vterm_screen_enable_reflow(t%screen, .true._c_bool)
        call vterm_screen_set_damage_merge(t%screen, 3_c_int)
        call vterm_screen_reset(t%screen, 1_c_int)
        if (t%own_palette) then
            call term_set_colors(t, t%default_fg, t%default_bg, t%palette)
        else
            call term_set_colors(t, t%default_fg, t%default_bg)
        end if
        if (allocated(t%sb)) deallocate(t%sb)
        if (allocated(t%places)) deallocate(t%places)
        allocate(t%sb(5000), t%places(32))
        t%sb_count = 0
        t%sb_head = 0
        t%nplaces = 0
        t%cursor_row = 0
        t%cursor_col = 0
        t%cursor_visible = .true.
        t%altscreen = .false.
        t%mouse_mode = 0
        t%bell = .false.
        t%chunking = .false.
        t%napc = 0
        t%ndcs = 0
        t%title = ""
        t%apc = ""
        t%dcs = ""
        t%dcs_command = ""
        t%title_part = ""
        t%motion = ""
        t%chunk_keys = ""
        t%chunk_data = ""
        call grid(t)
        t%fd = fortui_pty_spawn(args, int(n, c_int), dir // c_null_char, int(t%rows, c_int), &
            int(t%cols, c_int), int(t%cols * t%cell_px_w, c_int), &
            int(t%rows * t%cell_px_h, c_int), pid)
        if (t%fd < 0) then
            call report_error("fortui_term", "term_open", "cannot start '" // &
                args(1:index(args, c_null_char) - 1) // "'")
            call vterm_free(t%vt)
            t%vt = c_null_ptr
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
            "built without the terminal emulator (-DENABLE_TERM=1, libvterm)")
#endif
    end subroutine term_open

    subroutine term_close(t)
        !! End the program (SIGHUP, as when a terminal window closes) and free
        !! the screen.
        type(term_t), intent(inout) :: t
#ifdef ENABLE_TERM
        integer :: st
        if (c_associated(t%watch)) call fortui_pty_unwatch(t%watch)
        t%watch = c_null_ptr
        if (t%pid > 0 .and. t%alive) st = c_kill(int(t%pid, c_int), 1_c_int)
        if (t%fd >= 0) st = c_close(int(t%fd, c_int))
        if (c_associated(t%vt)) call vterm_free(t%vt)
#endif
        t%vt = c_null_ptr
        t%screen = c_null_ptr
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
#ifdef ENABLE_TERM
        integer :: k
        t%default_fg = fg
        t%default_bg = bg
        if (.not. c_associated(t%screen)) return
        call vterm_screen_set_default_colors(t%screen, vt_rgb(fg), vt_rgb(bg))
        if (present(palette)) then
            t%palette = palette
            t%own_palette = .true.
            do k = 1, 16
                call vterm_state_set_palette_color(t%state, int(k - 1, c_int), vt_rgb(palette(k)))
            end do
        end if
        t%dirty = .true.
#else
        t%default_fg = fg
        t%default_bg = bg
        if (present(palette)) continue
#endif
    end subroutine term_set_colors

    logical function term_pump(t, budget_bytes) result(changed)
        !! Read what the program wrote (at most `budget_bytes` this call, so the
        !! host stays responsive under heavy output) and update the screen.
        !! True when the screen, cursor or title changed.
        type(term_t), intent(inout), target :: t
        integer, intent(in), optional :: budget_bytes
#ifdef ENABLE_TERM
        character(kind=c_char, len=65536) :: buf
        integer(c_int) :: fds(2)
        integer(c_long) :: got
        integer :: budget, done, st

        changed = .false.
        if (.not. c_associated(t%vt)) return
        budget = 4 * 1024 * 1024
        if (present(budget_bytes)) budget = budget_bytes
        done = 0
        do while (t%alive .and. done < budget)
            fds(1) = int(t%fd, c_int)
            fds(2) = 1_c_int ! POLLIN in the low half of the events/revents pair
            if (c_poll(fds, 1_c_long, 0_c_int) <= 0) exit
            got = c_read(int(t%fd, c_int), buf, int(len(buf), c_size_t))
            if (got <= 0) then
                ! EIO: the program and everything it started have ended.
                t%alive = .false.
                exit
            end if
            call feed(t, buf(1:int(got)))
            done = done + int(got)
        end do
        if (.not. t%alive .and. t%pid > 0 .and. t%exit_status < 0) then
            st = fortui_pty_exited(int(t%pid, c_int))
            if (st >= 0) t%exit_status = st
            changed = .true.
        end if
        if (c_associated(t%watch)) call fortui_pty_rearm(t%watch)
        call vterm_screen_flush_damage(t%screen)
        if (t%dirty) then
            call refresh(t)
            t%dirty = .false.
            t%generation = modulo(t%generation + 1, 2**30)
            changed = .true.
        end if
#else
        changed = .false.
        if (present(budget_bytes)) continue
        if (t%alive) continue
#endif
    end function term_pump

    subroutine term_key(t, press)
        !! A key press as the terminal sends it to the program.
        type(term_t), intent(inout) :: t
        type(key_press_t), intent(in) :: press
#ifdef ENABLE_TERM
        integer(c_int) :: m, k
        if (.not. c_associated(t%vt)) return
        m = 0
        if (iand(press%mods, MOD_SHIFT) /= 0) m = ior(m, 1_c_int)
        if (iand(press%mods, MOD_ALT) /= 0) m = ior(m, 2_c_int)
        if (iand(press%mods, MOD_CTRL) /= 0) m = ior(m, 4_c_int)
        if (press%key == KEY_NONE) then
            if (press%code > 0) call vterm_keyboard_unichar(t%vt, int(press%code, c_int32_t), m)
            return
        end if
        select case (press%key)
        case (KEY_ENTER); k = VK_ENTER
        case (KEY_TAB); k = VK_TAB
        case (KEY_BACKSPACE); k = VK_BACKSPACE
        case (KEY_ESCAPE); k = VK_ESCAPE
        case (KEY_ARROW_UP); k = VK_UP
        case (KEY_ARROW_DOWN); k = VK_DOWN
        case (KEY_ARROW_LEFT); k = VK_LEFT
        case (KEY_ARROW_RIGHT); k = VK_RIGHT
        case (KEY_INSERT); k = VK_INS
        case (KEY_DELETE); k = VK_DEL
        case (KEY_HOME); k = VK_HOME
        case (KEY_END); k = VK_END
        case (KEY_PAGE_UP); k = VK_PAGEUP
        case (KEY_PAGE_DOWN); k = VK_PAGEDOWN
        case (KEY_SPACE)
            call vterm_keyboard_unichar(t%vt, 32_c_int32_t, m)
            return
        case (KEY_F1:KEY_F12); k = VK_FUNCTION_0 + int(press%key - KEY_F1 + 1, c_int)
        case default; return
        end select
        call vterm_keyboard_key(t%vt, k, m)
#else
        if (press%key == 0 .or. t%alive) continue
#endif
    end subroutine term_key

    subroutine term_paste(t, text)
        !! Pasted text, bracketed when the program asked for that.
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: text
#ifdef ENABLE_TERM
        integer :: pos, cp, nb
        if (.not. c_associated(t%vt)) return
        call vterm_keyboard_start_paste(t%vt)
        pos = 1
        do while (pos <= len(text))
            call decode_utf8(text, pos, cp, nb)
            if (cp == 10) cp = 13
            call vterm_keyboard_unichar(t%vt, int(cp, c_int32_t), 0_c_int)
            pos = pos + nb
        end do
        call vterm_keyboard_end_paste(t%vt)
#else
        if (len(text) > 0 .or. t%alive) continue
#endif
    end subroutine term_paste

    subroutine term_mouse(t, row, col, button, pressed, moved, mods)
        !! Pointer events for a program that asked for mouse reports (button
        !! 1-3, 4/5 for the wheel; `moved` for motion only).
        type(term_t), intent(inout) :: t
        integer, intent(in) :: row, col, button, mods
        logical, intent(in) :: pressed, moved
#ifdef ENABLE_TERM
        integer(c_int) :: m
        if (.not. c_associated(t%vt)) return
        m = 0
        if (iand(mods, MOD_SHIFT) /= 0) m = ior(m, 1_c_int)
        if (iand(mods, MOD_ALT) /= 0) m = ior(m, 2_c_int)
        if (iand(mods, MOD_CTRL) /= 0) m = ior(m, 4_c_int)
        call vterm_mouse_move(t%vt, int(row, c_int), int(col, c_int), m)
        if (.not. moved) call vterm_mouse_button(t%vt, int(button, c_int), &
            logical(pressed, c_bool), m)
#else
        if (row + col + button + mods > 0 .or. pressed .or. moved .or. t%alive) continue
#endif
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
        !! New size in cells (and pixels per cell): the screen reflows and the
        !! program gets SIGWINCH.
        type(term_t), intent(inout) :: t
        integer, intent(in) :: rows, cols, cell_px_w, cell_px_h
#ifdef ENABLE_TERM
        integer :: st
        if (rows == t%rows .and. cols == t%cols .and. cell_px_w == t%cell_px_w .and. &
            cell_px_h == t%cell_px_h) return
        t%cell_px_w = max(1, cell_px_w)
        t%cell_px_h = max(1, cell_px_h)
        if (rows /= t%rows .or. cols /= t%cols) then
            t%rows = max(1, rows)
            t%cols = max(1, cols)
            if (c_associated(t%vt)) call vterm_set_size(t%vt, int(t%rows, c_int), &
                int(t%cols, c_int))
            call grid(t)
        end if
        if (t%fd >= 0) st = fortui_pty_resize(int(t%fd, c_int), int(t%rows, c_int), &
            int(t%cols, c_int), int(t%cols * t%cell_px_w, c_int), &
            int(t%rows * t%cell_px_h, c_int))
        t%dirty = .true.
#else
        t%rows = rows
        t%cols = cols
        t%cell_px_w = cell_px_w
        t%cell_px_h = cell_px_h
#endif
    end subroutine term_resize

#ifdef ENABLE_TERM
    ! --- screen ----------------------------------------------------------------

    subroutine grid(t)
        type(term_t), intent(inout) :: t
        integer :: n
        n = t%rows * t%cols
        if (allocated(t%cp)) then
            if (size(t%cp) == n) return
            deallocate(t%cp, t%fg, t%bg, t%attr)
        end if
        allocate(t%cp(n), t%fg(n), t%bg(n), t%attr(n))
        t%cp = 32
        t%fg = t%default_fg
        t%bg = 0
        t%attr = 0
        t%dirty = .true.
    end subroutine grid

    subroutine refresh(t)
        !! The cells from libvterm into the screen arrays.
        type(term_t), intent(inout) :: t
        type(vt_cell_t) :: cell
        integer :: r, c, k, st
        call grid(t)
        do r = 0, t%rows - 1
            do c = 0, t%cols - 1
                k = r * t%cols + c + 1
                st = vterm_screen_get_cell(t%screen, vt_pos_t(int(r, c_int), int(c, c_int)), &
                    cell)
                call convert(t, cell, t%cp(k), t%fg(k), t%bg(k), t%attr(k))
                if (c > 0) then
                    if (iand(t%attr(k - 1), CELL_WIDE) /= 0) t%attr(k) = ior(t%attr(k), CELL_CONT)
                end if
            end do
        end do
    end subroutine refresh

    subroutine convert(t, cell, cp, fg, bg, attr)
        type(term_t), intent(in) :: t
        type(vt_cell_t), intent(inout) :: cell
        integer(int32), intent(out) :: cp, fg, bg, attr
        integer(int32) :: swap
        integer :: a
        cp = cell%chars(1)
        if (cp == 0) cp = 32
        a = int(cell%attrs)
        attr = 0
        if (btest(a, 0)) attr = ior(attr, CELL_BOLD)
        if (iand(ishft(a, -1), 3) /= 0) attr = ior(attr, CELL_UNDERLINE)
        if (btest(a, 3)) attr = ior(attr, CELL_ITALIC)
        if (btest(a, 7)) attr = ior(attr, CELL_STRIKE)
        if (cell%width > 1) attr = ior(attr, CELL_WIDE)
        fg = colour(t, cell%fg, .true.)
        bg = colour(t, cell%bg, .false.)
        if (btest(a, 5)) then
            swap = fg
            fg = bg
            bg = swap
            if (iand(ishft(fg, -24), 255_int32) == 0) fg = ior(t%default_bg, ishft(-1_int32, 24))
            if (iand(ishft(bg, -24), 255_int32) == 0) bg = t%default_fg
        end if
        if (btest(a, 6)) fg = bg
        ! Faint text arrives as alternative font 1 (see faint_as_font).
        if (iand(ishft(a, -8), 15) == 1) then
            attr = ior(attr, CELL_DIM)
            if (iand(ishft(bg, -24), 255_int32) == 0) then
                fg = blend(fg, t%default_bg)
            else
                fg = blend(fg, bg)
            end if
        end if
    end subroutine convert

    pure integer(int32) function blend(a, b) result(c)
        !! Halfway between two colours (opaque).
        integer(int32), intent(in) :: a, b
        integer :: k, v
        c = ishft(-1_int32, 24)
        do k = 0, 2
            v = (int(iand(ishft(a, -8 * k), 255_int32)) + int(iand(ishft(b, -8 * k), 255_int32))) / 2
            c = ior(c, ishft(int(v, int32), 8 * k))
        end do
    end function blend

    integer(int32) function colour(t, col, foreground) result(rgba)
        !! ui_rgba of a libvterm colour; the default background is transparent
        !! (the widget's own fill shows).
        type(term_t), intent(in) :: t
        integer(c_int8_t), intent(inout) :: col(4)
        logical, intent(in) :: foreground
        integer :: typ
        typ = iand(int(col(1)), 255)
        if (iand(typ, 2) /= 0 .and. foreground) then
            rgba = t%default_fg
            return
        end if
        if (iand(typ, 4) /= 0 .and. .not. foreground) then
            rgba = 0
            return
        end if
        if (iand(typ, 1) /= 0) call vterm_screen_convert_color_to_rgb(t%screen, col)
        rgba = int(iand(int(col(2)), 255), int32) + ishft(int(iand(int(col(3)), 255), int32), 8) &
            + ishft(int(iand(int(col(4)), 255), int32), 16) + ishft(-1_int32, 24)
    end function colour

    function vt_rgb(rgba) result(col)
        integer(int32), intent(in) :: rgba
        integer(c_int8_t) :: col(4)
        col(1) = 0
        col(2) = int(byte_of(rgba, 0), c_int8_t)
        col(3) = int(byte_of(rgba, 1), c_int8_t)
        col(4) = int(byte_of(rgba, 2), c_int8_t)
    end function vt_rgb

    integer function byte_of(v, k)
        integer(int32), intent(in) :: v
        integer, intent(in) :: k
        byte_of = int(iand(ishft(v, -8 * k), 255_int32))
        if (byte_of > 127) byte_of = byte_of - 256
    end function byte_of

    ! --- input from the program -------------------------------------------------

    subroutine feed(t, raw)
        !! Program output to libvterm, cut after each string terminator (the
        !! cursor motion an image owes comes before the text after it) and
        !! after each erase of the display (which removes the images it erases;
        !! libvterm does not report erasing).
        type(term_t), intent(inout) :: t
        character(*), intent(in) :: raw
        character(len=*), parameter :: CSI = achar(27) // "["
        integer :: first, k, cut, kind, j
        integer(c_size_t) :: n
        character(len=:), allocatable :: bytes
        bytes = faint_as_font(raw)
        first = 1
        do while (first <= len(bytes))
            cut = 0
            kind = 0
            k = index(bytes(first:), achar(27) // "\")
            if (k > 0) then
                cut = first + k
                kind = 1
            end if
            do j = 1, 4
                k = index(bytes(first:), CSI // trim(ERASES(j)))
                if (k == 0) cycle
                k = first + k + len_trim(ERASES(j))
                if (cut == 0 .or. k < cut) then
                    cut = k
                    kind = 1 + j
                end if
            end do
            if (cut == 0) cut = len(bytes)
            n = vterm_input_write(t%vt, bytes(first:cut), int(cut - first + 1, c_size_t))
            first = cut + 1
            select case (kind)
            case (2, 3); call erase_images(t, 0)
            case (4, 5); call erase_images(t, t%cursor_row)
            end select
            call owed_motion(t)
        end do
    end subroutine feed

    function faint_as_font(bytes) result(out)
        !! libvterm keeps no faint attribute: SGR 2 becomes alternative font 1
        !! (SGR 11), which it keeps per cell, and SGR 22 also selects font 0.
        !! Colour arguments (38/48/58 with 5;n or 2;r;g;b) pass unchanged.
        !! Sequences cut by the end of a read are left as they are.
        character(*), intent(in) :: bytes
        character(len=:), allocatable :: out, buf
        integer :: n, p, q, k, a, b, skip
        character(len=8) :: tok
        allocate(character(len=len(bytes) + 64) :: buf)
        n = 0
        p = 1
        do
            q = index(bytes(p:), achar(27) // "[")
            if (q == 0) exit
            q = p + q - 1
            k = q + 2
            do while (k <= len(bytes))
                if (verify(bytes(k:k), "0123456789;:") /= 0) exit
                k = k + 1
            end do
            if (k > len(bytes)) exit
            if (bytes(k:k) /= "m" .or. index(bytes(q + 2:k - 1), "2") == 0) then
                call put(bytes(p:k))
                p = k + 1
                cycle
            end if
            call put(bytes(p:q + 1))
            a = q + 2
            skip = 0
            do while (a <= k - 1 .or. a == q + 2)
                b = index(bytes(a:k), ";") - 1
                if (b < 0) b = k - a
                tok = bytes(a:a + b - 1)
                if (a > q + 2) call put(";")
                if (skip > 0) then
                    skip = skip - 1
                    call put(trim(tok))
                else if (tok == "2") then
                    call put("11")
                else if (tok == "22") then
                    call put("22;10")
                else
                    call put(trim(tok))
                    if (tok == "38" .or. tok == "48" .or. tok == "58") then
                        if (bytes(a + b + 1:a + b + 2) == "5;") skip = 2
                        if (bytes(a + b + 1:a + b + 2) == "2;") skip = 4
                    end if
                end if
                a = a + b + 1
                if (a > k - 1) exit
            end do
            call put("m")
            p = k + 1
            if (p > len(bytes)) exit
        end do
        if (p <= len(bytes)) call put(bytes(p:))
        out = buf(1:n)
    contains
        subroutine put(s)
            character(*), intent(in) :: s
            character(len=:), allocatable :: grown
            if (n + len(s) > len(buf)) then
                allocate(character(len=2 * (n + len(s))) :: grown)
                grown(1:n) = buf(1:n)
                call move_alloc(grown, buf)
            end if
            buf(n + 1:n + len(s)) = s
            n = n + len(s)
        end subroutine put
    end function faint_as_font

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
        integer(c_size_t) :: n
        if (len(t%motion) == 0) return
        m = t%motion
        t%motion = ""
        n = vterm_input_write(t%vt, m, int(len(m), c_size_t))
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

    ! --- libvterm callbacks ------------------------------------------------------

    subroutine cb_output(s, n, user) bind(C)
        !! What libvterm answers or encodes for the program (keys, replies).
        !! Its device attributes reply gains "4": this terminal shows sixel.
        type(c_ptr), value :: s, user
        integer(c_size_t), value :: n
        type(term_t), pointer :: t
        character(kind=c_char, len=int(n)), pointer :: str
        call c_f_pointer(user, t)
        call c_f_pointer(s, str)
        if (str == achar(27) // "[?1;2c") then
            call write_all(t%fd, achar(27) // "[?62;4;22c")
        else
            call write_all(t%fd, str)
        end if
    end subroutine cb_output

    integer(c_int) function cb_damage(rect, user) bind(C)
        type(vt_rect_t), value :: rect
        type(c_ptr), value :: user
        type(term_t), pointer :: t
        call c_f_pointer(user, t)
        t%dirty = .true.
        cb_damage = 1
        if (rect%start_row < 0) continue
    end function cb_damage

    integer(c_int) function cb_moverect(dest, src, user) bind(C)
        !! Text moved (scrolling): images in the moved rows go with it.
        type(vt_rect_t), value :: dest, src
        type(c_ptr), value :: user
        type(term_t), pointer :: t
        integer :: k, dy
        call c_f_pointer(user, t)
        t%dirty = .true.
        cb_moverect = 1
        dy = dest%start_row - src%start_row
        if (dy == 0 .or. src%start_col /= 0 .or. src%end_col < t%cols) return
        ! Scrolling up from the top row pushes lines into the scrollback, and
        ! cb_sb_pushline moves the images; libvterm reports some of those
        ! scrolls here as well.
        if (dest%start_row == 0 .and. dy < 0) return
        do k = 1, t%nplaces
            if (t%places(k)%row >= src%start_row .and. t%places(k)%row < src%end_row) &
                t%places(k)%row = t%places(k)%row + dy
        end do
        call drop_old_places(t)
    end function cb_moverect

    integer(c_int) function cb_movecursor(pos, oldpos, visible, user) bind(C)
        type(vt_pos_t), value :: pos, oldpos
        integer(c_int), value :: visible
        type(c_ptr), value :: user
        type(term_t), pointer :: t
        call c_f_pointer(user, t)
        t%cursor_row = pos%row
        t%cursor_col = pos%col
        t%dirty = .true.
        cb_movecursor = 1
        if (oldpos%row < 0 .or. visible < 0) continue
    end function cb_movecursor

    integer(c_int) function cb_settermprop(prop, val, user) bind(C)
        integer(c_int), value :: prop
        type(c_ptr), value :: val, user
        type(term_t), pointer :: t
        integer(c_int), pointer :: ival
        type(vt_fragment_t), pointer :: frag
        call c_f_pointer(user, t)
        cb_settermprop = 1
        select case (prop)
        case (PROP_CURSORVISIBLE)
            call c_f_pointer(val, ival)
            t%cursor_visible = ival /= 0
            t%dirty = .true.
        case (PROP_ALTSCREEN)
            call c_f_pointer(val, ival)
            t%altscreen = ival /= 0
            ! Images belong to the screen they were shown on.
            t%nplaces = 0
            t%dirty = .true.
        case (PROP_MOUSE)
            call c_f_pointer(val, ival)
            t%mouse_mode = ival
        case (PROP_TITLE)
            call c_f_pointer(val, frag)
            if (frag_initial(frag)) t%title_part = ""
            t%title_part = t%title_part // frag_text(frag)
            if (frag_final(frag)) then
                t%title = t%title_part
                t%dirty = .true.
            end if
        end select
    end function cb_settermprop

    integer(c_int) function cb_bell(user) bind(C)
        type(c_ptr), value :: user
        type(term_t), pointer :: t
        call c_f_pointer(user, t)
        t%bell = .true.
        cb_bell = 1
    end function cb_bell

    integer(c_int) function cb_sb_pushline(cols, cells, user) bind(C)
        !! A line scrolled off the top: into the scrollback ring.
        integer(c_int), value :: cols
        type(c_ptr), value :: cells, user
        type(term_t), pointer :: t
        type(vt_cell_t), pointer :: row(:)
        integer :: c
        call c_f_pointer(user, t)
        call c_f_pointer(cells, row, [int(cols)])
        cb_sb_pushline = 1
        ! The top line leaves the screen: images move up with the text (libvterm
        ! merges scrolling into damage here, so moverect does not report it).
        t%places(1:t%nplaces)%row = t%places(1:t%nplaces)%row - 1
        call drop_old_places(t)
        t%sb_head = modulo(t%sb_head, size(t%sb)) + 1
        t%sb_count = min(t%sb_count + 1, size(t%sb))
        associate(line => t%sb(t%sb_head))
            if (allocated(line%cp)) then
                if (size(line%cp) /= cols) deallocate(line%cp, line%fg, line%bg, line%attr)
            end if
            if (.not. allocated(line%cp)) allocate(line%cp(cols), line%fg(cols), &
                line%bg(cols), line%attr(cols))
            do c = 1, int(cols)
                call convert(t, row(c), line%cp(c), line%fg(c), line%bg(c), line%attr(c))
                if (c > 1) then
                    if (iand(line%attr(c - 1), CELL_WIDE) /= 0) &
                        line%attr(c) = ior(line%attr(c), CELL_CONT)
                end if
            end do
        end associate
    end function cb_sb_pushline

    integer(c_int) function cb_sb_clear(user) bind(C)
        type(c_ptr), value :: user
        type(term_t), pointer :: t
        call c_f_pointer(user, t)
        t%sb_count = 0
        cb_sb_clear = 1
    end function cb_sb_clear

    integer(c_int) function cb_dcs(command, commandlen, frag, user) bind(C)
        !! Device control strings: "q" ones are sixel images.
        type(c_ptr), value :: command, user
        integer(c_size_t), value :: commandlen
        type(vt_fragment_t), value, target :: frag
        type(term_t), pointer :: t
        character(kind=c_char, len=int(commandlen)), pointer :: cmd
        call c_f_pointer(user, t)
        cb_dcs = 1
        if (frag_initial(frag)) then
            call c_f_pointer(command, cmd)
            t%dcs_command = cmd
            t%ndcs = 0
        end if
        if (len(t%dcs_command) == 0) return
        if (t%dcs_command(len(t%dcs_command):) /= "q") return
        call append(t%dcs, t%ndcs, frag_text(frag))
        if (frag_final(frag)) then
            call show_sixel(t, t%dcs_command(1:len(t%dcs_command) - 1), t%dcs(1:t%ndcs))
            t%ndcs = 0
            t%dcs_command = ""
        end if
    end function cb_dcs

    integer(c_int) function cb_apc(frag, user) bind(C)
        !! Application program commands: "G..." ones are kitty graphics.
        type(vt_fragment_t), value, target :: frag
        type(c_ptr), value :: user
        type(term_t), pointer :: t
        call c_f_pointer(user, t)
        cb_apc = 1
        if (frag_initial(frag)) t%napc = 0
        if (t%napc < 64 * 1024 * 1024) call append(t%apc, t%napc, frag_text(frag))
        if (frag_final(frag)) then
            if (t%napc > 0) then
                if (t%apc(1:1) == "G") call kitty_command(t, t%apc(2:t%napc))
            end if
            t%napc = 0
        end if
    end function cb_apc

    function frag_text(frag) result(s)
        type(vt_fragment_t), intent(in) :: frag
        character(len=:), allocatable :: s
        character(kind=c_char, len=int(iand(frag%bits, 1073741823_c_size_t))), pointer :: p
        integer :: n
        n = int(iand(frag%bits, 1073741823_c_size_t))
        if (n == 0 .or. .not. c_associated(frag%str)) then
            s = ""
            return
        end if
        call c_f_pointer(frag%str, p)
        s = p
    end function frag_text

    logical function frag_initial(frag)
        type(vt_fragment_t), intent(in) :: frag
        frag_initial = btest(frag%bits, 30)
    end function frag_initial

    logical function frag_final(frag)
        type(vt_fragment_t), intent(in) :: frag
        frag_final = btest(frag%bits, 31)
    end function frag_final

    subroutine append(buf, n, s)
        character(len=:), allocatable, intent(inout) :: buf
        integer, intent(inout) :: n
        character(*), intent(in) :: s
        character(len=:), allocatable :: grown
        if (.not. allocated(buf)) buf = ""
        if (n + len(s) > len(buf)) then
            allocate(character(len=max(4096, 2 * (n + len(s)))) :: grown)
            grown(1:n) = buf(1:n)
            call move_alloc(grown, buf)
        end if
        buf(n + 1:n + len(s)) = s
        n = n + len(s)
    end subroutine append

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
            t%motion = repeat(achar(10), max(0, rows - 1)) // achar(27) // "[" // &
                itoa(t%cursor_col + cols + 1) // "G"
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
            if (t%places(k)%row + t%places(k)%rows <= -size(t%sb)) cycle
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
#endif

end module fortui_term
