module fortui_context
! Context Object Pattern implementation for Issue #64
! Encapsulates all global mutable state in context objects to enable:
! - Thread safety through isolated state
! - Multiple UI instances (reentrancy) 
! - Clean testing without state bleed
! - Explicit state dependencies
use fortui_error, only: report_error, report_warning
use fortui_backend, only: backend_t, backend_registry
use fortui_units, only: ui_context
use fortui_widget_renderer, only: renderer_t
implicit none
private

! Public types and procedures - INTERNAL USE ONLY
! NOTE: fortui_context_t and lifecycle functions are INTERNAL - not user-visible
public :: get_default_context, set_default_context
public :: ui_context
! Internal exports for fortui_core module only
public :: fortui_context_t, create_context, destroy_context
public :: widget_state_map, widget_state_entry, widget_state_union
! Export widget state types for use by fortui_widgets
public :: button_state, text_state, slider_state, checkbox_state, viewport_state

! Backend-specific state union (replaces class(*) for backends)
type :: backend_state_union
    ! Backend type discriminator
    integer :: backend_type = 0  ! 0=none, 1=tui, 2=gui
    ! Concrete backend state storage
    ! NOTE: These will be defined when backend modules are refactored
    integer :: placeholder  ! Temporary until backend state types are defined
end type backend_state_union

! Define widget state types here to avoid circular dependencies
! Button widget state
type :: button_state
    logical :: pressed = .false.
    logical :: hover = .false.
    logical :: clicked_this_frame = .false.
    integer :: last_frame_clicked = -1
end type button_state

! Text widget state
type :: text_state
    character(len=1024) :: value = ""
    logical :: focused = .false.
    integer :: cursor_pos = 1
end type text_state

! Slider widget state
type :: slider_state
    real :: current_value = 0.0
    logical :: dragging = .false.
    real :: last_mouse_x = 0.0
end type slider_state

! Checkbox widget state
type :: checkbox_state
    logical :: checked = .false.
    logical :: hover = .false.
end type checkbox_state

! Viewport widget state
type :: viewport_state
    logical :: dragging = .false.
    real :: last_mouse_x = 0.0
    real :: last_mouse_y = 0.0
    real :: viewport_x = 0.0
    real :: viewport_y = 0.0
    real :: viewport_w = 0.0
    real :: viewport_h = 0.0
    real :: prev_scale_x = 1.0
    real :: prev_scale_y = 1.0
    real :: prev_off_x = 0.0
    real :: prev_off_y = 0.0
end type viewport_state

! Widget state storage types (defined before context type)
! Union type for widget-specific state (replaces class(*))
type :: widget_state_union
    ! State type discriminator
    integer :: state_type = 0  ! 0=none, 1=button, 2=text, 3=slider, 4=checkbox, 5=viewport
    ! Concrete state storage (only one active at a time)
    type(button_state) :: button
    type(text_state) :: text
    type(slider_state) :: slider
    type(checkbox_state) :: checkbox
    type(viewport_state) :: viewport
end type widget_state_union

type :: widget_state_entry
    character(len=256) :: id = ""
    character(len=32) :: widget_type = ""
    type(widget_state_union) :: state
    logical :: active = .false.
end type widget_state_entry

type :: widget_state_map
    type(widget_state_entry), allocatable :: entries(:)
    integer :: count = 0
    integer :: capacity = 0
contains
    procedure :: get => map_get_state
    procedure :: set => map_set_state
    procedure :: clear => map_clear
    procedure :: resize => map_resize
end type widget_state_map

! Master context object containing all fortui state
type :: fortui_context_t
    ! Core lifecycle state
    logical :: initialized = .false.
    logical :: is_valid_instance = .true.
    logical :: shutting_down = .false.
    
    ! Backend management
    character(len=32) :: active_backend = ""
    type(backend_t), pointer :: backend => null()
    
    ! Widget renderer (collaboration pattern)
    type(renderer_t), pointer :: renderer => null()
    
    ! Window/display state
    integer :: window_width = 80
    integer :: window_height = 24
    character(len=256) :: window_title = "Fortui"
    integer :: target_fps = 60
    logical :: vsync_enabled = .true.
    character(len=32) :: idle_mode = "adaptive"
    integer :: idle_fps = 12
    
    ! Unit system context (encapsulates fortui_units state)
    type(ui_context) :: units
    
    ! Backend-specific state (union type storage)
    type(backend_state_union) :: backend_state
    
    ! Widget state storage (hash table for scalability)
    type(widget_state_map) :: widget_states
    
    ! Backend registry (moved from global module state)
    type(backend_registry) :: backends
    
    ! Frame management
    logical :: in_frame = .false.
    integer :: frame_count = 0
    logical :: should_quit = .false.
    
    ! DPI and scaling
    real :: dpi_scale = 1.0
    
contains
    procedure :: init => context_init
    procedure :: shutdown => context_shutdown
    procedure :: begin_frame => context_begin_frame
    procedure :: end_frame => context_end_frame
    procedure :: is_valid => context_is_valid
    procedure :: validate => context_validate
    procedure :: get_renderer => context_get_renderer
    procedure :: set_renderer => context_set_renderer
