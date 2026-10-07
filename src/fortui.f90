module fortui
!! FortUI public API: immediate composition, retained runtime semantics.
use fortui_core, only: ui_init, ui_shutdown, ui_frame_begin, ui_present, &
    ui_should_close, ui_request_quit, ui_is_initialized, ui_get_backend, &
    column_begin, column_end, row_begin, row_end, view
use fortui_widgets, only: button, text, slider, checkbox, viewport
implicit none
private

public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_request_quit, ui_is_initialized, ui_get_backend
public :: column_begin, column_end, row_begin, row_end
public :: button, text, slider, checkbox, viewport, view

end module fortui
