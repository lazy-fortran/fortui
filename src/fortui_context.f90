module fortui_context
! Context management: global state, widget state map, context lifecycle
! Also contains the unit system context type (formerly fortui_units)
use fortui_error, only: report_error, report_warning
implicit none
private

public :: get_default_context, set_default_context
public :: ui_context, ui_get_context, ui_set_context
public :: fortui_context_t, create_context, destroy_context
public :: widget_state_map, widget_state_t
public :: KIND_NONE, KIND_BUTTON, KIND_TEXT, KIND_SLIDER
public :: KIND_CHECKBOX, KIND_VIEWPORT

! Unit system context type (DPI, font, cell sizing)
type :: ui_context
    real :: dpi_scale = 1.0
    real :: em_dp = 16.0
    real :: text_scale = 1.0
    real :: cell_w_dp = 8.0
    real :: cell_h_dp = 16.0
end type ui_context

type(ui_context), save :: global_unit_context = ui_context()

! Widget kind constants
integer, parameter :: KIND_NONE = 0
integer, parameter :: KIND_BUTTON = 1
integer, parameter :: KIND_TEXT = 2
integer, parameter :: KIND_SLIDER = 3
integer, parameter :: KIND_CHECKBOX = 4
integer, parameter :: KIND_VIEWPORT = 5

! Flat discriminated widget state: all widget fields in one struct
type :: widget_state_t
    character(len=256) :: id = ""
    integer :: kind = KIND_NONE
    logical :: active = .false.
    ! Common position/size
    real :: pos_x = 0.0, pos_y = 0.0
    real :: size_w = 0.0, size_h = 0.0
    ! Button fields
    logical :: pressed = .false.
    logical :: hover = .false.
    logical :: clicked_this_frame = .false.
    integer :: last_frame_clicked = -1
    ! Text fields
    character(len=1024) :: text_value = ""
    logical :: focused = .false.
    integer :: cursor_pos = 1
    ! Slider fields
    real :: current_value = 0.0
    logical :: dragging = .false.
    real :: last_mouse_x = 0.0
    real :: last_mouse_y = 0.0
    ! Checkbox fields
    logical :: checked = .false.
    ! Viewport fields
    real :: prev_scale_x = 1.0, prev_scale_y = 1.0
    real :: prev_off_x = 0.0, prev_off_y = 0.0
    real :: viewport_w = 0.0, viewport_h = 0.0
end type widget_state_t

type :: widget_state_map
    type(widget_state_t), allocatable :: entries(:)
    integer :: count = 0
    integer :: capacity = 0
contains
    procedure :: get => map_get_state
    procedure :: ensure => map_ensure
    procedure :: clear => map_clear
    procedure :: resize => map_resize
end type widget_state_map

! Master context object containing all fortui state
type :: fortui_context_t
    logical :: initialized = .false.
    logical :: is_valid_instance = .true.
    logical :: shutting_down = .false.

    ! Backend management (integer flag, not abstract type)
    character(len=32) :: active_backend = ""
    integer :: active_backend_id = 0

    ! Window/display state
    integer :: window_width = 80
    integer :: window_height = 24
    character(len=256) :: window_title = "Fortui"
    integer :: target_fps = 60
    logical :: vsync_enabled = .true.
    character(len=32) :: idle_mode = "adaptive"
    integer :: idle_fps = 12

    ! Unit system context
    type(ui_context) :: units

    ! Widget state storage
    type(widget_state_map) :: widget_states

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
end type fortui_context_t

! Thread-local default context
type(fortui_context_t), pointer :: default_context => null()
!$OMP THREADPRIVATE(default_context)

contains

function create_context() result(ctx)
    type(fortui_context_t), pointer :: ctx

    allocate(ctx)

    ctx%widget_states%capacity = 64
    allocate(ctx%widget_states%entries(ctx%widget_states%capacity))
    ctx%widget_states%count = 0

    ctx%units%dpi_scale = 1.0
    ctx%units%em_dp = 16.0
    ctx%units%text_scale = 1.0
    ctx%units%cell_w_dp = 8.0
    ctx%units%cell_h_dp = 16.0

    ctx%is_valid_instance = .true.
    ctx%initialized = .false.
