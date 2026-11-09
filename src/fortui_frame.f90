module fortui_frame
!! Backend-neutral semantic frame produced by the FortUI composition DSL.
use iso_fortran_env, only: int32, int64
use fortui_layout, only: layout_box_t
use fortui_text, only: text_line_t, TEXT_DEFAULT_SIZE, TEXT_STYLE_REGULAR, &
    TEXT_STYLE_BOLD, TEXT_STYLE_MONO
implicit none
private

integer, parameter, public :: UI_NONE = 0
integer, parameter, public :: UI_TEXT = 1
integer, parameter, public :: UI_BUTTON = 2
integer, parameter, public :: UI_SLIDER = 3
integer, parameter, public :: UI_CHECKBOX = 4
integer, parameter, public :: UI_TAB = 5
integer, parameter, public :: UI_CANVAS = 6
integer, parameter, public :: UI_SCROLL_TEXT = 7
integer, parameter, public :: UI_TEXT_INPUT = 8

integer, parameter, public :: LAYER_POINTS = 1
integer, parameter, public :: LAYER_LINES = 2
integer, parameter, public :: LAYER_VERTICES = 3

! Presentation style tokens (role, default size and weight; backends choose colour).
integer, parameter, public :: UI_BODY = 1
integer, parameter, public :: UI_CAPTION = 2
integer, parameter, public :: UI_HEADING = 3
integer, parameter, public :: UI_TITLE = 4
! Monospaced text for code, logs and diffs; spaces are kept.
integer, parameter, public :: UI_CODE = 5

! Semantic tones of text (backends choose the colours).
integer, parameter, public :: UI_TONE_NORMAL = 0
integer, parameter, public :: UI_TONE_POSITIVE = 1
integer, parameter, public :: UI_TONE_NEGATIVE = 2
integer, parameter, public :: UI_TONE_MUTED = 3
integer, parameter, public :: UI_TONE_ACCENT = 4
! Roles of code tokens and diff lines (backends choose the colours).
integer, parameter, public :: UI_TONE_KEYWORD = 5, UI_TONE_STRING = 6, UI_TONE_COMMENT = 7, &
    UI_TONE_NUMBER = 8, UI_TONE_TYPE = 9, UI_TONE_PREPROC = 10, UI_TONE_ADDED = 11, &
    UI_TONE_REMOVED = 12, UI_TONE_HUNK = 13, UI_TONE_LINK = 14, UI_TONE_STRONG = 15, &
    UI_TONE_EMPHASIS = 16

integer, parameter, public :: WIDTH_NATURAL = 0, WIDTH_FIXED = 1, WIDTH_FILL = 2

! Width that fills the remaining space of the current container.
real, parameter, public :: UI_FILL = -1.0

! Presentation metrics shared by composition (hit regions) and renderers.
real, parameter, public :: SCROLL_PADDING = 8.0
real, parameter, public :: SCROLLBAR_WIDTH = 10.0
real, parameter, public :: INPUT_PADDING = 6.0
real, parameter, public :: CONTROL_PADDING = 12.0

type, public :: canvas_view_t
    !! Canvas transform: local = world * zoom + pan (logical units from canvas origin).
    real :: zoom = 1.0
    real :: pan_x = 0.0
    real :: pan_y = 0.0
end type canvas_view_t

type, public :: ui_layer_ref_t
    !! Descriptor of a retained drawable canvas layer referenced by one frame.
    !! `version`/`index_version` change whenever the store copied new data, so a
    !! backend compares them with what it realized; `vertex_*` names the shared
    !! vertex layer holding the positions.
    character(len=128) :: key = ""
    integer :: kind = 0
    integer :: slot = 0
    integer :: serial = 0
    integer :: version = 0
    integer :: index_version = 0
    integer :: vertex_slot = 0
    integer :: vertex_serial = 0
    integer :: vertex_version = 0
    integer :: vertex_count = 0
    integer :: index_count = 0
end type ui_layer_ref_t

type, public :: ui_label_t
    !! Canvas text label anchored at world coordinates, drawn at a fixed logical size.
    real :: x = 0.0
    real :: y = 0.0
    real :: size = 14.0
    integer(int32) :: rgba = -1
    character(len=:), allocatable :: text
