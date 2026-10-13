module fortui_backend_headless
!! Headless backend: deterministic semantic oracle. It owns no platform
!! resources; canvas layers are realized with the same generation bookkeeping
!! and upload counters a GPU backend uses. Text uses fixed metrics.
use fortui_backend, only: ui_backend_t, ui_backend_caps_t
use fortui_frame, only: ui_frame_t
use fortui_input, only: input_state_t
use fortui_canvas, only: canvas_store_t, canvas_realize_frame
use fortui_text, only: text_use_fixed_metrics
implicit none
private

type, extends(ui_backend_t), public :: headless_backend_t
    logical :: closed = .false.
contains
    procedure :: name => headless_name
    procedure :: init => headless_init
    procedure :: shutdown => headless_shutdown
    procedure :: poll => headless_poll
    procedure :: present => headless_present
    procedure :: should_close => headless_should_close
    procedure :: install_text_metrics => headless_metrics
    procedure :: capabilities => headless_caps
end type headless_backend_t

contains

function headless_name(self) result(name)
    class(headless_backend_t), intent(in) :: self
    character(len=:), allocatable :: name
    name = "headless"
    if (.false.) name = merge("closed  ", "headless", self%closed)
end function headless_name

logical function headless_init(self, width, height, title, target_fps, vsync)
    class(headless_backend_t), intent(inout) :: self
    integer, intent(in) :: width, height, target_fps
    character(*), intent(in) :: title
    logical, intent(in) :: vsync
    self%closed = .false.
    headless_init = width > 0 .and. height > 0 .and. len(title) >= 0 .and. &
        target_fps >= 0 .and. (vsync .or. .not. vsync)
end function headless_init

subroutine headless_shutdown(self)
    class(headless_backend_t), intent(inout) :: self
    self%closed = .true.
end subroutine headless_shutdown

subroutine headless_poll(self, input, width, height, scale, timeout_ms)
    !! No platform events; tests inject synthetic events through the runtime.
    class(headless_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    integer, intent(inout) :: width, height
    real, intent(inout) :: scale
    integer, intent(in), optional :: timeout_ms
    if (self%closed .and. present(timeout_ms)) input%resized = .false.
    width = max(1, width)
    height = max(1, height)
    scale = max(1.0, scale)
end subroutine headless_poll

subroutine headless_present(self, frame, store, wait_for_events)
    class(headless_backend_t), intent(inout) :: self
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(inout), target :: store
    logical, intent(in) :: wait_for_events
    if (self%closed .and. wait_for_events) return
    call canvas_realize_frame(store, frame)
end subroutine headless_present

logical function headless_should_close(self)
    class(headless_backend_t), intent(in) :: self
    headless_should_close = self%closed
end function headless_should_close

subroutine headless_metrics(self)
    class(headless_backend_t), intent(inout) :: self
    if (self%closed) return
    call text_use_fixed_metrics()
end subroutine headless_metrics

function headless_caps(self) result(caps)
    class(headless_backend_t), intent(in) :: self
    type(ui_backend_caps_t) :: caps
    caps%canvas_layers = .true.
    caps%pointer = .true.
    caps%text_entry = .true.
    if (.false.) caps%graphical = self%closed
end function headless_caps

end module fortui_backend_headless
