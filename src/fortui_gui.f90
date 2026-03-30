module fortui_gui
! GUI backend implementation using raylib
! When ENABLE_GUI is not defined, provides no-op stubs
#ifdef ENABLE_GUI
use fortui_input, only: input_reset, input_set_mouse, input_set_key
use fortui_error, only: report_error
use iso_c_binding
#endif
implicit none
private

#ifdef ENABLE_GUI
public :: gui_init, gui_shutdown, gui_begin_frame, gui_render
public :: gui_is_available, gui_check_quit
public :: gui_set_cell, gui_is_active
public :: gui_get_width, gui_get_height
public :: gui_fill_rect, gui_draw_text, gui_draw_border

! Raylib Color type
type, bind(C) :: rl_color
    integer(c_int8_t) :: r, g, b, a
end type rl_color

! Module state
logical, save :: gui_active = .false.
integer, save :: grid_cols = 80
integer, save :: grid_rows = 24
integer, save :: g_cell_w = 10
integer, save :: g_cell_h = 20
integer, save :: g_font_size = 20

! Cell buffer for deferred rendering
integer, parameter :: MAX_CELLS = 16384
type :: cell_entry_t
    integer :: x = 0, y = 0, ch = 0, fg = 0, bg = 0
end type cell_entry_t
type(cell_entry_t), save :: cell_buffer(MAX_CELLS)
integer, save :: cell_count = 0

! Raylib key constants
integer(c_int), parameter :: RL_KEY_ESCAPE = 256
integer(c_int), parameter :: RL_KEY_ENTER = 257
integer(c_int), parameter :: RL_KEY_TAB = 258
integer(c_int), parameter :: RL_KEY_SPACE = 32
integer(c_int), parameter :: RL_KEY_RIGHT = 262
integer(c_int), parameter :: RL_KEY_LEFT = 263
integer(c_int), parameter :: RL_KEY_DOWN = 264
integer(c_int), parameter :: RL_KEY_UP = 265

! Raylib config flags
integer(c_int), parameter :: RL_FLAG_VSYNC = 64
integer(c_int), parameter :: RL_FLAG_RESIZABLE = 4

! Raylib mouse buttons
integer(c_int), parameter :: RL_MOUSE_LEFT = 0
integer(c_int), parameter :: RL_MOUSE_RIGHT = 1

! Raylib C interface
interface
    subroutine rl_init_window(w, h, title) &
        bind(C, name="InitWindow")
        import :: c_int, c_char
        integer(c_int), intent(in), value :: w, h
        character(c_char), intent(in) :: title(*)
    end subroutine

    subroutine rl_close_window() &
        bind(C, name="CloseWindow")
    end subroutine

    logical(c_bool) function rl_window_should_close() &
        bind(C, name="WindowShouldClose")
        import :: c_bool
    end function

    subroutine rl_begin_drawing() &
        bind(C, name="BeginDrawing")
    end subroutine

    subroutine rl_end_drawing() &
        bind(C, name="EndDrawing")
    end subroutine

    subroutine rl_clear_background(color) &
        bind(C, name="ClearBackground")
        import :: rl_color
        type(rl_color), intent(in), value :: color
    end subroutine

    subroutine rl_draw_rectangle(x, y, w, h, color) &
        bind(C, name="DrawRectangle")
        import :: c_int, rl_color
        integer(c_int), intent(in), value :: x, y, w, h
        type(rl_color), intent(in), value :: color
    end subroutine

    subroutine rl_draw_text(text, x, y, font_size, color) &
        bind(C, name="DrawText")
        import :: c_int, c_char, rl_color
        character(c_char), intent(in) :: text(*)
        integer(c_int), intent(in), value :: x, y, font_size
        type(rl_color), intent(in), value :: color
    end subroutine

    integer(c_int) function rl_measure_text(text, font_size) &
        bind(C, name="MeasureText")
        import :: c_int, c_char
        character(c_char), intent(in) :: text(*)
        integer(c_int), intent(in), value :: font_size
    end function

    subroutine rl_set_target_fps(fps) &
        bind(C, name="SetTargetFPS")
        import :: c_int
        integer(c_int), intent(in), value :: fps
    end subroutine

    integer(c_int) function rl_get_screen_width() &
        bind(C, name="GetScreenWidth")
        import :: c_int
    end function

    integer(c_int) function rl_get_screen_height() &
        bind(C, name="GetScreenHeight")
        import :: c_int
    end function

    integer(c_int) function rl_get_key_pressed() &
        bind(C, name="GetKeyPressed")
        import :: c_int
    end function

    logical(c_bool) function rl_is_key_pressed(key) &
        bind(C, name="IsKeyPressed")
        import :: c_int, c_bool
        integer(c_int), intent(in), value :: key
    end function

    logical(c_bool) function rl_is_mouse_button_pressed(btn) &
        bind(C, name="IsMouseButtonPressed")
        import :: c_int, c_bool
        integer(c_int), intent(in), value :: btn
    end function

    logical(c_bool) function rl_is_mouse_button_down(btn) &
        bind(C, name="IsMouseButtonDown")
        import :: c_int, c_bool
        integer(c_int), intent(in), value :: btn
    end function

    integer(c_int) function rl_get_mouse_x() &
        bind(C, name="GetMouseX")
        import :: c_int
    end function

    integer(c_int) function rl_get_mouse_y() &
        bind(C, name="GetMouseY")
        import :: c_int
    end function

    real(c_float) function rl_get_mouse_wheel_move() &
        bind(C, name="GetMouseWheelMove")
        import :: c_float
    end function

    subroutine rl_set_config_flags(flags) &
        bind(C, name="SetConfigFlags")
        import :: c_int
        integer(c_int), intent(in), value :: flags
    end subroutine
