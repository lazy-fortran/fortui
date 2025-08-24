module fortui_backend
! Backend abstraction layer for fortui - resolves circular dependency (Issue #60)
! Provides abstract interface and registry for backend implementations
use iso_c_binding
implicit none
private

! Public interface for backend operations
public :: backend_t, register_backend, get_backend, select_best_backend
public :: backend_capability, backend_registry, backend_entry
! Context-aware backend registry functions
public :: register_backend_ctx, get_backend_ctx, select_best_backend_ctx
! Export procedure interfaces
public :: init_proc, shutdown_proc, begin_frame_proc, render_proc
public :: is_available_proc, check_quit_proc

! Backend capability flags
type :: backend_capability
    logical :: graphics = .false.      ! Can render graphics primitives
    logical :: colors = .false.        ! Supports color output
    logical :: mouse = .false.         ! Mouse input support
    logical :: unicode = .false.       ! Unicode character support
    logical :: async_events = .false.  ! Asynchronous event handling
end type backend_capability

! Concrete backend type with procedure pointers (no polymorphism)
type :: backend_t
    type(backend_capability) :: capabilities
    ! Backend type discriminator
    integer :: backend_type = 0  ! 0=none, 1=tui, 2=gui
    ! Procedure pointers for backend operations
    procedure(init_proc), pointer, nopass :: init => null()
    procedure(shutdown_proc), pointer, nopass :: shutdown => null()
    procedure(begin_frame_proc), pointer, nopass :: begin_frame => null()
    procedure(render_proc), pointer, nopass :: render => null()
    procedure(is_available_proc), pointer, nopass :: is_available => null()
    procedure(check_quit_proc), pointer, nopass :: check_quit => null()
    ! Backend-specific data pointer
    type(c_ptr) :: backend_data = c_null_ptr
end type backend_t

! Interface definitions for backend procedures (procedural, not OO)
abstract interface
    subroutine init_proc(backend_data, width, height, title, target_fps, vsync)
        import :: c_ptr
        type(c_ptr), intent(inout) :: backend_data
        integer, intent(in) :: width, height
        character(*), intent(in) :: title
        integer, intent(in) :: target_fps
        logical, intent(in) :: vsync
    end subroutine init_proc
    
    subroutine shutdown_proc(backend_data)
        import :: c_ptr
        type(c_ptr), intent(inout) :: backend_data
    end subroutine shutdown_proc
    
    subroutine begin_frame_proc(backend_data)
        import :: c_ptr
        type(c_ptr), intent(inout) :: backend_data
    end subroutine begin_frame_proc
    
    subroutine render_proc(backend_data, tree_ptr)
        import :: c_ptr
        type(c_ptr), intent(inout) :: backend_data
        type(c_ptr), intent(in) :: tree_ptr  ! Pointer to render tree
    end subroutine render_proc
    
    logical function is_available_proc(backend_data)
        import :: c_ptr
        type(c_ptr), intent(in) :: backend_data
    end function is_available_proc
    
    logical function check_quit_proc(backend_data)
        import :: c_ptr
        type(c_ptr), intent(inout) :: backend_data
    end function check_quit_proc
end interface

! Backend registry entry type
type :: backend_entry
    character(len=32) :: name
    type(backend_t) :: backend
end type backend_entry

! Backend registry container (for context storage)
type :: backend_registry
    type(backend_entry), allocatable :: entries(:)
    integer :: count = 0
end type backend_registry

! Legacy backend registry entry type for backward compatibility
type :: legacy_backend_entry
    character(len=32) :: name
    type(backend_t) :: backend
end type legacy_backend_entry

! Legacy global registry for backward compatibility with default context
type(legacy_backend_entry), allocatable :: registered_backends(:)
integer :: num_backends = 0

contains

! Legacy backend registry functions for backward compatibility
subroutine register_backend(name, backend)
    character(*), intent(in) :: name
    type(backend_t), intent(in) :: backend
    
    type(legacy_backend_entry), allocatable :: temp(:)
    integer :: i
    
    ! Check for duplicate registration
    do i = 1, num_backends
        if (registered_backends(i)%name == name) then
            ! Replace existing backend
            registered_backends(i)%backend = backend
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
    registered_backends(num_backends)%backend = backend
end subroutine register_backend

function get_backend(name) result(backend)
    character(*), intent(in) :: name
    type(backend_t), pointer :: backend
    
    integer :: i
    
    backend => null()
    do i = 1, num_backends
        if (registered_backends(i)%name == name) then
            allocate(backend)
            backend = registered_backends(i)%backend
            exit
        end if
    end do
end function get_backend

function select_best_backend() result(backend_name)
    character(len=32) :: backend_name
    type(backend_t), pointer :: backend
    
    ! Try GUI first if available
    backend => get_backend("gui")
    if (associated(backend)) then
        if (associated(backend%is_available)) then
            if (backend%is_available(backend%backend_data)) then
                backend_name = "gui"
                deallocate(backend)
                return
            end if
        end if
        deallocate(backend)
    end if
    
    ! Fallback to TUI
    backend => get_backend("tui")
    if (associated(backend)) then
        if (associated(backend%is_available)) then
            if (backend%is_available(backend%backend_data)) then
                backend_name = "tui"
                deallocate(backend)
                return
            end if
        end if
        deallocate(backend)
    end if
    
    ! No backend available
    backend_name = ""
end function select_best_backend
! Context-aware backend registry functions (Issue #64)
! These functions operate on context-managed backend registries

subroutine register_backend_ctx(registry, name, backend)
    type(backend_registry), intent(inout) :: registry
    character(*), intent(in) :: name
    type(backend_t), intent(in) :: backend
    
    type(backend_entry), allocatable :: temp(:)
    integer :: i
    
    ! Check for duplicate registration
    do i = 1, registry%count
        if (registry%entries(i)%name == name) then
            ! Replace existing backend
            registry%entries(i)%backend = backend
            return
        end if
    end do
    
    ! Resize array if needed
    if (.not. allocated(registry%entries)) then
        allocate(registry%entries(4))
    else if (registry%count >= size(registry%entries)) then
        allocate(temp(size(registry%entries) * 2))
        temp(1:registry%count) = registry%entries(1:registry%count)
        call move_alloc(temp, registry%entries)
    end if
    
    ! Add new backend
    registry%count = registry%count + 1
    registry%entries(registry%count)%name = trim(adjustl(name))
    registry%entries(registry%count)%backend = backend
end subroutine register_backend_ctx

function get_backend_ctx(registry, name) result(backend)
    type(backend_registry), intent(in) :: registry
    character(*), intent(in) :: name
    type(backend_t), pointer :: backend
    
    integer :: i
    
    backend => null()
    do i = 1, registry%count
        if (registry%entries(i)%name == name) then
            allocate(backend)
            backend = registry%entries(i)%backend
            exit
        end if
    end do
end function get_backend_ctx

function select_best_backend_ctx(registry) result(backend_name)
    type(backend_registry), intent(in) :: registry
    character(len=32) :: backend_name
    type(backend_t), pointer :: backend
    
    ! Try GUI first if available
    backend => get_backend_ctx(registry, "gui")
    if (associated(backend)) then
        if (associated(backend%is_available)) then
            if (backend%is_available(backend%backend_data)) then
                backend_name = "gui"
                deallocate(backend)
                return
            end if
        end if
        deallocate(backend)
    end if
    
    ! Fallback to TUI
    backend => get_backend_ctx(registry, "tui")
    if (associated(backend)) then
        if (associated(backend%is_available)) then
            if (backend%is_available(backend%backend_data)) then
                backend_name = "tui"
                deallocate(backend)
                return
            end if
        end if
        deallocate(backend)
    end if
    
    ! No backend available
    backend_name = ""
end function select_best_backend_ctx

end module fortui_backend