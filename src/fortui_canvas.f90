module fortui_canvas
!! Runtime-owned retained canvas geometry and backend-neutral canvas helpers.
!!
!! Consumers submit layers by key and generation. Data is copied into the store
!! only when the generation changes; backends realize (upload) a layer only when
!! its realized generation differs. Upload counters are backend-neutral evidence.
use iso_fortran_env, only: int32
use fortui_frame, only: canvas_view_t, ui_frame_t, LAYER_POINTS, LAYER_LINES
implicit none
private

public :: canvas_view_t, LAYER_POINTS, LAYER_LINES

type, public :: canvas_events_t
    !! Pointer semantics for one canvas in one frame. World coordinates use the
    !! view passed to `canvas_begin` (after any change the caller made earlier).
    logical :: hovered = .false.
    logical :: pressed = .false.
    logical :: released = .false.
    logical :: clicked = .false.
    logical :: double_clicked = .false.
    logical :: captured = .false.
    logical :: dragging = .false.
    logical :: drag_started = .false.
    logical :: drag_ended = .false.
    real :: x = 0.0
    real :: y = 0.0
    real :: local_x = 0.0
    real :: local_y = 0.0
    real :: press_x = 0.0
    real :: press_y = 0.0
    real :: drag_dx = 0.0
    real :: drag_dy = 0.0
    real :: wheel = 0.0
    real :: width = 0.0
    real :: height = 0.0
end type canvas_events_t

type, public :: canvas_layer_t
    logical :: in_use = .false.
    character(len=:), allocatable :: key
    integer :: serial = 0
    integer :: kind = 0
    integer :: last_frame = -1
    logical :: has_data = .false.
    integer :: generation = 0
    integer :: index_generation = 0
    logical :: realized = .false.
    logical :: realized_indices = .false.
    integer :: realized_generation = 0
    integer :: realized_index_generation = 0
    integer :: vertex_uploads = 0
    integer :: index_uploads = 0
    integer :: vertex_count = 0
    integer :: index_count = 0
    real, allocatable :: xy(:, :)
    real, allocatable :: sizes(:)
    integer(int32), allocatable :: rgba(:)
    integer(int32), allocatable :: indices(:)
    logical :: world_size = .true.
    real :: min_pixels = 1.0
    real :: line_width = 1.0
end type canvas_layer_t

type, public :: canvas_store_t
    type(canvas_layer_t), allocatable :: layers(:)
    integer :: next_serial = 0
    integer :: vertex_uploads = 0
    integer :: index_uploads = 0
contains
    procedure :: acquire => store_acquire
    procedure :: lookup => store_lookup
    procedure :: collect => store_collect
    procedure :: realize => store_realize
    procedure :: active_layers => store_active_layers
end type canvas_store_t

public :: ui_rgba, canvas_to_world, canvas_to_local, canvas_zoom_at
public :: canvas_realize_frame

contains

pure integer(int32) function ui_rgba(r, g, b, a) result(c)
    !! Pack 0..255 channels so that the bytes in memory are R, G, B, A
    !! (little-endian hosts), the layout uploaded to GPU colour attributes.
    integer, intent(in) :: r, g, b
    integer, intent(in), optional :: a
    integer :: aa, top

    aa = 255
    if (present(a)) aa = a
    top = iand(aa, 255)
    if (top > 127) top = top - 256
    c = int(iand(r, 255), int32) + ishft(int(iand(g, 255), int32), 8) + &
        ishft(int(iand(b, 255), int32), 16) + ishft(int(top, int32), 24)
end function ui_rgba

pure subroutine canvas_to_world(v, local_x, local_y, world_x, world_y)
    type(canvas_view_t), intent(in) :: v
    real, intent(in) :: local_x, local_y
    real, intent(out) :: world_x, world_y
    world_x = (local_x - v%pan_x) / v%zoom
    world_y = (local_y - v%pan_y) / v%zoom
end subroutine canvas_to_world

pure subroutine canvas_to_local(v, world_x, world_y, local_x, local_y)
    type(canvas_view_t), intent(in) :: v
    real, intent(in) :: world_x, world_y
    real, intent(out) :: local_x, local_y
    local_x = world_x * v%zoom + v%pan_x
    local_y = world_y * v%zoom + v%pan_y
end subroutine canvas_to_local

pure subroutine canvas_zoom_at(v, factor, local_x, local_y, min_zoom, max_zoom)
    !! Multiply zoom by `factor`, keeping the world point under (local_x, local_y).
    type(canvas_view_t), intent(inout) :: v
    real, intent(in) :: factor, local_x, local_y
    real, intent(in), optional :: min_zoom, max_zoom
    real :: wx, wy, lo, hi

    lo = 1.0e-6
    hi = 1.0e6
    if (present(min_zoom)) lo = min_zoom
    if (present(max_zoom)) hi = max_zoom
    call canvas_to_world(v, local_x, local_y, wx, wy)
    v%zoom = max(lo, min(hi, v%zoom * factor))
    v%pan_x = local_x - wx * v%zoom
    v%pan_y = local_y - wy * v%zoom
end subroutine canvas_zoom_at