end interface
#endif

contains

#ifdef ENABLE_GUI

pure function ubyte(n) result(b)
    integer, intent(in) :: n
    integer(c_int8_t) :: b

    if (n > 127) then
        b = int(n - 256, c_int8_t)
    else
        b = int(n, c_int8_t)
    end if
end function ubyte

pure function make_color(r, g, b, a) result(c)
    integer, intent(in) :: r, g, b, a
    type(rl_color) :: c

    c%r = ubyte(r)
    c%g = ubyte(g)
    c%b = ubyte(b)
    c%a = ubyte(a)
end function make_color

pure function rc_to_fg(rc) result(c)
    integer, intent(in) :: rc
    type(rl_color) :: c
    integer :: base

    base = iand(rc, 255)
    select case (base)
    case (0)
        c = make_color(200, 200, 200, 255)
    case (1)
        c = make_color(0, 0, 0, 255)
    case (2)
        c = make_color(230, 50, 50, 255)
    case (3)
        c = make_color(50, 200, 50, 255)
    case (4)
        c = make_color(230, 230, 50, 255)
    case (5)
        c = make_color(80, 120, 230, 255)
    case (6)
        c = make_color(200, 50, 200, 255)
    case (7)
        c = make_color(50, 200, 200, 255)
    case (8)
        c = make_color(240, 240, 240, 255)
    case default
        c = make_color(200, 200, 200, 255)
    end select
end function rc_to_fg

pure function rc_to_bg(rc) result(c)
    integer, intent(in) :: rc
    type(rl_color) :: c
    integer :: base

    base = iand(rc, 255)
    select case (base)
    case (0)
        c = make_color(30, 30, 30, 0)
    case (1)
        c = make_color(0, 0, 0, 255)
    case (2)
        c = make_color(180, 40, 40, 255)
    case (3)
        c = make_color(40, 150, 40, 255)
    case (4)
        c = make_color(180, 180, 40, 255)
    case (5)
        c = make_color(40, 80, 180, 255)
    case (6)
        c = make_color(150, 40, 150, 255)
    case (7)
        c = make_color(40, 150, 150, 255)
    case (8)
        c = make_color(240, 240, 240, 255)
    case default
        c = make_color(30, 30, 30, 0)
    end select
end function rc_to_bg

pure function map_rl_key(rl_key) result(fortui_key)
    integer, intent(in) :: rl_key
    integer :: fortui_key

    select case (rl_key)
    case (256)
        fortui_key = 27
    case (257)
        fortui_key = 13
    case (258)
        fortui_key = 9
    case (32)
        fortui_key = 32
    case (265)
        fortui_key = 65517
    case (264)
        fortui_key = 65516
    case (263)
        fortui_key = 65515
    case (262)
        fortui_key = 65514
    case default
        fortui_key = rl_key
    end select
