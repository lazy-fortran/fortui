module fortui_termbox2_interface
! C interface bindings for termbox2 library
! Provides types, constants, and C library bindings for TUI backend
use iso_c_binding
implicit none
private

! Public types
public :: tb_event, tb_cell

! Public constants
public :: TB_KEY_ESC, TB_KEY_CTRL_C, TB_KEY_CTRL_D, TB_KEY_CTRL_Z
public :: TB_KEY_ARROW_UP, TB_KEY_ARROW_DOWN, TB_KEY_ARROW_LEFT, TB_KEY_ARROW_RIGHT
public :: TB_KEY_ENTER, TB_KEY_TAB, TB_KEY_SPACE, TB_KEY_BACKSPACE, TB_KEY_DELETE
public :: TB_EVENT_KEY, TB_EVENT_RESIZE, TB_EVENT_MOUSE
public :: TB_KEY_MOUSE_LEFT, TB_KEY_MOUSE_MIDDLE, TB_KEY_MOUSE_RIGHT
public :: TB_KEY_MOUSE_WHEEL_UP, TB_KEY_MOUSE_WHEEL_DOWN
public :: TB_COLOR_BLACK, TB_COLOR_RED, TB_COLOR_GREEN, TB_COLOR_YELLOW
public :: TB_COLOR_BLUE, TB_COLOR_MAGENTA, TB_COLOR_CYAN, TB_COLOR_WHITE, TB_COLOR_DEFAULT

! Public C interface procedures
public :: tb_init, tb_shutdown, tb_width, tb_height, tb_peek_event
public :: tb_set_cell, tb_clear, tb_present, tb_set_cursor, tb_hide_cursor

! Event structure for C interoperability
type, bind(C) :: tb_event
    integer(c_int) :: type
    integer(c_int) :: mod
    integer(c_int) :: key
    integer(c_int32_t) :: ch
    integer(c_int) :: w, h
    integer(c_int) :: x, y
end type tb_event

! Cell structure for terminal rendering
type, bind(C) :: tb_cell
    integer(c_int32_t) :: ch
    integer(c_int) :: fg
    integer(c_int) :: bg
end type tb_cell

! Termbox2 constants
integer, parameter :: TB_KEY_ESC = 27
integer, parameter :: TB_KEY_CTRL_C = 3
integer, parameter :: TB_KEY_CTRL_D = 4
integer, parameter :: TB_KEY_CTRL_Z = 26
integer, parameter :: TB_KEY_ARROW_UP = 65517     ! 0xffff - 18
integer, parameter :: TB_KEY_ARROW_DOWN = 65516   ! 0xffff - 19
integer, parameter :: TB_KEY_ARROW_LEFT = 65515   ! 0xffff - 20
integer, parameter :: TB_KEY_ARROW_RIGHT = 65514  ! 0xffff - 21
integer, parameter :: TB_KEY_ENTER = 13
integer, parameter :: TB_KEY_TAB = 9
integer, parameter :: TB_KEY_SPACE = 32
integer, parameter :: TB_KEY_BACKSPACE = 8
integer, parameter :: TB_KEY_DELETE = 127
integer, parameter :: TB_EVENT_KEY = 1
integer, parameter :: TB_EVENT_RESIZE = 2
integer, parameter :: TB_EVENT_MOUSE = 3

! Mouse event types (0xffff - offset)
integer, parameter :: TB_KEY_MOUSE_LEFT = 65512        ! 0xffff - 23
integer, parameter :: TB_KEY_MOUSE_RIGHT = 65511       ! 0xffff - 24
integer, parameter :: TB_KEY_MOUSE_MIDDLE = 65510      ! 0xffff - 25
integer, parameter :: TB_KEY_MOUSE_RELEASE = 65509     ! 0xffff - 26
integer, parameter :: TB_KEY_MOUSE_WHEEL_UP = 65508    ! 0xffff - 27
integer, parameter :: TB_KEY_MOUSE_WHEEL_DOWN = 65507  ! 0xffff - 28

! Color constants
integer, parameter :: TB_COLOR_BLACK = 0
integer, parameter :: TB_COLOR_RED = 1
integer, parameter :: TB_COLOR_GREEN = 2
integer, parameter :: TB_COLOR_YELLOW = 3
integer, parameter :: TB_COLOR_BLUE = 4
integer, parameter :: TB_COLOR_MAGENTA = 5
integer, parameter :: TB_COLOR_CYAN = 6
integer, parameter :: TB_COLOR_WHITE = 7
integer, parameter :: TB_COLOR_DEFAULT = 0

! Real termbox2 C library interface
interface
    ! Core termbox2 functions
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
    
    integer(c_int) function tb_peek_event(event, timeout_ms) &
        bind(C, name="tb_peek_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
        integer(c_int), intent(in), value :: timeout_ms
    end function tb_peek_event
    
    subroutine tb_set_cell(x, y, ch, fg, bg) bind(C, name="tb_set_cell")
        import :: c_int, c_int32_t
        integer(c_int), intent(in), value :: x, y
        integer(c_int32_t), intent(in), value :: ch
        integer(c_int), intent(in), value :: fg, bg
    end subroutine tb_set_cell
    
    subroutine tb_clear() bind(C, name="tb_clear")
    end subroutine tb_clear
    
    subroutine tb_present() bind(C, name="tb_present")
    end subroutine tb_present
    
    subroutine tb_set_cursor(x, y) bind(C, name="tb_set_cursor")
        import :: c_int
        integer(c_int), intent(in), value :: x, y
    end subroutine tb_set_cursor
    
    subroutine tb_hide_cursor() bind(C, name="tb_hide_cursor")
    end subroutine tb_hide_cursor
end interface

end module fortui_termbox2_interface