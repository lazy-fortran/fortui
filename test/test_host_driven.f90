program test_host_driven
    !! Hosts that drive the frames and report semantic events (the browser):
    !! ui_run in both modes, containers in the frame, and activation, values and
    !! submission without pointer routing.
    use fortui
    use fortui_backend_headless, only: headless_backend_t
    use fortui_testing, only: ui_inject_host, ui_frame_boxes
    use fortui_input, only: HOST_ACTIVATE, HOST_VALUE, HOST_SUBMIT
    use fortui_layout, only: layout_box_t, KIND_COLUMN, KIND_ROW
    implicit none

    integer :: frames, stat, nbox, box_of_go
    logical :: clicked, submitted, again
    character(len=:), allocatable :: name
    real :: gain
    type(layout_box_t), allocatable :: boxes(:)

    ! Native mode: ui_run loops until the application quits.
    frames = 0
    call ui_init(headless_backend_t(), 400, 300, "loop", stat=stat)
    call ui_run(count_three)
    call check(frames == 3, "ui_run loops on native hosts until quit")
    call ui_shutdown()

    ! Host-driven mode: ui_run returns at once; the host calls each frame.
    frames = 0
    name = ""
    gain = 10.0
    call ui_init(headless_backend_t(host_driven=.true.), 800, 600, "driven", stat=stat)
    call ui_run(compose)
    call check(frames == 0, "ui_run returns at once when the host drives frames")
    again = ui_run_step()
    call check(frames == 1, "the host's step composes one frame")

    call ui_frame_boxes(boxes, nbox, "c/go", box_of_go)
    call check(nbox == 2, "two containers recorded")
    call check(boxes(1)%kind == KIND_COLUMN .and. boxes(1)%parent == 0 .and. &
        abs(boxes(1)%gap - 10.0) < 1e-6, "outer column with its gap")
    call check(boxes(2)%kind == KIND_ROW .and. boxes(2)%parent == 1 .and. &
        abs(boxes(2)%cross - 40.0) < 1e-6 .and. boxes(2)%after == 0, "row inside it, first child")
    call check(box_of_go == 2, "a node knows its container")

    call ui_inject_host(HOST_ACTIVATE, "c/go")
    again = ui_run_step()
    call check(clicked, "an activation event clicks the button without a pointer")

    call ui_inject_host(HOST_VALUE, "c/name", "Ada")
    call ui_inject_host(HOST_SUBMIT, "c/name")
    again = ui_run_step()
    call check(name == "Ada" .and. submitted, "a native field reports its value and Enter")

    call ui_inject_host(HOST_VALUE, "c/gain", "37.5")
    again = ui_run_step()
    call check(abs(gain - 37.5) < 1e-4, "a native slider reports its value")
    call ui_inject_host(HOST_VALUE, "c/gain", "12x")
    again = ui_run_step()
    call check(abs(gain - 37.5) < 1e-4, "a value that is no number is ignored")

    call ui_shutdown()
    call check(ui_is_initialized(), "a host-driven application keeps running")
    print *, "fortui host-driven tests passed"

contains

    subroutine count_three()
        frames = frames + 1
        call text("frame")
        if (frames >= 3) call ui_request_quit()
    end subroutine count_three

    subroutine compose()
        frames = frames + 1
        call column_begin(10.0, id="c")
        call row_begin(8.0, height=40.0)
        call text("label")
        clicked = button("go", "Go")
        call row_end()
        if (text_input("name", name, submitted=submitted, width=UI_FILL)) continue
        if (slider("gain", 0.0, 100.0, gain)) continue
        call column_end()
    end subroutine compose

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            print *, "FAIL: ", what
            error stop 1
        end if
    end subroutine check

end program test_host_driven
