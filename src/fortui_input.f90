module fortui_input
!! Backend-neutral input snapshot and routing against the previous semantic frame.
use fortui_frame, only: ui_frame_t
implicit none
private

! Backend-neutral named keys. Printable characters arrive as typed text.
integer, parameter, public :: KEY_NONE = 0
integer, parameter, public :: KEY_ENTER = 1
integer, parameter, public :: KEY_ESCAPE = 2
integer, parameter, public :: KEY_TAB = 3
integer, parameter, public :: KEY_BACKSPACE = 4
integer, parameter, public :: KEY_DELETE = 5
integer, parameter, public :: KEY_HOME = 6
integer, parameter, public :: KEY_END = 7
integer, parameter, public :: KEY_ARROW_LEFT = 8
integer, parameter, public :: KEY_ARROW_RIGHT = 9
integer, parameter, public :: KEY_ARROW_UP = 10
integer, parameter, public :: KEY_ARROW_DOWN = 11
integer, parameter, public :: KEY_PAGE_UP = 12
integer, parameter, public :: KEY_PAGE_DOWN = 13
integer, parameter, public :: KEY_SPACE = 14
integer, parameter, public :: KEY_INSERT = 15
integer, parameter, public :: MAX_FRAME_KEYS = 32
integer, parameter, public :: MAX_FRAME_TEXT = 256
real, parameter, public :: DRAG_THRESHOLD = 4.0
real, parameter, public :: DOUBLE_CLICK_SECONDS = 0.4
real, parameter, public :: DOUBLE_CLICK_DISTANCE = 6.0

type, public :: input_state_t
    ! Host window in logical units and framebuffer pixels per unit; persistent.
    integer :: width = 1
    integer :: height = 1
    real :: scale = 1.0
    ! Positional uncertainty of the pointer in logical units (half a terminal
    ! cell for cell-based mice); hit tests may widen their tolerance by it.
    real :: pointer_slop = 0.0
    real :: pointer_x = -1.0
    real :: pointer_y = -1.0
    real :: pointer_dx = 0.0
    real :: pointer_dy = 0.0
    logical :: pointer_down = .false.
    logical :: pointer_pressed = .false.
    logical :: pointer_released = .false.
    integer :: scroll_y = 0
    real :: wheel = 0.0
    integer :: key_count = 0
    integer :: keys(MAX_FRAME_KEYS) = KEY_NONE
    ! Typed-text length when each key arrived, preserving key/text ordering.
    integer :: key_text_pos(MAX_FRAME_KEYS) = 0
    character(len=MAX_FRAME_TEXT) :: text = ""
    integer :: text_len = 0
    logical :: resized = .false.
    double precision :: time = 0.0d0
    real :: press_x = 0.0
    real :: press_y = 0.0
    logical :: drag_exceeded = .false.
    character(len=96) :: click_id = ""
    character(len=96) :: double_click_id = ""
    character(len=96) :: last_click_id = ""
    double precision :: last_click_time = -1.0d9
    real :: last_click_x = 0.0
    real :: last_click_y = 0.0
    character(len=96) :: focus_id = ""
    character(len=96) :: active_id = ""
    character(len=96) :: activated_id = ""
    character(len=96) :: scroll_id = ""
end type input_state_t

public :: input_begin_frame, input_update_pointer, input_scroll, input_set_key
public :: input_route, input_activated, input_focused, input_active
public :: input_hovered, input_key_arrived
public :: input_type_text, input_set_time, input_wheel_for, input_has_events

contains

subroutine input_begin_frame(input)
    type(input_state_t), intent(inout) :: input

    input%pointer_dx = 0.0
    input%pointer_dy = 0.0
    input%pointer_pressed = .false.
    input%pointer_released = .false.
    input%scroll_y = 0
    input%wheel = 0.0
    input%key_count = 0
    input%text_len = 0
    input%resized = .false.
    input%activated_id = ""
    input%scroll_id = ""
    input%click_id = ""
    input%double_click_id = ""
end subroutine input_begin_frame

logical function input_has_events(input)
    !! Whether this frame's input could change presentation (idle-wait decision).
    type(input_state_t), intent(in) :: input
    input_has_events = abs(input%pointer_dx) > 0.0 .or. &
        abs(input%pointer_dy) > 0.0 .or. input%pointer_pressed .or. &
        input%pointer_released .or. abs(input%wheel) > 0.0 .or. &
        input%key_count > 0 .or. input%text_len > 0 .or. input%resized
end function input_has_events

subroutine input_type_text(input, utf8)
    !! Append committed UTF-8 text typed during this frame.
    type(input_state_t), intent(inout) :: input
    character(*), intent(in) :: utf8
    integer :: n

    n = min(len(utf8), MAX_FRAME_TEXT - input%text_len)
    if (n <= 0) return
    input%text(input%text_len + 1:input%text_len + n) = utf8(1:n)
    input%text_len = input%text_len + n
end subroutine input_type_text

