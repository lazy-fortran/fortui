module fortui_tui
!! Terminal platform + renderer backend using termbox2.
use iso_c_binding
use fortui_frame, only: ui_frame_t, ui_node_t, UI_TEXT, UI_BUTTON, UI_SLIDER, UI_CHECKBOX, UI_VIEWPORT
use fortui_input, only: input_state_t, input_update_pointer, input_scroll, input_set_key
use fortui_error, only: report_error
implicit none
private

real, parameter :: CELL_W_DP = 8.0
real, parameter :: CELL_H_DP = 16.0

integer, parameter :: TB_KEY_ESC = 27
integer, parameter :: TB_KEY_CTRL_C = 3
integer, parameter :: TB_EVENT_KEY = 1
integer, parameter :: TB_EVENT_RESIZE = 2
integer, parameter :: TB_EVENT_MOUSE = 3
integer, parameter :: TB_KEY_MOUSE_LEFT = 65512
integer, parameter :: TB_KEY_MOUSE_RIGHT = 65511
integer, parameter :: TB_KEY_MOUSE_RELEASE = 65509
integer, parameter :: TB_KEY_MOUSE_WHEEL_UP = 65508
integer, parameter :: TB_KEY_MOUSE_WHEEL_DOWN = 65507
integer(c_int), parameter :: TB_INPUT_ESC = 1
integer(c_int), parameter :: TB_INPUT_MOUSE = 4
integer(c_int), parameter :: TB_OUTPUT_256 = 2
integer, parameter :: C_DEFAULT = 0, C_BLACK = 1, C_RED = 2, C_GREEN = 3
integer, parameter :: C_YELLOW = 4, C_BLUE = 5, C_CYAN = 7, C_WHITE = 8
integer, parameter :: C_BOLD = 256

logical, save :: active = .false.
logical, save :: quit_requested = .false.

type, bind(C) :: tb_event
    integer(c_int8_t) :: type
    integer(c_int8_t) :: mod
    integer(c_int16_t) :: key
    integer(c_int32_t) :: ch
    integer(c_int32_t) :: w, h, x, y
end type tb_event

