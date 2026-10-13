module fortui_backend
!! Backend interface between the backend-neutral runtime and a platform/renderer.
!!
!! The runtime hands a backend only semantic frame data, the canvas store
!! (owned layer data keyed by canvas/key with generations) and the normalized
!! input snapshot. A backend owns its platform resources (windows, GPU buffers,
!! fonts) and reports text metrics, so layout never depends on one renderer.
use fortui_frame, only: ui_frame_t
use fortui_input, only: input_state_t
use fortui_canvas, only: canvas_store_t
implicit none
private

type, public :: ui_backend_caps_t
    !! Capabilities a backend actually implements (false means unsupported).
    logical :: graphical = .false.
    logical :: canvas_layers = .false.
    logical :: proportional_text = .false.
    logical :: event_waiting = .false.
    logical :: high_dpi = .false.
    logical :: pointer = .false.
    logical :: text_entry = .false.
end type ui_backend_caps_t

type, abstract, public :: ui_backend_t
contains
    procedure(backend_name_i), deferred :: name
    procedure(backend_init_i), deferred :: init
    procedure(backend_shutdown_i), deferred :: shutdown
    procedure(backend_poll_i), deferred :: poll
    procedure(backend_present_i), deferred :: present
    procedure(backend_should_close_i), deferred :: should_close
    procedure(backend_metrics_i), deferred :: install_text_metrics
    procedure(backend_caps_i), deferred :: capabilities
end type ui_backend_t

abstract interface
    function backend_name_i(self) result(name)
        import :: ui_backend_t
        class(ui_backend_t), intent(in) :: self
        character(len=:), allocatable :: name
    end function backend_name_i

    logical function backend_init_i(self, width, height, title, target_fps, vsync)
        !! Create platform resources; width/height are logical units.
        import :: ui_backend_t
        class(ui_backend_t), intent(inout) :: self
        integer, intent(in) :: width, height, target_fps
        character(*), intent(in) :: title
        logical, intent(in) :: vsync
    end function backend_init_i

    subroutine backend_shutdown_i(self)
        !! Release every platform resource, including retained canvas resources.
        import :: ui_backend_t
        class(ui_backend_t), intent(inout) :: self
    end subroutine backend_shutdown_i

    subroutine backend_poll_i(self, input, width, height, scale, timeout_ms)
        !! Translate platform events into the normalized input snapshot and report
        !! the logical window size and framebuffer scale (device px per unit).
        import :: ui_backend_t, input_state_t
        class(ui_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        integer, intent(inout) :: width, height
        real, intent(inout) :: scale
        integer, intent(in), optional :: timeout_ms
    end subroutine backend_poll_i

    subroutine backend_present_i(self, frame, store, wait_for_events)
        !! Realize a semantic frame. Canvas layers referenced by the frame are
        !! realized through store%realize (upload only on a generation change);
        !! resources of released or reassigned store slots are freed. With
        !! `wait_for_events`, the backend may block in its next event wait.
        import :: ui_backend_t, ui_frame_t, canvas_store_t
        class(ui_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(inout), target :: store
        logical, intent(in) :: wait_for_events
    end subroutine backend_present_i

    logical function backend_should_close_i(self)
        import :: ui_backend_t
        class(ui_backend_t), intent(in) :: self
    end function backend_should_close_i

    subroutine backend_metrics_i(self)
        !! Install the text metrics used by layout (fortui_text) for this backend.
        import :: ui_backend_t
        class(ui_backend_t), intent(inout) :: self
    end subroutine backend_metrics_i

    function backend_caps_i(self) result(caps)
        import :: ui_backend_t, ui_backend_caps_t
        class(ui_backend_t), intent(in) :: self
        type(ui_backend_caps_t) :: caps
    end function backend_caps_i
end interface

end module fortui_backend