end function create_context

subroutine destroy_context(ctx)
    type(fortui_context_t), pointer :: ctx

    if (.not. associated(ctx)) return

    if (ctx%initialized) then
        call ctx%shutdown()
    end if

    call ctx%widget_states%clear()

    ctx%is_valid_instance = .false.

    deallocate(ctx)
    ctx => null()
end subroutine destroy_context

function get_default_context() result(ctx)
    type(fortui_context_t), pointer :: ctx

    ctx => default_context
end function get_default_context

subroutine set_default_context(ctx)
    type(fortui_context_t), pointer :: ctx

    if (associated(default_context)) then
        call destroy_context(default_context)
    end if

    default_context => ctx
end subroutine set_default_context

subroutine context_init(self, backend_name, width, height, &
    title, target_fps, vsync)
    class(fortui_context_t), intent(inout) :: self
    character(*), intent(in) :: backend_name
    integer, intent(in) :: width, height
    character(*), intent(in) :: title
    integer, intent(in), optional :: target_fps
    logical, intent(in), optional :: vsync

    if (.not. self%is_valid()) then
        call report_error("fortui_context", "context_init", &
            "Invalid context")
        return
    end if

    if (self%initialized) then
        call self%shutdown()
    end if

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

    self%in_frame = .false.
    self%frame_count = 0
    self%should_quit = .false.

    self%initialized = .true.
end subroutine context_init

subroutine context_shutdown(self)
    class(fortui_context_t), intent(inout) :: self

    if (.not. self%initialized) return

    self%shutting_down = .true.

    if (self%in_frame) then
        call self%end_frame()
    end if

    call self%widget_states%clear()

    self%initialized = .false.
    self%active_backend = ""
    self%active_backend_id = 0
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
        call report_error("fortui_context", &
            "context_begin_frame", "Invalid context")
        return
    end if

    if (.not. self%initialized) then
        call report_error("fortui_context", &
            "context_begin_frame", "Context not initialized")
        return
    end if

    if (self%in_frame) then
        call self%end_frame()
    end if

    self%in_frame = .true.
    self%frame_count = self%frame_count + 1
end subroutine context_begin_frame

subroutine context_end_frame(self)
    class(fortui_context_t), intent(inout) :: self

    if (.not. self%in_frame) then
        call report_warning("fortui_context", &
            "context_end_frame", "Not in frame")
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

    if (.not. self%is_valid_instance) then
        is_valid = .false.
        if (present(error_msg)) &
            error_msg = "Context instance is invalid"
        return
    end if

    if (self%dpi_scale <= 0.0 .or. self%dpi_scale > 10.0) then
        is_valid = .false.
        if (present(error_msg)) then
            write(error_msg, '(A,F6.2)') &
                "Invalid DPI scale: ", self%dpi_scale
        end if
        return
    end if

    if (self%units%cell_w_dp <= 0.0 .or. &
        self%units%cell_h_dp <= 0.0) then
        is_valid = .false.
        if (present(error_msg)) &
            error_msg = "Invalid cell dimensions"
        return
    end if

    if (self%target_fps <= 0 .or. &
        self%target_fps > 1000) then
        is_valid = .false.
        if (present(error_msg)) then
            write(error_msg, '(A,I0)') &
                "Invalid target FPS: ", self%target_fps
        end if
        return
    end if

    if (present(error_msg)) error_msg = "Context is valid"
end subroutine context_validate

! Widget state map: find entry by id and kind
function map_get_state(self, id, kind) result(index)
    class(widget_state_map), intent(in) :: self
    character(*), intent(in) :: id
    integer, intent(in) :: kind
    integer :: index

    integer :: i

    index = 0
    do i = 1, self%count
        if (self%entries(i)%active .and. &
            self%entries(i)%kind == kind .and. &
            trim(self%entries(i)%id) == trim(id)) then
            index = i
            return
        end if
    end do
