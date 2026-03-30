module fortui_backend
! Backend abstraction layer: abstract interface and registry
use iso_c_binding
implicit none
private

! Public interface for backend operations
public :: backend_interface, register_backend, get_backend, select_best_backend
public :: backend_capability, backend_registry, backend_entry

! Backend capability flags
type :: backend_capability
    logical :: graphics = .false.      ! Can render graphics primitives
    logical :: colors = .false.        ! Supports color output
    logical :: mouse = .false.         ! Mouse input support
    logical :: unicode = .false.       ! Unicode character support
    logical :: async_events = .false.  ! Asynchronous event handling
end type backend_capability

! Abstract interface that all backends must implement
type, abstract :: backend_interface
    type(backend_capability) :: capabilities
contains
    procedure(init_proc), deferred :: init
    procedure(shutdown_proc), deferred :: shutdown
    procedure(begin_frame_proc), deferred :: begin_frame
    procedure(render_proc), deferred :: render
    procedure(is_available_proc), deferred :: is_available
    procedure(check_quit_proc), deferred :: check_quit
end type backend_interface

! Interface definitions for backend procedures
abstract interface
    subroutine init_proc(self, width, height, title, target_fps, vsync)
        import :: backend_interface
        class(backend_interface), intent(inout) :: self
        integer, intent(in) :: width, height
        character(*), intent(in) :: title
        integer, intent(in) :: target_fps
        logical, intent(in) :: vsync
    end subroutine init_proc
    
    subroutine shutdown_proc(self)
        import :: backend_interface
        class(backend_interface), intent(inout) :: self
    end subroutine shutdown_proc
    
    subroutine begin_frame_proc(self)
        import :: backend_interface
        class(backend_interface), intent(inout) :: self
    end subroutine begin_frame_proc
    
    subroutine render_proc(self, tree)
        import :: backend_interface
        class(backend_interface), intent(inout) :: self
        class(*), intent(in) :: tree
    end subroutine render_proc
    
    logical function is_available_proc(self)
        import :: backend_interface
        class(backend_interface), intent(in) :: self
    end function is_available_proc
    
    logical function check_quit_proc(self)
        import :: backend_interface
        class(backend_interface), intent(inout) :: self
    end function check_quit_proc
end interface

! Backend registry entry type
type :: backend_entry
    character(len=32) :: name
    class(backend_interface), pointer :: backend => null()
end type backend_entry

! Backend registry container (for context storage)
type :: backend_registry
    type(backend_entry), allocatable :: entries(:)
    integer :: count = 0
end type backend_registry

! Global backend registry
type(backend_entry), allocatable :: registered_backends(:)
integer :: num_backends = 0

contains

subroutine register_backend(name, backend)
    character(*), intent(in) :: name
    class(backend_interface), intent(in) :: backend
    
    type(backend_entry), allocatable :: temp(:)
    integer :: i
    
    ! Check for duplicate registration
    do i = 1, num_backends
        if (registered_backends(i)%name == name) then
            ! Replace existing backend
            ! Old backend will be automatically deallocated when reassigned
            allocate(registered_backends(i)%backend, source=backend)
            return
        end if
    end do
    
    ! Resize array if needed
    if (.not. allocated(registered_backends)) then
        allocate(registered_backends(4))
    else if (num_backends >= size(registered_backends)) then
        allocate(temp(size(registered_backends) * 2))
        temp(1:num_backends) = registered_backends(1:num_backends)
        call move_alloc(temp, registered_backends)
    end if
    
    ! Add new backend
    num_backends = num_backends + 1
    registered_backends(num_backends)%name = trim(adjustl(name))
    allocate(registered_backends(num_backends)%backend, source=backend)
end subroutine register_backend

function get_backend(name) result(backend)
    character(*), intent(in) :: name
    class(backend_interface), pointer :: backend
    
    integer :: i
    
    backend => null()
    do i = 1, num_backends
        if (registered_backends(i)%name == name) then
            backend => registered_backends(i)%backend
            exit
        end if
    end do
end function get_backend

function select_best_backend() result(backend_name)
    character(len=32) :: backend_name
    class(backend_interface), pointer :: backend
    
    ! Try GUI first if available
    backend => get_backend("gui")
    if (associated(backend)) then
        if (backend%is_available()) then
            backend_name = "gui"
            return
        end if
    end if
    
    ! Fallback to TUI
    backend => get_backend("tui")
    if (associated(backend)) then
        if (backend%is_available()) then
            backend_name = "tui"
            return
        end if
    end if
    
    ! No backend available
    backend_name = ""
end function select_best_backend

end module fortui_backend