module fortui_tui
! TUI backend implementation using termbox2
! Provides terminal user interface capabilities via plain module procedures
use fortui_input, only: input_reset, input_set_mouse, input_set_key
use fortui_error, only: report_error
use iso_c_binding
use iso_fortran_env, only: int64
implicit none
private

public :: tui_init, tui_shutdown, tui_begin_frame, tui_render
public :: tui_is_available, tui_check_quit
public :: tui_set_cell, tui_present_frame
public :: tui_get_width, tui_get_height, tui_is_active

! Termbox2 C library interface types and constants
type, bind(C) :: tb_event
    integer(c_int8_t) :: type
    integer(c_int8_t) :: mod
    integer(c_int16_t) :: key
    integer(c_int32_t) :: ch
    integer(c_int32_t) :: w, h
    integer(c_int32_t) :: x, y
end type tb_event

! Termbox2 constants
integer, parameter :: TB_KEY_ESC = 27
integer, parameter :: TB_KEY_CTRL_C = 3
integer, parameter :: TB_EVENT_KEY = 1
integer, parameter :: TB_EVENT_RESIZE = 2
integer, parameter :: TB_EVENT_MOUSE = 3

! Mouse button constants from termbox2
integer, parameter :: TB_KEY_MOUSE_LEFT = 65512
integer, parameter :: TB_KEY_MOUSE_RIGHT = 65511
integer, parameter :: TB_KEY_MOUSE_MIDDLE = 65510
integer, parameter :: TB_KEY_MOUSE_RELEASE = 65509
integer, parameter :: TB_KEY_MOUSE_WHEEL_UP = 65508
integer, parameter :: TB_KEY_MOUSE_WHEEL_DOWN = 65507

! Input modes
integer(c_int), parameter :: TB_INPUT_ESC = 1
integer(c_int), parameter :: TB_INPUT_MOUSE = 4

! Output modes
integer(c_int), parameter :: TB_OUTPUT_256 = 2

! Termbox2 color constants
integer(c_int), parameter, public :: TB_DEFAULT = 0
integer(c_int), parameter, public :: TB_BLACK = 1
integer(c_int), parameter, public :: TB_RED = 2
integer(c_int), parameter, public :: TB_GREEN = 3
integer(c_int), parameter, public :: TB_YELLOW = 4
integer(c_int), parameter, public :: TB_BLUE = 5
integer(c_int), parameter, public :: TB_MAGENTA = 6
integer(c_int), parameter, public :: TB_CYAN = 7
integer(c_int), parameter, public :: TB_WHITE = 8
integer(c_int), parameter, public :: TB_BOLD = 256
integer(c_int), parameter, public :: TB_UNDERLINE = 512
integer(c_int), parameter, public :: TB_REVERSE = 1024

! Module state
logical, save :: tui_active = .false.
logical, save :: quit_requested = .false.
integer, save :: stored_width = 0
integer, save :: stored_height = 0

