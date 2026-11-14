program test_vt
    !! The terminal engine against xterm behaviour: cursor addressing, erasing,
    !! scroll regions, insert and delete, the alternate screen, wide
    !! characters, autowrap, the scrollback ring, resizing and key encoding.
    use iso_fortran_env, only: int32
    use fortui_vt
    implicit none

    type(vt_t) :: vt
    integer :: failures = 0
    character(len=*), parameter :: E = achar(27)
    character(len=:), allocatable :: out

    call vt_open(vt, 5, 10, scrollback=20)
    call feed("hello" // achar(13) // achar(10) // "world")
    call check(row(0) == "hello" .and. row(1) == "world", "text and CR LF")
    call check(vt%cr == 1 .and. vt%cc == 5, "cursor after text")

    call feed(E // "[2;3H" // "X")
    call check(row(1) == "woXld", "CUP is 1-based")
    call feed(E // "[1;1H" // E // "[K")
    call check(row(0) == "", "EL erases to the end")
    call feed(E // "[2J" // E // "[H" // "abc" // E // "[1D" // E // "[@" // "Z")
    call check(row(0) == "abZc", "ICH inserts")
    call feed(E // "[1;1H" // E // "[2P")
    call check(row(0) == "Zc", "DCH deletes")

    ! Autowrap at the right margin, deferred until the next character.
    call feed(E // "[2J" // E // "[H" // "0123456789")
    call check(vt%cr == 0 .and. vt%cc == 9, "deferred wrap")
    call feed("A")
    call check(row(1) == "A", "wrap on the next character")

    ! Text ending at the right margin of the last row, then an escape: no
    ! scrolling (fed in one piece, as programs write it).
    call feed(E // "[2J" // E // "[5;1H" // "0123456789" // E // "(B" // E // "[1;1H" // "top")
    call check(row(4) == "0123456789" .and. row(0) == "top" .and. vt%sb_count == 0, &
        "no wrap without a following character")

    ! Scroll region: line feed at its bottom scrolls only the region.
    call feed(E // "[2J" // E // "[H" // "1" // achar(13) // achar(10) // "2" // achar(13) // &
        achar(10) // "3" // achar(13) // achar(10) // "4" // achar(13) // achar(10) // "5")
    call feed(E // "[2;4r" // E // "[4;1H" // achar(10))
    call check(row(0) == "1" .and. row(1) == "3" .and. row(3) == "" .and. row(4) == "5", &
        "scroll region")
    call check(vt%sb_count == 0, "region scrolls do not feed the scrollback")
    call feed(E // "[r" // E // "[2;1H" // E // "[L")
    call check(row(1) == "" .and. row(2) == "3", "IL")
    call feed(E // "[M")
    call check(row(1) == "3", "DL")

    ! Whole-screen scrolling goes into the scrollback ring.
    call feed(E // "[2J" // E // "[H" // repeat("x" // achar(13) // achar(10), 7) // "y")
    call check(vt%sb_count == 3 .and. row(-1) == "x" .and. row(4) == "y", "scrollback")

    ! Alternate screen keeps the main one.
    call feed(E // "[?1049h" // "alt")
    call check(vt%alt .and. index(row(vt%cr), "alt") > 0 .and. row(0) == "", &
        "alternate screen (cursor stays, screen cleared)")
    call feed(E // "[?1049l")
    call check(.not. vt%alt .and. row(4) == "y", "main screen back")

    ! Wide characters take two cells.
    call feed(E // "[2J" // E // "[H" // char(228) // char(184) // char(173) // "a")
    call check(vt%cp(1, vt_line(vt, 0)) == 20013 .and. &
        iand(vt%attr(2, vt_line(vt, 0)), VT_CONT) /= 0 .and. vt%cp(3, vt_line(vt, 0)) == 97, &
        "wide character")

    ! Colours: palette, bold is bright, RGB, reverse.
    call feed(E // "[2J" // E // "[H" // E // "[34mb" // E // "[1mB" // E // &
        "[0;38;2;10;20;30mr" // E // "[0;7mv" // E // "[0m")
    call check(vt%fg(1, vt_line(vt, 0)) == vt%palette(4), "blue")
    call check(vt%fg(2, vt_line(vt, 0)) == vt%palette(12), "bold blue is bright")
    call check(vt%fg(3, vt_line(vt, 0)) == int(z'FF1E140A', int32), "RGB colour")
    call check(vt%bg(4, vt_line(vt, 0)) == vt%default_fg, "reverse")

    ! Replies.
    call feed(E // "[3;4H" // E // "[6n" // E // "[c")
    call vt_take_output(vt, out)
    call check(out == E // "[3;4R" // E // "[?62;4;22c", "cursor report and attributes")

    ! Resize: a shorter screen moves lines above the cursor into the scrollback.
    call vt_open(vt, 5, 10, scrollback=20)
    call feed("a" // achar(13) // achar(10) // "b" // achar(13) // achar(10) // "c" // &
        achar(13) // achar(10) // "d")
    call vt_resize(vt, 2, 8)
    call check(row(0) == "c" .and. row(1) == "d" .and. row(-1) == "b" .and. vt%cr == 1, &
        "resize keeps the cursor line")

    ! Keys.
    call vt_key(vt, 5, 0, .false., .false., .false.)
    call vt_key(vt, 0, iachar("c"), .false., .false., .true.)
    call vt_key(vt, 7, 0, .false., .false., .true.)
    call vt_key(vt, 105, 0, .false., .false., .false.)
    call vt_take_output(vt, out)
    call check(out == E // "[A" // achar(3) // E // "[1;5D" // E // "[15~", "key encoding")
    call feed(E // "[?1h")
    call vt_key(vt, 5, 0, .false., .false., .false.)
    call vt_take_output(vt, out)
    call check(out == E // "OA", "application cursor keys")

    if (failures > 0) error stop "terminal engine tests failed"
    print *, "fortui terminal engine tests passed"

contains

    subroutine feed(s)
        character(*), intent(in) :: s
        integer :: pos, ev
        pos = 1
        do while (pos <= len(s))
            call vt_feed(vt, s, pos, ev)
        end do
    end subroutine feed

    function row(r) result(s)
        integer, intent(in) :: r
        character(len=:), allocatable :: s
        integer :: c, line
        s = ""
        line = vt_line(vt, r)
        do c = 1, vt%cols
            if (vt%alt .and. r >= 0) then
                s = s // achar(min(127, int(vt%acp(c, line))))
            else
                s = s // achar(min(127, int(vt%cp(c, line))))
            end if
        end do
        s = trim(s)
    end function row

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print *, "FAIL: ", what
            failures = failures + 1
        end if
    end subroutine check

end program test_vt
