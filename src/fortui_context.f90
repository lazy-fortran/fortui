module fortui_context
!! Runtime state retained behind the immediate composition API.
use fortui_frame, only: ui_frame_t
use fortui_input, only: input_state_t, host_event_t, MAX_HOST_EVENTS
use fortui_canvas, only: canvas_store_t
use fortui_text, only: text_line_t
use fortui_backend, only: ui_backend_t
use fortui_error, only: report_error
implicit none
private

type, public :: widget_state_t
    !! UI-local runtime state retained per widget identity (scroll, caret, caches).
    character(len=96) :: id = ""
    integer :: last_frame = -1
    real :: scroll = 0.0
    real :: anchor = 0.0
    logical :: dragging = .false.
    logical :: captured = .false.
    integer :: caret = 0
    character(len=:), allocatable :: cache_text
    real :: cache_width = -1.0
    real :: cache_size = 0.0
    logical :: cache_markdown = .false.
    type(text_line_t), allocatable :: cache_lines(:)
    integer :: cache_count = 0
    real :: cache_height = 0.0
    integer :: wraps = 0
end type widget_state_t

type, public :: fortui_context_t
    logical :: initialized = .false.
    logical :: in_frame = .false.
    logical :: should_quit = .false.
    ! Whether keys of the current frame went to a focused text field.
    logical :: text_focused = .false.
    integer :: frame_count = 0
    class(ui_backend_t), allocatable :: backend
    character(len=32) :: backend_name = ""
    type(input_state_t) :: input
    ! Composed and last presented frame; presenting swaps the two pointers.
    type(ui_frame_t) :: frames(2)
    type(ui_frame_t), pointer :: current_frame => null()
    type(ui_frame_t), pointer :: previous_frame => null()
    type(canvas_store_t) :: canvas
    type(widget_state_t), allocatable :: states(:)
    integer :: state_count = 0
    integer :: canvas_node = 0
    ! Idle waiting: the next poll may block unless a frame is requested, the
    ! runtime is continuous, or a widget consumed input (follow-up frame).
    logical :: continuous = .false.
    logical :: frame_requested = .false.
    logical :: followup = .false.
    logical :: wait_next = .false.
    !! Monotonic time (ui_time) at which a frame is due without input; negative: none.
    double precision :: wake_at = -1d0
    integer :: waiting_presents = 0
    integer :: followups = 0
    ! Identity diagnostics: duplicates are reported once per id.
    integer :: duplicates = 0
    character(len=96), allocatable :: reported(:)
    integer :: reported_count = 0
    ! Headless event injection applied by the next ui_frame_begin.
    logical :: inject_pointer = .false.
    real :: inject_x = 0.0
    real :: inject_y = 0.0
    logical :: inject_down = .false.
    real :: inject_wheel = 0.0
    integer :: inject_key_count = 0
    integer :: inject_keys(32) = 0
    character(len=256) :: inject_text = ""
    integer :: inject_text_len = 0
    integer :: inject_host_count = 0
    type(host_event_t) :: inject_host(MAX_HOST_EVENTS)
    double precision :: inject_time = -1.0d0
    logical :: inject_resize = .false.
    integer :: inject_width = 0
    integer :: inject_height = 0
contains
    procedure :: state => context_state
    procedure :: collect_states => context_collect_states
    procedure :: report_duplicate => context_report_duplicate
    procedure :: swap_frames => context_swap_frames
end type fortui_context_t

type(fortui_context_t), pointer, save :: default_context => null()

public :: create_context, destroy_context, get_default_context, set_default_context

contains

function create_context() result(ctx)
    type(fortui_context_t), pointer :: ctx

    allocate(ctx)
    ctx%current_frame => ctx%frames(1)
    ctx%previous_frame => ctx%frames(2)
    call ctx%current_frame%reset()
    call ctx%previous_frame%reset()
end function create_context

subroutine destroy_context(ctx)
    type(fortui_context_t), pointer :: ctx

    if (.not. associated(ctx)) return
    if (associated(default_context, ctx)) nullify(default_context)
    deallocate(ctx)
    nullify(ctx)
end subroutine destroy_context

function get_default_context() result(ctx)
    type(fortui_context_t), pointer :: ctx
    ctx => default_context
end function get_default_context

subroutine set_default_context(ctx)
    type(fortui_context_t), pointer :: ctx
    default_context => ctx
end subroutine set_default_context

integer function context_state(self, id) result(index)
    !! Index of the UI-local state for `id`, created on first use.
    class(fortui_context_t), intent(inout) :: self
    character(*), intent(in) :: id
    type(widget_state_t), allocatable :: grown(:)
    integer :: i

    if (.not. allocated(self%states)) allocate(self%states(16))
    do i = 1, self%state_count
        if (self%states(i)%id == id) then
            index = i
            self%states(i)%last_frame = self%frame_count
            return
        end if
    end do
    if (self%state_count >= size(self%states)) then
        allocate(grown(2 * size(self%states)))
        grown(1:self%state_count) = self%states(1:self%state_count)
        call move_alloc(grown, self%states)
    end if
    self%state_count = self%state_count + 1
    index = self%state_count
    self%states(index) = widget_state_t(id=id, last_frame=self%frame_count)
end function context_state

subroutine context_collect_states(self)
    !! Drop UI-local state of widgets absent from the current frame.
    class(fortui_context_t), intent(inout) :: self
    integer :: i, kept

    kept = 0
    do i = 1, self%state_count
        if (self%states(i)%last_frame == self%frame_count) then
            kept = kept + 1
            if (kept /= i) self%states(kept) = self%states(i)
        end if
    end do
    self%state_count = kept
end subroutine context_collect_states

subroutine context_swap_frames(self)
    !! The composed frame becomes the previous frame (no copy).
    class(fortui_context_t), intent(inout) :: self
    type(ui_frame_t), pointer :: presented

    presented => self%current_frame
    self%current_frame => self%previous_frame
    self%previous_frame => presented
end subroutine context_swap_frames

subroutine context_report_duplicate(self, id, proc)
    !! Count a duplicate identity in this frame; report each id once.
    class(fortui_context_t), intent(inout) :: self
    character(*), intent(in) :: id, proc
    character(len=96), allocatable :: grown(:)

    self%duplicates = self%duplicates + 1
    if (.not. allocated(self%reported)) allocate(self%reported(8))
    if (any(self%reported(1:self%reported_count) == id)) return
    if (self%reported_count >= size(self%reported)) then
        allocate(grown(2 * size(self%reported)))
        grown(1:self%reported_count) = self%reported(1:self%reported_count)
        call move_alloc(grown, self%reported)
    end if
    self%reported_count = self%reported_count + 1
    self%reported(self%reported_count) = id
    call report_error("fortui_widgets", proc, "duplicate id '" // trim(id) // &
        "' in one frame; widget skipped (use key= in loops)")
end subroutine context_report_duplicate

end module fortui_context
