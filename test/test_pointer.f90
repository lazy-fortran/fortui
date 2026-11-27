program test_pointer
    !! Pointer kinds, pressure, tilt and coalesced samples on a canvas, and
    !! two-finger gestures (pinch and pan) that never press.
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_inject_pointer_event
    implicit none
    integer :: fails = 0, stat
    type(canvas_view_t) :: view
    type(canvas_events_t) :: ev

    call ui_init(headless_backend_t(), 400, 300, 'pointer', stat=stat)
    call frame()

    ! A pen stroke: three samples arrive before one frame.
    call ui_inject_pointer_event(50.0, 50.0, .true., POINTER_PEN, pressure=0.2, tilt_x=10.0, tilt_y=-5.0)
    call ui_inject_pointer_event(55.0, 52.0, .true., POINTER_PEN, pressure=0.5, tilt_x=12.0, tilt_y=-4.0)
    call ui_inject_pointer_event(60.0, 54.0, .true., POINTER_PEN, pressure=0.9, tilt_x=14.0, tilt_y=-3.0)
    call frame()
    call check(ev%kind == POINTER_PEN .and. abs(ev%pressure - 0.9) < 1e-6 .and. &
        abs(ev%tilt_x - 14.0) < 1e-6, 'a pen reports kind, pressure and tilt')
    call check(size(ev%samples, 2) == 3, 'every sample of the frame arrives')
    if (size(ev%samples, 2) == 3) call check(abs(ev%samples(3, 1) - 0.2) < 1e-6 .and. &
        abs(ev%samples(1, 2) - (55.0 - 10.0)) < 1e-3, 'samples carry pressure, in canvas coordinates')
    call ui_inject_pointer_event(60.0, 54.0, .false., POINTER_PEN)
    call frame()
    call frame()

    ! One finger presses like a mouse.
    call ui_inject_pointer_event(100.0, 100.0, .true., POINTER_TOUCH, pressure=1.0, id=7)
    call frame()
    call check(ev%kind == POINTER_TOUCH .and. ev%pressed, 'one finger presses')
    ! A second finger turns it into a gesture without a click.
    call ui_inject_pointer_event(200.0, 100.0, .true., POINTER_TOUCH, pressure=1.0, id=8)
    call frame()
    call check(.not. ev%captured .and. ev%touches == 2, 'two fingers do not press')
    call ui_inject_pointer_event(300.0, 100.0, .true., POINTER_TOUCH, pressure=1.0, id=8)
    call frame()
    call check(abs(ev%pinch - 2.0) < 1e-5 .and. abs(ev%pan_dx - 50.0) < 1e-4 .and. abs(ev%pan_dy) < 1e-5, &
        'spreading two fingers pinches by their distance and pans by their centre')
    call ui_inject_pointer_event(300.0, 100.0, .false., POINTER_TOUCH, id=8)
    call ui_inject_pointer_event(100.0, 100.0, .false., POINTER_TOUCH, id=7)
    call frame()
    call check(.not. ev%clicked, 'a gesture ends without a click')
    call frame()
    call ui_inject_pointer_event(120.0, 120.0, .true., POINTER_TOUCH, id=9)
    call frame()
    call ui_inject_pointer_event(120.0, 120.0, .false., POINTER_TOUCH, id=9)
    call frame()
    call check(ev%clicked, 'after the gesture a tap clicks again')

    if (fails > 0) error stop 1
    print '(a)', 'test_pointer: all passed'

contains

    subroutine frame()
        call ui_frame_begin()
        call row_begin(0.0)
        call text('', width=10.0)
        call canvas_begin('c', view, ev, width=380.0, height=280.0)
        call canvas_end(view)
        call row_end()
        call ui_present()
    end subroutine frame

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print '(a)', 'FAIL ' // what
            fails = fails + 1
        end if
    end subroutine check

end program test_pointer
