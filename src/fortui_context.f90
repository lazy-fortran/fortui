module fortui_context
!! Runtime state retained behind the immediate composition API.
use fortui_frame, only: ui_frame_t
use fortui_input, only: input_state_t, input_begin_frame
implicit none
private

type, public :: fortui_context_t
    logical :: initialized = .false.
    logical :: in_frame = .false.
    logical :: should_quit = .false.
    integer :: frame_count = 0
    integer :: backend_id = 0
    character(len=32) :: backend_name = ""
    integer :: window_width = 0
    integer :: window_height = 0
    character(len=256) :: window_title = ""
    integer :: target_fps = 60
    logical :: vsync = .true.
    type(input_state_t) :: input
    type(ui_frame_t) :: current_frame
    type(ui_frame_t) :: previous_frame
contains
    procedure :: reset => context_reset
end type fortui_context_t

type(fortui_context_t), pointer, save :: default_context => null()

public :: create_context, destroy_context, get_default_context, set_default_context

contains

function create_context() result(ctx)
    type(fortui_context_t), pointer :: ctx

    allocate(ctx)
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

subroutine context_reset(self)
    class(fortui_context_t), intent(inout) :: self

    self%initialized = .false.
    self%in_frame = .false.
    self%should_quit = .false.
    self%frame_count = 0
    self%backend_id = 0
    self%backend_name = ""
    self%window_width = 0
    self%window_height = 0
    self%window_title = ""
    self%target_fps = 60
    self%vsync = .true.
    self%input = input_state_t()
    call input_begin_frame(self%input)
    call self%current_frame%reset()
    call self%previous_frame%reset()
end subroutine context_reset

end module fortui_context
