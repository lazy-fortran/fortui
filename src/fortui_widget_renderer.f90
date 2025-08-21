module fortui_widget_renderer
! Widget rendering abstraction for Widget-Renderer Collaboration Pattern
! Provides abstract interface for backend-specific rendering operations
! Issue #61: Eliminates tight coupling between widgets and backends
use fortui_error, only: report_error
implicit none
private

public :: widget_renderer_t, render_context_t, ui_rect, ui_color
public :: WIDGET_NORMAL, WIDGET_HOVER, WIDGET_PRESSED, WIDGET_FOCUSED, WIDGET_DISABLED

! Widget state constants
integer, parameter :: WIDGET_NORMAL = 0
integer, parameter :: WIDGET_HOVER = 1
integer, parameter :: WIDGET_PRESSED = 2
integer, parameter :: WIDGET_FOCUSED = 3
integer, parameter :: WIDGET_DISABLED = 4

! Basic geometric types
type :: ui_rect
    real :: x = 0.0
    real :: y = 0.0
    real :: width = 0.0
    real :: height = 0.0
end type ui_rect

type :: ui_color
    real :: r = 0.0
    real :: g = 0.0
    real :: b = 0.0
    real :: a = 1.0
end type ui_color

! Rendering context with backend-agnostic drawing state
type :: render_context_t
    real :: viewport_x = 0.0
    real :: viewport_y = 0.0
    real :: viewport_w = 800.0
    real :: viewport_h = 600.0
    real :: scale_x = 1.0
    real :: scale_y = 1.0
    logical :: clipping_enabled = .false.
end type render_context_t

! Abstract widget renderer interface
type, abstract :: widget_renderer_t
contains
    ! Primitive drawing operations (backend-specific)
    procedure(draw_rect_interface), deferred :: draw_rectangle
    procedure(draw_text_interface), deferred :: draw_text
    procedure(draw_line_interface), deferred :: draw_line
    procedure(draw_border_interface), deferred :: draw_border
    procedure(set_clip_interface), deferred :: set_clip_region
    procedure(get_text_size_interface), deferred :: get_text_size
    
    ! Composite drawing operations (shared implementations)
    procedure :: draw_button => render_button_default
    procedure :: draw_text_widget => render_text_default
    procedure :: draw_slider => render_slider_default
    procedure :: draw_checkbox => render_checkbox_default
    procedure :: draw_viewport => render_viewport_default
    procedure :: reset => renderer_reset
end type widget_renderer_t

! Abstract interfaces for primitive operations
abstract interface
    subroutine draw_rect_interface(self, x, y, width, height, color)
        import :: widget_renderer_t, ui_color
        class(widget_renderer_t), intent(inout) :: self
        real, intent(in) :: x, y, width, height
        type(ui_color), intent(in) :: color
    end subroutine draw_rect_interface
    
    subroutine draw_text_interface(self, text, x, y, color)
        import :: widget_renderer_t, ui_color
        class(widget_renderer_t), intent(inout) :: self
        character(*), intent(in) :: text
        real, intent(in) :: x, y
        type(ui_color), intent(in) :: color
    end subroutine draw_text_interface
    
    subroutine draw_line_interface(self, x1, y1, x2, y2, color)
        import :: widget_renderer_t, ui_color
        class(widget_renderer_t), intent(inout) :: self
        real, intent(in) :: x1, y1, x2, y2
        type(ui_color), intent(in) :: color
    end subroutine draw_line_interface
    
    subroutine draw_border_interface(self, x, y, width, height, color)
        import :: widget_renderer_t, ui_color
        class(widget_renderer_t), intent(inout) :: self
        real, intent(in) :: x, y, width, height
        type(ui_color), intent(in) :: color
    end subroutine draw_border_interface
    
    subroutine set_clip_interface(self, x, y, width, height)
        import :: widget_renderer_t
        class(widget_renderer_t), intent(inout) :: self
        real, intent(in) :: x, y, width, height
    end subroutine set_clip_interface
    
    subroutine get_text_size_interface(self, text, width, height)
        import :: widget_renderer_t
        class(widget_renderer_t), intent(in) :: self
        character(*), intent(in) :: text
        real, intent(out) :: width, height
    end subroutine get_text_size_interface
end interface

contains