integer function store_lookup(self, key) result(slot)
    class(canvas_store_t), intent(in) :: self
    character(*), intent(in) :: key
    integer :: i

    slot = 0
    if (.not. allocated(self%layers)) return
    do i = 1, size(self%layers)
        if (.not. self%layers(i)%in_use) cycle
        if (self%layers(i)%key == key) then
            slot = i
            return
        end if
    end do
end function store_lookup

integer function store_acquire(self, key, kind, frame_no) result(slot)
    !! Find or create the layer for `key`; a kind change creates a fresh layer.
    class(canvas_store_t), intent(inout) :: self
    character(*), intent(in) :: key
    integer, intent(in) :: kind, frame_no
    type(canvas_layer_t), allocatable :: grown(:)
    integer :: i, n

    slot = self%lookup(key)
    if (slot > 0) then
        if (self%layers(slot)%kind /= kind) then
            call release(self%layers(slot))
            slot = 0
        end if
    end if
    if (slot == 0) then
        if (.not. allocated(self%layers)) allocate(self%layers(8))
        do i = 1, size(self%layers)
            if (.not. self%layers(i)%in_use) then
                slot = i
                exit
            end if
        end do
        if (slot == 0) then
            n = size(self%layers)
            allocate(grown(2 * n))
            do i = 1, n
                call move_layer(self%layers(i), grown(i))
            end do
            call move_alloc(grown, self%layers)
            slot = n + 1
        end if
        self%next_serial = self%next_serial + 1
        self%layers(slot) = canvas_layer_t(in_use=.true., key=key, &
            serial=self%next_serial, kind=kind)
    end if
    self%layers(slot)%last_frame = frame_no
end function store_acquire

subroutine move_layer(from, to)
    type(canvas_layer_t), intent(inout) :: from, to

    to%in_use = from%in_use
    if (allocated(from%key)) call move_alloc(from%key, to%key)
    to%serial = from%serial
    to%kind = from%kind
    to%last_frame = from%last_frame
    to%has_data = from%has_data
    to%generation = from%generation
    to%index_generation = from%index_generation
    to%realized = from%realized
    to%realized_indices = from%realized_indices
    to%realized_generation = from%realized_generation
    to%realized_index_generation = from%realized_index_generation
    to%vertex_uploads = from%vertex_uploads
    to%index_uploads = from%index_uploads
    to%vertex_count = from%vertex_count
    to%index_count = from%index_count
    if (allocated(from%xy)) call move_alloc(from%xy, to%xy)
    if (allocated(from%sizes)) call move_alloc(from%sizes, to%sizes)
    if (allocated(from%rgba)) call move_alloc(from%rgba, to%rgba)
    if (allocated(from%indices)) call move_alloc(from%indices, to%indices)
    to%world_size = from%world_size
    to%min_pixels = from%min_pixels
    to%line_width = from%line_width
end subroutine move_layer

subroutine release(layer)
    type(canvas_layer_t), intent(inout) :: layer
    layer = canvas_layer_t()
end subroutine release

subroutine store_collect(self, frame_no)
    !! Release layers not submitted in frame `frame_no` (widget/layer removal).
    class(canvas_store_t), intent(inout) :: self
    integer, intent(in) :: frame_no
    integer :: i

    if (.not. allocated(self%layers)) return
    do i = 1, size(self%layers)
        if (self%layers(i)%in_use .and. self%layers(i)%last_frame /= frame_no) then
            call release(self%layers(i))
        end if
    end do
end subroutine store_collect

subroutine store_realize(self, slot, force, vertices, indices)
    !! Record realization of `slot`; report which buffers a backend must upload.
    class(canvas_store_t), intent(inout) :: self
    integer, intent(in) :: slot
    logical, intent(in) :: force
    logical, intent(out) :: vertices, indices

    associate(l => self%layers(slot))
        vertices = force .or. .not. l%realized .or. &
            l%realized_generation /= l%generation
        indices = l%kind == LAYER_LINES .and. (force .or. .not. l%realized_indices .or. &
            l%realized_index_generation /= l%index_generation)
        if (vertices) then
            l%vertex_uploads = l%vertex_uploads + 1
            self%vertex_uploads = self%vertex_uploads + 1
        end if
        if (indices) then
            l%index_uploads = l%index_uploads + 1
            self%index_uploads = self%index_uploads + 1
        end if
        l%realized = .true.
        l%realized_generation = l%generation
        if (l%kind == LAYER_LINES) then
            l%realized_indices = .true.
            l%realized_index_generation = l%index_generation
        end if
    end associate
end subroutine store_realize

subroutine canvas_realize_frame(store, frame)
    !! Resource-free realization of all layers a frame references (headless and
    !! terminal backends): generation bookkeeping and upload counters only.
    type(canvas_store_t), intent(inout) :: store
    type(ui_frame_t), intent(in) :: frame
    integer :: i
    logical :: vertices, indices

    do i = 1, frame%layer_count
        call store%realize(frame%layers(i)%slot, .false., vertices, indices)
    end do
end subroutine canvas_realize_frame

integer function store_active_layers(self) result(n)
    class(canvas_store_t), intent(in) :: self
    n = 0
    if (allocated(self%layers)) n = count(self%layers%in_use)
end function store_active_layers

end module fortui_canvas
