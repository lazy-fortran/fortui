module fortui
! Main fortui module - re-exports all public APIs for user convenience
! Users should "use fortui" to access the complete API

! Import core functionality
use fortui_core, only: ui_element, node, view, &
    ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close, &
    ui_set_idle_policy, column, row
use fortui_units, only: unit_value, ui_context, &
    dp, em, sp, px, cw, ch, convert_to_dp, ui_set_context
use fortui_widgets, only: button, text, slider, checkbox, viewport, &
    button_node_t, text_node_t, slider_node_t, checkbox_node_t

! Import Widget-Renderer Collaboration Pattern
use fortui_widget_renderer, only: widget_renderer_t, render_context_t, ui_rect, ui_color, &
    WIDGET_NORMAL, WIDGET_HOVER, WIDGET_PRESSED, WIDGET_FOCUSED, WIDGET_DISABLED
use fortui_renderable, only: renderable_widget_t, widget_state_t
use fortui_tui_renderer, only: tui_renderer_t
use fortui_gui_renderer, only: gui_renderer_t
use fortui_button_widget, only: button_widget_t, button_state_t
use fortui_text_widget, only: text_widget_t, text_state_t
use fortui_slider_widget, only: slider_widget_t, slider_state_t
use fortui_checkbox_widget, only: checkbox_widget_t, checkbox_state_t
use fortui_viewport_widget, only: viewport_widget_t, viewport_state_t

implicit none

! Re-export all imported types and procedures - they are now accessible via "use fortui"
public :: ui_element, node, view
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy, column, row
public :: unit_value, ui_context
public :: dp, em, sp, px, cw, ch, convert_to_dp, ui_set_context
public :: button, text, slider, checkbox, viewport
public :: button_node_t, text_node_t, slider_node_t, checkbox_node_t

! Widget-Renderer Collaboration Pattern types and interfaces
public :: widget_renderer_t, render_context_t, ui_rect, ui_color
public :: WIDGET_NORMAL, WIDGET_HOVER, WIDGET_PRESSED, WIDGET_FOCUSED, WIDGET_DISABLED
public :: renderable_widget_t, widget_state_t
public :: tui_renderer_t, gui_renderer_t
public :: button_widget_t, button_state_t
public :: text_widget_t, text_state_t
public :: slider_widget_t, slider_state_t
public :: checkbox_widget_t, checkbox_state_t
public :: viewport_widget_t, viewport_state_t

end module fortui
