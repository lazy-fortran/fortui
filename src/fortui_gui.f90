module fortui_gui
!! Graphical platform + renderer backend. Raylib is a bootstrap backend, not the FortUI abstraction.
#ifdef ENABLE_GUI
use iso_c_binding
use fortui_frame, only: ui_frame_t, ui_node_t, UI_TEXT, UI_BUTTON, UI_SLIDER, UI_CHECKBOX, UI_VIEWPORT
use fortui_input, only: input_state_t, input_update_pointer, input_scroll, input_set_key
#endif
implicit none
private

#ifdef ENABLE_GUI
type, bind(C) :: rl_color
    integer(c_int8_t) :: r, g, b, a
end type rl_color

integer(c_int), parameter :: RL_FLAG_VSYNC = 64
integer(c_int), parameter :: RL_FLAG_RESIZABLE = 4
integer(c_int), parameter :: RL_MOUSE_LEFT = 0
logical, save :: active = .false.

interface
    subroutine rl_init_window(w, h, title) bind(C, name="InitWindow")
        import :: c_int, c_char
        integer(c_int), value :: w, h
        character(c_char), intent(in) :: title(*)
    end subroutine
    subroutine rl_close_window() bind(C, name="CloseWindow")
    end subroutine
    logical(c_bool) function rl_window_should_close() bind(C, name="WindowShouldClose")
        import :: c_bool
    end function
    subroutine rl_begin_drawing() bind(C, name="BeginDrawing")
    end subroutine
    subroutine rl_end_drawing() bind(C, name="EndDrawing")
    end subroutine
    subroutine rl_clear_background(color) bind(C, name="ClearBackground")
        import :: rl_color
        type(rl_color), value :: color
    end subroutine
    subroutine rl_draw_rectangle(x, y, w, h, color) bind(C, name="DrawRectangle")
        import :: c_int, rl_color
        integer(c_int), value :: x, y, w, h
        type(rl_color), value :: color
    end subroutine
    subroutine rl_draw_text(text, x, y, font_size, color) bind(C, name="DrawText")
        import :: c_int, c_char, rl_color
        character(c_char), intent(in) :: text(*)
        integer(c_int), value :: x, y, font_size
        type(rl_color), value :: color
    end subroutine
    subroutine rl_set_target_fps(fps) bind(C, name="SetTargetFPS")
        import :: c_int
        integer(c_int), value :: fps
    end subroutine
    integer(c_int) function rl_get_key_pressed() bind(C, name="GetKeyPressed")
        import :: c_int
    end function
    logical(c_bool) function rl_is_mouse_button_pressed(btn) bind(C, name="IsMouseButtonPressed")
        import :: c_int, c_bool
        integer(c_int), value :: btn
    end function
    logical(c_bool) function rl_is_mouse_button_down(btn) bind(C, name="IsMouseButtonDown")
        import :: c_int, c_bool
        integer(c_int), value :: btn
    end function
    integer(c_int) function rl_get_mouse_x() bind(C, name="GetMouseX")
        import :: c_int
    end function
    integer(c_int) function rl_get_mouse_y() bind(C, name="GetMouseY")
        import :: c_int
    end function
    real(c_float) function rl_get_mouse_wheel_move() bind(C, name="GetMouseWheelMove")
        import :: c_float
    end function
    subroutine rl_set_config_flags(flags) bind(C, name="SetConfigFlags")
        import :: c_int
        integer(c_int), value :: flags
    end subroutine
end interface
#endif

public :: gui_init, gui_shutdown, gui_poll, gui_render_frame
public :: gui_is_available, gui_should_close

contains

logical function gui_init(width, height, title, target_fps, vsync)
    integer, intent(in) :: width, height, target_fps
    character(*), intent(in) :: title
    logical, intent(in) :: vsync
#ifdef ENABLE_GUI
    character(len=512) :: c_title
    integer :: n

    if (vsync) then
        call rl_set_config_flags(ior(RL_FLAG_VSYNC, RL_FLAG_RESIZABLE))
    else
        call rl_set_config_flags(RL_FLAG_RESIZABLE)
    end if

    c_title = ""
    n = min(len_trim(title), len(c_title) - 1)
    if (n > 0) c_title(1:n) = title(1:n)
    c_title(n + 1:n + 1) = char(0)
    call rl_init_window(int(width, c_int), int(height, c_int), c_title)
    call rl_set_target_fps(int(max(1, target_fps), c_int))
    active = .true.
    gui_init = .true.
#else
    gui_init = .false.
#endif
end function gui_init

subroutine gui_shutdown()
#ifdef ENABLE_GUI
    if (active) call rl_close_window()
    active = .false.
#endif
end subroutine gui_shutdown

subroutine gui_poll(input)
    use fortui_input, only: input_state_t
    type(input_state_t), intent(inout) :: input
#ifdef ENABLE_GUI
    integer :: key
    real(c_float) :: wheel

    if (.not. active) return
    call input_update_pointer(input, real(rl_get_mouse_x()), real(rl_get_mouse_y()), &
        logical(rl_is_mouse_button_down(RL_MOUSE_LEFT)), &
        logical(rl_is_mouse_button_pressed(RL_MOUSE_LEFT)))

    wheel = rl_get_mouse_wheel_move()
    if (wheel > 0.1_c_float) call input_scroll(input, 1)
    if (wheel < -0.1_c_float) call input_scroll(input, -1)

    do
        key = int(rl_get_key_pressed())
        if (key == 0) exit
        call input_set_key(input, map_key(key), key)
    end do
