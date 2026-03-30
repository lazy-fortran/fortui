module fortui_tui
! TUI backend implementation using termbox2
! Always compiled, provides terminal user interface capabilities
use fortui_backend
use fortui_input, only: input_reset, input_set_mouse, input_set_key
use fortui_render, only: render_register_backend, render_clear_backend
use fortui_error, only: report_error
use iso_c_binding
use iso_fortran_env, only: int64
implicit none
private

public :: tui_backend_t, register_tui_backend
public :: tui_set_cell, tui_present_frame, tui_get_width, tui_get_height
public :: tui_is_active

! TUI backend implementation
type, extends(backend_interface) :: tui_backend_t
    logical :: initialized = .false.
    integer :: width = 0
    integer :: height = 0
    logical :: mouse_enabled = .false.
    logical :: bracketed_paste = .false.
contains
    procedure :: init => tui_init
    procedure :: shutdown => tui_shutdown
    procedure :: begin_frame => tui_begin_frame
    procedure :: render => tui_render
    procedure :: is_available => tui_is_available
    procedure :: check_quit => tui_check_quit
end type tui_backend_t

! Termbox2 C library interface types and constants
type, bind(C) :: tb_event
    integer(c_int) :: type
    integer(c_int) :: mod
    integer(c_int) :: key
    integer(c_int32_t) :: ch
    integer(c_int) :: w, h
    integer(c_int) :: x, y
end type tb_event

! Termbox2 constants
integer, parameter :: TB_KEY_ESC = 27
integer, parameter :: TB_KEY_CTRL_C = 3
integer, parameter :: TB_EVENT_KEY = 1
integer, parameter :: TB_EVENT_RESIZE = 2
integer, parameter :: TB_EVENT_MOUSE = 3

! Mouse button constants from termbox2
integer, parameter :: TB_KEY_MOUSE_LEFT = 65509
integer, parameter :: TB_KEY_MOUSE_RIGHT = 65510
integer, parameter :: TB_KEY_MOUSE_MIDDLE = 65511
integer, parameter :: TB_KEY_MOUSE_RELEASE = 65512
integer, parameter :: TB_KEY_MOUSE_WHEEL_UP = 65513
integer, parameter :: TB_KEY_MOUSE_WHEEL_DOWN = 65514

! Input modes
integer(c_int), parameter :: TB_INPUT_CURRENT = 0
integer(c_int), parameter :: TB_INPUT_ESC = 1
integer(c_int), parameter :: TB_INPUT_ALT = 2
integer(c_int), parameter :: TB_INPUT_MOUSE = 4

! Output modes
integer(c_int), parameter :: TB_OUTPUT_CURRENT = 0
integer(c_int), parameter :: TB_OUTPUT_NORMAL = 1
integer(c_int), parameter :: TB_OUTPUT_256 = 2
integer(c_int), parameter :: TB_OUTPUT_216 = 3
integer(c_int), parameter :: TB_OUTPUT_GRAYSCALE = 4
integer(c_int), parameter :: TB_OUTPUT_TRUECOLOR = 5

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
integer(c_int), parameter, public :: TB_BOLD = 16777216
integer(c_int), parameter, public :: TB_UNDERLINE = 33554432
integer(c_int), parameter, public :: TB_REVERSE = 67108864

