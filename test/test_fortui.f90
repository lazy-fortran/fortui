program test_fortui
use fortui
use fortui_context, only: fortui_context_t, get_default_context
use fortui_frame, only: ui_frame_t, ui_node_t, UI_BUTTON
use fortui_input, only: input_state_t, input_begin_frame, input_update_pointer, &
    input_route, input_activated
implicit none

type(fortui_context_t), pointer :: ctx
type(ui_frame_t) :: frame
type(ui_node_t) :: node
type(input_state_t) :: input
real :: value
logical :: checked, clicked
integer :: stat

call ui_init("headless", 800, 600, "test", stat=stat)
call check(stat == 0, "headless init")
call check(trim(ui_get_backend()) == "headless", "headless backend name")

value = 50.0
checked = .false.
call ui_frame_begin()
call text("title", "Test")
call row_begin(8.0)
clicked = button("save", "Save")
call check(.not. clicked, "button is not spuriously activated")
call check(.not. checkbox("check", checked, "Check"), "checkbox is not spuriously toggled")
call row_end()
call check(.not. slider("value", 0.0, 100.0, 1.0, value, width=200.0), "slider unchanged")
call ui_present()

ctx => get_default_context()
call check(associated(ctx), "context exists")
call check(ctx%previous_frame%count == 4, "semantic frame contains four nodes")
call check(ctx%previous_frame%nodes(2)%x == 0.0, "row starts at zero")
call check(ctx%previous_frame%nodes(3)%x > ctx%previous_frame%nodes(2)%x, "row advances horizontally")

call frame%reset()
node%kind = UI_BUTTON
node%id = "probe"
node%x = 0.0
node%y = 0.0
node%width = 100.0
node%height = 40.0
node%focusable = .true.
stat = frame%append(node)

call input_begin_frame(input)
call input_update_pointer(input, 10.0, 10.0, .true., .true.)
call input_route(input, frame)
call check(trim(input%active_id) == "probe", "press captures semantic node")
call input_begin_frame(input)
call input_update_pointer(input, 10.0, 10.0, .false.)
call input_route(input, frame)
call check(input_activated(input, "probe"), "release activates captured node")

! A press and release inside one backend event batch (button already up, but a
! press was reported) is one complete click, not a lost press.
call input_begin_frame(input)
call input_update_pointer(input, 20.0, 20.0, .false., .true.)
call input_route(input, frame)
call check(input_activated(input, "probe"), "same-batch press+release activates")
call check(trim(input%click_id) == "probe", "same-batch press+release is a click")
call check(len_trim(input%active_id) == 0, "same-batch click leaves no capture")

call ui_shutdown()
call check(.not. ui_is_initialized(), "shutdown releases context")
print *, "fortui tests passed"

contains

subroutine check(condition, message)
    logical, intent(in) :: condition
    character(*), intent(in) :: message
    if (.not. condition) then
        write(*, '(a)') "FAIL: " // trim(message)
        error stop 1
    end if
end subroutine check

end program test_fortui
