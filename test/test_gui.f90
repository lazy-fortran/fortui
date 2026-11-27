program test_gui
    !! The graphical backend offscreen (Vulkan where there is a GPU, else the CPU
    !! renderer), reading the pixels back:
    !! - a classic button has the Windows 95 bevel pixels on screen;
    !! - its label is drawn (dark glyph pixels inside the face);
    !! - a fluent button's rounded corner is antialiased;
    !! - a press and release that arrive between two frames activate a button;
    !! - a canvas image shows in the first frame it is composed in.
    !! - a cell grid's last column reaches the canvas's right edge, while the
    !!   strip below its last row keeps the canvas fill;
    !! - an application's window background replaces the theme's window face.
    use iso_c_binding
    use iso_fortran_env, only: int8, int32
    use fortui
    use fortui_gui, only: gui_backend_t, gui_read_pixels, gui_inject, gui_is_available
    use fortui_context, only: fortui_context_t, get_default_context
    use fortwin, only: win_event_t, WIN_EV_MOTION, WIN_EV_BUTTON_DOWN, WIN_EV_BUTTON_UP
    implicit none

    integer :: failures = 0
    integer :: clicks = 0

    call test_classic_pixels()
    call test_fluent_corner()
    call test_quick_click()
    call test_image_first_frame()
    call test_mesh_depth()
    call test_cell_grid_edges()
    call test_window_background()
    call test_file_dialog_pixels()
    call test_startup_frame()
    call test_failed_window_render()

    if (failures > 0) then
        print '(i0,a)', failures, " gui checks failed"
        error stop 1
    end if
    print '(a)', " fortui gui tests passed"

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            failures = failures + 1
            print '(a)', "FAIL: " // what
        end if
    end subroutine check

    subroutine await_gpu(b)
        use fortwin, only: win_time, win_wait
        use fortui_input, only: input_state_t
        type(gui_backend_t), intent(inout) :: b
        type(input_state_t) :: input
        double precision :: started
        started = win_time()
        do while (.not. b%gpu .and. win_time() - started < 5.0d0)
            call b%poll(input, .false.)
            if (.not. b%gpu) call win_wait(b%win, 0.005)
        end do
        call check(b%gpu, "window adopts initialized GPU")
    end subroutine
    subroutine test_startup_frame()
#if !defined(_WIN32) && !defined(__APPLE__)
        use fortui_frame, only: ui_frame_t
        use fortui_canvas, only: canvas_store_t
        type(gui_backend_t) :: b
        type(ui_frame_t) :: frame
        type(canvas_store_t) :: store
        logical :: opened
        if (.not. gui_is_available()) return
        b%config%width = 120
        b%config%height = 80
        opened = b%init()
        call check(opened, "startup test opens")
        if (.not. opened) return
        call b%present(frame, store)
        call check(allocated(b%cpu%rgba), "first frame is available before GPU initialization")
        call await_gpu(b)
        if (b%gpu) call b%present(frame, store)
        call b%shutdown()
        call check(.not. associated(b%dev), "shutdown releases device ownership")
        opened = b%init()
        call check(opened, "immediate-close test opens")
        if (opened) call b%shutdown()
        call check(.not. c_associated(b%gpu_start), "immediate close joins initialization")
#endif
    end subroutine

    subroutine test_failed_window_render()
#if !defined(_WIN32) && !defined(__APPLE__)
        use fortgfx_gpu, only: gpu_close
        use fortwin, only: win_next_event, win_wait, win_time, win_wake
        use fortui_input, only: input_state_t
        use fortui_frame, only: ui_frame_t
        use fortui_canvas, only: canvas_store_t
        type(gui_backend_t) :: b
        type(ui_frame_t) :: frame
        type(canvas_store_t) :: store
        type(win_event_t) :: ev
        type(input_state_t) :: input
        integer :: k
        real(8) :: started
        logical :: opened
        if (.not. gui_is_available()) then
            print '(a)', " skip window-show test: no X display"
            return
        end if
        b%config%hidden = .true.
        b%config%width = 80
        b%config%height = 60
        opened = b%init()
        call check(opened, "window-show test opens")
        if (.not. opened) return
        call await_gpu(b)
        if (.not. b%gpu) then
            call b%shutdown()
            return
        end if
        call gpu_close(b%dev)
        call b%set_window_visible(.true.)
        call b%present(frame, store)
        started = win_time()
        do while (.not. b%win%mapped .and. win_time() - started < 1.0d0)
            call win_wait(b%win, 0.05)
            do while (win_next_event(b%win, ev))
            end do
        end do
        call check(b%win%mapped, "a failed first frame still shows the requested window")
        call b%poll(input, .false.)
        started = win_time()
        do k = 1, 10
            call b%present(frame, store)
            call b%poll(input, .true.)
        end do
        call check(win_time() - started > 1.0d0, "failed renders wait between idle retries")
        call win_wake()
        started = win_time()
        call b%present(frame, store)
        call b%poll(input, .true.)
        call check(win_time() - started < 0.5d0, "input wakes a delayed redraw")
        call b%shutdown()
