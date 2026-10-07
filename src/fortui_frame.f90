module fortui_frame
!! Backend-neutral semantic frame produced by the FortUI composition DSL.
implicit none
private

integer, parameter, public :: UI_NONE = 0
integer, parameter, public :: UI_TEXT = 1
integer, parameter, public :: UI_BUTTON = 2
integer, parameter, public :: UI_SLIDER = 3
integer, parameter, public :: UI_CHECKBOX = 4
integer, parameter, public :: UI_VIEWPORT = 5

type, public :: view
    real :: scale_x = 1.0
    real :: scale_y = 1.0
    real :: off_x = 0.0
    real :: off_y = 0.0
end type view

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
end type ui_node_t

type, public :: ui_frame_t
    type(ui_node_t), allocatable :: nodes(:)
    integer :: count = 0
contains
    procedure :: reset => frame_reset
    procedure :: append => frame_append
    procedure :: find => frame_find
end type ui_frame_t

contains

subroutine frame_reset(self)
    class(ui_frame_t), intent(inout) :: self

    if (.not. allocated(self%nodes)) allocate(self%nodes(64))
    self%count = 0
end subroutine frame_reset

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
