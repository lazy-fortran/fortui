module fortui_tui
! TUI backend implementation using termbox2
! Always compiled, provides terminal user interface capabilities
use fortui_backend
use fortui_hash, only: line_hash_t, calculate_line_hash, hash_equal
use iso_c_binding
use iso_fortran_env, only: int64
implicit none
private

public :: tui_backend_t, register_tui_backend, tb_cell

! TUI backend implementation
type, extends(backend_interface) :: tui_backend_t
    logical :: initialized = .false.
    integer :: width = 0
    integer :: height = 0
    logical :: mouse_enabled = .false.
    logical :: bracketed_paste = .false.
    ! Cell buffers for diff-based rendering
    type(tb_cell), allocatable :: front_buffer(:,:)
    type(tb_cell), allocatable :: back_buffer(:,:)
    ! Line hashes for efficient diff detection (Issue #63 fix)
    type(line_hash_t), allocatable :: line_hashes(:)
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
    
    ! Allocate cell buffers for diff-based rendering
    if (self%width > 0 .and. self%height > 0) then
        allocate(self%front_buffer(self%width, self%height))
        allocate(self%back_buffer(self%width, self%height))
        allocate(self%line_hashes(self%height))
        call clear_cell_buffers(self)
    end if
    
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
        ! Update back buffer with new frame content
        call render_tree_to_buffer(self, tree)
        
        ! Perform diff-based rendering with type-safe hash calculation
        call diff_and_present(self)
        
        ! Swap buffers
        call swap_buffers(self)
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

subroutine clear_cell_buffers(self)
    ! Initialize cell buffers with empty cells
    class(tui_backend_t), intent(inout) :: self
    type(tb_cell) :: empty_cell
    type(line_hash_t) :: empty_hash
    integer :: x, y
    
    ! Initialize empty cell
    empty_cell%ch = 32  ! Space character
    empty_cell%fg = 0   ! Default foreground
    empty_cell%bg = 0   ! Default background
    
    ! Clear both buffers
    if (allocated(self%front_buffer) .and. allocated(self%back_buffer)) then
        do y = 1, self%height
            do x = 1, self%width
                self%front_buffer(x, y) = empty_cell
                self%back_buffer(x, y) = empty_cell
            end do
        end do
    end if
    
    ! Clear line hashes
    if (allocated(self%line_hashes)) then
        empty_hash%value = 0_int64
        do y = 1, self%height
            self%line_hashes(y) = empty_hash
        end do
    end if
end subroutine clear_cell_buffers

subroutine render_tree_to_buffer(self, tree)
    ! Render UI tree to back buffer (placeholder implementation)
    class(tui_backend_t), intent(inout) :: self
    class(*), intent(in) :: tree
    
    ! Placeholder: For now just clear the back buffer
    ! Real implementation would traverse tree and draw widgets
    if (allocated(self%back_buffer)) then
        call clear_back_buffer(self)
    end if
end subroutine render_tree_to_buffer

subroutine clear_back_buffer(self)
    ! Clear only the back buffer
    class(tui_backend_t), intent(inout) :: self
    type(tb_cell) :: empty_cell
    integer :: x, y
    
    empty_cell%ch = 32
    empty_cell%fg = 0
    empty_cell%bg = 0
    
    if (allocated(self%back_buffer)) then
        do y = 1, self%height
            do x = 1, self%width
                self%back_buffer(x, y) = empty_cell
            end do
        end do
    end if
end subroutine clear_back_buffer

subroutine diff_and_present(self)
    ! Type-safe diff-based rendering using hash calculation
    ! Resolves Issue #63: Hash calculation integer overflow
    class(tui_backend_t), intent(inout) :: self
    type(line_hash_t) :: current_hash, old_hash
    integer :: y, x
    logical :: line_changed
    
    if (.not. allocated(self%front_buffer) .or. &
        .not. allocated(self%back_buffer) .or. &
        .not. allocated(self%line_hashes)) return
        
    ! Process each line
    do y = 1, self%height
        ! Calculate hash for current line in back buffer
        current_hash = calculate_line_hash(self%back_buffer(:, y))
        old_hash = self%line_hashes(y)
        
        ! Check if line changed using type-safe comparison
        line_changed = .not. hash_equal(current_hash, old_hash)
        
        if (line_changed) then
            ! Update this line in terminal
            do x = 1, self%width
                call tb_set_cell(x-1, y-1, &  ! Convert to 0-based indexing
                    self%back_buffer(x, y)%ch, &
                    self%back_buffer(x, y)%fg, &
                    self%back_buffer(x, y)%bg)
            end do
            
            ! Update stored hash
            self%line_hashes(y) = current_hash
        end if
    end do
    
    ! Present all changes
    call tb_present()
end subroutine diff_and_present

subroutine swap_buffers(self)
    ! Swap front and back buffers for next frame
    class(tui_backend_t), intent(inout) :: self
    type(tb_cell), allocatable :: temp_buffer(:,:)
    
    if (allocated(self%front_buffer) .and. allocated(self%back_buffer)) then
        ! Move front to temp, back to front, temp to back
        call move_alloc(self%front_buffer, temp_buffer)
        call move_alloc(self%back_buffer, self%front_buffer)
        call move_alloc(temp_buffer, self%back_buffer)
    end if
end subroutine swap_buffers

end module fortui_tui