end function map_rl_key

subroutine gui_init(width, height, title, target_fps, vsync)
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync

    character(len=512) :: c_title
    integer :: i, text_w

    if (vsync) then
        call rl_set_config_flags(ior(RL_FLAG_VSYNC, &
            RL_FLAG_RESIZABLE))
    else
        call rl_set_config_flags(RL_FLAG_RESIZABLE)
    end if

    c_title = title
    i = len_trim(title) + 1
    c_title(i:i) = char(0)

    call rl_init_window(int(width, c_int), &
        int(height, c_int), c_title)
    call rl_set_target_fps(int(target_fps, c_int))

    text_w = int(rl_measure_text("M" // char(0), &
        int(20, c_int)))
    if (text_w > 0) then
        g_cell_w = text_w
    else
        g_cell_w = 10
    end if
    g_cell_h = 20
    g_font_size = 20

    grid_cols = width / g_cell_w
    grid_rows = height / g_cell_h

    gui_active = .true.
    cell_count = 0
end subroutine gui_init

subroutine gui_shutdown()
    if (gui_active) then
        call rl_close_window()
        gui_active = .false.
    end if
end subroutine gui_shutdown

subroutine gui_begin_frame()
    integer :: rl_key, mx, my
    real(c_float) :: wheel

    if (.not. gui_active) return

    grid_cols = int(rl_get_screen_width()) / g_cell_w
    grid_rows = int(rl_get_screen_height()) / g_cell_h

    call rl_begin_drawing()
    call rl_clear_background(make_color(30, 30, 30, 255))

    cell_count = 0
    call input_reset()

    ! Poll keyboard
    do
        rl_key = int(rl_get_key_pressed())
        if (rl_key == 0) exit
        call input_set_key(map_rl_key(rl_key), rl_key)
    end do

    ! Poll mouse (convert pixel -> grid)
    mx = int(rl_get_mouse_x()) / g_cell_w
    my = int(rl_get_mouse_y()) / g_cell_h

    if (rl_is_mouse_button_pressed(RL_MOUSE_LEFT)) then
        call input_set_mouse(mx, my, 1)
    else if (rl_is_mouse_button_down(RL_MOUSE_LEFT)) then
        call input_set_mouse(mx, my, 1)
    else
        call input_set_mouse(mx, my, 0)
    end if

    if (rl_is_mouse_button_pressed(RL_MOUSE_RIGHT)) then
        call input_set_mouse(mx, my, 2)
    end if

    wheel = rl_get_mouse_wheel_move()
    if (wheel > 0.1) then
        call input_set_mouse(mx, my, 4)
    else if (wheel < -0.1) then
        call input_set_mouse(mx, my, 5)
    end if
end subroutine gui_begin_frame

subroutine gui_render()
    integer :: i, px, py
    character(len=2) :: ch_str
    type(rl_color) :: fg_c, bg_c

    if (.not. gui_active) return

    ! Flush cell buffer
    do i = 1, cell_count
        px = cell_buffer(i)%x * g_cell_w
        py = cell_buffer(i)%y * g_cell_h

        bg_c = rc_to_bg(cell_buffer(i)%bg)
        if (bg_c%a /= 0) then
            call rl_draw_rectangle(int(px, c_int), &
                int(py, c_int), int(g_cell_w, c_int), &
                int(g_cell_h, c_int), bg_c)
        end if

        if (cell_buffer(i)%ch > 31 .and. &
            cell_buffer(i)%ch < 127) then
            fg_c = rc_to_fg(cell_buffer(i)%fg)
            ch_str(1:1) = achar(cell_buffer(i)%ch)
            ch_str(2:2) = char(0)
            call rl_draw_text(ch_str, int(px, c_int), &
                int(py, c_int), int(g_font_size, c_int), &
                fg_c)
        end if
    end do

    call rl_end_drawing()
end subroutine gui_render