end function map_get_state

! Get-or-create: returns index, creating entry if needed
function map_ensure(self, id, kind) result(index)
    class(widget_state_map), intent(inout) :: self
    character(*), intent(in) :: id
    integer, intent(in) :: kind
    integer :: index

    integer :: i, slot

    ! Search for existing entry
    do i = 1, self%count
        if (self%entries(i)%active .and. &
            self%entries(i)%kind == kind .and. &
            trim(self%entries(i)%id) == trim(id)) then
            index = i
            return
        end if
    end do

    ! Not found: find empty slot
    slot = 0
    do i = 1, self%count
        if (.not. self%entries(i)%active) then
            slot = i
            exit
        end if
    end do

    ! No empty slot: extend
    if (slot == 0) then
        if (self%count >= self%capacity) then
            call self%resize()
        end if
        self%count = self%count + 1
        slot = self%count
    end if

    ! Initialize entry
    self%entries(slot)%id = trim(id)
    self%entries(slot)%kind = kind
    self%entries(slot)%active = .true.
    self%entries(slot)%pos_x = 0.0
    self%entries(slot)%pos_y = 0.0
    self%entries(slot)%size_w = 0.0
    self%entries(slot)%size_h = 0.0
    self%entries(slot)%pressed = .false.
    self%entries(slot)%hover = .false.
    self%entries(slot)%clicked_this_frame = .false.
    self%entries(slot)%last_frame_clicked = -1
    self%entries(slot)%text_value = ""
    self%entries(slot)%focused = .false.
    self%entries(slot)%cursor_pos = 1
    self%entries(slot)%current_value = 0.0
    self%entries(slot)%dragging = .false.
    self%entries(slot)%last_mouse_x = 0.0
    self%entries(slot)%last_mouse_y = 0.0
    self%entries(slot)%checked = .false.
    self%entries(slot)%prev_scale_x = 1.0
    self%entries(slot)%prev_scale_y = 1.0
    self%entries(slot)%prev_off_x = 0.0
    self%entries(slot)%prev_off_y = 0.0
    self%entries(slot)%viewport_w = 0.0
    self%entries(slot)%viewport_h = 0.0
    index = slot
end function map_ensure

subroutine map_clear(self)
    class(widget_state_map), intent(inout) :: self

    integer :: i

    do i = 1, self%count
        self%entries(i)%active = .false.
        self%entries(i)%id = ""
        self%entries(i)%kind = KIND_NONE
    end do

    self%count = 0
end subroutine map_clear

subroutine map_resize(self)
    class(widget_state_map), intent(inout) :: self

    type(widget_state_t), allocatable :: new_entries(:)
    integer :: new_capacity

    new_capacity = max(64, self%capacity * 2)
    allocate(new_entries(new_capacity))

    if (self%count > 0) then
        new_entries(1:self%count) = self%entries(1:self%count)
    end if

    call move_alloc(new_entries, self%entries)
    self%capacity = new_capacity
end subroutine map_resize

! Unit context accessors (formerly in fortui_units)

subroutine ui_get_context(ctx)
    type(ui_context), intent(out) :: ctx

    ctx = global_unit_context
end subroutine ui_get_context

subroutine ui_set_context(ctx)
    type(ui_context), intent(in) :: ctx

    if (ctx%dpi_scale > 0.0 .and. ctx%em_dp > 0.0 .and. &
        ctx%text_scale > 0.0 .and. ctx%cell_w_dp > 0.0 .and. &
        ctx%cell_h_dp > 0.0) then
        global_unit_context = ctx
    else
        call report_warning("fortui_context", &
            "ui_set_context", &
            "Invalid context values, keeping current")
    end if
end subroutine ui_set_context

end module fortui_context
