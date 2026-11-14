program theme_gallery
    !! Every control in every state, for comparing themes and backends:
    !!   FORTUI_THEME=classic fpm run --example theme_gallery
    !! Keys: 1 classic, 2 material, 3 material-dark.
    use iso_fortran_env, only: int32
    use fortui
    use fortui_backends, only: ui_init
    implicit none

    integer :: stat, tab = 1, volume = 40, k
    logical :: checked = .true., unchecked = .false.
    character(len=:), allocatable :: name, notes, status
    type(canvas_view_t) :: view
    real :: xy(2, 64)
    integer(int32) :: colours(64)
    integer, parameter :: ends(4) = [7, 12, 22, 31]
    integer, parameter :: tones(4) = [UI_TONE_KEYWORD, UI_TONE_NORMAL, UI_TONE_STRING, &
        UI_TONE_COMMENT]

    name = "Gallery"
    notes = "Fields keep their own caret." // new_line('a') // "Second line."
    status = "Ready"
    do k = 1, 64
        xy(:, k) = [20.0 + 4.0 * k, 70.0 + 40.0 * sin(0.2 * k)]
        colours(k) = ui_rgba(40 + 3 * k, 90, 200 - 2 * k)
    end do
    call ui_init("gui", 900, 640, "FortUI theme gallery", stat=stat)
    if (stat /= 0) error stop "no graphical backend"
    call ui_run(frame)
    call ui_shutdown()

contains

    subroutine frame()
        if (ui_key_pressed(KEY_ESCAPE)) call ui_request_quit()
        if (ui_shortcut("1")) call ui_set_theme("classic")
        if (ui_shortcut("2")) call ui_set_theme("material")
        if (ui_shortcut("3")) call ui_set_theme("material-dark")
        call split_begin("main", first=420.0, gap=16.0)
        call column_begin(8.0)
        call text("Theme gallery", style=UI_TITLE)
        call text("Theme " // ui_theme_name() // " (keys 1, 2, 3)", style=UI_CAPTION)
        call text("Buttons", style=UI_HEADING)
        call row_begin(8.0)
        if (button("ok", "OK", emphasis=UI_EMPHASIS_PRIMARY)) status = "OK pressed"
        if (button("cancel", "Cancel")) status = "Cancel pressed"
        if (button("help", "Help", emphasis=UI_EMPHASIS_QUIET)) status = "Help pressed"
        if (button("off", "Disabled", enabled=.false.)) continue
        call row_end()
        call text("Choices", style=UI_HEADING)
        if (checkbox("a", checked, "Checked option")) status = "option toggled"
        if (checkbox("b", unchecked, "Unchecked option")) status = "option toggled"
        if (checkbox("c", checked, "Disabled option", enabled=.false.)) continue
        call text("Volume " // ui_str(volume), style=UI_CAPTION)
        if (slider("vol", 0, 100, volume, width=300.0)) continue
        if (tabs("tabs", [character(10) :: "General", "Display", "Advanced"], tab)) continue
        call text("Fields", style=UI_HEADING)
        if (text_input("name", name, placeholder="Name", width=300.0)) continue
        if (text_input("empty", status, placeholder="Status", width=300.0)) continue
        if (text_input("notes", notes, lines=3, width=300.0)) continue
        if (link("site", "A link to somewhere", "https://example.org")) continue
        call text("call print_page(job) ! code tones", style=UI_CODE, ends=ends, tones=tones)
        call text(status, tone=UI_TONE_POSITIVE)
        call column_end()
        call split_next()
        call column_begin(8.0)
        call text("Scrolling text", style=UI_HEADING)
        call scroll_text("log", repeat("A line of text in a scrolling view. ", 40), &
            height=180.0)
        call text("Canvas", style=UI_HEADING)
        call canvas_begin("plot", view, width=UI_FILL, height=160.0, &
            fill=ui_rgba(255, 255, 255))
        call canvas_lines("curve", 1, xy, colours, reshape([(k, k + 1, k = 1, 63)], [2, 63]), &
            width=2.0)
        call canvas_points("dots", 1, xy, colours, size=6.0)
        call canvas_label(140.0, 110.0, "sin(x)", 12.0)
        call canvas_end(view)
        call column_end()
        call split_end()
    end subroutine frame

end program theme_gallery
