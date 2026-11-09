module fortui_backend
!! Backend interface between the backend-neutral runtime and a platform/renderer.
!!
!! An application injects a backend value: `call ui_init(headless_backend_t(), ...)`.
!! The runtime copies it, then hands it only semantic frame data, the read-only
!! canvas store (owned layer data keyed by canvas/key with data versions) and the
!! normalized input snapshot. A backend owns its platform resources (windows,
!! GPU buffers, fonts), its realization state (`canvas`) and reports text metrics,
!! so layout never depends on one renderer.
!!
!! Idle rule: `present` never blocks. The runtime decides at each present whether
!! the next frame may wait and passes that decision to the next `poll`; a host
!! that cannot block (a browser frame callback) treats `wait` as advisory.
use fortui_frame, only: ui_frame_t
use fortui_input, only: input_state_t
use fortui_canvas, only: canvas_store_t, canvas_realizer_t
implicit none
private

type, public :: ui_backend_caps_t
    !! Capabilities a backend actually implements (false means unsupported).
    logical :: graphical = .false.
    logical :: canvas_layers = .false.
    logical :: proportional_text = .false.
    logical :: event_waiting = .false.
    !! The host calls the application once per frame (ui_run returns at once).
    logical :: host_driven = .false.
    logical :: high_dpi = .false.
    logical :: pointer = .false.
    logical :: text_entry = .false.
end type ui_backend_caps_t

type, public :: ui_window_config_t
    !! Window request from ui_init (logical units; target_fps 0 = unlimited).
    integer :: width = 800
    integer :: height = 600
    character(len=256) :: title = ""
    integer :: target_fps = 60
    logical :: vsync = .true.
end type ui_window_config_t

type, public :: ui_backend_stats_t
    !! Work a backend actually performed (evidence for idle/upload behaviour).
    integer :: presents = 0
    integer :: waits = 0
    integer :: vertex_uploads = 0
    integer :: attribute_uploads = 0
    integer :: index_uploads = 0
end type ui_backend_stats_t

type, abstract, public :: ui_backend_t
    !! Set by the runtime before `init`.
    type(ui_window_config_t) :: config = ui_window_config_t()
    !! Canvas layers this backend realized (versions and upload counters).
    type(canvas_realizer_t) :: canvas = canvas_realizer_t()
    integer :: presents = 0
    integer :: waits = 0
contains
    procedure(backend_name_i), deferred :: name
    procedure(backend_init_i), deferred :: init
    procedure(backend_shutdown_i), deferred :: shutdown
    procedure(backend_poll_i), deferred :: poll
    procedure(backend_present_i), deferred :: present
    procedure(backend_should_close_i), deferred :: should_close
    procedure(backend_metrics_i), deferred :: install_text_metrics
    procedure(backend_caps_i), deferred :: capabilities
    procedure :: stats => backend_stats
    procedure :: hand_over => backend_hand_over
    procedure :: describe => backend_describe
end type ui_backend_t

abstract interface
    function backend_name_i(self) result(name)
        import :: ui_backend_t
        class(ui_backend_t), intent(in) :: self
        character(len=:), allocatable :: name
    end function backend_name_i

    logical function backend_init_i(self)
        !! Create platform resources for `self%config`; false (with a reported
        !! reason) when the host is unavailable. Never falls back to another host.
        import :: ui_backend_t
        class(ui_backend_t), intent(inout) :: self
    end function backend_init_i

    subroutine backend_shutdown_i(self)
        !! Release every platform resource, including realized canvas resources.
        import :: ui_backend_t
        class(ui_backend_t), intent(inout) :: self
    end subroutine backend_shutdown_i

    subroutine backend_poll_i(self, input, wait)
        !! Translate platform events into the normalized input snapshot and update
        !! input%width/height (logical units) and input%scale (device px per unit).
        !! With `wait`, block until at least one event arrives (idle frames).
        import :: ui_backend_t, input_state_t
        class(ui_backend_t), intent(inout) :: self
        type(input_state_t), intent(inout) :: input
        logical, intent(in) :: wait
    end subroutine backend_poll_i

    subroutine backend_present_i(self, frame, store)
        !! Realize one semantic frame without blocking. Layer data is read from
        !! the store and uploaded only when `self%canvas` reports a new version;
        !! resources of released or reassigned store slots are freed.
        import :: ui_backend_t, ui_frame_t, canvas_store_t
        class(ui_backend_t), intent(inout) :: self
        type(ui_frame_t), intent(in) :: frame
        type(canvas_store_t), intent(in), target :: store
    end subroutine backend_present_i

    logical function backend_should_close_i(self)
        !! Host close request (window manager, terminal interrupt).
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

contains

subroutine backend_hand_over(self)
    !! Called by ui_run when the host drives the frames, after the application
    !! is registered; a host may leave the program's main here for good.
    class(ui_backend_t), intent(inout) :: self
end subroutine backend_hand_over

function backend_stats(self) result(stats)
    class(ui_backend_t), intent(in) :: self
    type(ui_backend_stats_t) :: stats

    stats%presents = self%presents
    stats%waits = self%waits
    stats%vertex_uploads = self%canvas%vertex_uploads
    stats%attribute_uploads = self%canvas%attribute_uploads
    stats%index_uploads = self%canvas%index_uploads
end function backend_stats

function backend_describe(self) result(text)
    !! Human-readable realization choices (backends override; default: name).
    class(ui_backend_t), intent(in) :: self
    character(len=:), allocatable :: text
    text = self%name()
end function backend_describe

end module fortui_backend
