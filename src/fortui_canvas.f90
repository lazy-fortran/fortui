module fortui_canvas
!! Runtime-owned retained canvas geometry and backend-neutral canvas helpers.
!!
!! Consumers submit layers by key and generation. The store copies data only
!! when a generation (or the referenced vertex count) changes and then bumps the
!! layer's internal `version`. Vertex layers hold positions shared by several
!! point/line layers. Backends own a `canvas_realizer_t` that remembers which
!! versions they realized, so data is uploaded only after a real change.
use iso_fortran_env, only: int32
use fortui_frame, only: canvas_view_t, ui_frame_t, ui_layer_ref_t, LAYER_POINTS, &
    LAYER_LINES, LAYER_VERTICES
use fortui_error, only: report_error
implicit none
private

public :: canvas_view_t, LAYER_POINTS, LAYER_LINES, LAYER_VERTICES

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
    ! Caller generations of the copied data (index: line segments).
    integer :: generation = 0
    integer :: index_generation = 0
    ! Store-internal data versions, bumped on every copy.
    integer :: version = 0
    integer :: index_version = 0
    ! Drawable layers: the vertex layer they reference.
    integer :: vertex_slot = 0
    integer :: vertex_serial = 0
    integer :: vertex_count = 0
    integer :: index_count = 0
    ! Drawable layers: vertex count of the referenced layer at the last copy.
    integer :: seen_count = -1
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
contains
    procedure :: acquire => store_acquire
    procedure :: lookup => store_lookup
    procedure :: collect => store_collect
    procedure :: submit_vertices => store_submit_vertices
    procedure :: submit_points => store_submit_points
    procedure :: submit_lines => store_submit_lines
    procedure :: ref => store_ref
    procedure :: active_layers => store_active_layers
end type canvas_store_t

type :: realized_t
    integer :: serial = 0
    integer :: version = -1
    integer :: index_version = -1
    integer :: uploads = 0
    integer :: index_uploads = 0
end type realized_t

type, public :: canvas_realizer_t
    !! What one backend realized per store slot, with upload counters. A layer
    !! is uploaded when its serial or data version differs from the realized one
    !! or when the backend recreated its resource (`force`).
    type(realized_t), allocatable :: slots(:)
    integer :: vertex_uploads = 0
    integer :: attribute_uploads = 0
    integer :: index_uploads = 0
contains
    procedure :: sync => realizer_sync
    procedure :: vertices => realizer_vertices
    procedure :: layer => realizer_layer
    procedure :: realize_frame => realizer_realize_frame
    procedure :: uploads => realizer_uploads
end type canvas_realizer_t

public :: ui_rgba, canvas_to_world, canvas_to_local, canvas_zoom_at

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