! Module state: whether TUI is the active initialized backend
logical, save :: tui_active = .false.
logical, save :: quit_requested = .false.

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

    integer(c_int) function tb_height() bind(C, name="tb_height")
        import :: c_int
    end function tb_height

    subroutine tb_clear() bind(C, name="tb_clear")
    end subroutine tb_clear

    subroutine tb_set_clear_attributes(fg, bg) &
        bind(C, name="tb_set_clear_attributes")
        import :: c_int
        integer(c_int), intent(in), value :: fg, bg
    end subroutine tb_set_clear_attributes

    subroutine tb_present() bind(C, name="tb_present")
    end subroutine tb_present

    subroutine tb_set_cursor(cx, cy) bind(C, name="tb_set_cursor")
        import :: c_int
        integer(c_int), intent(in), value :: cx, cy
    end subroutine tb_set_cursor

    subroutine tb_hide_cursor() bind(C, name="tb_hide_cursor")
    end subroutine tb_hide_cursor

    subroutine tb_set_cell(x, y, ch, fg, bg) &
        bind(C, name="tb_set_cell")
        import :: c_int, c_int32_t
        integer(c_int), intent(in), value :: x, y
        integer(c_int32_t), intent(in), value :: ch
        integer(c_int), intent(in), value :: fg, bg
    end subroutine tb_set_cell

    subroutine tb_print(x, y, fg, bg, str) &
        bind(C, name="tb_print")
        import :: c_int, c_char
        integer(c_int), intent(in), value :: x, y, fg, bg
        character(c_char), intent(in) :: str(*)
    end subroutine tb_print

    integer(c_int) function tb_poll_event(event) &
        bind(C, name="tb_poll_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
    end function tb_poll_event

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

subroutine register_tui_backend()
    type(tui_backend_t) :: tui

    tui%capabilities%colors = .true.
    tui%capabilities%mouse = .true.
    tui%capabilities%unicode = .true.
    tui%capabilities%async_events = .true.
    tui%capabilities%graphics = .false.

    call register_backend("tui", tui)
end subroutine register_tui_backend

subroutine tui_init(self, width, height, title, target_fps, vsync)
    class(tui_backend_t), intent(inout) :: self
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
        call get_environment_variable("TERM", term_var, status=ios)
        if (ios == 0 .and. len_trim(term_var) > 0) then
            call report_error("fortui_tui", "tui_init", &
                "Failed to initialize termbox2. TUI requires a " &
                // "real terminal.")
        end if
        return
    end if

    ret = tb_set_output_mode(TB_OUTPUT_256)
    input_mode = TB_INPUT_ESC + TB_INPUT_MOUSE
    ret = tb_set_input_mode(input_mode)

    self%width = tb_width()
    self%height = tb_height()

    call tb_clear()
    call tb_hide_cursor()

    self%initialized = .true.
    self%mouse_enabled = .true.
    tui_active = .true.
    quit_requested = .false.

    call render_register_backend(tui_set_cell, tui_is_active, &
        tui_get_width, tui_get_height)
end subroutine tui_init

subroutine tui_shutdown(self)
    class(tui_backend_t), intent(inout) :: self

    if (self%initialized) then
        call render_clear_backend()
        call tb_shutdown()
        self%initialized = .false.
        tui_active = .false.
    end if
end subroutine tui_shutdown

subroutine tui_begin_frame(self)
    class(tui_backend_t), intent(inout) :: self

    type(tb_event) :: event
    integer :: ret

    if (.not. self%initialized) return

    self%width = tb_width()
    self%height = tb_height()
    call tb_clear()
    call input_reset()

    ! Wait for first event (16ms timeout avoids busy-spin)
    ret = tb_peek_event(event, 16)
    if (ret > 0) then
        call process_tb_event(self, event)
    end if

    ! Drain remaining pending events
    do
        ret = tb_peek_event(event, 0)
        if (ret <= 0) exit
        call process_tb_event(self, event)
    end do
end subroutine tui_begin_frame

subroutine process_tb_event(self, event)
    class(tui_backend_t), intent(inout) :: self
    type(tb_event), intent(in) :: event

    if (event%type == TB_EVENT_KEY) then
        if (event%key == TB_KEY_ESC .or. &
            event%key == TB_KEY_CTRL_C) then
            quit_requested = .true.
        end if
        call input_set_key(int(event%key), int(event%ch))

    else if (event%type == TB_EVENT_MOUSE) then
        select case (int(event%key))
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

    else if (event%type == TB_EVENT_RESIZE) then
        self%width = int(event%w)
        self%height = int(event%h)
    end if
end subroutine process_tb_event

subroutine tui_render(self, tree)
    class(tui_backend_t), intent(inout) :: self
    class(*), intent(in) :: tree

    if (self%initialized) then
        call tb_present()
    end if
end subroutine tui_render

logical function tui_is_available(self)
    class(tui_backend_t), intent(in) :: self
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

logical function tui_check_quit(self)
    class(tui_backend_t), intent(inout) :: self

    tui_check_quit = quit_requested
end function tui_check_quit

! Public helpers for widgets to draw directly to termbox2

logical function tui_is_active()
    tui_is_active = tui_active
end function tui_is_active

subroutine tui_set_cell(x, y, ch, fg, bg)
    integer, intent(in) :: x, y, ch, fg, bg

    if (.not. tui_active) return
    call tb_set_cell(int(x, c_int), int(y, c_int), &
        int(ch, c_int32_t), int(fg, c_int), int(bg, c_int))
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