#endif
end subroutine gui_poll

subroutine gui_render_frame(frame)
    use fortui_frame, only: ui_frame_t
    type(ui_frame_t), intent(in) :: frame
#ifdef ENABLE_GUI
    integer :: i
    if (.not. active) return
    call rl_begin_drawing()
    call rl_clear_background(color(30, 30, 30, 255))
    do i = 1, frame%count
        call draw_node(frame%nodes(i))
    end do
    call rl_end_drawing()
#endif
end subroutine gui_render_frame

logical function gui_is_available()
#ifdef ENABLE_GUI
    character(len=256) :: value
    integer :: status

    call get_environment_variable("FORTUI_HEADLESS", value, status=status)
    if (status == 0 .and. trim(value) == "1") then
        gui_is_available = .false.
        return
    end if
#ifdef __linux__
    call get_environment_variable("DISPLAY", value, status=status)
    if (status == 0 .and. len_trim(value) > 0) then
        gui_is_available = .true.
        return
    end if
    call get_environment_variable("WAYLAND_DISPLAY", value, status=status)
    gui_is_available = status == 0 .and. len_trim(value) > 0
#else
    gui_is_available = .true.
#endif
#else
    gui_is_available = .false.
#endif
end function gui_is_available

logical function gui_should_close()
#ifdef ENABLE_GUI
    gui_should_close = .not. active .or. logical(rl_window_should_close())
#else
    gui_should_close = .true.
#endif
end function gui_should_close

#ifdef ENABLE_GUI
subroutine draw_node(node)
    type(ui_node_t), intent(in) :: node
    type(rl_color) :: fg, fill
    integer :: x, y, w, h, knob
    real :: fraction

    x = nint(node%x)
    y = nint(node%y)
    w = max(1, nint(node%width))
    h = max(1, nint(node%height))

    fg = color(235, 235, 235, 255)
    fill = color(55, 75, 105, 255)
    if (node%disabled) then
        fg = color(120, 120, 120, 255)
        fill = color(50, 50, 50, 255)
    else if (node%active) then
        fill = color(95, 125, 170, 255)
    else if (node%hovered) then
        fill = color(70, 95, 130, 255)
    end if
    if (node%focused) fg = color(255, 220, 90, 255)

    select case (node%kind)
    case (UI_TEXT)
        call draw_text(node%text, x, y, 20, fg)
    case (UI_BUTTON)
        call rl_draw_rectangle(x, y, w, h, fill)
        call draw_text(node%text, x + 12, y + 6, 20, fg)
    case (UI_CHECKBOX)
        call rl_draw_rectangle(x, y + 4, 22, 22, fill)
        if (node%checked) call draw_text("x", x + 6, y + 3, 20, color(120, 230, 140, 255))
        if (len_trim(node%text) > 0) call draw_text(node%text, x + 32, y + 6, 20, fg)
    case (UI_SLIDER)
        call rl_draw_rectangle(x, y + h / 2 - 2, w, 4, color(80, 80, 80, 255))
        if (node%max_value > node%min_value) then
            fraction = (node%value - node%min_value) / (node%max_value - node%min_value)
        else
            fraction = 0.0
        end if
        fraction = max(0.0, min(1.0, fraction))
        knob = x + nint(fraction * real(w))
        call rl_draw_rectangle(knob - 5, y + 4, 10, max(8, h - 8), fg)
    case (UI_VIEWPORT)
        call draw_border(x, y, w, h, fg)
    end select
end subroutine draw_node

subroutine draw_text(value, x, y, size, c)
    character(*), intent(in) :: value
    integer, intent(in) :: x, y, size
    type(rl_color), intent(in) :: c
    character(len=1024) :: c_text
    integer :: n

    n = min(len_trim(value), len(c_text) - 1)
    c_text = ""
    if (n > 0) c_text(1:n) = value(1:n)
    c_text(n + 1:n + 1) = char(0)
    call rl_draw_text(c_text, int(x, c_int), int(y, c_int), int(size, c_int), c)
end subroutine draw_text

subroutine draw_border(x, y, w, h, c)
    integer, intent(in) :: x, y, w, h
    type(rl_color), intent(in) :: c
    call rl_draw_rectangle(x, y, w, 1, c)
    call rl_draw_rectangle(x, y + h - 1, w, 1, c)
    call rl_draw_rectangle(x, y, 1, h, c)
    call rl_draw_rectangle(x + w - 1, y, 1, h, c)
end subroutine draw_border

pure function map_key(key) result(mapped)
    integer, intent(in) :: key
    integer :: mapped
    select case (key)
    case (256); mapped = 27
    case (257); mapped = 13
    case (258); mapped = 9
    case (32);  mapped = 32
    case (265); mapped = 65517
    case (264); mapped = 65516
    case (263); mapped = 65515
    case (262); mapped = 65514
    case default; mapped = key
    end select
end function map_key

pure function color(r, g, b, a) result(c)
    integer, intent(in) :: r, g, b, a
    type(rl_color) :: c
    c%r = byte(r)
    c%g = byte(g)
    c%b = byte(b)
    c%a = byte(a)
end function color

pure integer(c_int8_t) function byte(value)
    integer, intent(in) :: value
    if (value > 127) then
        byte = int(value - 256, c_int8_t)
    else
        byte = int(value, c_int8_t)
    end if
end function byte
#endif

end module fortui_gui