end type ui_label_t

type, public :: ui_node_t
    integer :: kind = UI_NONE
    character(len=96) :: id = ""
    character(len=512) :: text = ""
    real :: x = 0.0
    real :: y = 0.0
    real :: width = 0.0
    real :: height = 0.0
    logical :: focusable = .false.
    logical :: disabled = .false.
    logical :: hovered = .false.
    logical :: focused = .false.
    logical :: active = .false.
    real :: value = 0.0
    real :: min_value = 0.0
    real :: max_value = 1.0
    logical :: checked = .false.
    integer :: style = UI_BODY
    integer :: tone = UI_TONE_NORMAL
    ! Container the node was composed in (index into boxes; 0: page root).
    integer :: box = 0
    ! How the width was asked for: WIDTH_NATURAL, WIDTH_FIXED or WIDTH_FILL.
    integer :: width_mode = 0
    ! Runs of rich text: byte offset where each run ends, and its tone.
    integer, allocatable :: run_end(:), run_tone(:)
    real :: text_size = TEXT_DEFAULT_SIZE
    logical :: ellipsis = .false.
    character(len=:), allocatable :: body
    type(text_line_t), allocatable :: lines(:)
    integer :: line_count = 0
    real :: scroll = 0.0
    real :: content_height = 0.0
    integer :: caret = 0
    logical :: markdown = .false.
    integer(int32) :: fill = 0
    type(canvas_view_t) :: canvas_view = canvas_view_t()
    integer :: layer_first = 0
    integer :: layer_count = 0
    integer :: label_first = 0
    integer :: label_count = 0
end type ui_node_t

type, public :: ui_frame_t
    type(ui_node_t), allocatable :: nodes(:)
    integer :: count = 0
    ! Containers of the composition, for hosts that lay out themselves.
    type(layout_box_t), allocatable :: boxes(:)
    integer :: box_count = 0
    type(ui_layer_ref_t), allocatable :: layers(:)
    integer :: layer_count = 0
    type(ui_label_t), allocatable :: labels(:)
    integer :: label_count = 0
    ! Open-addressing index of node ids (0 = empty bucket).
    integer, allocatable :: buckets(:)
contains
    procedure :: reset => frame_reset
    procedure :: append => frame_append
    procedure :: find => frame_find
    procedure :: append_layer => frame_append_layer
    procedure :: append_label => frame_append_label
end type ui_frame_t

public :: style_size, style_weight

contains

pure real function style_size(style) result(size)
    !! Default logical text size of a style token.
    integer, intent(in) :: style
    select case (style)
    case (UI_CAPTION); size = 15.0
    case (UI_HEADING); size = 17.0
    case (UI_TITLE); size = 26.0
    case (UI_CODE); size = 15.0
    case default; size = TEXT_DEFAULT_SIZE
    end select
end function style_size

pure integer function style_weight(style) result(weight)
    !! Font (TEXT_STYLE_REGULAR, TEXT_STYLE_BOLD or TEXT_STYLE_MONO) of a style token.
    integer, intent(in) :: style
    weight = TEXT_STYLE_REGULAR
    if (style == UI_HEADING .or. style == UI_TITLE) weight = TEXT_STYLE_BOLD
    if (style == UI_CODE) weight = TEXT_STYLE_MONO
end function style_weight

subroutine frame_reset(self)
    class(ui_frame_t), intent(inout) :: self

    if (.not. allocated(self%nodes)) allocate(self%nodes(64))
    if (.not. allocated(self%buckets)) allocate(self%buckets(256))
    self%count = 0
    self%box_count = 0
    self%layer_count = 0
    self%label_count = 0
    self%buckets = 0
end subroutine frame_reset

integer function frame_append_layer(self, layer) result(index)
    class(ui_frame_t), intent(inout) :: self
    type(ui_layer_ref_t), intent(in) :: layer
    type(ui_layer_ref_t), allocatable :: grown(:)

    if (.not. allocated(self%layers)) allocate(self%layers(8))
    if (self%layer_count >= size(self%layers)) then
        allocate(grown(2 * size(self%layers)))
        grown(1:self%layer_count) = self%layers(1:self%layer_count)
        call move_alloc(grown, self%layers)
    end if
    self%layer_count = self%layer_count + 1
    self%layers(self%layer_count) = layer
    index = self%layer_count
