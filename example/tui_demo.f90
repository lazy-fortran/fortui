program tui_demo
    !! Terminal realization of the same semantic controls (run in a real terminal).
    use fortui
    use fortui_tui, only: tui_backend_t
    implicit none

    logical :: checked
    integer :: value, stat

    checked = .false.
    value = 25

    call ui_init(tui_backend_t(), 80, 24, "FortUI TUI demo", stat=stat)
    if (stat /= 0) error stop "No terminal available"

    do while (.not. ui_should_close())
        call ui_frame_begin()
        if (ui_key_pressed(KEY_ESCAPE)) call ui_request_quit()
        call text("FortUI TUI", style=UI_HEADING)
        call row_begin(8.0)
        if (button("one", "One")) value = 10
        if (button("two", "Two")) value = 90
        if (button("quit", "Quit")) call ui_request_quit()
        call row_end()
        call text("Value " // ui_str(value))
        if (slider("value", 0, 100, value, step=5, width=240.0)) continue
        if (checkbox("check", checked, "Enabled")) continue
        call ui_present()
    end do

    call ui_shutdown()
end program tui_demo
