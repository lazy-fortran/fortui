program test_tb
    !! The terminal layer against fortui's own terminal emulator (fortui_vt):
    !! rendered cells fed to the emulator must show the grid, and keys and
    !! mouse events as the emulator encodes them (as xterm does) must decode to
    !! the same keys, buttons and positions.
    use iso_fortran_env, only: int32
    use fortui_tb
    use fortui_vt, only: vt_t, vt_open, vt_feed, vt_line, vt_key, vt_mouse, &
        vt_take_output, VT_BOLD
    implicit none

    integer :: failures = 0
    integer(int32), parameter :: RGB = int(z'FFFFFF', int32)

    call test_render_truecolor()
    call test_render_256()
    call test_keys()
    call test_mouse()
    call test_partial_and_replies()

    if (failures > 0) then
        print '(i0,a)', failures, " terminal checks failed"
        error stop 1
    end if
    print '(a)', " fortui_tb tests passed"

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            failures = failures + 1
            print '(a)', "FAIL: " // what
        end if
    end subroutine check

    subroutine feed(vt, s)
        type(vt_t), intent(inout) :: vt
        character(*), intent(in) :: s
        integer :: pos, event
        pos = 1
        do while (pos <= len(s))
            call vt_feed(vt, s, pos, event)
        end do
    end subroutine feed

    subroutine put_text(g, x, y, s, fg, bg)
        type(tb_grid_t), intent(inout) :: g
        integer, intent(in) :: x, y
        integer, intent(in) :: s(:)
        integer(int32), intent(in) :: fg, bg
        integer :: k
        do k = 1, size(s)
            call tb_grid_set(g, x + k - 1, y, int(s(k), int32), fg, bg)
        end do
    end subroutine put_text

    logical function shows(vt, g, x, y)
        !! Emulator cell (x, y), 1-based, has the grid's character and colours
        !! (truecolor attributes; colour 0 is the default).
        type(vt_t), intent(in) :: vt
        type(tb_grid_t), intent(in) :: g
        integer, intent(in) :: x, y
        integer :: line
        integer(int32) :: fg, bg
        line = vt_line(vt, y - 1)
        fg = iand(g%fg(x, y), RGB)
        bg = iand(g%bg(x, y), RGB)
        shows = vt%cp(x, line) == g%ch(x, y) .and. &
            (rgb_of(vt%fg(x, line)) == fg .or. (fg == 0 .and. vt%fg(x, line) == vt%default_fg)) &
            .and. rgb_of(vt%bg(x, line)) == bg
    end function shows

    pure integer function count_moves(s) result(n)
        !! Cursor positionings (ESC [ row ; col H) in s.
        character(*), intent(in) :: s
        integer :: k
        n = 0
        do k = 1, len(s)
            if (s(k:k) == "H") n = n + 1
        end do
    end function count_moves

    pure integer(int32) function rgb_of(c) result(rgb)
        !! 0x00RRGGBB of an emulator colour (bytes R, G, B, A in memory order).
        integer(int32), intent(in) :: c
        rgb = ior(ior(ishft(iand(c, 255_int32), 16), iand(c, 65280_int32)), &
            iand(ishft(c, -16), 255_int32))
    end function rgb_of

    subroutine test_render_truecolor()
        type(tb_grid_t) :: back, front
        type(vt_t) :: vt
        character(len=:), allocatable :: out
        integer(int32) :: red, blue, white
        integer :: x, y, line
        logical :: all_ok

        red = int(z'C81E3C', int32)
        blue = int(z'1F4E79', int32)
        white = int(z'FFFFFF', int32)
        call tb_grid_resize(back, 12, 3)
        call tb_grid_resize(front, 12, 3)
        call tb_grid_clear(back, white, blue)
        front%ch = -1
        ! "Héllo ❯" in bold red on blue, a wide 漢 at column 9, defaults below.
        call put_text(back, 1, 1, [72, 233, 108, 108, 111, 32, 10095], ior(red, TB_BOLD), blue)
        call tb_grid_set(back, 9, 1, 28450_int32, white, blue)
        call put_text(back, 1, 3, [97, 98, 99], 0_int32, 0_int32)
        out = ""
        call tb_render(back, front, TB_OUTPUT_TRUECOLOR, out)
        call vt_open(vt, 3, 12, 0)
        call feed(vt, out)
        all_ok = .true.
        do y = 1, 3
            do x = 1, 12
                if (y == 1 .and. x == 10) cycle
                if (.not. shows(vt, back, x, y)) then
                    all_ok = .false.
                    print '(a,i0,a,i0)', "  differs at column ", x, " row ", y
                end if
            end do
        end do
        call check(all_ok, "every cell reaches the terminal with its colours")
        line = vt_line(vt, 0)
        call check(iand(vt%attr(1, line), VT_BOLD) /= 0, "bold attribute")
        call check(all(front%ch(1:9, 1) == back%ch(1:9, 1)) .and. front%ch(10, 1) == -2, &
            "front grid follows, the cell under the wide character is covered")

        ! One changed cell: only it is sent.
        call tb_grid_set(back, 5, 2, 120_int32, red, blue)
        out = ""
        call tb_render(back, front, TB_OUTPUT_TRUECOLOR, out)
        call feed(vt, out)
        call check(shows(vt, back, 5, 2), "changed cell drawn")
        call check(index(out, "x") == len(out) .and. count_moves(out) == 1, &
            "only the changed cell is sent")
        out = ""
        call tb_render(back, front, TB_OUTPUT_TRUECOLOR, out)
        call check(len(out) == 0, "an unchanged frame sends nothing")

        ! Black needs TB_HI_BLACK; plain 0 is the terminal's default colour.
        call tb_grid_set(back, 1, 2, 66_int32, ior(0_int32, TB_HI_BLACK), white)
        out = ""
        call tb_render(back, front, TB_OUTPUT_TRUECOLOR, out)
        call feed(vt, out)
        line = vt_line(vt, 1)
        call check(vt%cp(1, line) == 66 .and. rgb_of(vt%fg(1, line)) == 0 .and. &
            vt%fg(1, line) /= vt%default_fg, "black foreground")
    end subroutine test_render_truecolor

    subroutine test_render_256()
        type(tb_grid_t) :: back, front
        type(vt_t) :: vt
        character(len=:), allocatable :: out
        integer :: line

        call tb_grid_resize(back, 4, 1)
        call tb_grid_resize(front, 4, 1)
        call tb_grid_clear(back, 0_int32, 0_int32)
        front%ch = -1
        call tb_grid_set(back, 2, 1, 65_int32, ior(196_int32, TB_UNDERLINE), 21_int32)
        call tb_grid_set(back, 3, 1, 66_int32, TB_HI_BLACK, 0_int32)
        out = ""
        call tb_render(back, front, TB_OUTPUT_256, out)
        call vt_open(vt, 1, 4, 0)
        call feed(vt, out)
        line = vt_line(vt, 0)
        call check(vt%cp(2, line) == 65 .and. vt%fg(2, line) == vt%palette(196) .and. &
            vt%bg(2, line) == vt%palette(21), "256-colour palette entries")
        call check(vt%fg(3, line) == vt%palette(0), "palette black")
        call check(vt%fg(1, line) == vt%default_fg .and. vt%bg(1, line) == 0, &
            "default colours")
    end subroutine test_render_256

    integer function decoded_key(vt, final) result(k)
        !! The key the emulator's last encoding decodes to (ch for a character).
        type(vt_t), intent(inout) :: vt
        logical, intent(in) :: final
        character(len=:), allocatable :: s
        type(tb_event) :: ev
        integer :: used
        call vt_take_output(vt, s)
        call tb_decode(s, final, ev, used)
        k = -1
        if (used /= len(s) .or. ev%type /= TB_EVENT_KEY) return
        k = ev%key
        if (ev%ch /= 0) k = -ev%ch
    end function decoded_key

    subroutine test_keys()
        type(vt_t) :: vt
        integer :: mode, n, k
        integer, parameter :: named(14) = [1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 3]
        integer :: expect(14)
        character(len=:), allocatable :: s
        type(tb_event) :: ev
        integer :: used, pos

        expect = [TB_KEY_ENTER, TB_KEY_TAB, TB_KEY_ESC, TB_KEY_ARROW_UP, TB_KEY_ARROW_DOWN, &
            TB_KEY_ARROW_LEFT, TB_KEY_ARROW_RIGHT, TB_KEY_INSERT, TB_KEY_DELETE, &
            TB_KEY_HOME, TB_KEY_END, TB_KEY_PGUP, TB_KEY_PGDN, TB_KEY_BACKSPACE2]
        call vt_open(vt, 4, 20, 0)
        ! Normal and application cursor keys (the latter is what tb_init selects).
        do mode = 1, 2
            if (mode == 2) call feed(vt, achar(27) // "[?1h" // achar(27) // "=")
            do n = 1, size(named)
                call vt_key(vt, named(n), 0, .false., .false., .false.)
                k = decoded_key(vt, .true.)
                if (named(n) == 3) then
                    call check(k == TB_KEY_BACKSPACE2 .or. k == TB_KEY_BACKSPACE, "Backspace")
                else
                    call check(k == expect(n), "named key " // achar(48 + n / 10) // &
                        achar(48 + mod(n, 10)))
                end if
            end do
            do n = 1, 12
                call vt_key(vt, 100 + n, 0, .false., .false., .false.)
                call check(decoded_key(vt, .true.) == TB_KEY_F1 - (n - 1), "function key")
            end do
            call vt_key(vt, 5, 0, .true., .false., .true.)
            call check(decoded_key(vt, .true.) == TB_KEY_ARROW_UP, "Ctrl+Shift+Up")
        end do
        call vt_key(vt, 0, iachar("a"), .false., .false., .false.)
        call check(decoded_key(vt, .true.) == -iachar("a"), "letter")
        call vt_key(vt, 0, 233, .false., .false., .false.)
        call check(decoded_key(vt, .true.) == -233, "two-byte UTF-8")
        call vt_key(vt, 0, 28450, .false., .false., .false.)
        call check(decoded_key(vt, .true.) == -28450, "three-byte UTF-8")
        call vt_key(vt, 0, 128512, .false., .false., .false.)
        call check(decoded_key(vt, .true.) == -128512, "four-byte UTF-8")
        call vt_key(vt, 0, iachar("c"), .false., .false., .true.)
        call check(decoded_key(vt, .true.) == TB_KEY_CTRL_C, "Ctrl+C")

        ! Several keys in one read come out one by one.
        s = "x" // achar(27) // "OA" // achar(27) // "[3~" // achar(13)
        pos = 1
        k = 0
        do while (pos <= len(s))
            call tb_decode(s(pos:), .false., ev, used)
            if (used == 0) exit
            pos = pos + used
            k = k + 1
            select case (k)
            case (1); call check(ev%ch == iachar("x"), "first of several")
            case (2); call check(ev%key == TB_KEY_ARROW_UP, "second of several")
            case (3); call check(ev%key == TB_KEY_DELETE, "third of several")
            case (4); call check(ev%key == TB_KEY_ENTER, "fourth of several")
            end select
        end do
        call check(k == 4 .and. pos == len(s) + 1, "four keys from one read")
    end subroutine test_keys

    subroutine mouse_event(vt, row, col, button, pressed, moved, ev)
        type(vt_t), intent(inout) :: vt
        integer, intent(in) :: row, col, button
        logical, intent(in) :: pressed, moved
        type(tb_event), intent(out) :: ev
        character(len=:), allocatable :: s
        integer :: used
        call vt_mouse(vt, row, col, button, pressed, moved, .false., .false., .false.)
        call vt_take_output(vt, s)
        call tb_decode(s, .false., ev, used)
        if (used /= len(s)) ev%type = -1
    end subroutine mouse_event

    subroutine test_mouse()
        type(vt_t) :: vt
        type(tb_event) :: ev
        integer :: enc

        call vt_open(vt, 24, 80, 0)
        ! SGR (what tb_set_input_mode asks for), then the old X10 bytes.
        do enc = 1, 2
            if (enc == 1) then
                call feed(vt, achar(27) // "[?1003h" // achar(27) // "[?1006h")
            else
                call feed(vt, achar(27) // "[?1006l")
            end if
            call mouse_event(vt, 4, 9, 0, .true., .false., ev)
            call check(ev%type == TB_EVENT_MOUSE .and. ev%key == TB_KEY_MOUSE_LEFT .and. &
                ev%x == 9 .and. ev%y == 4 .and. ev%mod == 0, "left press and position")
            call mouse_event(vt, 5, 10, 0, .true., .true., ev)
            call check(ev%key == TB_KEY_MOUSE_LEFT .and. ev%mod == TB_MOD_MOTION .and. &
                ev%x == 10 .and. ev%y == 5, "drag")
            call mouse_event(vt, 5, 10, 0, .false., .false., ev)
            call check(ev%key == TB_KEY_MOUSE_RELEASE .and. ev%mod == 0, "release")
            call mouse_event(vt, 6, 11, -1, .false., .true., ev)
            call check(ev%key == TB_KEY_MOUSE_RELEASE .and. ev%mod == TB_MOD_MOTION, &
                "motion without a button")
            call mouse_event(vt, 1, 1, 2, .true., .false., ev)
            call check(ev%key == TB_KEY_MOUSE_RIGHT, "right button")
            call mouse_event(vt, 1, 1, 1, .true., .false., ev)
            call check(ev%key == TB_KEY_MOUSE_MIDDLE, "middle button")
            call mouse_event(vt, 2, 3, 64, .true., .false., ev)
            call check(ev%key == TB_KEY_MOUSE_WHEEL_UP .and. ev%x == 3, "wheel up")
            call mouse_event(vt, 2, 3, 65, .true., .false., ev)
            call check(ev%key == TB_KEY_MOUSE_WHEEL_DOWN, "wheel down")
        end do
    end subroutine test_mouse

    subroutine test_partial_and_replies()
        type(tb_event) :: ev
        integer :: used
        character(len=*), parameter :: E = achar(27)

        call tb_decode(E // "[", .false., ev, used)
        call check(used == 0, "incomplete sequence waits")
        call tb_decode(E // "[", .true., ev, used)
        call check(used == 1 .and. ev%key == TB_KEY_ESC, "lone Escape after waiting")
        call tb_decode(E, .false., ev, used)
        call check(used == 0, "Escape alone waits for a sequence")
        call tb_decode(achar(195), .false., ev, used)
        call check(used == 0, "incomplete UTF-8 waits")
        call tb_decode(E // "[?62;4c" // "q", .false., ev, used)
        call check(used == 8 .and. ev%type == 0, "device attributes reply is dropped")
        call tb_decode(E // "_Gi=1;OK" // E // "\", .false., ev, used)
        call check(used == 11 .and. ev%type == 0, "kitty graphics reply is dropped")
        call tb_decode(E // "]11;rgb:0000/0000/0000" // achar(7), .false., ev, used)
        call check(used == 24 .and. ev%type == 0, "OSC reply is dropped")
        call tb_decode(E // "x", .false., ev, used)
        call check(used == 1 .and. ev%key == TB_KEY_ESC, "Alt+x is Escape, then x")
    end subroutine test_partial_and_replies

end program test_tb