! Termbox2 C interface
interface
    integer(c_int) function tb_init() bind(C, name="tb_init")
        import :: c_int
    end function tb_init

    subroutine tb_shutdown() bind(C, name="tb_shutdown")
    end subroutine tb_shutdown

    integer(c_int) function tb_width() bind(C, name="tb_width")
        import :: c_int
    end function tb_width

    integer(c_int) function tb_height() &
        bind(C, name="tb_height")
        import :: c_int
    end function tb_height

    subroutine tb_clear() bind(C, name="tb_clear")
    end subroutine tb_clear

    subroutine tb_present() bind(C, name="tb_present")
    end subroutine tb_present

    subroutine tb_hide_cursor() bind(C, name="tb_hide_cursor")
    end subroutine tb_hide_cursor

    subroutine tb_set_cell(x, y, ch, fg, bg) &
        bind(C, name="tb_set_cell")
        import :: c_int, c_int16_t, c_int32_t
        integer(c_int), intent(in), value :: x, y
        integer(c_int32_t), intent(in), value :: ch
        integer(c_int16_t), intent(in), value :: fg, bg
    end subroutine tb_set_cell

    subroutine tb_print(x, y, fg, bg, str) &
        bind(C, name="tb_print")
        import :: c_int, c_int16_t, c_char
        integer(c_int), intent(in), value :: x, y
        integer(c_int16_t), intent(in), value :: fg, bg
        character(c_char), intent(in) :: str(*)
    end subroutine tb_print

    integer(c_int) function tb_peek_event(event, timeout) &
        bind(C, name="tb_peek_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
        integer(c_int), intent(in), value :: timeout
    end function tb_peek_event

    integer(c_int) function tb_set_input_mode(mode) &
        bind(C, name="tb_set_input_mode")
        import :: c_int
        integer(c_int), intent(in), value :: mode
    end function tb_set_input_mode

    integer(c_int) function tb_set_output_mode(mode) &
        bind(C, name="tb_set_output_mode")
        import :: c_int
        integer(c_int), intent(in), value :: mode
    end function tb_set_output_mode
end interface

contains

subroutine tui_init(width, height, title, target_fps, vsync)
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync

    integer :: ret
    integer :: input_mode
    character(len=256) :: term_var
    integer :: ios

    ret = tb_init()
    if (ret /= 0) then
        call get_environment_variable("TERM", term_var, &
            status=ios)
        if (ios == 0 .and. len_trim(term_var) > 0) then
            call report_error("fortui_tui", "tui_init", &
                "Failed to initialize termbox2. TUI " &
                // "requires a real terminal.")
        end if
        return
    end if

    ret = tb_set_output_mode(TB_OUTPUT_256)
    input_mode = TB_INPUT_ESC + TB_INPUT_MOUSE
    ret = tb_set_input_mode(input_mode)

    stored_width = int(tb_width())
    stored_height = int(tb_height())

    call tb_clear()
    call tb_hide_cursor()

    tui_active = .true.
    quit_requested = .false.
end subroutine tui_init

subroutine tui_shutdown()
    if (tui_active) then
        call tb_shutdown()
        tui_active = .false.
    end if
end subroutine tui_shutdown

subroutine tui_begin_frame()
    type(tb_event) :: event
    integer :: ret

    if (.not. tui_active) return

    stored_width = int(tb_width())
    stored_height = int(tb_height())
    call tb_clear()
    call input_reset()

    ! Wait for first event (50ms timeout)
    ret = tb_peek_event(event, 50)
    if (ret > 0) then
        call process_tb_event(event)
    end if

    ! Drain remaining pending events
    do
        ret = tb_peek_event(event, 0)
        if (ret <= 0) exit
        call process_tb_event(event)
    end do
end subroutine tui_begin_frame

subroutine process_tb_event(event)
    type(tb_event), intent(in) :: event

    integer :: key_unsigned

    key_unsigned = iand(int(event%key), 65535)

    if (int(event%type) == TB_EVENT_KEY) then
        if (key_unsigned == TB_KEY_ESC .or. &
            key_unsigned == TB_KEY_CTRL_C) then
            quit_requested = .true.
        end if
        call input_set_key(key_unsigned, int(event%ch))

    else if (int(event%type) == TB_EVENT_MOUSE) then
        select case (key_unsigned)
        case (TB_KEY_MOUSE_LEFT)
            call input_set_mouse(int(event%x), &
                int(event%y), 1)
        case (TB_KEY_MOUSE_RIGHT)
            call input_set_mouse(int(event%x), &
                int(event%y), 2)
        case (TB_KEY_MOUSE_RELEASE)
            call input_set_mouse(int(event%x), &
                int(event%y), 0)
        case (TB_KEY_MOUSE_WHEEL_UP)
            call input_set_mouse(int(event%x), &
                int(event%y), 4)
        case (TB_KEY_MOUSE_WHEEL_DOWN)
            call input_set_mouse(int(event%x), &
                int(event%y), 5)
        end select

    else if (int(event%type) == TB_EVENT_RESIZE) then
        stored_width = int(event%w)
        stored_height = int(event%h)
    end if
end subroutine process_tb_event

subroutine tui_render()
    if (tui_active) then
        call tb_present()
    end if
end subroutine tui_render

logical function tui_is_available()
    character(len=256) :: env_var
    integer :: ios

    call get_environment_variable("FORTUI_HEADLESS", env_var, &
        status=ios)
    if (ios == 0 .and. trim(env_var) == "1") then
        tui_is_available = .false.
        return
    end if

    call get_environment_variable("CI", env_var, status=ios)
    if (ios == 0) then
        tui_is_available = .false.
        return
    end if

    call get_environment_variable("GITHUB_ACTIONS", env_var, &
        status=ios)
    if (ios == 0) then
        tui_is_available = .false.
        return
    end if

    call get_environment_variable("TERM", env_var, status=ios)
    if (ios /= 0 .or. len_trim(env_var) == 0) then
        tui_is_available = .false.
        return
    end if

    tui_is_available = .true.
end function tui_is_available

logical function tui_check_quit()
    tui_check_quit = quit_requested
end function tui_check_quit

logical function tui_is_active()
    tui_is_active = tui_active
end function tui_is_active

subroutine tui_set_cell(x, y, ch, fg, bg)
    integer, intent(in) :: x, y, ch, fg, bg

    if (.not. tui_active) return
    call tb_set_cell(int(x, c_int), int(y, c_int), &
        int(ch, c_int32_t), &
        int(fg, c_int16_t), int(bg, c_int16_t))
end subroutine tui_set_cell

subroutine tui_present_frame()
    if (.not. tui_active) return
    call tb_present()
end subroutine tui_present_frame

integer function tui_get_width()
    if (tui_active) then
        tui_get_width = int(tb_width())
    else
        tui_get_width = 80
    end if
end function tui_get_width

integer function tui_get_height()
    if (tui_active) then
        tui_get_height = int(tb_height())
    else
        tui_get_height = 24
    end if
end function tui_get_height

end module fortui_tui