! --- store -------------------------------------------------------------------

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
    !! Find or create the layer for `key`; a kind change creates a fresh layer
    !! (new serial). A key submitted twice in one frame is reported and yields 0.
    class(canvas_store_t), intent(inout) :: self
    character(*), intent(in) :: key
    integer, intent(in) :: kind, frame_no
    type(canvas_layer_t), allocatable :: grown(:)
    integer :: i, n

    slot = self%lookup(key)
    if (slot > 0) then
        if (self%layers(slot)%last_frame == frame_no) then
            call report_error("fortui_canvas", "acquire", &
                "duplicate canvas layer key '" // key // "' in one frame; skipped")
            slot = 0
            return
        end if
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
    to%version = from%version
    to%index_version = from%index_version
    to%vertex_slot = from%vertex_slot
    to%vertex_serial = from%vertex_serial
    to%vertex_count = from%vertex_count
    to%index_count = from%index_count
    to%seen_count = from%seen_count
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

integer function store_submit_vertices(self, key, generation, xy, frame_no) result(slot)
    !! Shared vertex layer: positions xy(2,n), copied when `generation` changes.
    class(canvas_store_t), intent(inout) :: self
    character(*), intent(in) :: key
    integer, intent(in) :: generation, frame_no
    real, intent(in) :: xy(:, :)
    integer :: n

    slot = self%acquire(key, LAYER_VERTICES, frame_no)
    if (slot == 0) return
    associate(l => self%layers(slot))
        if (l%has_data .and. l%generation == generation) return
        n = size(xy, 2)
        if (size(xy, 1) < 2) then
            if (n > 0) call report_error("fortui_canvas", "canvas_vertices", &
                "positions need two rows (x, y); layer '" // key // "' is empty")
            n = 0
        end if
        if (allocated(l%xy)) deallocate(l%xy)
        allocate(l%xy(2, n))
        if (n > 0) l%xy = xy(1:2, 1:n)
        l%vertex_count = n
        l%generation = generation
        l%version = l%version + 1
        l%has_data = .true.
    end associate
end function store_submit_vertices

integer function store_submit_points(self, key, vertex_slot, generation, rgba, sizes, &
    size, frame_no) result(slot)
    !! Point layer drawing the vertices of `vertex_slot` with colours rgba(n) or
    !! rgba(1) and diameters sizes(n) or a uniform `size`. Colours and sizes are
    !! copied when `generation` or the vertex count changes.
    class(canvas_store_t), intent(inout) :: self
    character(*), intent(in) :: key
    integer, intent(in) :: vertex_slot, generation, frame_no
    integer(int32), intent(in) :: rgba(:)
    real, intent(in), optional :: sizes(:)
    real, intent(in), optional :: size
    integer :: n, nc
    real :: uniform

    slot = self%acquire(key, LAYER_POINTS, frame_no)
    if (slot == 0) return
    n = self%layers(vertex_slot)%vertex_count
    associate(l => self%layers(slot))
        if (l%has_data .and. l%generation == generation .and. &
            l%vertex_serial == self%layers(vertex_slot)%serial .and. &
            l%seen_count == n) return
        nc = n
        if (ubound(rgba, 1) /= 1 .and. ubound(rgba, 1) < n) then
            call report_error("fortui_canvas", "canvas_points", "layer '" // key // &
                "': fewer colours than vertices; extra vertices not drawn")
            nc = max(0, ubound(rgba, 1))
        end if
        if (present(sizes)) then
            if (ubound(sizes, 1) < nc) then
                call report_error("fortui_canvas", "canvas_points", "layer '" // &
                    key // "': fewer sizes than vertices; extra vertices not drawn")
                nc = max(0, ubound(sizes, 1))
            end if
        end if
        uniform = 4.0
        if (present(size)) uniform = size
        if (allocated(l%rgba)) deallocate(l%rgba)
        if (allocated(l%sizes)) deallocate(l%sizes)
        allocate(l%rgba(nc), l%sizes(nc))
        if (nc > 0) then
            if (ubound(rgba, 1) == 1) then
                l%rgba = rgba(1)
            else
                l%rgba = rgba(1:nc)
            end if
            if (present(sizes)) then
                l%sizes = sizes(1:nc)
            else
                l%sizes = uniform
            end if
        end if
        l%vertex_slot = vertex_slot
        l%vertex_serial = self%layers(vertex_slot)%serial
        l%vertex_count = nc
        l%seen_count = n
        l%generation = generation
        l%version = l%version + 1
        l%has_data = .true.
    end associate
end function store_submit_points

integer function store_submit_lines(self, key, vertex_slot, generation, rgba, &
    segment_generation, segments, frame_no) result(slot)
    !! Indexed line layer over the vertices of `vertex_slot`: per-vertex colours
    !! rgba(n) or rgba(1) (copied when `generation` or the vertex count changes)
    !! and 1-based vertex pairs segments(2,ns) (revalidated and copied when
    !! `segment_generation` or the vertex count changes). Segments referencing a
    !! missing vertex are dropped and reported.
    class(canvas_store_t), intent(inout) :: self
    character(*), intent(in) :: key
    integer, intent(in) :: vertex_slot, generation, segment_generation, frame_no
    integer(int32), intent(in) :: rgba(:)
    integer, intent(in) :: segments(:, :)
    integer :: n, ns, k, kept, dropped
    logical :: count_changed

    slot = self%acquire(key, LAYER_LINES, frame_no)
    if (slot == 0) return
    n = self%layers(vertex_slot)%vertex_count
    associate(l => self%layers(slot))
        count_changed = .not. l%has_data .or. l%seen_count /= n .or. &
            l%vertex_serial /= self%layers(vertex_slot)%serial
        if (count_changed .or. l%generation /= generation) then
            if (allocated(l%rgba)) deallocate(l%rgba)
            if (ubound(rgba, 1) == 1) then
                allocate(l%rgba(n))
                l%rgba = rgba(1)
            else if (ubound(rgba, 1) >= n) then
                allocate(l%rgba(n))
                if (n > 0) l%rgba = rgba(1:n)
            else
                if (n > 0) call report_error("fortui_canvas", "canvas_lines", &
                    "layer '" // key // "': fewer colours than vertices; not drawn")
                allocate(l%rgba(0))
            end if
            l%generation = generation
            l%version = l%version + 1
        end if
        if (count_changed .or. l%index_generation /= segment_generation) then
            ns = size(segments, 2)
            if (size(segments, 1) < 2) ns = 0
            if (size(l%rgba) < n) ns = 0
            if (allocated(l%indices)) deallocate(l%indices)
            allocate(l%indices(2 * ns))
            kept = 0
            do k = 1, ns
                if (min(segments(1, k), segments(2, k)) < 1 .or. &
                    max(segments(1, k), segments(2, k)) > n) cycle
                l%indices(2 * kept + 1) = int(segments(1, k) - 1, int32)
                l%indices(2 * kept + 2) = int(segments(2, k) - 1, int32)
                kept = kept + 1
            end do
            dropped = ns - kept
            if (dropped > 0) call report_error("fortui_canvas", "canvas_lines", &
                "layer '" // key // "': segments outside the vertex range dropped")
            l%index_count = 2 * kept
            l%index_generation = segment_generation
            l%index_version = l%index_version + 1
        end if
        l%vertex_slot = vertex_slot
        l%vertex_serial = self%layers(vertex_slot)%serial
        l%vertex_count = n
        l%seen_count = n
        l%has_data = .true.
    end associate
end function store_submit_lines

function store_ref(self, slot) result(ref)
    !! Frame descriptor of drawable layer `slot`.
    class(canvas_store_t), intent(in) :: self
    integer, intent(in) :: slot
    type(ui_layer_ref_t) :: ref

    associate(l => self%layers(slot))
        ref%key = l%key
        ref%kind = l%kind
        ref%slot = slot
        ref%serial = l%serial
        ref%version = l%version
        ref%index_version = l%index_version
        ref%vertex_slot = l%vertex_slot
        ref%vertex_serial = l%vertex_serial
        ref%vertex_count = l%vertex_count
        ref%index_count = l%index_count
        if (l%vertex_slot > 0) ref%vertex_version = self%layers(l%vertex_slot)%version
    end associate
end function store_ref

integer function store_active_layers(self) result(n)
    class(canvas_store_t), intent(in) :: self
    n = 0
    if (allocated(self%layers)) n = count(self%layers%in_use)
end function store_active_layers

! --- realization tracker -----------------------------------------------------

subroutine realizer_sync(self, store)
    !! Forget realizations of slots that were released or reassigned.
    class(canvas_realizer_t), intent(inout) :: self
    type(canvas_store_t), intent(in) :: store
    type(realized_t), allocatable :: grown(:)
    integer :: i, n

    n = 0
    if (allocated(store%layers)) n = size(store%layers)
    if (.not. allocated(self%slots)) allocate(self%slots(max(n, 8)))
    if (size(self%slots) < n) then
        allocate(grown(n))
        grown(1:size(self%slots)) = self%slots
        call move_alloc(grown, self%slots)
    end if
    do i = 1, size(self%slots)
        if (self%slots(i)%serial == 0) cycle
        if (i > n) then
            self%slots(i) = realized_t()
        else if (.not. store%layers(i)%in_use .or. &
            store%layers(i)%serial /= self%slots(i)%serial) then
            self%slots(i) = realized_t()
        end if
    end do
end subroutine realizer_sync

logical function realizer_vertices(self, store, slot, force) result(upload)
    !! Whether vertex layer `slot` must be uploaded; records the realization.
    class(canvas_realizer_t), intent(inout) :: self
    type(canvas_store_t), intent(in) :: store
    integer, intent(in) :: slot
    logical, intent(in) :: force

    associate(r => self%slots(slot), l => store%layers(slot))
        upload = force .or. r%serial /= l%serial .or. r%version /= l%version
        if (upload) then
            r%serial = l%serial
            r%version = l%version
            r%uploads = r%uploads + 1
            self%vertex_uploads = self%vertex_uploads + 1
        end if
    end associate
end function realizer_vertices

subroutine realizer_layer(self, ref, force, attributes, indices)
    !! Which buffers of drawable layer `ref` must be uploaded; records them.
    class(canvas_realizer_t), intent(inout) :: self
    type(ui_layer_ref_t), intent(in) :: ref
    logical, intent(in) :: force
    logical, intent(out) :: attributes, indices

    associate(r => self%slots(ref%slot))
        if (r%serial /= ref%serial) r = realized_t(serial=ref%serial)
        attributes = force .or. r%version /= ref%version
        indices = ref%kind == LAYER_LINES .and. &
            (force .or. r%index_version /= ref%index_version)
        if (attributes) then
            r%version = ref%version
            r%uploads = r%uploads + 1
            self%attribute_uploads = self%attribute_uploads + 1
        end if
        if (indices) then
            r%index_version = ref%index_version
            r%index_uploads = r%index_uploads + 1
            self%index_uploads = self%index_uploads + 1
        end if
    end associate
end subroutine realizer_layer

subroutine realizer_realize_frame(self, store, frame)
    !! Resource-free realization of every layer a frame references (headless
    !! and terminal backends): the same decisions a GPU backend makes.
    class(canvas_realizer_t), intent(inout) :: self
    type(canvas_store_t), intent(in) :: store
    type(ui_frame_t), intent(in) :: frame
    integer :: i
    logical :: attributes, indices, upload

    call self%sync(store)
    do i = 1, frame%layer_count
        associate(ref => frame%layers(i))
            if (ref%vertex_slot > 0) upload = self%vertices(store, ref%vertex_slot, &
                .false.)
            call self%layer(ref, .false., attributes, indices)
        end associate
    end do
end subroutine realizer_realize_frame

subroutine realizer_uploads(self, slot, uploads, index_uploads)
    !! Upload counts of the layer currently realized in `slot` (-1 if none).
    class(canvas_realizer_t), intent(in) :: self
    integer, intent(in) :: slot
    integer, intent(out) :: uploads, index_uploads

    uploads = -1
    index_uploads = -1
    if (.not. allocated(self%slots) .or. slot < 1) return
    if (slot > size(self%slots)) return
    if (self%slots(slot)%serial == 0) return
    uploads = self%slots(slot)%uploads
    index_uploads = self%slots(slot)%index_uploads
end subroutine realizer_uploads

end module fortui_canvas
