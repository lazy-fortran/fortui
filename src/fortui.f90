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
        ui_time, ui_wake_after, ui_shortcut, ui_clipboard_set, ui_clipboard_text, ui_set_title, &
        ui_waker, ui_set_window_margin, ui_set_window_size, ui_set_window_visible, &
        ui_maximize_window, ui_set_window_background, ui_open_url, ui_offer_file, ui_primary_set, &
        ui_primary_text, ui_text_width, ui_backend_capabilities, ui_backend_caps_t, ui_backend_description, &
        ui_run, ui_run_step, ui_frame_proc, ui_set_theme, ui_theme_name, ui_locale, ui_url_param, &
        ui_width_class, UI_COMPACT, UI_MEDIUM, UI_EXPANDED, UI_LARGE, ui_set_url_param, ui_location, &
        ui_store_get, ui_store_set, ui_store_use
    use fortui_net, only: net_request_t, net_stream_t, net_fetch, net_poll, net_cancel, &
        net_stream_open, net_stream_next, net_stream_close, net_set_base, NET_IDLE, NET_PENDING, &
        NET_DONE, NET_FAILED, NET_UNSUPPORTED, NET_CANCELLED, NET_OPEN
    use fortui_layout, only: column_begin, column_end, row_begin, row_end, split_begin, &
        split_next, split_end
    use fortui_widgets, only: text, button, link, slider, checkbox, tabs, list_box, scroll_text, &
        text_input, canvas_begin, canvas_end, canvas_vertices, canvas_points, canvas_mesh, &
        canvas_lines, canvas_label, canvas_image, canvas_cells, canvas_keys, ui_cell_metrics, &
        ui_set_cell_font, ui_focus, &
        ui_reveal
    use fortui_controls, only: icon, badge, chip, segmented, dropdown, menu, avatar, ui_user_colour, toast, &
        modal_begin, modal_end, scroll_begin, scroll_end, virtual_list_begin, virtual_list_end, &
        grid_state_t, data_grid
    use fortui_icons, only: icon_names
    use fortui_commands, only: command_history_t, command_record, command_undo, command_redo, &
        command_undo_label, command_redo_label, command_shortcuts, command_clear
    use fortui_mesh, only: canvas_camera_t, camera_orbit, camera_project, mesh_grid, mesh_tube
    use fortui_file_dialog, only: file_dialog_t, file_dialog_open, file_dialog_show, &
        file_open_button, file_dialog_poll, file_dialog_cancel, FILE_IDLE, FILE_PENDING, FILE_ACCEPTED, FILE_CANCELLED
    use fortui_canvas, only: canvas_view_t, canvas_events_t, ui_rgba, canvas_to_world, &
        canvas_to_local, canvas_zoom_at
    use fortui_frame, only: UI_BODY, UI_CAPTION, UI_HEADING, UI_TITLE, UI_FILL, UI_CODE, &
        UI_TONE_NORMAL, UI_TONE_POSITIVE, UI_TONE_NEGATIVE, UI_TONE_MUTED, UI_TONE_ACCENT, &
        UI_TONE_KEYWORD, UI_TONE_STRING, UI_TONE_COMMENT, UI_TONE_NUMBER, UI_TONE_TYPE, &
        UI_TONE_PREPROC, UI_TONE_ADDED, UI_TONE_REMOVED, UI_TONE_HUNK, UI_TONE_LINK, &
        UI_TONE_STRONG, UI_TONE_EMPHASIS, UI_TONE_ATTENTION, UI_EMPHASIS_NORMAL, &
        UI_EMPHASIS_PRIMARY, UI_EMPHASIS_QUIET
    use fortui_text, only: ui_str
    use fortui_input, only: POINTER_MOUSE, POINTER_PEN, POINTER_TOUCH
    use fortui_input, only: KEY_ENTER, KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, &
        KEY_HOME, KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN, &
        KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_SPACE, KEY_INSERT, KEY_F1, KEY_F12, key_press_t, &
        MOD_CTRL, MOD_ALT, MOD_SHIFT, MOD_META
    use fortui_frame, only: CELL_BOLD, CELL_ITALIC, CELL_UNDERLINE, CELL_STRIKE, CELL_WIDE, &
        CELL_CONT, CELL_DIM
    implicit none
    private

    public :: file_dialog_t, file_dialog_open, file_dialog_show, file_open_button, file_dialog_poll, file_dialog_cancel
    public :: FILE_IDLE, FILE_PENDING, FILE_ACCEPTED, FILE_CANCELLED
    public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
    public :: ui_locale, ui_url_param, ui_width_class, UI_COMPACT, UI_MEDIUM, UI_EXPANDED, UI_LARGE
    public :: ui_set_url_param, ui_location, ui_store_get, ui_store_set, ui_store_use
    public :: POINTER_MOUSE, POINTER_PEN, POINTER_TOUCH
    public :: net_request_t, net_stream_t, net_fetch, net_poll, net_cancel, net_stream_open, &
        net_stream_next, net_stream_close, net_set_base, NET_IDLE, NET_PENDING, NET_DONE, &
        NET_FAILED, NET_UNSUPPORTED, NET_CANCELLED, NET_OPEN
    public :: ui_run, ui_run_step, ui_frame_proc, ui_set_theme, ui_theme_name
    public :: ui_request_quit, ui_is_initialized, ui_get_backend
    public :: ui_backend_capabilities, ui_backend_caps_t, ui_backend_description
    public :: ui_request_frame, ui_set_continuous, ui_window_size, ui_scale
    public :: ui_time, ui_wake_after, ui_clipboard_set, ui_clipboard_text, ui_set_title, ui_waker
    public :: ui_set_window_margin, ui_set_window_size, ui_set_window_visible
    public :: ui_maximize_window, ui_set_window_background, ui_open_url, ui_offer_file, ui_primary_set, &
        ui_primary_text
    public :: ui_key_pressed, ui_text_width, ui_str
    public :: ui_shortcut, ui_focus, ui_reveal
    public :: column_begin, column_end, row_begin, row_end
    public :: icon, badge, chip, segmented, dropdown, menu, avatar, ui_user_colour, toast, modal_begin, modal_end
    public :: command_history_t, command_record, command_undo, command_redo, command_undo_label, &
        command_redo_label, command_shortcuts, command_clear
    public :: scroll_begin, scroll_end, virtual_list_begin, virtual_list_end
    public :: grid_state_t, data_grid, icon_names
    public :: split_begin, split_next, split_end
    public :: text, button, link, slider, checkbox, tabs, list_box, scroll_text, text_input
    public :: canvas_begin, canvas_end, canvas_vertices, canvas_points, canvas_lines, canvas_mesh
    public :: canvas_camera_t, camera_orbit, camera_project, mesh_grid, mesh_tube
    public :: canvas_label, canvas_image, canvas_view_t, canvas_events_t, ui_rgba
    public :: canvas_to_world, canvas_to_local, canvas_zoom_at
    public :: UI_BODY, UI_CAPTION, UI_HEADING, UI_TITLE, UI_FILL, UI_CODE
    public :: UI_TONE_NORMAL, UI_TONE_POSITIVE, UI_TONE_NEGATIVE, UI_TONE_MUTED, UI_TONE_ACCENT
    public :: UI_TONE_KEYWORD, UI_TONE_STRING, UI_TONE_COMMENT, UI_TONE_NUMBER, UI_TONE_TYPE
    public :: UI_TONE_PREPROC, UI_TONE_ADDED, UI_TONE_REMOVED, UI_TONE_HUNK, UI_TONE_LINK
    public :: UI_TONE_STRONG, UI_TONE_EMPHASIS, UI_TONE_ATTENTION
    public :: UI_EMPHASIS_NORMAL, UI_EMPHASIS_PRIMARY, UI_EMPHASIS_QUIET
    public :: KEY_ENTER, KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, KEY_HOME
    public :: KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN
    public :: KEY_PAGE_UP, KEY_PAGE_DOWN, KEY_SPACE, KEY_INSERT, KEY_F1, KEY_F12
    public :: canvas_cells, canvas_keys, key_press_t, MOD_CTRL, MOD_ALT, MOD_SHIFT, MOD_META
    public :: ui_cell_metrics, ui_set_cell_font, CELL_BOLD, CELL_ITALIC, CELL_UNDERLINE
    public :: CELL_STRIKE, CELL_WIDE, CELL_CONT, CELL_DIM

end module fortui
