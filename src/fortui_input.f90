module fortui_input
!! Backend-neutral input snapshot and routing against the previous semantic frame.
use fortui_frame, only: ui_frame_t
implicit none
private

integer, parameter, public :: KEY_NONE = 0
integer, parameter, public :: KEY_TAB = 9
integer, parameter, public :: KEY_ENTER = 13
integer, parameter, public :: KEY_SPACE = 32
integer, parameter, public :: KEY_ESCAPE = 27
integer, parameter, public :: KEY_ARROW_UP = 65517
integer, parameter, public :: KEY_ARROW_DOWN = 65516
integer, parameter, public :: KEY_ARROW_LEFT = 65515
integer, parameter, public :: KEY_ARROW_RIGHT = 65514

type, public :: input_state_t
    real :: pointer_x = -1.0
    real :: pointer_y = -1.0
    real :: pointer_dx = 0.0
    real :: pointer_dy = 0.0
    logical :: pointer_down = .false.
    logical :: pointer_pressed = .false.
    logical :: pointer_released = .false.
    integer :: scroll_y = 0
    integer :: key = KEY_NONE
    integer :: key_char = 0
    character(len=96) :: focus_id = ""
    character(len=96) :: active_id = ""
    character(len=96) :: activated_id = ""
    character(len=96) :: scroll_id = ""
end type input_state_t

public :: input_begin_frame, input_update_pointer, input_scroll, input_set_key
public :: input_route, input_activated, input_focused, input_active
public :: input_hovered, input_scroll_for, input_key_for

contains

subroutine input_begin_frame(input)
    type(input_state_t), intent(inout) :: input

    input%pointer_dx = 0.0
    input%pointer_dy = 0.0
    input%pointer_pressed = .false.
    input%pointer_released = .false.
    input%scroll_y = 0
    input%key = KEY_NONE
    input%key_char = 0
    input%activated_id = ""
    input%scroll_id = ""
end subroutine input_begin_frame

subroutine input_update_pointer(input, x, y, down, pressed)
    type(input_state_t), intent(inout) :: input
    real, intent(in) :: x, y
    logical, intent(in) :: down
    logical, intent(in), optional :: pressed

    logical :: was_down

    was_down = input%pointer_down
    if (input%pointer_x >= 0.0) then
        input%pointer_dx = input%pointer_dx + x - input%pointer_x
        input%pointer_dy = input%pointer_dy + y - input%pointer_y
    end if

    input%pointer_x = x
    input%pointer_y = y
    input%pointer_down = down
    if (present(pressed)) input%pointer_pressed = input%pointer_pressed .or. pressed
    if (.not. was_down .and. down) input%pointer_pressed = .true.
    if (was_down .and. .not. down) input%pointer_released = .true.
end subroutine input_update_pointer

subroutine input_scroll(input, amount)
    type(input_state_t), intent(inout) :: input
    integer, intent(in) :: amount
    input%scroll_y = input%scroll_y + amount
end subroutine input_scroll

subroutine input_set_key(input, key, key_char)
    type(input_state_t), intent(inout) :: input
    integer, intent(in) :: key
    integer, intent(in), optional :: key_char

    input%key = key
    if (present(key_char)) input%key_char = key_char
end subroutine input_set_key

subroutine input_route(input, previous)
    type(input_state_t), intent(inout) :: input
    type(ui_frame_t), intent(in) :: previous

    integer :: hit, i, focused_index, first_focus, next_focus

    if (input%key == KEY_TAB) then
        first_focus = 0
        focused_index = 0
        do i = 1, previous%count
            if (.not. previous%nodes(i)%focusable .or. previous%nodes(i)%disabled) cycle
            if (first_focus == 0) first_focus = i
            if (trim(previous%nodes(i)%id) == trim(input%focus_id)) focused_index = i
        end do

        next_focus = 0
        if (focused_index > 0) then
            do i = focused_index + 1, previous%count
                if (previous%nodes(i)%focusable .and. .not. previous%nodes(i)%disabled) then
                    next_focus = i
                    exit
                end if
            end do
        end if
        if (next_focus == 0) next_focus = first_focus
        if (next_focus > 0) input%focus_id = previous%nodes(next_focus)%id
    end if

    if (input%pointer_pressed) then
        hit = hit_test(previous, input%pointer_x, input%pointer_y, .true.)
        if (hit > 0) then
            input%active_id = previous%nodes(hit)%id
            if (previous%nodes(hit)%focusable) input%focus_id = previous%nodes(hit)%id
        else
            input%active_id = ""
        end if
    end if

    if (input%pointer_released) then
        hit = hit_test(previous, input%pointer_x, input%pointer_y, .true.)
        if (hit > 0) then
            if (trim(previous%nodes(hit)%id) == trim(input%active_id)) then
                input%activated_id = previous%nodes(hit)%id
            end if
        end if
        input%active_id = ""
    end if

    if ((input%key == KEY_ENTER .or. input%key == KEY_SPACE) .and. &
        len_trim(input%focus_id) > 0) then
        input%activated_id = input%focus_id
    end if

    if (input%scroll_y /= 0) then
        hit = hit_test(previous, input%pointer_x, input%pointer_y, .false.)
        if (hit > 0) input%scroll_id = previous%nodes(hit)%id
    end if
end subroutine input_route

integer function hit_test(frame, x, y, interactive_only) result(index)
    type(ui_frame_t), intent(in) :: frame
    real, intent(in) :: x, y
    logical, intent(in) :: interactive_only
    integer :: i

    index = 0
    do i = frame%count, 1, -1
        if (interactive_only .and. .not. frame%nodes(i)%focusable) cycle
        if (frame%nodes(i)%disabled) cycle
        if (x >= frame%nodes(i)%x .and. x < frame%nodes(i)%x + frame%nodes(i)%width .and. &
            y >= frame%nodes(i)%y .and. y < frame%nodes(i)%y + frame%nodes(i)%height) then
            index = i
            return
        end if
    end do
end function hit_test

logical function input_activated(input, id)
    type(input_state_t), intent(in) :: input
    character(*), intent(in) :: id
    input_activated = len_trim(input%activated_id) > 0 .and. &
        trim(input%activated_id) == trim(id)
end function input_activated

logical function input_focused(input, id)
    type(input_state_t), intent(in) :: input
    character(*), intent(in) :: id
    input_focused = len_trim(input%focus_id) > 0 .and. trim(input%focus_id) == trim(id)
end function input_focused

logical function input_active(input, id)
    type(input_state_t), intent(in) :: input
    character(*), intent(in) :: id
    input_active = len_trim(input%active_id) > 0 .and. trim(input%active_id) == trim(id)
end function input_active

logical function input_hovered(input, x, y, width, height)
    type(input_state_t), intent(in) :: input
    real, intent(in) :: x, y, width, height
    input_hovered = input%pointer_x >= x .and. input%pointer_x < x + width .and. &
        input%pointer_y >= y .and. input%pointer_y < y + height
end function input_hovered

integer function input_scroll_for(input, id)
    type(input_state_t), intent(in) :: input
    character(*), intent(in) :: id

    if (trim(input%scroll_id) == trim(id)) then
        input_scroll_for = input%scroll_y
    else
        input_scroll_for = 0
    end if
end function input_scroll_for

integer function input_key_for(input, id)
    type(input_state_t), intent(in) :: input
    character(*), intent(in) :: id

    if (trim(input%focus_id) == trim(id)) then
        input_key_for = input%key
    else
        input_key_for = KEY_NONE
    end if
end function input_key_for

end module fortui_input
