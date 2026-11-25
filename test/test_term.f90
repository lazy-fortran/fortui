program test_term
    !! The terminal emulator against programs on a pseudo-terminal: text and
    !! colours, the device attributes reply (sixel advertised), a sixel image
    !! and the cursor below it, a kitty image with its reply, images scrolling
    !! into the scrollback, keys reaching the program, and the shown cursor
    !! during synchronized output.
    use iso_fortran_env, only: int32, int64
    use fortui_term, only: term_t, term_open, term_close, term_pump, term_key, &
        term_available
    use fortui_input, only: key_press_t, KEY_NONE, KEY_ENTER
    use fortui_frame, only: CELL_DIM
    implicit none

    type(term_t), target, save :: t
    integer :: failures = 0

    if (.not. term_available()) then
        print *, "terminal emulator tests skipped (built without -DENABLE_TERM=1)"
        stop
    end if
    call test_text()
    call test_device_attributes()
    call test_sixel()
    call test_kitty()
    call test_kitty_chunks()
    call test_clear()
    call test_kitty_bottom()
    call test_scroll()
    call test_keys()
    call test_sync_cursor()
    if (failures > 0) error stop "terminal emulator tests failed"
    print *, "fortui terminal emulator tests passed"

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print *, "FAIL: ", what
            failures = failures + 1
        end if
    end subroutine check

    subroutine run(script, rows)
        !! Run `sh -c script` to its end on a fresh terminal.
        character(*), intent(in) :: script
        integer, intent(in), optional :: rows
        character(len=512) :: cmd(3)
        logical :: ok, changed
        integer(int64) :: t0, now, rate
        integer :: r
        r = 24
        if (present(rows)) r = rows
        cmd(1) = "/bin/sh"
        cmd(2) = "-c"
        cmd(3) = script
        call term_open(t, r, 80, 8, 16, cmd, ok=ok)
        call check(ok, "terminal starts: " // script)
        call system_clock(t0, rate)
        do
            changed = term_pump(t)
            if (.not. t%alive .and. t%exit_status >= 0) exit
            call system_clock(now)
            if (real(now - t0) / real(rate) > 5.0) exit
        end do
    end subroutine run

    function row_text(r) result(s)
        integer, intent(in) :: r
        character(len=:), allocatable :: s
        integer :: c
        s = ""
        do c = 1, t%cols
            if (t%cp(r * t%cols + c) < 128) then
                s = s // achar(t%cp(r * t%cols + c))
            else
                s = s // "?"
            end if
        end do
        s = trim(s)
    end function row_text

    subroutine test_text()
        call run("printf 'hello\033[31mred\033[0m\nnext'")
        call check(row_text(0) == "hellored", "first row text: " // row_text(0))
        call check(row_text(1) == "next", "second row text")
        call check(iand(t%fg(6), int(z'00FFFFFF', int32)) /= iand(t%fg(1), &
            int(z'00FFFFFF', int32)), "red differs from the default colour")
        call check(iand(t%fg(6), 255_int32) > 150 .and. &
            iand(ishft(t%fg(6), -8), 255_int32) < 100, "red is red")
        call check(t%exit_status == 0, "exit status")
        call term_close(t)
        ! Faint (SGR 2) halves the colour; a truecolour argument 2 is no faint.
        call run("printf 'n\033[2mf\033[22mn\033[38;2;200;100;0mc'")
        call check(iand(t%attr(2), CELL_DIM) /= 0 .and. iand(t%attr(1), CELL_DIM) == 0 .and. &
            iand(t%attr(3), CELL_DIM) == 0, "faint text and its end")
        call check(iand(t%fg(2), 255_int32) < iand(t%fg(1), 255_int32), "faint is darker")
        call check(iand(t%attr(4), CELL_DIM) == 0 .and. iand(t%fg(4), 255_int32) == 200, &
            "truecolour argument is not faint")
        call term_close(t)
        ! Bold blue shows bright blue (palette 12), plain blue stays blue.
        call run("printf '\033[34mb\033[1;34mB'")
        call check(t%fg(1) /= t%fg(2), "bold is bright")
        call term_close(t)
    end subroutine test_text

    subroutine test_device_attributes()
        ! The program asks (ESC [ c) and prints what came back.
        call run("stty raw -echo; printf '\033[c'; r=$(dd bs=1 count=11 2>/dev/null); " // &
            "stty sane; printf '\n%s' ""$r"" | tr '\033' E")
        call check(index(row_text(1), "E[?62;4;22c") > 0, &
            "device attributes advertise sixel: " // row_text(1))
        call term_close(t)
    end subroutine test_device_attributes

    subroutine test_sixel()
        ! 8 x 24 red pixels in four bands; the last starts at pixel row 18,
        ! in the second row of 16-pixel cells, where X follows in column 3.
        call run("printf 'ab\033Pq#1;2;100;0;0#1!8~-!8~-!8~-!8~\033\\X'")
        call check(t%nplaces == 1, "sixel placement")
        if (t%nplaces == 1) then
            call check(t%places(1)%row == 0 .and. t%places(1)%col == 2, "sixel at the cursor")
            associate(im => t%images(t%places(1)%image))
                call check(im%width == 8 .and. im%height == 24, "sixel size")
                call check(im%rgba(1, 1) == int(z'FF0000FF', int32), "sixel colour")
            end associate
        end if
        call check(row_text(1) == "  X", "cursor after a sixel (xterm): " // row_text(1))
        call term_close(t)
    end subroutine test_sixel

    subroutine test_kitty()
        ! 2 x 1 RGB pixels (red, green), id 7: the reply is printed back.
        call run("stty raw -echo; printf '\033_Ga=T,f=24,s=2,v=1,i=7;/wAAAP8A\033\\'; " // &
            "r=$(dd bs=1 count=11 2>/dev/null); stty sane; printf '\n%s' ""$r"" | tr '\033' E")
        call check(t%nplaces == 1, "kitty placement")
        if (t%nplaces == 1) then
            associate(im => t%images(t%places(1)%image))
                call check(im%id == 7 .and. im%width == 2 .and. im%height == 1, "kitty image")
                call check(im%rgba(2, 1) == int(z'FF00FF00', int32), "kitty pixel")
            end associate
        end if
        call check(index(row_text(1), "E_Gi=7;OK") > 0 .or. index(row_text(2), "E_Gi=7;OK") &
            > 0, "kitty reply")
        call term_close(t)
    end subroutine test_kitty

    subroutine test_kitty_chunks()
        ! The keys alone in the first chunk, data in later ones (as chafa sends).
        call run("printf '\033_Ga=T,f=32,s=4,v=2,c=2,r=1,m=1,q=2\033\\\033_Gm=1;/wAA//8AAP//\033\\\033_Gm=1;AAD//wAA//8AAP//AAD//wAA//8AAP8=\033\\\033_Gm=0\033\\X'")
        call check(t%nplaces == 1, "chunked kitty placement")
        if (t%nplaces == 1) call check(t%images(t%places(1)%image)%width == 4, &
            "chunked kitty image")
        call check(t%cp(3) == iachar("X"), "cursor after a 2-cell kitty image")
        call term_close(t)
    end subroutine test_kitty_chunks

    subroutine test_kitty_bottom()
        ! An image three rows tall on the last row: the cursor stops at the
        ! bottom and the screen does not scroll (fortui's terminal host draws
        ! images there and repaints only cells it changed).
        call run("printf '\033[24;1H\033_Ga=T,f=24,s=1,v=1,c=2,r=3;/wAA\033\\X'")
        call check(t%nplaces == 1 .and. t%sb_count == 0, "image at the bottom: no scrolling")
        call check(t%cp(23 * t%cols + 3) == iachar("X"), "cursor after the image, last row")
        call term_close(t)
    end subroutine test_kitty_bottom

    subroutine test_clear()
        ! clear (ESC [H ESC [2J ESC [3J) erases the image with the text.
        call run("printf '\033Pq#1;2;100;0;0#1!8~\033\\'; printf '\033[H\033[2J\033[3Jok'")
        call check(t%nplaces == 0, "clear removes images")
        call check(row_text(0) == "ok", "text after clear")
        call term_close(t)
    end subroutine test_clear

    subroutine test_scroll()
        call run("printf '\033Pq#1;2;100;0;0#1!8~\033\\'; i=0; while [ $i -lt 30 ]; do " // &
            "echo line$i; i=$((i+1)); done", rows=10)
        call check(t%nplaces == 1, "image kept in the scrollback")
        if (t%nplaces == 1) call check(t%places(1)%row < 0, "image scrolled with the text")
        if (t%nplaces == 1) call check(t%places(1)%row == -t%sb_count, &
            "image row follows the scrollback")
        call check(t%sb_count > 0, "scrollback filled")
        call term_close(t)
    end subroutine test_scroll

    subroutine test_keys()
        character(len=512) :: cmd(3)
        type(key_press_t) :: p
        logical :: ok, changed
        integer(int64) :: t0, now, rate
        integer :: k
        cmd(1) = "/bin/sh"
        cmd(2) = "-c"
        cmd(3) = "read -r x; echo got:$x"
        call term_open(t, 24, 80, 8, 16, cmd, ok=ok)
        do k = 1, 2
            p%key = KEY_NONE
            p%code = iachar("h") + k - 1
            p%mods = 0
            call term_key(t, p)
        end do
        p%key = KEY_ENTER
        p%code = 0
        call term_key(t, p)
        call system_clock(t0, rate)
        do
            changed = term_pump(t)
            if (.not. t%alive) exit
            call system_clock(now)
            if (real(now - t0) / real(rate) > 5.0) exit
        end do
        changed = term_pump(t)
        call check(row_text(1) == "got:hi", "typed keys reach the program: " // row_text(1))
        call term_close(t)
    end subroutine test_keys

    subroutine test_sync_cursor()
        ! Between ?2026h and ?2026l the last complete frame stays, cursor
        ! included (tmux moves it through other panes while it redraws).
        character(len=512) :: cmd(3)
        logical :: ok, changed
        integer(int64) :: t0, now, rate
        cmd(1) = "/bin/sh"
        cmd(2) = "-c"
        cmd(3) = "printf '\033[3;5Hab'; sleep 0.3; printf '\033[?2026h\033[20;30Hxy'; sleep 2"
        call term_open(t, 24, 80, 8, 16, cmd, ok=ok)
        call system_clock(t0, rate)
        do
            changed = term_pump(t)
            if (t%vt%sync .and. t%vt%cr == 19) exit
            call system_clock(now)
            if (real(now - t0) / real(rate) > 5.0) exit
        end do
        changed = term_pump(t)
        call check(t%vt%sync, "synchronized output has begun")
        call check(t%cursor_row == 2 .and. t%cursor_col == 6, "cursor of the last frame: " // &
            itoa(t%cursor_row) // "," // itoa(t%cursor_col))
        call check(len(row_text(19)) == 0, "text of the last frame")
        call term_close(t)
    end subroutine test_sync_cursor

    function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=12) :: b
        write (b, '(i0)') i
        s = trim(b)
    end function itoa

end program test_term