! Default button rendering using primitives
subroutine render_button_default(self, id, label, bounds, visual_state, pressed)
    class(widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id, label
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: pressed
    
    type(ui_color) :: bg_color, text_color, border_color
    real :: text_width, text_height, text_x, text_y
    
    ! Determine colors based on state
    select case(visual_state)
    case(WIDGET_NORMAL)
        bg_color = ui_color(0.8, 0.8, 0.8, 1.0)
        text_color = ui_color(0.0, 0.0, 0.0, 1.0)
        border_color = ui_color(0.5, 0.5, 0.5, 1.0)
    case(WIDGET_HOVER)
        bg_color = ui_color(0.9, 0.9, 0.9, 1.0)
        text_color = ui_color(0.0, 0.0, 0.0, 1.0)
        border_color = ui_color(0.3, 0.3, 0.3, 1.0)
    case(WIDGET_PRESSED)
        bg_color = ui_color(0.7, 0.7, 0.7, 1.0)
        text_color = ui_color(0.0, 0.0, 0.0, 1.0)
        border_color = ui_color(0.2, 0.2, 0.2, 1.0)
    case default
        bg_color = ui_color(0.6, 0.6, 0.6, 1.0)
        text_color = ui_color(0.4, 0.4, 0.4, 1.0)
        border_color = ui_color(0.4, 0.4, 0.4, 1.0)
    end select
    
    ! Draw button background
    call self%draw_rectangle(bounds%x, bounds%y, bounds%width, bounds%height, bg_color)
    
    ! Draw border
    call self%draw_border(bounds%x, bounds%y, bounds%width, bounds%height, border_color)
    
    ! Center and draw text
    call self%get_text_size(label, text_width, text_height)
    text_x = bounds%x + (bounds%width - text_width) * 0.5
    text_y = bounds%y + (bounds%height - text_height) * 0.5
    call self%draw_text(label, text_x, text_y, text_color)
end subroutine render_button_default

! Default text widget rendering
subroutine render_text_default(self, id, text, bounds, visual_state, focused)
    class(widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id, text
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: focused
    
    type(ui_color) :: text_color
    
    select case(visual_state)
    case(WIDGET_FOCUSED)
        text_color = ui_color(0.0, 0.0, 1.0, 1.0)
    case default
        text_color = ui_color(0.0, 0.0, 0.0, 1.0)
    end select
    
    call self%draw_text(text, bounds%x, bounds%y, text_color)
end subroutine render_text_default

! Default slider rendering
subroutine render_slider_default(self, id, bounds, visual_state, dragging, value)
    class(widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: dragging
    real, intent(in) :: value
    
    type(ui_color) :: track_color, knob_color
    real :: knob_x, knob_width
    
    ! Track colors
    track_color = ui_color(0.6, 0.6, 0.6, 1.0)
    
    select case(visual_state)
    case(WIDGET_PRESSED)
        knob_color = ui_color(0.2, 0.4, 0.8, 1.0)
    case(WIDGET_HOVER)
        knob_color = ui_color(0.3, 0.5, 0.9, 1.0)
    case default
        knob_color = ui_color(0.4, 0.6, 1.0, 1.0)
    end select
    
    ! Draw track
    call self%draw_rectangle(bounds%x, bounds%y + bounds%height * 0.4, &
                           bounds%width, bounds%height * 0.2, track_color)
    
    ! Draw knob
    knob_width = bounds%height * 0.8
    knob_x = bounds%x + (bounds%width - knob_width) * value
    call self%draw_rectangle(knob_x, bounds%y + bounds%height * 0.1, &
                           knob_width, knob_width, knob_color)
end subroutine render_slider_default

! Default checkbox rendering
subroutine render_checkbox_default(self, id, label, bounds, visual_state, hover, checked)
    class(widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id, label
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: hover, checked
    
    type(ui_color) :: box_color, check_color, text_color, border_color
    real :: box_size, label_x
    
    box_size = min(bounds%height * 0.8, 20.0)
    
    select case(visual_state)
    case(WIDGET_HOVER)
        box_color = ui_color(0.95, 0.95, 0.95, 1.0)
        border_color = ui_color(0.3, 0.3, 0.3, 1.0)
    case default
        box_color = ui_color(1.0, 1.0, 1.0, 1.0)
        border_color = ui_color(0.5, 0.5, 0.5, 1.0)
    end select
    
    check_color = ui_color(0.0, 0.7, 0.0, 1.0)
    text_color = ui_color(0.0, 0.0, 0.0, 1.0)
    
    ! Draw checkbox box
    call self%draw_rectangle(bounds%x, bounds%y + (bounds%height - box_size) * 0.5, &
                           box_size, box_size, box_color)
    call self%draw_border(bounds%x, bounds%y + (bounds%height - box_size) * 0.5, &
                         box_size, box_size, border_color)
    
    ! Draw checkmark if checked
    if (checked) then
        call self%draw_text("X", bounds%x + box_size * 0.25, &
                          bounds%y + (bounds%height - box_size) * 0.5, check_color)
    end if
    
    ! Draw label
    label_x = bounds%x + box_size + 8.0
    call self%draw_text(label, label_x, bounds%y, text_color)
end subroutine render_checkbox_default

! Default viewport rendering
subroutine render_viewport_default(self, id, bounds, visual_state, active)
    class(widget_renderer_t), intent(inout) :: self
    character(*), intent(in) :: id
    type(ui_rect), intent(in) :: bounds
    integer, intent(in) :: visual_state
    logical, intent(in) :: active
    
    type(ui_color) :: bg_color, border_color
    
    if (active) then
        bg_color = ui_color(0.9, 0.9, 1.0, 1.0)
        border_color = ui_color(0.0, 0.0, 0.5, 1.0)
    else
        bg_color = ui_color(0.95, 0.95, 0.95, 1.0)
        border_color = ui_color(0.7, 0.7, 0.7, 1.0)
    end if
    
    call self%draw_rectangle(bounds%x, bounds%y, bounds%width, bounds%height, bg_color)
    call self%draw_border(bounds%x, bounds%y, bounds%width, bounds%height, border_color)
end subroutine render_viewport_default

! Reset renderer state (for testing/mocking)
subroutine renderer_reset(self)
    class(widget_renderer_t), intent(inout) :: self
    ! Base implementation does nothing - subclasses can override
end subroutine renderer_reset

end module fortui_widget_renderer