#endif
    end subroutine test_failed_window_render

    subroutine test_file_dialog_pixels()
        use fortui_testing, only: ui_node_rect
        type(gui_backend_t) :: b
        type(file_dialog_t) :: d
        integer(int8), allocatable :: px(:,:,:)
        character(12), parameter :: names(3) = [character(12) :: &
            "classic", "fluent-light", "fluent-dark"]
        real :: x, y, width, height
        integer :: k, w, h, stat
        logical :: found
        do k = 1, size(names)
            b%offscreen = .true.
            call ui_init(b, 800, 650, "Open photo", stat=stat)
            call ui_set_theme(trim(names(k)))
            call file_dialog_open(d, "Open photo", ".", ".png,.jpg")
            call ui_frame_begin()
            call file_dialog_show(d)
            call ui_present()
            call read_frame(px, w, h)
            found = ui_node_rect("file-dialog/accept", x, y, width, height)
            call check(found .and. y + height <= h, "dialog actions visible in " // trim(names(k)))
            call check(any(px(1:3, 400, 300) /= px(1:3, 4, 4)), &
                "dialog surface visible in " // trim(names(k)))
            call ui_shutdown()
        end do
    end subroutine

    subroutine compose()
        call ui_frame_begin()
        if (button("ok", "OK", emphasis=UI_EMPHASIS_PRIMARY)) clicks = clicks + 1
        if (button("cancel", "Cancel")) clicks = clicks + 100
        call ui_present()
    end subroutine compose

    logical function rgb_is(px, x, y, hex)
        integer(int8), intent(in) :: px(:, :, :)
        integer, intent(in) :: x, y, hex
        integer :: r, g, b
        r = iand(int(px(1, x + 1, y + 1)), 255)
        g = iand(int(px(2, x + 1, y + 1)), 255)
        b = iand(int(px(3, x + 1, y + 1)), 255)
        rgb_is = r == iand(ishft(hex, -16), 255) .and. g == iand(ishft(hex, -8), 255) .and. &
            b == iand(hex, 255)
    end function rgb_is

    subroutine test_window_background()
        !! A terminal's black, not the classic theme's grey, where nothing is drawn.
        type(gui_backend_t) :: b
        integer(int8), allocatable :: px(:, :, :)
        integer :: w, h, stat
        b%offscreen = .true.
        call ui_init(b, 60, 40, "test", stat=stat, theme_name="classic")
        call check(stat == 0, "offscreen init")
        if (stat /= 0) return
        call ui_set_window_background(ui_rgba(0, 0, 0))
        call ui_frame_begin()
        call ui_present()
        call read_frame(px, w, h)
        call check(w == 60 .and. h == 40, "read back the frame")
        if (w == 60) call check(rgb_is(px, 4, 4, int(z'000000')) .and. &
            rgb_is(px, 50, 30, int(z'000000')), "own window background")
        call ui_shutdown()
    end subroutine test_window_background

    subroutine test_classic_pixels()
        !! Classic margin 8: OK (default) at (8, 8), Cancel right below at (8, 31),
        !! both 75 x 23.
        type(gui_backend_t) :: b
        integer(int8), allocatable :: px(:, :, :)
        integer :: w, h, x, y, dark
        integer :: stat

        b%offscreen = .true.
        call ui_init(b, 120, 80, "test", stat=stat, theme_name="classic")
        call check(stat == 0, "offscreen init")
        if (stat /= 0) return
        call ui_set_theme("classic")
        call compose()
        call read_frame(px, w, h)
        call check(w == 120 .and. h == 80, "read back the frame")
        if (w /= 120) return
        call check(rgb_is(px, 8, 8, int(z'000000')) .and. rgb_is(px, 9, 9, int(z'FFFFFF')) &
            .and. rgb_is(px, 10, 10, int(z'DFDFDF')) .and. rgb_is(px, 80, 28, int(z'808080')) &
            .and. rgb_is(px, 81, 29, int(z'000000')) .and. rgb_is(px, 82, 30, int(z'000000')), &
            "default button bevel on screen")
        call check(rgb_is(px, 8, 31, int(z'FFFFFF')) .and. rgb_is(px, 82, 53, int(z'000000')) &
            .and. rgb_is(px, 9, 32, int(z'DFDFDF')) .and. rgb_is(px, 81, 52, int(z'808080')), &
            "push button bevel on screen")
        call check(rgb_is(px, 4, 4, int(z'C0C0C0')), "window face")
        dark = 0
        do y = 35, 49
            do x = 20, 70
                if (iand(int(px(1, x + 1, y + 1)), 255) < 64) dark = dark + 1
            end do
        end do
        call check(dark > 20, "label glyphs drawn")
        call ui_shutdown()
    end subroutine test_classic_pixels

    subroutine test_fluent_corner()
        !! Fluent margin 16: the primary OK button (32 px high, 4 px corners) is
        !! brand blue #0F6CBD inside and blended at its rounded top-left corner.
        type(gui_backend_t) :: b
        integer(int8), allocatable :: px(:, :, :)
        integer :: w, h, stat, r
        b%offscreen = .true.
        call ui_init(b, 200, 140, "test", stat=stat, theme_name="fluent-light")
        if (stat /= 0) return
        call ui_set_theme("fluent-light")
        call compose()
        call read_frame(px, w, h)
        if (w /= 200) return
        call check(rgb_is(px, 20, 32, int(z'0F6CBD')), "primary fill")
        r = iand(int(px(1, 17 + 1, 16 + 1)), 255)
        call check(r /= int(z'0F') .and. r /= int(z'F5'), "antialiased corner")
        call ui_shutdown()
    end subroutine test_fluent_corner

    subroutine test_quick_click()
        !! Press and release of the left button queued before one frame (a quick
        !! click or tap) click the Cancel button under the pointer.
        type(gui_backend_t) :: b
        integer :: stat, k
        b%offscreen = .true.
        call ui_init(b, 120, 80, "test", stat=stat, theme_name="classic")
        if (stat /= 0) return
        call ui_set_theme("classic")
        clicks = 0
        call compose()
        call push_motion(40.0, 42.0)
        call compose()
        call push_button(.true., 40.0, 42.0)
        call push_button(.false., 40.0, 42.0)
        do k = 1, 3
            call compose()
        end do
        call check(clicks == 100, "quick click activates the button under it")
        call ui_shutdown()
    end subroutine test_quick_click

    subroutine test_image_first_frame()
        !! One frame, then read: the image's red pixels are on screen at once.
        type(gui_backend_t) :: b
        integer(int8), allocatable :: px(:, :, :)
        integer :: w, h, stat
        integer(c_int32_t) :: red(4, 4)
        type(canvas_view_t) :: view
        b%offscreen = .true.
        call ui_init(b, 100, 100, "test", stat=stat, theme_name="fluent-light")
        if (stat /= 0) return
        call ui_set_theme("fluent-light")
        red = ui_rgba(255, 0, 0)
        call ui_frame_begin()
        call canvas_begin("c", view, width=60.0, height=60.0, fill=ui_rgba(0, 0, 255))
        call canvas_image("img", 1, red, 10.0, 10.0, 40.0, 40.0)
        call canvas_end(view)
        call ui_present()
        call read_frame(px, w, h)
        if (w /= 100) return
        call check(rgb_is(px, 16 + 30, 16 + 30, int(z'FF0000')), "image in the first frame")
        call check(rgb_is(px, 16 + 5, 16 + 5, int(z'0000FF')), "canvas fill around it")
        call ui_shutdown()
    end subroutine test_image_first_frame

    subroutine test_mesh_depth()
        !! A red square in front of a blue one, the blue one composed last: red
        !! shows in the middle, the canvas fill where neither is.
        type(gui_backend_t) :: b
        integer(int8), allocatable :: px(:, :, :)
        integer :: w, h, stat, r, bl
        real :: xyz(3, 8)
        integer(int32) :: colours(8), tris(3, 4)
        type(canvas_view_t) :: view
        b%offscreen = .true.
        call ui_init(b, 100, 100, "test", stat=stat, theme_name="fluent-light")
        if (stat /= 0) return
        call ui_set_theme("fluent-light")
        xyz = reshape([1.0, -1.0, -1.0, 1.0, 1.0, -1.0, 1.0, 1.0, 1.0, 1.0, -1.0, 1.0, &
            -1.0, -2.0, -2.0, -1.0, 2.0, -2.0, -1.0, 2.0, 2.0, -1.0, -2.0, 2.0], [3, 8])
        colours(1:4) = ui_rgba(255, 0, 0)
        colours(5:8) = ui_rgba(0, 0, 255)
        tris = reshape([4, 5, 6, 4, 6, 7, 0, 1, 2, 0, 2, 3], [3, 4])
        call ui_frame_begin()
        call canvas_begin("c", view, width=60.0, height=60.0, fill=ui_rgba(0, 255, 0))
        call canvas_mesh("m", 1, xyz, colours, tris, camera_orbit(0.0, 0.0, 9.0, 1.0))
        call canvas_end(view)
        call ui_present()
        call read_frame(px, w, h)
        if (w /= 100) return
        r = iand(int(px(1, 16 + 30 + 1, 16 + 30 + 1)), 255)
        bl = iand(int(px(3, 16 + 30 + 1, 16 + 30 + 1)), 255)
        call check(r > 150 .and. bl < 50, "the nearer mesh face shows in front")
        call check(rgb_is(px, 16 + 2, 16 + 2, int(z'00FF00')), "the canvas fill around the mesh")
        call ui_shutdown()
    end subroutine test_mesh_depth

    subroutine test_cell_grid_edges()
        !! Two green rows of two cells in a blue canvas much larger than them.
        type(gui_backend_t) :: b
        integer(int8), allocatable :: px(:, :, :)
        integer :: w, h, stat
        integer(int32) :: cp(4), fg(4), bg(4), attr(4)
        type(canvas_view_t) :: view
        b%offscreen = .true.
        call ui_init(b, 200, 200, "test", stat=stat, theme_name="fluent-light")
        if (stat /= 0) return
        call ui_set_theme("fluent-light")
        cp = iachar("x")
        fg = ui_rgba(0, 255, 0)
        bg = ui_rgba(0, 255, 0)
        attr = 0
        call ui_frame_begin()
        call canvas_begin("c", view, width=160.0, height=160.0, fill=ui_rgba(0, 0, 255))
        call canvas_cells("cells", 1, 2, 2, cp, fg, bg, attr, 0.0, 0.0, 40.0, 40.0, 10.0, &
            extend_edges=.true.)
        call canvas_end(view)
        call ui_present()
        call read_frame(px, w, h)
        if (w /= 200) return
        call check(rgb_is(px, 16 + 155, 16 + 2, int(z'00FF00')), &
            "the first row's background reaches the right edge")
        call check(rgb_is(px, 16 + 5, 16 + 155, int(z'0000FF')), &
            "below the last row the canvas fill shows")
        call check(rgb_is(px, 16 + 155, 16 + 155, int(z'0000FF')), &
            "the corner below the last row keeps the canvas fill")
        call ui_shutdown()
    end subroutine test_cell_grid_edges

    subroutine read_frame(px, w, h)
        integer(int8), allocatable, intent(out) :: px(:, :, :)
        integer, intent(out) :: w, h
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        call gui_read_pixels(ctx%backend, px, w, h)
        block
            integer :: u, i, j
            character(len=256) :: dump
            integer :: n
            call get_environment_variable("FORTUI_TEST_DUMP", dump, n)
            if (n > 0) then
                open (newunit=u, file=trim(dump) // "/" // trim(ui_theme_name()) // ".ppm", &
                    access="stream", form="unformatted", status="replace")
                write (u) "P6 " // ui_str(w) // " " // ui_str(h) // " 255" // achar(10)
                write (u) ((px(1:3, i, j), i = 1, w), j = 1, h)
                close (u)
            end if
        end block
    end subroutine read_frame

    subroutine push_button(down, x, y)
        logical, intent(in) :: down
        real, intent(in) :: x, y
        type(fortui_context_t), pointer :: ctx
        type(win_event_t) :: ev
        ctx => get_default_context()
        ev%kind = merge(WIN_EV_BUTTON_DOWN, WIN_EV_BUTTON_UP, down)
        ev%button = 1
        ev%x = x
        ev%y = y
        call gui_inject(ctx%backend, ev)
    end subroutine push_button

    subroutine push_motion(x, y)
        real, intent(in) :: x, y
        type(fortui_context_t), pointer :: ctx
        type(win_event_t) :: ev
        ctx => get_default_context()
        ev%kind = WIN_EV_MOTION
        ev%x = x
        ev%y = y
        call gui_inject(ctx%backend, ev)
    end subroutine push_motion

end program test_gui
