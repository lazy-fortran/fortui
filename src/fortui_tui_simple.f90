module fortui_tui_simple
! Minimal TUI backend implementation for polymorphism removal testing
! This is a simplified version to validate the procedural interface works
use fortui_backend
use fortui_error, only: report_error
use iso_c_binding
implicit none
private

public :: register_simple_tui_backend

! Simple TUI backend data (no complex termbox2 integration yet)
type :: simple_tui_data_t
    logical :: initialized = .false.
    integer :: width = 80
    integer :: height = 24
end type simple_tui_data_t

contains

! Simple procedural TUI backend implementation
subroutine simple_tui_init_proc(backend_data, width, height, title, target_fps, vsync)
    type(c_ptr), intent(inout) :: backend_data
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in) :: target_fps
    logical, intent(in) :: vsync
    
    type(simple_tui_data_t), pointer :: tui_data
    
    ! Allocate backend data if not already allocated
    if (.not. c_associated(backend_data)) then
        allocate(tui_data)
        backend_data = c_loc(tui_data)
    else
        call c_f_pointer(backend_data, tui_data)
    end if
    
    ! Simple initialization
    tui_data%initialized = .true.
    tui_data%width = max(width, 80)
    tui_data%height = max(height, 24)
end subroutine simple_tui_init_proc

subroutine simple_tui_shutdown_proc(backend_data)
    type(c_ptr), intent(inout) :: backend_data
    type(simple_tui_data_t), pointer :: tui_data
    
    if (c_associated(backend_data)) then
        call c_f_pointer(backend_data, tui_data)
        if (tui_data%initialized) then
            tui_data%initialized = .false.
        end if
    end if
end subroutine simple_tui_shutdown_proc

subroutine simple_tui_begin_frame_proc(backend_data)
    type(c_ptr), intent(inout) :: backend_data
    ! Stub implementation for testing
end subroutine simple_tui_begin_frame_proc

subroutine simple_tui_render_proc(backend_data, tree_ptr)
    type(c_ptr), intent(inout) :: backend_data
    type(c_ptr), intent(in) :: tree_ptr
    ! Stub implementation for testing
end subroutine simple_tui_render_proc

logical function simple_tui_is_available_proc(backend_data)
    type(c_ptr), intent(in) :: backend_data
    ! Simple availability check - assume always available for testing
    simple_tui_is_available_proc = .true.
end function simple_tui_is_available_proc

logical function simple_tui_check_quit_proc(backend_data)
    type(c_ptr), intent(inout) :: backend_data
    ! Stub implementation - never quit for testing
    simple_tui_check_quit_proc = .false.
end function simple_tui_check_quit_proc

! Register this simple TUI backend
subroutine register_simple_tui_backend()
    type(backend_t) :: tui_backend
    
    ! Set up the procedural backend
    tui_backend%backend_type = 1  ! TUI type
    tui_backend%capabilities%colors = .true.
    tui_backend%capabilities%mouse = .false.
    tui_backend%capabilities%unicode = .true.
    
    ! Set procedure pointers
    tui_backend%init => simple_tui_init_proc
    tui_backend%shutdown => simple_tui_shutdown_proc
    tui_backend%begin_frame => simple_tui_begin_frame_proc
    tui_backend%render => simple_tui_render_proc
    tui_backend%is_available => simple_tui_is_available_proc
    tui_backend%check_quit => simple_tui_check_quit_proc
    
    ! Initialize data pointer
    tui_backend%backend_data = c_null_ptr
    
    ! Register with the backend system
    call register_backend("tui", tui_backend)
end subroutine register_simple_tui_backend

end module fortui_tui_simple