end function frame_append_layer

integer function frame_append_label(self, label) result(index)
    class(ui_frame_t), intent(inout) :: self
    type(ui_label_t), intent(in) :: label
    type(ui_label_t), allocatable :: grown(:)

    if (.not. allocated(self%labels)) allocate(self%labels(64))
    if (self%label_count >= size(self%labels)) then
        allocate(grown(2 * size(self%labels)))
        grown(1:self%label_count) = self%labels(1:self%label_count)
        call move_alloc(grown, self%labels)
    end if
    self%label_count = self%label_count + 1
    self%labels(self%label_count) = label
    index = self%label_count
end function frame_append_label

integer function frame_append(self, node) result(index)
    !! Append a node; a non-empty id is indexed for `find` (callers reject
    !! duplicate ids before appending).
    class(ui_frame_t), intent(inout) :: self
    type(ui_node_t), intent(in) :: node

    type(ui_node_t), allocatable :: grown(:)
    integer :: new_capacity

    if (.not. allocated(self%nodes)) allocate(self%nodes(64))
    if (.not. allocated(self%buckets)) then
        allocate(self%buckets(256))
        self%buckets = 0
    end if
    if (self%count >= size(self%nodes)) then
        new_capacity = max(64, 2 * size(self%nodes))
        allocate(grown(new_capacity))
        if (self%count > 0) grown(1:self%count) = self%nodes(1:self%count)
        call move_alloc(grown, self%nodes)
    end if

    self%count = self%count + 1
    self%nodes(self%count) = node
    index = self%count
    if (len_trim(node%id) == 0) return
    if (4 * self%count > 3 * size(self%buckets)) call rehash(self, &
        4 * size(self%buckets))
    call insert(self, index)
end function frame_append

integer function frame_find(self, id) result(index)
    !! Index of the node with identity `id` (0 when absent).
    class(ui_frame_t), intent(in) :: self
    character(*), intent(in) :: id
    integer :: b, mask

    index = 0
    if (.not. allocated(self%buckets) .or. len_trim(id) == 0) return
    mask = size(self%buckets) - 1
    b = id_hash(id, mask)
    do
        if (self%buckets(b + 1) == 0) return
        if (self%buckets(b + 1) <= self%count) then
            if (self%nodes(self%buckets(b + 1))%id == id) then
                index = self%buckets(b + 1)
                return
            end if
        end if
        b = iand(b + 1, mask)
    end do
end function frame_find

subroutine insert(self, index)
    type(ui_frame_t), intent(inout) :: self
    integer, intent(in) :: index
    integer :: b, mask

    mask = size(self%buckets) - 1
    b = id_hash(self%nodes(index)%id, mask)
    do while (self%buckets(b + 1) /= 0)
        b = iand(b + 1, mask)
    end do
    self%buckets(b + 1) = index
end subroutine insert

subroutine rehash(self, buckets)
    type(ui_frame_t), intent(inout) :: self
    integer, intent(in) :: buckets
    integer :: i

    deallocate(self%buckets)
    allocate(self%buckets(buckets))
    self%buckets = 0
    do i = 1, self%count
        if (len_trim(self%nodes(i)%id) > 0) call insert(self, i)
    end do
end subroutine rehash

pure integer function id_hash(id, mask) result(b)
    !! FNV-1a over the trimmed bytes, reduced to a bucket in 0..mask.
    character(*), intent(in) :: id
    integer, intent(in) :: mask
    integer(int64), parameter :: LOW32 = 4294967295_int64
    integer(int64) :: h
    integer :: i

    h = 2166136261_int64
    do i = 1, len_trim(id)
        h = iand(ieor(h, int(iachar(id(i:i)), int64)) * 16777619_int64, LOW32)
    end do
    b = int(iand(h, int(mask, int64)))
end function id_hash

end module fortui_frame
