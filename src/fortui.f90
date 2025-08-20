module fortui
! Main fortui module - re-exports all public APIs for user convenience
! Users should "use fortui" to access the complete API
use fortui_core
use fortui_units
use fortui_widgets
implicit none

! Re-export all public types from fortui_core
public :: ui_element, node, view

! Re-export all public procedures from fortui_core
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy
public :: column, row

! Re-export all public types from fortui_units
public :: unit_value, ui_context

! Re-export all public unit constructor functions from fortui_units
public :: dp, em, sp, px, cw, ch

! Re-export all public functions from fortui_units
public :: convert_to_dp, ui_get_context, ui_set_context

! Re-export all public widget functions from fortui_widgets
public :: button, text, slider, checkbox
public :: widget, viewport

! Re-export widget node types from fortui_widgets
public :: button_node_t, text_node_t, slider_node_t, checkbox_node_t

end module fortui