end type fortui_context_t

! Widget state map implementation (types defined above)

! Thread-local default context for backward compatibility
type(fortui_context_t), pointer :: default_context => null()
!$OMP THREADPRIVATE(default_context)

contains

! Context creation and lifecycle management
function create_context() result(ctx)
    type(fortui_context_t), pointer :: ctx
    
    allocate(ctx)
    
    ! Initialize widget state map with initial capacity
    ctx%widget_states%capacity = 64
    allocate(ctx%widget_states%entries(ctx%widget_states%capacity))
    ctx%widget_states%count = 0
    
    ! Backend registry is initialized on first use
    
    ! Initialize units context with defaults
    ctx%units%dpi_scale = 1.0
    ctx%units%em_dp = 16.0
    ctx%units%text_scale = 1.0
    ctx%units%cell_w_dp = 8.0
    ctx%units%cell_h_dp = 16.0
    
    ! Mark as valid and uninitialized
    ctx%is_valid_instance = .true.
    ctx%initialized = .false.
end function create_context

subroutine destroy_context(ctx)
    type(fortui_context_t), pointer :: ctx
    
    if (.not. associated(ctx)) return
    
    ! Shutdown if still initialized
    if (ctx%initialized) then
        call ctx%shutdown()
    end if
    
    ! Clear widget states
    call ctx%widget_states%clear()
    
    ! Backend registry and backend_state will be automatically deallocated
    ! when context goes out of scope (Fortran automatic memory management)
    
    ! Mark as invalid to prevent use after free
    ctx%is_valid_instance = .false.
    
    ! Deallocate context
    deallocate(ctx)
    ctx => null()
end subroutine destroy_context

! Default context management for backward compatibility
function get_default_context() result(ctx)
    type(fortui_context_t), pointer :: ctx
    
    ctx => default_context
end function get_default_context

subroutine set_default_context(ctx)
    type(fortui_context_t), pointer :: ctx
    
    ! Clean up existing default context if it exists
    if (associated(default_context)) then
        call destroy_context(default_context)
    end if
    
    default_context => ctx
end subroutine set_default_context

! Context lifecycle methods
subroutine context_init(self, backend_name, width, height, title, target_fps, vsync)
    class(fortui_context_t), intent(inout) :: self
    character(*), intent(in) :: backend_name
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in), optional :: target_fps
    logical, intent(in), optional :: vsync
    
    ! Validate context before initialization
    if (.not. self%is_valid()) then
        call report_error("fortui_context", "context_init", "Invalid context")
        return
    end if
    
    ! Reset if already initialized
    if (self%initialized) then
        call self%shutdown()
    end if
    
    ! Store configuration
    self%active_backend = trim(backend_name)
    self%window_width = max(1, width)
    self%window_height = max(1, height)
    self%window_title = trim(title)
    
    if (present(target_fps)) then
        self%target_fps = max(1, target_fps)
    end if
    
    if (present(vsync)) then
        self%vsync_enabled = vsync
    end if
    
    ! Reset frame state
    self%in_frame = .false.
    self%frame_count = 0
    self%should_quit = .false.
    
    self%initialized = .true.
end subroutine context_init

subroutine context_shutdown(self)
    class(fortui_context_t), intent(inout) :: self
    
    if (.not. self%initialized) return
    
    ! Mark as shutting down to suppress cleanup error messages
    self%shutting_down = .true.
    
    ! End current frame if in progress
    if (self%in_frame) then
        call self%end_frame()
    end if
    
    ! Disconnect from backend
    self%backend => null()
    
    ! Clear all widget states
    call self%widget_states%clear()
    
    ! Backend registry and backend_state will be automatically deallocated
    ! when context goes out of scope (Fortran automatic memory management)
    
    ! Reset state
    self%initialized = .false.
    self%active_backend = ""
    self%window_width = 0
    self%window_height = 0
    self%window_title = ""
    self%target_fps = 60
    self%vsync_enabled = .true.
    self%idle_mode = "adaptive"
    self%idle_fps = 12
    self%in_frame = .false.
    self%frame_count = 0
    self%should_quit = .false.
    self%dpi_scale = 1.0
end subroutine context_shutdown

subroutine context_begin_frame(self)
    class(fortui_context_t), intent(inout) :: self
    
    if (.not. self%is_valid()) then
        call report_error("fortui_context", "context_begin_frame", "Invalid context")
        return
    end if
    
    if (.not. self%initialized) then
        call report_error("fortui_context", "context_begin_frame", "Context not initialized")
        return
    end if
    
    if (self%in_frame) then
        call report_warning("fortui_context", "context_begin_frame", "Already in frame")
        ! Auto-end previous frame to allow new frame to begin
        call self%end_frame()
    end if
    
    self%in_frame = .true.
    self%frame_count = self%frame_count + 1
end subroutine context_begin_frame