interface
    integer(c_int) function tb_init() bind(C, name="tb_init")
        import :: c_int
    end function
    subroutine tb_shutdown() bind(C, name="tb_shutdown")
    end subroutine
    subroutine tb_clear() bind(C, name="tb_clear")
    end subroutine
    subroutine tb_present() bind(C, name="tb_present")
    end subroutine
    subroutine tb_hide_cursor() bind(C, name="tb_hide_cursor")
    end subroutine
    subroutine tb_set_cell(x, y, ch, fg, bg) bind(C, name="tb_set_cell")
        import :: c_int, c_int16_t, c_int32_t
        integer(c_int), value :: x, y
        integer(c_int32_t), value :: ch
        integer(c_int16_t), value :: fg, bg
    end subroutine
    integer(c_int) function tb_peek_event(event, timeout) bind(C, name="tb_peek_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
        integer(c_int), value :: timeout
    end function
    integer(c_int) function tb_set_input_mode(mode) bind(C, name="tb_set_input_mode")
        import :: c_int
        integer(c_int), value :: mode
    end function
    integer(c_int) function tb_set_output_mode(mode) bind(C, name="tb_set_output_mode")
        import :: c_int
        integer(c_int), value :: mode
    end function
end interface

public :: tui_init, tui_shutdown, tui_poll, tui_render_frame
public :: tui_is_available, tui_should_close

contains

logical function tui_init()
    integer :: status

    status = tb_init()
    tui_init = status == 0
    if (.not. tui_init) then
        call report_error("fortui_tui", "tui_init", "termbox2 could not initialize a terminal")
        return
    end if
    status = tb_set_output_mode(TB_OUTPUT_256)
    status = tb_set_input_mode(TB_INPUT_ESC + TB_INPUT_MOUSE)
    call tb_hide_cursor()
    active = .true.
    quit_requested = .false.
end function tui_init

subroutine tui_shutdown()
    if (active) call tb_shutdown()
    active = .false.
end subroutine tui_shutdown

subroutine tui_poll(input, timeout_ms)
    type(input_state_t), intent(inout) :: input
    integer, intent(in), optional :: timeout_ms
    type(tb_event) :: event
    integer :: status, timeout

    if (.not. active) return
    timeout = 50
    if (present(timeout_ms)) timeout = max(0, timeout_ms)

    status = tb_peek_event(event, timeout)
    if (status > 0) call process_event(input, event)
    do
        status = tb_peek_event(event, 0)
        if (status <= 0) exit
        call process_event(input, event)
    end do
end subroutine tui_poll

subroutine process_event(input, event)
    type(input_state_t), intent(inout) :: input
    type(tb_event), intent(in) :: event
    integer :: key

    key = iand(int(event%key), 65535)
    select case (int(event%type))
    case (TB_EVENT_KEY)
        if (key == TB_KEY_ESC .or. key == TB_KEY_CTRL_C) quit_requested = .true.
        call input_set_key(input, key, int(event%ch))
    case (TB_EVENT_MOUSE)
        select case (key)
        case (TB_KEY_MOUSE_LEFT)
            call input_update_pointer(input, real(event%x) * CELL_W_DP, real(event%y) * CELL_H_DP, .true., .true.)
        case (TB_KEY_MOUSE_RELEASE)
            call input_update_pointer(input, real(event%x) * CELL_W_DP, real(event%y) * CELL_H_DP, .false.)
        case (TB_KEY_MOUSE_WHEEL_UP)
            call input_update_pointer(input, real(event%x) * CELL_W_DP, real(event%y) * CELL_H_DP, input%pointer_down)
            call input_scroll(input, 1)
        case (TB_KEY_MOUSE_WHEEL_DOWN)
            call input_update_pointer(input, real(event%x) * CELL_W_DP, real(event%y) * CELL_H_DP, input%pointer_down)
            call input_scroll(input, -1)
        case (TB_KEY_MOUSE_RIGHT)
            call input_update_pointer(input, real(event%x) * CELL_W_DP, real(event%y) * CELL_H_DP, input%pointer_down)
        end select
    end select
end subroutine process_event

subroutine tui_render_frame(frame)
    type(ui_frame_t), intent(in) :: frame
    integer :: i

    if (.not. active) return
    call tb_clear()
    do i = 1, frame%count
        call draw_node(frame%nodes(i))
    end do
    call tb_present()
end subroutine tui_render_frame

subroutine draw_node(node)
    type(ui_node_t), intent(in) :: node
    integer :: x, y, w, h, fg, bg, knob, track, i
    real :: fraction
    character(len=512) :: label

    x = max(0, nint(node%x / CELL_W_DP))
    y = max(0, nint(node%y / CELL_H_DP))
    w = max(1, nint(node%width / CELL_W_DP))
    h = max(1, nint(node%height / CELL_H_DP))

    fg = C_WHITE
    bg = C_DEFAULT
    if (node%disabled) fg = C_BLACK
    if (node%hovered) fg = C_CYAN + C_BOLD
    if (node%focused) fg = C_YELLOW + C_BOLD
    if (node%active) then
        fg = C_BLACK + C_BOLD
        bg = C_WHITE
    end if

    select case (node%kind)
    case (UI_TEXT)
        call draw_string(x, y, trim(node%text), fg, bg, w)
    case (UI_BUTTON)
        call put_cell(x, y, iachar('['), fg, bg)
        label = " " // trim(node%text) // " "
        call draw_string(x + 1, y, trim(label), fg, bg, max(0, w - 2))
        call put_cell(x + w - 1, y, iachar(']'), fg, bg)
    case (UI_CHECKBOX)
        call put_cell(x, y, iachar('['), fg, bg)
        if (node%checked) then
            call put_cell(x + 1, y, iachar('x'), C_GREEN + C_BOLD, bg)
        else
            call put_cell(x + 1, y, iachar(' '), fg, bg)
        end if
        call put_cell(x + 2, y, iachar(']'), fg, bg)
        if (len_trim(node%text) > 0) call draw_string(x + 4, y, trim(node%text), fg, bg, max(0, w - 4))
    case (UI_SLIDER)
        if (node%max_value > node%min_value) then
            fraction = (node%value - node%min_value) / (node%max_value - node%min_value)
        else
            fraction = 0.0
        end if
        fraction = max(0.0, min(1.0, fraction))
        track = max(1, w - 2)
        knob = nint(fraction * real(max(0, track - 1)))
        call put_cell(x, y, iachar('['), fg, bg)
        do i = 0, track - 1
            if (i < knob) then
                call put_cell(x + 1 + i, y, iachar('='), C_CYAN, bg)
            else if (i == knob) then
                call put_cell(x + 1 + i, y, iachar('|'), C_WHITE + C_BOLD, bg)
            else
                call put_cell(x + 1 + i, y, iachar('-'), fg, bg)
            end if
        end do
        call put_cell(x + w - 1, y, iachar(']'), fg, bg)
    case (UI_VIEWPORT)
        call draw_border(x, y, w, h, fg, bg)
    end select
end subroutine draw_node

subroutine draw_border(x, y, w, h, fg, bg)
    integer, intent(in) :: x, y, w, h, fg, bg
    integer :: i
    if (w < 2 .or. h < 2) return
    call put_cell(x, y, iachar('+'), fg, bg)
    call put_cell(x + w - 1, y, iachar('+'), fg, bg)
    call put_cell(x, y + h - 1, iachar('+'), fg, bg)
    call put_cell(x + w - 1, y + h - 1, iachar('+'), fg, bg)
    do i = 1, w - 2
        call put_cell(x + i, y, iachar('-'), fg, bg)
        call put_cell(x + i, y + h - 1, iachar('-'), fg, bg)
    end do
    do i = 1, h - 2
        call put_cell(x, y + i, iachar('|'), fg, bg)
        call put_cell(x + w - 1, y + i, iachar('|'), fg, bg)
    end do
end subroutine draw_border

subroutine draw_string(x, y, value, fg, bg, limit)
    integer, intent(in) :: x, y, fg, bg, limit
    character(*), intent(in) :: value
    integer :: i, n
    n = min(len_trim(value), max(0, limit))
    do i = 1, n
        call put_cell(x + i - 1, y, iachar(value(i:i)), fg, bg)
    end do
end subroutine draw_string

subroutine put_cell(x, y, ch, fg, bg)
    integer, intent(in) :: x, y, ch, fg, bg
    call tb_set_cell(int(x, c_int), int(y, c_int), int(ch, c_int32_t), &
        int(fg, c_int16_t), int(bg, c_int16_t))
end subroutine put_cell

logical function tui_is_available()
    character(len=256) :: value
    integer :: status

    call get_environment_variable("FORTUI_HEADLESS", value, status=status)
    if (status == 0 .and. trim(value) == "1") then
        tui_is_available = .false.
        return
    end if
    call get_environment_variable("TERM", value, status=status)
    tui_is_available = status == 0 .and. len_trim(value) > 0
end function tui_is_available

logical function tui_should_close()
    tui_should_close = quit_requested
end function tui_should_close

end module fortui_tui
