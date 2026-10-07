program fortui_demo
use fortui
implicit none

real :: gain
logical :: grid
logical :: running
type(view) :: camera
integer :: stat

gain = 1.0
grid = .false.
camera = view()

call ui_init("auto", 900, 640, "FortUI demo", stat=stat)
if (stat /= 0) error stop "No interactive backend available"

running = .true.
do while (running .and. .not. ui_should_close())
    call ui_frame_begin()

    call text("title", "FortUI")
    call row_begin(8.0)
    if (button("zoom_in", "Zoom In")) then
        camera%scale_x = camera%scale_x * 1.2
        camera%scale_y = camera%scale_y * 1.2
    end if
    if (button("zoom_out", "Zoom Out")) then
        camera%scale_x = camera%scale_x / 1.2
        camera%scale_y = camera%scale_y / 1.2
    end if
    if (button("quit", "Quit")) running = .false.
    call row_end()

    call text("gain_label", "Gain")
    if (slider("gain", 0.1, 5.0, 0.1, gain, width=260.0)) continue
    if (checkbox("grid", grid, "Show grid")) continue
    if (viewport("plot", 640.0, 360.0, camera)) continue

    call ui_present()
end do

call ui_shutdown()
end program fortui_demo
