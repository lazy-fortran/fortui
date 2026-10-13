module fortui
!! FortUI public API: immediate composition, retained runtime semantics.
use fortui_core, only: ui_init, ui_shutdown, ui_frame_begin, ui_present, &
    ui_should_close, ui_request_quit, ui_is_initialized, ui_get_backend, &
    column_begin, column_end, row_begin, row_end, split_begin, split_next, split_end, &
    view, ui_request_frame, ui_set_continuous, ui_window_size, ui_scale, ui_stats, &
    ui_stats_t, ui_canvas_layer_uploads, ui_set_font, ui_inject_pointer, &
    ui_inject_wheel, ui_inject_key, ui_inject_text, ui_inject_time, ui_inject_resize, &
    ui_backend_capabilities, ui_backend_caps_t
use fortui_widgets, only: button, text, slider, checkbox, viewport, canvas_begin, &
    canvas_end, canvas_points, canvas_lines, canvas_label, scroll_text, text_input
use fortui_canvas, only: canvas_view_t, canvas_events_t, ui_rgba, canvas_to_world, &
    canvas_to_local, canvas_zoom_at
use fortui_text, only: ui_text_width => text_width, utf8_length
use fortui_input, only: KEY_ENTER, KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, &
    KEY_HOME, KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN, &
    KEY_PAGE_UP, KEY_PAGE_DOWN
implicit none
private

public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_request_quit, ui_is_initialized, ui_get_backend
public :: column_begin, column_end, row_begin, row_end
public :: split_begin, split_next, split_end
public :: button, text, slider, checkbox, viewport, view
public :: canvas_begin, canvas_end, canvas_points, canvas_lines, canvas_label
public :: canvas_view_t, canvas_events_t, ui_rgba, canvas_to_world, canvas_to_local
public :: canvas_zoom_at
public :: scroll_text, text_input, ui_text_width, utf8_length
public :: ui_request_frame, ui_set_continuous, ui_window_size, ui_scale
public :: ui_stats, ui_stats_t, ui_canvas_layer_uploads, ui_set_font
public :: ui_inject_pointer, ui_inject_wheel, ui_inject_key, ui_inject_text
public :: ui_inject_time, ui_inject_resize, ui_backend_capabilities, ui_backend_caps_t
public :: KEY_ENTER, KEY_ESCAPE, KEY_TAB, KEY_BACKSPACE, KEY_DELETE, KEY_HOME
public :: KEY_END, KEY_ARROW_LEFT, KEY_ARROW_RIGHT, KEY_ARROW_UP, KEY_ARROW_DOWN
public :: KEY_PAGE_UP, KEY_PAGE_DOWN

end module fortui
