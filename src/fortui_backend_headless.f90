module fortui_backend_headless
!! Headless backend: deterministic semantic oracle. It owns no platform
!! resources; canvas layers are realized with the same version tracking and
!! upload counters a GPU backend uses. Text uses fixed metrics. Requested idle
!! waits are counted, never performed (tests inject events between frames).
use fortui_backend, only: ui_backend_t, ui_backend_caps_t
use fortui_frame, only: ui_frame_t
use fortui_input, only: input_state_t
use fortui_canvas, only: canvas_store_t
use fortui_text, only: text_use_fixed_metrics
implicit none
private

type, extends(ui_backend_t), public :: headless_backend_t
    logical :: running = .false.
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
end function headless_name

logical function headless_init(self)
    class(headless_backend_t), intent(inout) :: self
    self%running = self%config%width > 0 .and. self%config%height > 0
    headless_init = self%running
end function headless_init

subroutine headless_shutdown(self)
    class(headless_backend_t), intent(inout) :: self
    self%running = .false.
end subroutine headless_shutdown

subroutine headless_poll(self, input, wait)
    !! No platform events; the window keeps the requested or injected size.
    class(headless_backend_t), intent(inout) :: self
    type(input_state_t), intent(inout) :: input
    logical, intent(in) :: wait
    if (wait) self%waits = self%waits + 1
    input%width = max(1, input%width)
    input%height = max(1, input%height)
    input%scale = max(1.0, input%scale)
end subroutine headless_poll

subroutine headless_present(self, frame, store)
    class(headless_backend_t), intent(inout) :: self
    type(ui_frame_t), intent(in) :: frame
    type(canvas_store_t), intent(in), target :: store
    call self%canvas%realize_frame(store, frame)
    self%presents = self%presents + 1
end subroutine headless_present

logical function headless_should_close(self)
    class(headless_backend_t), intent(in) :: self
    headless_should_close = .not. self%running
end function headless_should_close

subroutine headless_metrics(self)
    class(headless_backend_t), intent(inout) :: self
    call text_use_fixed_metrics()
end subroutine headless_metrics

function headless_caps(self) result(caps)
    class(headless_backend_t), intent(in) :: self
    type(ui_backend_caps_t) :: caps
    caps%canvas_layers = .true.
    caps%pointer = .true.
    caps%text_entry = .true.
end function headless_caps

end module fortui_backend_headless
