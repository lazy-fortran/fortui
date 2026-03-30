module fortui_input
! Per-frame input state for immediate-mode widgets
! Populated by backend during begin_frame, read by widgets during their calls
! Also manages keyboard focus for Tab navigation
implicit none
private

public :: input_state_t, frame_input
public :: input_reset, input_set_mouse, input_set_key
public :: input_get_mouse_x, input_get_mouse_y
public :: input_get_mouse_left, input_get_mouse_right
public :: input_get_scroll_y, input_get_key, input_get_key_char

! Focus management
public :: input_focus_begin_frame, input_register_focusable
public :: input_has_focus, input_set_focus

! Backend-agnostic key constants
integer, parameter, public :: KEY_TAB = 9
integer, parameter, public :: KEY_ENTER = 13
integer, parameter, public :: KEY_SPACE = 32
integer, parameter, public :: KEY_ARROW_UP = 65517
integer, parameter, public :: KEY_ARROW_DOWN = 65516
integer, parameter, public :: KEY_ARROW_LEFT = 65515
integer, parameter, public :: KEY_ARROW_RIGHT = 65514

type :: input_state_t
    integer :: mouse_x = -1
    integer :: mouse_y = -1
    logical :: mouse_left_click = .false.
    logical :: mouse_left_down = .false.
    logical :: mouse_right_click = .false.
    integer :: scroll_y = 0
    integer :: key = 0
    integer :: key_char = 0
    logical :: has_key_event = .false.
    logical :: has_mouse_event = .false.
end type input_state_t

type(input_state_t), save :: frame_input

! Focus tracking state
integer, parameter :: MAX_FOCUSABLE = 256
character(len=256), save :: focus_id = ""
character(len=256), save :: focus_ids(MAX_FOCUSABLE)
integer, save :: focus_count = 0

contains

subroutine input_reset()
    frame_input%mouse_left_click = .false.
    frame_input%mouse_right_click = .false.
    frame_input%scroll_y = 0
    frame_input%key = 0
    frame_input%key_char = 0
    frame_input%has_key_event = .false.
    frame_input%has_mouse_event = .false.
end subroutine input_reset

subroutine input_set_mouse(x, y, button_id)
    integer, intent(in) :: x, y, button_id

    frame_input%mouse_x = x
    frame_input%mouse_y = y
    frame_input%has_mouse_event = .true.

    select case (button_id)
    case (1)
        frame_input%mouse_left_click = .true.
        frame_input%mouse_left_down = .true.
    case (2)
        frame_input%mouse_right_click = .true.
    case (0)
        frame_input%mouse_left_down = .false.
    case (4)
        frame_input%scroll_y = 1
    case (5)
        frame_input%scroll_y = -1
    end select
end subroutine input_set_mouse

subroutine input_set_key(key_code, char_code)
    integer, intent(in) :: key_code, char_code

    frame_input%key = key_code
    frame_input%key_char = char_code
    frame_input%has_key_event = .true.
end subroutine input_set_key

integer function input_get_mouse_x()
    input_get_mouse_x = frame_input%mouse_x
end function input_get_mouse_x

integer function input_get_mouse_y()
    input_get_mouse_y = frame_input%mouse_y
end function input_get_mouse_y

logical function input_get_mouse_left()
    input_get_mouse_left = frame_input%mouse_left_click
end function input_get_mouse_left

logical function input_get_mouse_right()
    input_get_mouse_right = frame_input%mouse_right_click
end function input_get_mouse_right

integer function input_get_scroll_y()
    input_get_scroll_y = frame_input%scroll_y
end function input_get_scroll_y

integer function input_get_key()
    input_get_key = frame_input%key
end function input_get_key

integer function input_get_key_char()
    input_get_key_char = frame_input%key_char
end function input_get_key_char

! Focus management: process Tab navigation using previous frame's
! widget list, then clear list for this frame to rebuild.
subroutine input_focus_begin_frame()
    integer :: i, cur_idx, next_idx

    if (frame_input%key == KEY_TAB .and. focus_count > 0) then
        cur_idx = 0
        do i = 1, focus_count
            if (trim(focus_ids(i)) == trim(focus_id)) then
                cur_idx = i
                exit
            end if
        end do

        if (cur_idx == 0) then
            focus_id = focus_ids(1)
        else
            next_idx = mod(cur_idx, focus_count) + 1
            focus_id = focus_ids(next_idx)
        end if
    end if

    focus_count = 0
end subroutine input_focus_begin_frame

subroutine input_register_focusable(id)
    character(*), intent(in) :: id

    if (focus_count < MAX_FOCUSABLE) then
        focus_count = focus_count + 1
        focus_ids(focus_count) = id
    end if
end subroutine input_register_focusable

logical function input_has_focus(id)
    character(*), intent(in) :: id

    input_has_focus = (len_trim(focus_id) > 0 .and. &
        trim(focus_id) == trim(id))
end function input_has_focus

subroutine input_set_focus(id)
    character(*), intent(in) :: id

    focus_id = id
end subroutine input_set_focus

end module fortui_input
