program test_layout_focus
    !! Wrapping rows, top alignment, focus asked for from another container,
    !! tab bars that keep their labels whole, and window width classes.
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_inject_resize, ui_node_rect, ui_focused_id
    implicit none
    integer :: fails = 0, stat, tab, k
    logical :: ask_focus = .false., twins = .false.
    character(len=:), allocatable :: name, other
    real :: x(5), y(5), w, h, below_y, ignore
    character(len=40) :: short_labels(3), long_labels(3)

    name = ''
    other = ''
    tab = 1
    short_labels = [character(len=40) :: 'A', 'B', 'C']
    long_labels = [character(len=40) :: 'A very long tab label', 'Another long tab label', 'Third long one']
    call ui_init(headless_backend_t(), 400, 300, 'layout', stat=stat)

    call frame(wrapping=.true.)
    do k = 1, 5
        call check(ui_node_rect('wrap/b' // achar(48 + k), x(k), y(k), w, h), 'button found')
    end do
    call check(y(1) == y(3) .and. y(4) > y(1) .and. x(4) == x(1) .and. y(5) == y(4), &
        'a wrapping row continues on a new line')
    call check(ui_node_rect('after', ignore, below_y, w, h) .and. below_y > y(5), &
        'the next item comes below all lines of a wrapped row')

    call frame(wrapping=.false.)
    call check(ui_node_rect('wrap/b4', x(4), y(4), w, h) .and. y(4) == y(1), 'a plain row stays one line')

    ask_focus = .true.
    call frame(wrapping=.false.)
    call frame(wrapping=.false.)
    call check(ui_focused_id() == 'panel/name', 'ui_focus reaches a field in another container, got "' // &
        ui_focused_id() // '"')
    ask_focus = .true.
    twins = .true.
    call frame(wrapping=.false.)
    call frame(wrapping=.false.)
    call check(ui_focused_id() == 'panel/name', 'an ambiguous name moves no focus')

    call check(ui_width_class() == UI_COMPACT, 'a 400 unit window is compact')
    call ui_inject_resize(900, 600)
    call frame(wrapping=.false.)
    call check(ui_width_class() == UI_EXPANDED, 'a 900 unit window is expanded')
    call ui_inject_resize(1300, 800)
    call frame(wrapping=.false.)
    call check(ui_width_class() == UI_LARGE, 'a 1300 unit window is large')

    if (fails > 0) error stop 1
    print '(a)', 'test_layout_focus: all passed'

contains

    subroutine frame(wrapping)
        logical, intent(in) :: wrapping
        real :: a1, a2, wa, wb, hh
        call ui_frame_begin()
        if (ask_focus) call ui_focus('name')
        ask_focus = .false.
        call row_begin(10.0, id='wrap', wrap=wrapping)
        do k = 1, 5
            if (button('b' // achar(48 + k), 'Button ' // achar(48 + k), width=100.0)) continue
        end do
        call row_end()
        call text('after', id='after')
        call column_begin(4.0, id='panel')
        if (text_input('name', name, width=200.0)) continue
        call column_end()
        if (twins) then
            call column_begin(4.0, id='other')
            if (text_input('name', other, width=200.0)) continue
            call column_end()
        end if
        if (tabs('short', short_labels, tab, width=300.0)) continue
        if (tabs('long', long_labels, tab, width=300.0)) continue
        call ui_present()
        if (ui_node_rect('short#1', a1, hh, wa, hh) .and. ui_node_rect('short#2', a2, hh, wb, hh)) &
            call check(abs(wa - 100.0) < 0.5 .and. abs(wb - 100.0) < 0.5, 'short tabs share the width')
        if (ui_node_rect('long#1', a1, hh, wa, hh)) &
            call check(wa > 100.0, 'long tabs keep their labels whole')
    end subroutine frame

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print '(a)', 'FAIL ' // what
            fails = fails + 1
        end if
    end subroutine check

end program test_layout_focus