subroutine context_end_frame(self)
    class(fortui_context_t), intent(inout) :: self
    
    if (.not. self%in_frame) then
        call report_warning("fortui_context", "context_end_frame", "Not in frame")
        return
    end if
    
    self%in_frame = .false.
end subroutine context_end_frame

logical function context_is_valid(self)
    class(fortui_context_t), intent(in) :: self
    
    context_is_valid = self%is_valid_instance
end function context_is_valid

subroutine context_validate(self, is_valid, error_msg)
    class(fortui_context_t), intent(in) :: self
    logical, intent(out) :: is_valid
    character(*), intent(out), optional :: error_msg
    
    is_valid = .true.
    
    ! Check instance validity
    if (.not. self%is_valid_instance) then
        is_valid = .false.
        if (present(error_msg)) error_msg = "Context instance is invalid"
        return
    end if
    
    ! Check DPI scale bounds
    if (self%dpi_scale <= 0.0 .or. self%dpi_scale > 10.0) then
        is_valid = .false.
        if (present(error_msg)) then
            write(error_msg, '(A,F6.2)') "Invalid DPI scale: ", self%dpi_scale
        end if
        return
    end if
    
    ! Check cell dimensions
    if (self%units%cell_w_dp <= 0.0 .or. self%units%cell_h_dp <= 0.0) then
        is_valid = .false.
        if (present(error_msg)) error_msg = "Invalid cell dimensions"
        return
    end if
    
    ! Check target FPS
    if (self%target_fps <= 0 .or. self%target_fps > 1000) then
        is_valid = .false.
        if (present(error_msg)) then
            write(error_msg, '(A,I0)') "Invalid target FPS: ", self%target_fps
        end if
        return
    end if
    
    if (present(error_msg)) error_msg = "Context is valid"
end subroutine context_validate

! Widget state map implementation
function map_get_state(self, id, widget_type) result(index)
    class(widget_state_map), intent(in) :: self
    character(*), intent(in) :: id
    character(*), intent(in) :: widget_type
    integer :: index
    
    integer :: i
    
    index = 0  ! Not found
    
    ! Linear search for now (can be optimized with hash table later)
    do i = 1, self%count
        if (self%entries(i)%active .and. &
            trim(self%entries(i)%id) == trim(id) .and. &
            trim(self%entries(i)%widget_type) == trim(widget_type)) then
            
            ! Always return valid index for active entries
            index = i
            return
        end if
    end do
end function map_get_state

subroutine map_set_state(self, id, widget_type, state)
    class(widget_state_map), intent(inout) :: self
    character(*), intent(in) :: id
    character(*), intent(in) :: widget_type
    type(widget_state_union), intent(in) :: state
    
    integer :: i, slot
    
    ! Look for existing entry
    slot = 0
    do i = 1, self%count
        if (self%entries(i)%active .and. &
            trim(self%entries(i)%id) == trim(id) .and. &
            trim(self%entries(i)%widget_type) == trim(widget_type)) then
            slot = i
            exit
        end if
    end do
    
    ! If not found, look for empty slot
    if (slot == 0) then
        do i = 1, self%count
            if (.not. self%entries(i)%active) then
                slot = i
                exit
            end if
        end do
    end if
    
    ! If still no slot, extend array
    if (slot == 0) then
        if (self%count >= self%capacity) then
            call self%resize()
        end if
        self%count = self%count + 1
        slot = self%count
    end if
    
    ! Store state
    self%entries(slot)%id = trim(id)
    self%entries(slot)%widget_type = trim(widget_type)
    
    ! Copy union state directly (no allocation needed)
    self%entries(slot)%state = state
    self%entries(slot)%active = .true.
end subroutine map_set_state

subroutine map_clear(self)
    class(widget_state_map), intent(inout) :: self
    
    integer :: i
    
    ! Clear all state objects (automatic deallocation on reassignment)
    do i = 1, self%count
        self%entries(i)%active = .false.
        self%entries(i)%id = ""
        self%entries(i)%widget_type = ""
        ! Note: allocatable state is automatically deallocated
    end do
    
    self%count = 0
end subroutine map_clear

subroutine map_resize(self)
    class(widget_state_map), intent(inout) :: self
    
    type(widget_state_entry), allocatable :: new_entries(:)
    integer :: new_capacity
    
    ! Double the capacity
    new_capacity = max(64, self%capacity * 2)
    allocate(new_entries(new_capacity))
    
    ! Copy existing entries
    if (self%count > 0) then
        new_entries(1:self%count) = self%entries(1:self%count)
    end if
    
    ! Replace array
    call move_alloc(new_entries, self%entries)
    self%capacity = new_capacity
end subroutine map_resize

! Renderer management methods
function context_get_renderer(self) result(renderer)
    class(fortui_context_t), intent(in) :: self
    type(renderer_t), pointer :: renderer
    
    renderer => self%renderer
end function context_get_renderer

subroutine context_set_renderer(self, renderer)
    class(fortui_context_t), intent(inout) :: self
    type(renderer_t), intent(in), target :: renderer
    
    self%renderer => renderer
end subroutine context_set_renderer

end module fortui_context