module fortui_tui
! TUI backend implementation using termbox2
! Always compiled, provides terminal user interface capabilities
use fortui_backend
use iso_c_binding
implicit none
private

public :: tui_backend_t, register_tui_backend

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

type, bind(C) :: tb_cell
    integer(c_int32_t) :: ch
    integer(c_int) :: bg
    integer(c_int) :: fg
end type tb_cell

! Termbox2 constants
integer, parameter :: TB_KEY_ESC = 27
integer, parameter :: TB_EVENT_KEY = 1
integer, parameter :: TB_EVENT_RESIZE = 2
integer, parameter :: TB_EVENT_MOUSE = 3

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
    
    subroutine tb_set_clear_attributes(fg, bg) bind(C, name="tb_set_clear_attributes")
        import :: c_int
        integer(c_int), intent(in), value :: fg, bg
    end subroutine tb_set_clear_attributes
    
    subroutine tb_present() bind(C, name="tb_present")
    end subroutine tb_present
    
    subroutine tb_set_cursor(cx, cy) bind(C, name="tb_set_cursor")
        import :: c_int
        integer(c_int), intent(in), value :: cx, cy
    end subroutine tb_set_cursor
    
    subroutine tb_set_cell(x, y, ch, fg, bg) bind(C, name="tb_set_cell")
        import :: c_int, c_int32_t
        integer(c_int), intent(in), value :: x, y
        integer(c_int32_t), intent(in), value :: ch
        integer(c_int), intent(in), value :: fg, bg
    end subroutine tb_set_cell
    
    subroutine tb_print(x, y, fg, bg, str) bind(C, name="tb_print")
        import :: c_int, c_char
        integer(c_int), intent(in), value :: x, y, fg, bg
        character(c_char), intent(in) :: str(*)
    end subroutine tb_print
    
    integer(c_int) function tb_poll_event(event) bind(C, name="tb_poll_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
    end function tb_poll_event
    
    integer(c_int) function tb_peek_event(event, timeout) bind(C, name="tb_peek_event")
        import :: c_int, tb_event
        type(tb_event), intent(out) :: event
        integer(c_int), intent(in), value :: timeout
    end function tb_peek_event
    
    integer(c_int) function tb_set_input_mode(mode) bind(C, name="tb_set_input_mode")
        import :: c_int
        integer(c_int), intent(in), value :: mode
    end function tb_set_input_mode
    
    integer(c_int) function tb_set_output_mode(mode) bind(C, name="tb_set_output_mode")
        import :: c_int
        integer(c_int), intent(in), value :: mode
    end function tb_set_output_mode
end interface

contains

subroutine register_tui_backend()
    type(tui_backend_t) :: tui
    
    ! Set TUI capabilities
    tui%capabilities%colors = .true.
    tui%capabilities%mouse = .true.
    tui%capabilities%unicode = .true.
    tui%capabilities%async_events = .true.
    tui%capabilities%graphics = .false.  ! TUI doesn't support graphics primitives
    
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
    
    ! Initialize termbox2
    ret = tb_init()
    if (ret /= 0) then
        print *, "Error: Failed to initialize termbox2"
        return
    end if
    
    ! Set output mode to support colors
    ret = tb_set_output_mode(TB_OUTPUT_256)
    
    ! Enable mouse and ESC input
    input_mode = TB_INPUT_ESC + TB_INPUT_MOUSE
    ret = tb_set_input_mode(input_mode)
    
    ! Get terminal dimensions
    self%width = tb_width()
    self%height = tb_height()
    
    ! Clear screen with default colors
    call tb_clear()
    
    self%initialized = .true.
    self%mouse_enabled = .true.
end subroutine tui_init

subroutine tui_shutdown(self)
    class(tui_backend_t), intent(inout) :: self
    
    if (self%initialized) then
        call tb_shutdown()
        self%initialized = .false.
    end if
end subroutine tui_shutdown

subroutine tui_begin_frame(self)
    class(tui_backend_t), intent(inout) :: self
    
    if (self%initialized) then
        ! Update dimensions in case of resize
        self%width = tb_width()
        self%height = tb_height()
        
        ! Clear screen for new frame
        call tb_clear()
    end if
end subroutine tui_begin_frame

subroutine tui_render(self, tree)
    class(tui_backend_t), intent(inout) :: self
    class(*), intent(in) :: tree
    
    if (self%initialized) then
        ! Render the UI tree to the terminal (placeholder implementation)
        call tb_clear()
        call tb_present()
    end if
end subroutine tui_render

logical function tui_is_available(self)
    class(tui_backend_t), intent(in) :: self
    
    ! TUI is always available (terminal always exists)
    tui_is_available = .true.
end function tui_is_available

logical function tui_check_quit(self)
    class(tui_backend_t), intent(inout) :: self
    
    type(tb_event) :: event
    integer :: ret
    
    tui_check_quit = .false.
    
    if (.not. self%initialized) return
    
    ! Check for events with no timeout (non-blocking)
    ret = tb_peek_event(event, 0)
    
    if (ret > 0) then
        if (event%type == TB_EVENT_KEY) then
            ! Check for ESC key
            if (event%key == TB_KEY_ESC) then
                tui_check_quit = .true.
            end if
        end if
    end if
end function tui_check_quit

end module fortui_tui