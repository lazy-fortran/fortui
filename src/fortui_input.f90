module fortui_input
! Per-frame input state for immediate-mode widgets
! Populated by backend during begin_frame, read by widgets during their calls
implicit none
private

public :: input_state_t, frame_input
public :: input_reset, input_set_mouse, input_set_key
public :: input_get_mouse_x, input_get_mouse_y
public :: input_get_mouse_left, input_get_mouse_right
public :: input_get_scroll_y, input_get_key, input_get_key_char

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

end module fortui_input
