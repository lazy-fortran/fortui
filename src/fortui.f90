module fortui
! Clean public API module - only re-exports user-facing functionality
! No internal implementation details exposed

! Import core functionality  
use fortui_core, only: &
    ! Lifecycle management
    ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close, &
    ui_set_idle_policy, ui_get_context, &
    ui_is_initialized, ui_get_backend, ui_get_fortui_context, &
    ! Layout types and constructors
    ui_element, node, view, widget_wrapper, &
    column, row, widget, &
    ! Backend detection
    is_gui_available, is_tui_available, is_headless_environment, resolve_backend, &
    set_environment_variable_simulation, clear_environment_variable_simulation

! Import widget functionality
use fortui_widgets, only: &
    ! Widget functions (immediate-mode)
    button, text, slider, checkbox, viewport

implicit none

! Re-export all imported symbols
! Lifecycle management
public :: ui_init, ui_shutdown, ui_frame_begin, ui_present, ui_should_close
public :: ui_set_idle_policy, ui_get_context
public :: ui_is_initialized, ui_get_backend, ui_get_fortui_context
! Layout types and constructors  
public :: ui_element, node, view, widget_wrapper
public :: column, row, widget
! Backend detection
public :: is_gui_available, is_tui_available, is_headless_environment, resolve_backend
public :: set_environment_variable_simulation, clear_environment_variable_simulation
! Widget functions
public :: button, text, slider, checkbox, viewport

end module fortui