logical function gui_is_available()
    character(len=256) :: env_var
    integer :: ios

    call get_environment_variable("FORTUI_HEADLESS", &
        env_var, status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        gui_is_available = .false.
        return
    end if

    call get_environment_variable("CI", env_var, status=ios)
    if (ios == 0) then
        gui_is_available = .false.
        return
    end if

    call get_environment_variable("GITHUB_ACTIONS", &
        env_var, status=ios)
    if (ios == 0) then
        gui_is_available = .false.
        return
    end if

    call get_environment_variable("DISPLAY", env_var, &
        status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        gui_is_available = .true.
        return
    end if

    call get_environment_variable("WAYLAND_DISPLAY", &
        env_var, status=ios)
    if (ios == 0 .and. len_trim(env_var) > 0) then
        gui_is_available = .true.
        return
    end if

    gui_is_available = .false.
end function gui_is_available

logical function gui_check_quit()
    if (gui_active) then
        gui_check_quit = logical(rl_window_should_close())
    else
        gui_check_quit = .true.
    end if
end function gui_check_quit

subroutine gui_set_cell(x, y, ch, fg, bg)
    integer, intent(in) :: x, y, ch, fg, bg

    if (.not. gui_active) return
    if (cell_count >= MAX_CELLS) return
    cell_count = cell_count + 1
    cell_buffer(cell_count)%x = x
    cell_buffer(cell_count)%y = y
    cell_buffer(cell_count)%ch = ch
    cell_buffer(cell_count)%fg = fg
    cell_buffer(cell_count)%bg = bg
end subroutine gui_set_cell

logical function gui_is_active()
    gui_is_active = gui_active
end function gui_is_active

integer function gui_get_width()
    gui_get_width = grid_cols
end function gui_get_width

integer function gui_get_height()
    gui_get_height = grid_rows
end function gui_get_height

subroutine gui_fill_rect(x, y, w, h, color)
    integer, intent(in) :: x, y, w, h, color

    type(rl_color) :: c

    if (.not. gui_active) return
    c = rc_to_bg(color)
    if (c%a == 0) c = make_color(30, 30, 30, 255)
    call rl_draw_rectangle(int(x * g_cell_w, c_int), &
        int(y * g_cell_h, c_int), &
        int(w * g_cell_w, c_int), &
        int(h * g_cell_h, c_int), c)
end subroutine gui_fill_rect

subroutine gui_draw_text(x, y, str, fg, bg)
    integer, intent(in) :: x, y, fg, bg
    character(*), intent(in) :: str

    integer :: px, py, bw
    type(rl_color) :: fg_c, bg_c
    character(len=1024) :: c_str
    integer :: slen

    if (.not. gui_active) return
    slen = len_trim(str)
    if (slen == 0) return

    px = x * g_cell_w
    py = y * g_cell_h
    bw = slen * g_cell_w

    bg_c = rc_to_bg(bg)
    if (bg_c%a /= 0) then
        call rl_draw_rectangle(int(px, c_int), &
            int(py, c_int), int(bw, c_int), &
            int(g_cell_h, c_int), bg_c)
    end if

    c_str = str(1:slen) // char(0)
    fg_c = rc_to_fg(fg)
    call rl_draw_text(c_str, int(px, c_int), &
        int(py + 2, c_int), int(g_font_size, c_int), fg_c)
end subroutine gui_draw_text

subroutine gui_draw_border(x, y, w, h, fg, bg)
    integer, intent(in) :: x, y, w, h, fg, bg

    integer :: px, py, pw, ph
    type(rl_color) :: fg_c, bg_c

    if (.not. gui_active) return

    px = x * g_cell_w
    py = y * g_cell_h
    pw = w * g_cell_w
    ph = h * g_cell_h

    bg_c = rc_to_bg(bg)
    if (bg_c%a /= 0) then
        call rl_draw_rectangle(int(px, c_int), &
            int(py, c_int), int(pw, c_int), &
            int(ph, c_int), bg_c)
    end if

    fg_c = rc_to_fg(fg)
    call rl_draw_rectangle(int(px, c_int), &
        int(py, c_int), int(pw, c_int), &
        int(1, c_int), fg_c)
    call rl_draw_rectangle(int(px, c_int), &
        int(py + ph - 1, c_int), int(pw, c_int), &
        int(1, c_int), fg_c)
    call rl_draw_rectangle(int(px, c_int), &
        int(py, c_int), int(1, c_int), &
        int(ph, c_int), fg_c)
    call rl_draw_rectangle(int(px + pw - 1, c_int), &
        int(py, c_int), int(1, c_int), &
        int(ph, c_int), fg_c)
end subroutine gui_draw_border

#endif

end module fortui_gui
