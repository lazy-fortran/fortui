program gui_demo
! GUI backend demonstration
! Uses automatic backend selection: GUI if available, TUI otherwise
! Same code works with both backends via the render dispatch layer
!
! Controls:
!   Mouse click   - interact with widgets
!   Tab           - cycle keyboard focus
!   Enter / Space - activate focused button or toggle checkbox
!   Left / Right  - adjust focused slider
!   ESC           - quit
use fortui
implicit none

logical :: running, save_clicked, load_clicked, auto_save
real :: volume, brightness
integer :: frame_count
character(len=64) :: status_text
type(view) :: plot_view
type(node) :: root_node

volume = 50.0
brightness = 75.0
auto_save = .false.
frame_count = 0
plot_view = view()

call ui_init("auto", 640, 480, "fortui GUI Demo", &
    target_fps=60, vsync=.true.)
call ui_set_idle_policy("adaptive", idle_fps=12)

running = .true.
root_node = column()

do while (running .and. .not. ui_should_close())
    call ui_frame_begin()
    frame_count = frame_count + 1

    write(status_text, '(A,I6,A,F5.1,A,F5.1,A)') &
        "Frame:", frame_count, " Vol:", volume, &
        " Brt:", brightness, "%"

    call text("title", "fortui GUI Demo", text_size=2.0)
    call text("status", trim(status_text))
    call text("sep1", value=repeat('-', 50), width=50.0)

    call row_begin(2.0)
    save_clicked = button("save", "Save")
    load_clicked = button("load", "Load")
    call row_end()

    call text("sep2", value=repeat('-', 50), width=50.0)

    call row_begin(1.0)
    call text("vol_lbl", value="Volume: ", width=8.0)
    if (slider("volume", 0.0, 100.0, 1.0, volume, &
        width=30.0)) then
    end if
    call row_end()

    call row_begin(1.0)
    call text("brt_lbl", value="Bright: ", width=8.0)
    if (slider("brightness", 0.0, 100.0, 1.0, brightness, &
        width=30.0)) then
    end if
    call row_end()

    auto_save = checkbox("autosave", auto_save, "Auto-Save")

    call text("sep3", value=repeat('-', 50), width=50.0)
    if (viewport("demo_vp", 40.0, 8.0, plot_view)) then
    end if

    if (save_clicked) then
        status_text = "Saved!"
    end if
    if (load_clicked) then
        volume = 50.0
        brightness = 75.0
        auto_save = .false.
    end if

    call ui_present(root_node)
end do

call ui_shutdown()

end program gui_demo
