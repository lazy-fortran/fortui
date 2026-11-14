program test_sdl_gpu
    !! SDL GPU backend, rendering offscreen and reading the pixels back (skipped
    !! without -DENABLE_SDL=1 or without a GPU):
    !! - a classic button has the Windows 95 bevel pixels on screen;
    !! - its label is drawn (dark glyph pixels inside the face);
    !! - a material button's rounded corner is antialiased;
    !! - a press and release that arrive between two frames activate a button.
    use iso_c_binding
    use iso_fortran_env, only: int8
    use fortui
    use fortui_gui_sdl
    use fortui_context, only: fortui_context_t, get_default_context
    implicit none

    integer :: failures = 0
#ifdef ENABLE_SDL
    integer :: clicks = 0
    character(len=16) :: mode = "classic"

    interface
        logical(c_bool) function SDL_PushEvent(ev) bind(C, name="SDL_PushEvent")
            import :: c_bool, c_int8_t
            integer(c_int8_t) :: ev(128)
        end function
    end interface

    if (.not. sdl_is_available()) then
        print '(a)', "sdl gpu: skipped (no GPU device or FORTUI_HEADLESS=1)"
        stop
    end if
    call test_classic_pixels()
    call test_material_corner()
    call test_quick_click()
#else
    print '(a)', "sdl gpu: skipped (built without -DENABLE_SDL=1)"
#endif

    if (failures > 0) then
        print '(i0,a)', failures, " sdl gpu checks failed"
        error stop 1
    end if
    print '(a)', " fortui sdl gpu tests passed"

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            failures = failures + 1
            print '(a)', "FAIL: " // what
        end if
    end subroutine check

#ifdef ENABLE_SDL
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

    subroutine test_classic_pixels()
        !! Classic margin 8: OK (default) at (8, 8), Cancel right below at (8, 31),
        !! both 75 x 23.
        type(sdl_backend_t) :: b
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

    subroutine test_material_corner()
        !! Material margin 16: the filled OK pill is the primary colour #6750A4
        !! inside and blended where its left edge crosses a pixel.
        type(sdl_backend_t) :: b
        integer(int8), allocatable :: px(:, :, :)
        integer :: w, h, stat, r
        b%offscreen = .true.
        call ui_init(b, 200, 140, "test", stat=stat, theme_name="material")
        if (stat /= 0) return
        call ui_set_theme("material")
        call compose()
        call read_frame(px, w, h)
        if (w /= 200) return
        call check(rgb_is(px, 24, 36, int(z'6750A4')), "primary fill")
        r = iand(int(px(1, 16 + 1, 36 + 1)), 255)
        call check(r /= int(z'67') .and. r /= int(z'FE'), "antialiased corner")
        call ui_shutdown()
    end subroutine test_material_corner

    subroutine test_quick_click()
        !! Press and release of the left button queued before one frame (a quick
        !! click or tap) click the Cancel button under the pointer.
        type(sdl_backend_t) :: b
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

    subroutine read_frame(px, w, h)
        integer(int8), allocatable, intent(out) :: px(:, :, :)
        integer, intent(out) :: w, h
        type(fortui_context_t), pointer :: ctx
        ctx => get_default_context()
        call sdl_read_pixels(ctx%backend, px, w, h)
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
        integer(c_int8_t) :: ev(128)
        ev = 0
        ev(1:4) = transfer(int(merge(int(z'401'), int(z'402'), down), c_int32_t), ev(1:4))
        ev(25) = 1
        ev(26) = merge(1_c_int8_t, 0_c_int8_t, down)
        ev(27) = 1
        ev(29:32) = transfer(real(x, c_float), ev(1:4))
        ev(33:36) = transfer(real(y, c_float), ev(1:4))
        if (.not. SDL_PushEvent(ev)) call check(.false., "push button event")
    end subroutine push_button

    subroutine push_motion(x, y)
        real, intent(in) :: x, y
        integer(c_int8_t) :: ev(128)
        ev = 0
        ev(1:4) = transfer(int(z'400', c_int32_t), ev(1:4))
        ev(29:32) = transfer(real(x, c_float), ev(1:4))
        ev(33:36) = transfer(real(y, c_float), ev(1:4))
        if (.not. SDL_PushEvent(ev)) call check(.false., "push motion event")
    end subroutine push_motion
#endif

end program test_sdl_gpu