subroutine input_set_time(input, seconds)
    type(input_state_t), intent(inout) :: input
    double precision, intent(in) :: seconds
    input%time = seconds
end subroutine input_set_time

real function input_wheel_for(input, id)
    type(input_state_t), intent(in) :: input
    character(*), intent(in) :: id

    input_wheel_for = 0.0
    if (len_trim(input%scroll_id) > 0 .and. trim(input%scroll_id) == trim(id)) &
        input_wheel_for = input%wheel
end function input_wheel_for

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
    if (down .and. .not. was_down) then
        input%press_x = x
        input%press_y = y
        input%drag_exceeded = .false.
    else if (down) then
        if (abs(x - input%press_x) > DRAG_THRESHOLD .or. &
            abs(y - input%press_y) > DRAG_THRESHOLD) input%drag_exceeded = .true.
    end if
end subroutine input_update_pointer

subroutine input_scroll(input, amount, wheel)
    !! Record wheel motion: integer notches and, optionally, precise wheel steps.
    type(input_state_t), intent(inout) :: input
    integer, intent(in) :: amount
    real, intent(in), optional :: wheel
    input%scroll_y = input%scroll_y + amount
    if (present(wheel)) then
        input%wheel = input%wheel + wheel
    else
        input%wheel = input%wheel + real(amount)
    end if
end subroutine input_scroll

subroutine input_set_key(input, key)
    !! Record a named key (KEY_*); KEY_NONE and unknown values are ignored.
    type(input_state_t), intent(inout) :: input
    integer, intent(in) :: key

    if (key <= KEY_NONE .or. key > KEY_INSERT) return
    if (input%key_count < MAX_FRAME_KEYS) then
        input%key_count = input%key_count + 1
        input%keys(input%key_count) = key
        input%key_text_pos(input%key_count) = input%text_len
    end if
end subroutine input_set_key

subroutine input_route(input, previous)
    type(input_state_t), intent(inout) :: input
    type(ui_frame_t), intent(in) :: previous

    integer :: hit, i, focused_index, first_focus, next_focus

    ! Pointer capture ends when its node disappears or the button is up.
    if (len_trim(input%active_id) > 0) then
        if (previous%find(trim(input%active_id)) == 0) input%active_id = ""
    end if
    if (.not. input%pointer_down .and. &
        .not. input%pointer_released) input%active_id = ""

    if (input_key_arrived(input, KEY_TAB)) then
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
                if (previous%nodes(i)%focusable .and. &
                    .not. previous%nodes(i)%disabled) then
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
                if (.not. input%drag_exceeded) call register_click(input)
            end if
        end if
        input%active_id = ""
    end if

    if ((input_key_arrived(input, KEY_ENTER) .or. input_key_arrived(input, KEY_SPACE)) &
        .and. len_trim(input%focus_id) > 0) then
        input%activated_id = input%focus_id
    end if

    if (input%scroll_y /= 0) then
        hit = hit_test(previous, input%pointer_x, input%pointer_y, .false.)
        if (hit > 0) input%scroll_id = previous%nodes(hit)%id
    end if
end subroutine input_route

subroutine register_click(input)
    !! A click is press+release on one node without exceeding the drag threshold.
    type(input_state_t), intent(inout) :: input

    input%click_id = input%activated_id
    if (trim(input%last_click_id) == trim(input%click_id) .and. &
        input%time - input%last_click_time <= DOUBLE_CLICK_SECONDS .and. &
        abs(input%press_x - input%last_click_x) <= DOUBLE_CLICK_DISTANCE .and. &
        abs(input%press_y - input%last_click_y) <= DOUBLE_CLICK_DISTANCE) then
        input%double_click_id = input%click_id
        input%last_click_id = ""
        input%last_click_time = -1.0d9
    else
        input%last_click_id = input%click_id
        input%last_click_time = input%time
        input%last_click_x = input%press_x
        input%last_click_y = input%press_y
    end if
end subroutine register_click

integer function hit_test(frame, x, y, interactive_only) result(index)
    type(ui_frame_t), intent(in) :: frame
    real, intent(in) :: x, y
    logical, intent(in) :: interactive_only
    integer :: i

    index = 0
    do i = frame%count, 1, -1
        if (interactive_only .and. .not. frame%nodes(i)%focusable) cycle
        if (len_trim(frame%nodes(i)%id) == 0) cycle
        if (frame%nodes(i)%disabled) cycle
        if (x >= frame%nodes(i)%x .and. &
            x < frame%nodes(i)%x + frame%nodes(i)%width .and. &
            y >= frame%nodes(i)%y .and. &
            y < frame%nodes(i)%y + frame%nodes(i)%height) then
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

logical function input_key_arrived(input, key)
    !! Whether `key` is among the keys of this frame.
    type(input_state_t), intent(in) :: input
    integer, intent(in) :: key
    input_key_arrived = any(input%keys(1:input%key_count) == key)
end function input_key_arrived

end module fortui_input
