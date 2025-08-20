module fortui_widgets
! Simplified widgets module to test compilation
use fortui_widgets_button, only: button_node_t, button
implicit none
private

! Re-export button widget
public :: button_node_t, button

! Placeholder types for other widgets
public :: text_node_t, slider_node_t, checkbox_node_t
public :: text, slider, checkbox, viewport

! Widget node types (simplified placeholders)
type :: text_node_t
    character(len=256) :: id = ""
    character(len=1024) :: value = ""
    real :: width_dp = 0.0
    real :: height_dp = 0.0
end type text_node_t

type :: slider_node_t
    character(len=256) :: id = ""
    real :: min_val = 0.0
    real :: max_val = 100.0
    real :: width_dp = 0.0
    real :: height_dp = 0.0
end type slider_node_t

type :: checkbox_node_t
    character(len=256) :: id = ""
    character(len=256) :: label = ""
    logical :: checked = .false.
    real :: width_dp = 0.0
    real :: height_dp = 0.0
end type checkbox_node_t

contains

! Placeholder implementations returning widget nodes
function text(id, value, text_size, width, height) result(widget_node)
    character(*), intent(in) :: id
    character(*), intent(in), optional :: value
    real, intent(in), optional :: text_size, width, height
    type(text_node_t) :: widget_node
    
    widget_node%id = id
    if (present(value)) widget_node%value = value
    if (present(width)) widget_node%width_dp = width
    if (present(height)) widget_node%height_dp = height
end function text

logical function slider(id, min_val, max_val, step_val, value, width, height) result(value_changed)
    character(*), intent(in) :: id
    real, intent(in), optional :: min_val, max_val, step_val
    real, intent(inout), optional :: value
    real, intent(in), optional :: width, height
    
    ! Placeholder - no value change
    value_changed = .false.
end function slider

logical function checkbox(id, checked, label, width, height) result(toggled)
    character(*), intent(in) :: id
    logical, intent(inout), optional :: checked
    character(*), intent(in), optional :: label
    real, intent(in), optional :: width, height
    
    ! Placeholder - no toggle
    toggled = .false.
end function checkbox

function viewport(id, width, height, view_state) result(viewport_node)
    use fortui_core, only: node, view
    character(*), intent(in) :: id
    real, intent(in) :: width, height
    type(view), intent(inout) :: view_state
    type(node) :: viewport_node
    
    ! Placeholder - return empty node
    ! In full implementation would set up viewport properties
end function viewport

end module fortui_widgets