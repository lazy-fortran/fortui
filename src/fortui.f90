module fortui
    !! FortUI public API: immediate Fortran composition over a retained runtime.
    !!
    !! Lifecycle (backend injection), frame transactions, containers, widgets,
    !! canvas layers, keys, style tokens and small text helpers. Backends live in
    !! their own modules (fortui_backend_headless, fortui_tui, fortui_gui_raylib);
    !! fortui_backends adds ui_init(name, ...); fortui_testing adds automation.
    use fortui_core, only: ui_init, ui_shutdown, ui_frame_begin, ui_present, &
        ui_should_close, ui_request_quit, ui_is_initialized, ui_get_backend, &
        ui_request_frame, ui_set_continuous, ui_window_size, ui_scale, ui_key_pressed, &
        ui_time, ui_wake_after, &
        ui_text_width, ui_backend_capabilities, ui_backend_caps_t, ui_backend_description, &
        ui_run, ui_run_step, ui_frame_proc
    use fortui_layout, only: column_begin, column_end, row_begin, row_end, split_begin, &
        split_next, split_end
    use fortui_widgets, only: text, button, link, slider, checkbox, tabs, scroll_text, &
        text_input, canvas_begin, canvas_end, canvas_vertices, canvas_points, &
        canvas_lines, canvas_label
    use fortui_canvas, only: canvas_view_t, canvas_events_t, ui_rgba, canvas_to_world, &
        canvas_to_local, canvas_zoom_at
    use fortui_frame, only: UI_BODY, UI_CAPTION, UI_HEADING, UI_TITLE, UI_FILL, UI_CODE, &
        UI_TONE_NORMAL, UI_TONE_POSITIVE, UI_TONE_NEGATIVE, UI_TONE_MUTED, UI_TONE_ACCENT, &
        UI_TONE_KEYWORD, UI_TONE_STRING, UI_TONE_COMMENT, UI_TONE_NUMBER, UI_TONE_TYPE, &
        UI_TONE_PREPROC, UI_TONE_ADDED, UI_TONE_REMOVED, UI_TONE_HUNK, UI_TONE_LINK, &
        UI_TONE_STRONG, UI_TONE_EMPHASIS, UI_TONE_ATTENTION
    use fortui_text, only: ui_str
    use fortui_input, only: KEY_ENTER, KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, &
        KEY_HOME, KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN, &
        KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_SPACE, KEY_INSERT
    implicit none
    private

    public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
    public :: ui_run, ui_run_step, ui_frame_proc
    public :: ui_request_quit, ui_is_initialized, ui_get_backend
    public :: ui_backend_capabilities, ui_backend_caps_t, ui_backend_description
    public :: ui_request_frame, ui_set_continuous, ui_window_size, ui_scale
    public :: ui_time, ui_wake_after
    public :: ui_key_pressed, ui_text_width, ui_str
    public :: column_begin, column_end, row_begin, row_end
    public :: split_begin, split_next, split_end
    public :: text, button, link, slider, checkbox, tabs, scroll_text, text_input
    public :: canvas_begin, canvas_end, canvas_vertices, canvas_points, canvas_lines
    public :: canvas_label, canvas_view_t, canvas_events_t, ui_rgba
    public :: canvas_to_world, canvas_to_local, canvas_zoom_at
    public :: UI_BODY, UI_CAPTION, UI_HEADING, UI_TITLE, UI_FILL, UI_CODE
    public :: UI_TONE_NORMAL, UI_TONE_POSITIVE, UI_TONE_NEGATIVE, UI_TONE_MUTED, UI_TONE_ACCENT
    public :: UI_TONE_KEYWORD, UI_TONE_STRING, UI_TONE_COMMENT, UI_TONE_NUMBER, UI_TONE_TYPE
    public :: UI_TONE_PREPROC, UI_TONE_ADDED, UI_TONE_REMOVED, UI_TONE_HUNK, UI_TONE_LINK
    public :: UI_TONE_STRONG, UI_TONE_EMPHASIS, UI_TONE_ATTENTION
    public :: KEY_ENTER, KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, KEY_HOME
    public :: KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN
    public :: KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_SPACE, KEY_INSERT

end module fortui
