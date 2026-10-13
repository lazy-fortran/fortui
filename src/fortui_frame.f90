module fortui_frame
!! Backend-neutral semantic frame produced by the FortUI composition DSL.
use iso_fortran_env, only: int32
use fortui_text, only: text_line_t, TEXT_DEFAULT_SIZE
implicit none
private

integer, parameter, public :: UI_NONE = 0
integer, parameter, public :: UI_TEXT = 1
integer, parameter, public :: UI_BUTTON = 2
integer, parameter, public :: UI_SLIDER = 3
integer, parameter, public :: UI_CHECKBOX = 4
integer, parameter, public :: UI_VIEWPORT = 5
integer, parameter, public :: UI_CANVAS = 6
integer, parameter, public :: UI_SCROLL_TEXT = 7
integer, parameter, public :: UI_TEXT_INPUT = 8

integer, parameter, public :: LAYER_POINTS = 1
integer, parameter, public :: LAYER_LINES = 2

! Presentation metrics shared by composition (hit regions) and renderers.
real, parameter, public :: SCROLL_PADDING = 8.0
real, parameter, public :: SCROLLBAR_WIDTH = 10.0
real, parameter, public :: INPUT_PADDING = 6.0

type, public :: view
    real :: scale_x = 1.0
    real :: scale_y = 1.0
    real :: off_x = 0.0
    real :: off_y = 0.0
end type view

type, public :: canvas_view_t
    !! Canvas transform: local = world * zoom + pan (logical units from canvas origin).
    real :: zoom = 1.0
    real :: pan_x = 0.0
    real :: pan_y = 0.0
end type canvas_view_t

type, public :: ui_layer_ref_t
    !! Descriptor of a retained canvas geometry layer referenced by one frame.
    character(len=128) :: key = ""
    integer :: kind = 0
    integer :: slot = 0
    integer :: generation = 0
    integer :: index_generation = 0
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
    type(view) :: camera
    real :: text_size = TEXT_DEFAULT_SIZE
    character(len=:), allocatable :: body
    type(text_line_t), allocatable :: lines(:)
    integer :: line_count = 0
    real :: scroll = 0.0
    real :: content_height = 0.0
    integer :: caret = 0
    logical :: markdown = .false.
    integer(int32) :: fill = 0
    type(canvas_view_t) :: canvas_view
    integer :: layer_first = 0
    integer :: layer_count = 0
    integer :: label_first = 0
    integer :: label_count = 0
end type ui_node_t

type, public :: ui_frame_t
    type(ui_node_t), allocatable :: nodes(:)
    integer :: count = 0
    type(ui_layer_ref_t), allocatable :: layers(:)
    integer :: layer_count = 0
    type(ui_label_t), allocatable :: labels(:)
    integer :: label_count = 0
contains
    procedure :: reset => frame_reset
    procedure :: append => frame_append
    procedure :: find => frame_find
    procedure :: append_layer => frame_append_layer
    procedure :: append_label => frame_append_label
end type ui_frame_t

contains

subroutine frame_reset(self)
    class(ui_frame_t), intent(inout) :: self

    if (.not. allocated(self%nodes)) allocate(self%nodes(64))
    self%count = 0
    self%layer_count = 0
    self%label_count = 0
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
    class(ui_frame_t), intent(inout) :: self
    type(ui_node_t), intent(in) :: node

    type(ui_node_t), allocatable :: grown(:)
    integer :: new_capacity

    if (.not. allocated(self%nodes)) allocate(self%nodes(64))
    if (self%count >= size(self%nodes)) then
        new_capacity = max(64, 2 * size(self%nodes))
        allocate(grown(new_capacity))
        if (self%count > 0) grown(1:self%count) = self%nodes(1:self%count)
        call move_alloc(grown, self%nodes)
    end if

    self%count = self%count + 1
    self%nodes(self%count) = node
    index = self%count
end function frame_append

integer function frame_find(self, id) result(index)
    class(ui_frame_t), intent(in) :: self
    character(*), intent(in) :: id
    integer :: i

    index = 0
    do i = self%count, 1, -1
        if (trim(self%nodes(i)%id) == trim(id)) then
            index = i
            return
        end if
    end do
end function frame_find

end module fortui_frame
