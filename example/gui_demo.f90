program gui_demo
use fortui
implicit none

logical :: auto_save, running
logical :: save_clicked, load_clicked
real :: volume
type(view) :: camera
integer :: stat
character(len=64) :: status

auto_save = .false.
volume = 50.0
camera = view()
status = "Ready"

call ui_init("auto", 800, 600, "FortUI semantic GUI/TUI demo", stat=stat)
if (stat /= 0) error stop "No interactive FortUI backend available"

running = .true.
do while (running .and. .not. ui_should_close())
    call ui_frame_begin()

    call text("title", "FortUI semantic demo", text_size=1.25)
    call row_begin(8.0)
    save_clicked = button("save", "Save")
    load_clicked = button("load", "Load")
    if (button("quit", "Quit")) running = .false.
    call row_end()

    call row_begin(8.0)
    call text("volume_label", "Volume")
    if (slider("volume", 0.0, 100.0, 1.0, volume, width=240.0)) status = "Volume changed"
    call row_end()

    if (checkbox("autosave", auto_save, "Auto-save")) status = "Auto-save toggled"
    if (viewport("preview", 480.0, 260.0, camera)) status = "Viewport changed"
    call text("status", "Status: " // trim(status))

    if (save_clicked) status = "Saved"
    if (load_clicked) then
        status = "Loaded"
        volume = 50.0
    end if

    call ui_present()
end do

call ui_shutdown()
end program gui_demo
