module fortui
! Clean public API module - only re-exports user-facing functionality
use fortui_core, only: &
    ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close, &
    ui_set_idle_policy, &
    ui_is_initialized, ui_get_backend, &
    node, view, column, row

use fortui_widgets, only: &
    button, text, slider, checkbox, viewport

implicit none

public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy, ui_is_initialized, ui_get_backend
public :: node, view, column, row
public :: button, text, slider, checkbox, viewport

end module fortui
