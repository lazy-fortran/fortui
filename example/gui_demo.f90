program gui_demo
    !! Semantic controls realized by whichever interactive backend is available.
    use fortui
    use fortui_backends, only: ui_init
    implicit none

    logical :: auto_save
    integer :: volume, tab, stat
    character(len=64) :: status

    auto_save = .false.
    volume = 50
    tab = 1
    status = "Ready"

    call ui_init("auto", 800, 600, "FortUI semantic GUI/TUI demo", stat=stat)
    if (stat /= 0) error stop "No interactive FortUI backend available"

    do while (.not. ui_should_close())
        call ui_frame_begin()
        if (ui_key_pressed(KEY_ESCAPE)) call ui_request_quit()
        call column_begin(8.0)
        call text("FortUI semantic demo", style=UI_TITLE)
        if (tabs("tab", [character(8) :: "Controls", "About"], tab)) status = "Tab changed"
        select case (tab)
        case (1)
            call row_begin(8.0)
            if (button("save", "Save")) status = "Saved"
            if (button("load", "Load")) then
                status = "Loaded"
                volume = 50
            end if
            if (button("quit", "Quit")) call ui_request_quit()
            call row_end()
            call text("Volume " // ui_str(volume), style=UI_CAPTION)
            if (slider("volume", 0, 100, volume, width=240.0)) status = "Volume changed"
            if (checkbox("autosave", auto_save, "Auto-save")) status = "Auto-save toggled"
        case (2)
            call text("Widgets emit semantics; backends realize them.", width=UI_FILL, &
                ellipsis=.true.)
        end select
        call text("Status: " // trim(status), style=UI_CAPTION)
        call column_end()
        call ui_present()
    end do

    call ui_shutdown()
end program gui_demo
