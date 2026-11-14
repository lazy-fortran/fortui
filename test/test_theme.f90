program test_theme
    !! Themes: names, the user's choice from FORTUI_THEME or the config file, theme
    !! metrics in composition, and the painters. The classic button is checked
    !! pixel by pixel against Windows 95 (colours measured in a Windows 95
    !! screenshot: white and black outside, #DFDFDF and #808080 inside, black frame
    !! on the default button), rasterizing the display list in this test.
    use iso_c_binding
    use iso_fortran_env, only: int32
    use fortui_theme, only: ui_theme_t, theme, theme_named, theme_select, theme_requested, &
        theme_rgb, STYLE_CLASSIC, STYLE_MATERIAL
    use fortui_frame, only: ui_frame_t, ui_node_t, UI_BUTTON, UI_CHECKBOX, UI_EMPHASIS_PRIMARY, &
        ui_control_height
    use fortui_paint, only: paint_list_t, paint_frame, PAINT_RECT, PAINT_TEXT, PATTERN_CHECKER
    implicit none

    interface
        integer(c_int) function setenv(name, value, overwrite) bind(C, name="setenv")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: name(*), value(*)
            integer(c_int), value :: overwrite
        end function
        integer(c_int) function unsetenv(name) bind(C, name="unsetenv")
            import :: c_int, c_char
            character(kind=c_char), intent(in) :: name(*)
        end function
    end interface

    integer :: failures = 0

    call test_names()
    call test_requested()
    call test_classic_button()
    call test_classic_checkbox()
    call test_material_button()

    if (failures > 0) then
        print '(i0,a)', failures, " theme checks failed"
        error stop 1
    end if
    print '(a)', " fortui theme tests passed"

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        if (.not. ok) then
            failures = failures + 1
            print '(a)', "FAIL: " // what
        end if
    end subroutine check

    subroutine test_names()
        type(ui_theme_t) :: t
        logical :: ok
        call theme_named("Classic", t, ok)
        call check(ok .and. t%kind == STYLE_CLASSIC .and. t%control_height == 23.0, &
            "classic: 23 px buttons")
        call theme_named("material-dark", t, ok)
        call check(ok .and. t%kind == STYLE_MATERIAL .and. t%dark, "material-dark")
        call theme_named("no-such-theme", t, ok)
        call check(.not. ok, "unknown names are refused")
        call check(theme_rgb(int(z'C0C0C0')) == int(z'FFC0C0C0', int32), &
            "packed like ui_rgba (R in the low byte)")
    end subroutine test_names

    subroutine test_requested()
        !! FORTUI_THEME wins over `theme =` in $XDG_CONFIG_HOME/fortui/config,
        !! which wins over the application's default.
        character(len=512) :: dir
        integer :: u, rc
        dir = "build/test-theme-config"
        call execute_command_line("mkdir -p " // trim(dir) // "/fortui")
        open (newunit=u, file=trim(dir) // "/fortui/config", status="replace", action="write")
        write (u, '(a)') "# FortUI settings"
        write (u, '(a)') "theme = classic"
        close (u)
        rc = setenv("XDG_CONFIG_HOME" // c_null_char, trim(dir) // c_null_char, 1_c_int)
        rc = unsetenv("FORTUI_THEME" // c_null_char)
        call check(theme_requested("material") == "classic", "config file theme")
        rc = setenv("FORTUI_THEME" // c_null_char, "material-dark" // c_null_char, 1_c_int)
        call check(theme_requested("material") == "material-dark", "environment wins")
        rc = unsetenv("FORTUI_THEME" // c_null_char)
        rc = setenv("XDG_CONFIG_HOME" // c_null_char, trim(dir) // "/none" // c_null_char, &
            1_c_int)
        call check(theme_requested("material") == "material", "application default")
    end subroutine test_requested

    subroutine paint_one(node, w, h, list)
        type(ui_node_t), intent(in) :: node
        integer, intent(in) :: w, h
        type(paint_list_t), intent(inout) :: list
        type(ui_frame_t) :: frame
        integer :: k
        call frame%reset()
        k = frame%append(node)
        call paint_frame(frame, 1.0, real(w), real(h), list)
    end subroutine paint_one

    function raster(list, w, h) result(px)
        !! Square, solid rectangles and checker patterns of a display list, in
        !! order, onto a w x h canvas (text ignored).
        type(paint_list_t), intent(in) :: list
        integer, intent(in) :: w, h
        integer(int32) :: px(0:w - 1, 0:h - 1)
        integer :: k, x, y
        px = 0
        do k = 1, list%n
            associate(c => list%cmds(k))
                if (c%kind /= PAINT_RECT .or. c%radius > 0.0) cycle
                do y = max(0, nint(c%y)), min(h - 1, nint(c%y + c%h) - 1)
                    do x = max(0, nint(c%x)), min(w - 1, nint(c%x + c%w) - 1)
                        if (c%pattern == PATTERN_CHECKER) then
                            if (modulo(x + y, 2) == 0) then
                                if (c%fill /= 0) px(x, y) = c%fill
                            else
                                if (c%stroke /= 0) px(x, y) = c%stroke
                            end if
                        else if (c%fill /= 0) then
                            px(x, y) = c%fill
                        end if
                    end do
                end do
            end associate
        end do
    end function raster

    subroutine test_classic_button()
        type(ui_node_t) :: node
        type(paint_list_t) :: list
        integer(int32), allocatable :: px(:, :)
        integer(int32) :: white, light, grey, black, face
        logical :: ok

        call theme_select("classic", ok)
        call check(ui_control_height() == 23.0, "classic metrics in composition")
        white = theme_rgb(int(z'FFFFFF'))
        light = theme_rgb(int(z'DFDFDF'))
        grey = theme_rgb(int(z'808080'))
        black = theme_rgb(int(z'000000'))
        face = theme_rgb(int(z'C0C0C0'))
        node%kind = UI_BUTTON
        node%text = "Cancel"
        node%x = 10.0
        node%y = 10.0
        node%width = 75.0
        node%height = 23.0
        call paint_one(node, 100, 40, list)
        allocate(px(0:99, 0:39))
        px = raster(list, 100, 40)
        call check(px(10, 10) == white .and. px(83, 10) == white .and. px(10, 31) == white, &
            "outer top and left edges white")
        call check(px(84, 10) == black .and. px(84, 32) == black .and. px(10, 32) == black, &
            "outer bottom and right edges black, corners included")
        call check(px(11, 11) == light .and. px(82, 11) == light .and. px(11, 30) == light, &
            "inner top and left edges light grey")
        call check(px(83, 11) == grey .and. px(83, 31) == grey .and. px(11, 31) == grey, &
            "inner bottom and right edges grey")
        call check(px(15, 15) == face, "button face")
        call check(count(list%cmds(1:list%n)%kind == PAINT_TEXT) == 1, "one label")

        node%emphasis = UI_EMPHASIS_PRIMARY
        call paint_one(node, 100, 40, list)
        px = raster(list, 100, 40)
        call check(px(10, 10) == black .and. px(84, 32) == black .and. px(11, 11) == white &
            .and. px(83, 31) == black .and. px(12, 12) == light .and. px(82, 30) == grey, &
            "default button: black frame around the bevel")
    end subroutine test_classic_button

    subroutine test_classic_checkbox()
        !! 13 px sunken box: grey/white outside, black/light grey inside, white
        !! inside that, and the check glyph's corner pixels.
        type(ui_node_t) :: node
        type(paint_list_t) :: list
        integer(int32), allocatable :: px(:, :)
        logical :: ok
        call theme_select("classic", ok)
        node%kind = UI_CHECKBOX
        node%text = "Option"
        node%checked = .true.
        node%width = 80.0
        node%height = 13.0
        call paint_one(node, 100, 20, list)
        allocate(px(0:99, 0:19))
        px = raster(list, 100, 20)
        call check(px(0, 0) == theme_rgb(int(z'808080')) .and. &
            px(12, 12) == theme_rgb(int(z'FFFFFF')) .and. &
            px(1, 1) == theme_rgb(int(z'000000')) .and. &
            px(11, 11) == theme_rgb(int(z'DFDFDF')), "sunken check box edge")
        call check(px(2, 2) == theme_rgb(int(z'FFFFFF')), "white inside")
        call check(px(9, 3) == theme_rgb(int(z'000000')) .and. &
            px(3, 3) == theme_rgb(int(z'FFFFFF')) .and. px(3, 5) == theme_rgb(int(z'000000')) &
            .and. px(5, 9) == theme_rgb(int(z'000000')), "check glyph")
    end subroutine test_classic_checkbox

    subroutine test_material_button()
        !! Filled primary button: one fully rounded rectangle in the primary colour.
        type(ui_node_t) :: node
        type(paint_list_t) :: list
        logical :: ok
        integer :: k, n
        call theme_select("material", ok)
        call check(ui_control_height() == 40.0, "material metrics in composition")
        node%kind = UI_BUTTON
        node%text = "Save"
        node%width = 100.0
        node%height = 40.0
        node%emphasis = UI_EMPHASIS_PRIMARY
        call paint_one(node, 120, 50, list)
        n = 0
        do k = 1, list%n
            if (list%cmds(k)%kind == PAINT_RECT .and. list%cmds(k)%radius == 20.0 .and. &
                list%cmds(k)%fill == theme%primary) n = n + 1
        end do
        call check(n == 1, "fully rounded primary fill")
        call check(theme%primary == theme_rgb(int(z'6750A4')), "M3 baseline primary #6750A4")
    end subroutine test_material_button

end program test_theme
