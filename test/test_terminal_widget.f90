program test_terminal_widget
    !! The terminal widget on the headless host: the grid follows the space the
    !! widget gets, typed text and Enter reach the program once the widget has
    !! the focus (Tab stays with it), and Ctrl+Shift+C copies the selection
    !! text the widget computes.
    use iso_fortran_env, only: int64
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_inject_text, ui_inject_key, ui_focused_id
    use fortui_term, only: term_t, term_close, term_available
    use fortui_terminal, only: terminal, terminal_view_t, terminal_selection
    implicit none

    type(term_t), target, save :: t
    type(terminal_view_t), save :: v
    character(len=64) :: cmd(3)
    integer :: stat, k, failures
    integer(int64) :: t0, now, rate
    real :: cw, ch

    failures = 0
    if (.not. term_available()) then
        print *, "terminal widget tests skipped (built without -DENABLE_TERM=1)"
        stop
    end if
    call ui_init(headless_backend_t(), 640, 400, "terminal", stat=stat)
    cmd(1) = "/bin/sh"
    cmd(2) = "-c"
    cmd(3) = "read -r x; echo got:$x; read -r y"
    call frame()
    call ui_cell_metrics(14.0, cw, ch)
    call check(v%cols == int(640.0 / v%cell_w) .and. v%rows == int(400.0 / v%cell_h), &
        "grid fills the widget")
    call check(t%cols == v%cols .and. t%rows == v%rows, "program sees the grid size")
    call check(trim(ui_focused_id()) == "term", "terminal has the focus")
    call ui_inject_key(KEY_TAB)
    call frame()
    call check(trim(ui_focused_id()) == "term", "Tab stays with the terminal")
    call ui_inject_text("hi")
    call frame()
    call ui_inject_key(KEY_ENTER)
    call system_clock(t0, rate)
    do k = 1, 1000
        call frame()
        if (index(row(1), "got:") > 0) exit
        call system_clock(now)
        if (real(now - t0) / real(rate) > 5.0) exit
    end do
    ! The Tab went to the program: the shell read it as part of the line.
    call check(index(row(1), "got:") == 1 .and. index(row(1), "hi") > 0, &
        "typed text reaches the program: " // row(1))
    v%selected = .true.
    v%anchor = [1, 0]
    v%head = [1, 3]
    call check(terminal_selection(t, v) == "got:", "selection text")
    call term_close(t)
    call ui_shutdown()
    if (failures > 0) error stop "terminal widget tests failed"
    print *, "fortui terminal widget tests passed"

contains

    subroutine frame()
        call ui_frame_begin()
        call terminal("term", t, v, 14.0, UI_FILL, UI_FILL, cmd)
        call ui_focus("term")
        call ui_present()
    end subroutine frame

    function row(r) result(s)
        integer, intent(in) :: r
        character(len=:), allocatable :: s
        integer :: c
        s = ""
        if (.not. allocated(t%cp)) return
        do c = 1, t%cols
            if (t%cp(r * t%cols + c) < 128) s = s // achar(t%cp(r * t%cols + c))
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

end program test_terminal_widget
