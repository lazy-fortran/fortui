program tui_demo
use fortui
implicit none

logical :: running, checked
real :: value
type(view) :: camera

running = .true.
checked = .false.
value = 25.0
camera = view()

call ui_init("tui", 80, 24, "FortUI TUI demo")

do while (running .and. .not. ui_should_close())
    call ui_frame_begin()

    call text("title", "FortUI TUI")
    call row_begin(8.0)
    if (button("one", "One")) value = 10.0
    if (button("two", "Two")) value = 90.0
    if (button("quit", "Quit")) running = .false.
    call row_end()

    call text("slider_label", "Value")
    if (slider("value", 0.0, 100.0, 5.0, value, width=240.0)) continue
    if (checkbox("check", checked, "Enabled")) continue
    if (viewport("view", 320.0, 128.0, camera)) continue

    call ui_present()
end do

call ui_shutdown()
end program tui_demo
