module fortui_widget_renderer
! Widget rendering abstraction for Widget-Renderer Collaboration Pattern
! Provides abstract interface for backend-specific rendering operations
! Issue #61: Eliminates tight coupling between widgets and backends
use fortui_error, only: report_error
use iso_c_binding
implicit none
private

public :: render_context_t, ui_rect, ui_color
! renderer_t is internal - not exposed to users
public :: WIDGET_NORMAL, WIDGET_HOVER, WIDGET_PRESSED, WIDGET_FOCUSED, WIDGET_DISABLED
! Export procedure interfaces
public :: draw_rect_proc, draw_text_proc, draw_line_proc, draw_border_proc
public :: set_clip_proc, get_text_size_proc

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

! Concrete renderer type with procedure pointers (no polymorphism)
type :: renderer_t
    ! Renderer type discriminator
    integer :: renderer_type = 0  ! 0=none, 1=tui, 2=gui
    ! Procedure pointers for primitive drawing operations
    procedure(draw_rect_proc), pointer, nopass :: draw_rectangle => null()
    procedure(draw_text_proc), pointer, nopass :: draw_text => null()
    procedure(draw_line_proc), pointer, nopass :: draw_line => null()
    procedure(draw_border_proc), pointer, nopass :: draw_border => null()
    procedure(set_clip_proc), pointer, nopass :: set_clip_region => null()
    procedure(get_text_size_proc), pointer, nopass :: get_text_size => null()
    ! Renderer-specific data pointer
    type(c_ptr) :: renderer_data = c_null_ptr
contains
    ! Composite drawing operations (shared implementations)
    procedure :: draw_button => render_button_default
    procedure :: draw_text_widget => render_text_default
    procedure :: draw_slider => render_slider_default
    procedure :: draw_checkbox => render_checkbox_default
    procedure :: draw_viewport => render_viewport_default
    procedure :: reset => renderer_reset
end type renderer_t

! Procedural interfaces for primitive operations (no polymorphism)
interface
    subroutine draw_rect_proc(renderer_data, x, y, width, height, color)
        import :: c_ptr, ui_color
        type(c_ptr), intent(inout) :: renderer_data
        real, intent(in) :: x, y, width, height
        type(ui_color), intent(in) :: color
    end subroutine draw_rect_proc
    
    subroutine draw_text_proc(renderer_data, text, x, y, color)
        import :: c_ptr, ui_color
        type(c_ptr), intent(inout) :: renderer_data
        character(*), intent(in) :: text
        real, intent(in) :: x, y
        type(ui_color), intent(in) :: color
    end subroutine draw_text_proc
    
    subroutine draw_line_proc(renderer_data, x1, y1, x2, y2, color)
        import :: c_ptr, ui_color
        type(c_ptr), intent(inout) :: renderer_data
        real, intent(in) :: x1, y1, x2, y2
        type(ui_color), intent(in) :: color
    end subroutine draw_line_proc
    
    subroutine draw_border_proc(renderer_data, x, y, width, height, color)
        import :: c_ptr, ui_color
        type(c_ptr), intent(inout) :: renderer_data
        real, intent(in) :: x, y, width, height
        type(ui_color), intent(in) :: color
    end subroutine draw_border_proc
    
    subroutine set_clip_proc(renderer_data, x, y, width, height)
        import :: c_ptr
        type(c_ptr), intent(inout) :: renderer_data
        real, intent(in) :: x, y, width, height
    end subroutine set_clip_proc
    
    subroutine get_text_size_proc(renderer_data, text, width, height)
        import :: c_ptr
        type(c_ptr), intent(in) :: renderer_data
        character(*), intent(in) :: text
        real, intent(out) :: width, height
    end subroutine get_text_size_proc
end interface

contains

! Default button rendering using primitives
subroutine render_button_default(self, id, label, bounds, visual_state, pressed)
    class(renderer_t), intent(inout) :: self
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
    if (associated(self%draw_rectangle)) then
        call self%draw_rectangle(self%renderer_data, bounds%x, bounds%y, &
                                bounds%width, bounds%height, bg_color)
    end if
    
    ! Draw border
    if (associated(self%draw_border)) then
        call self%draw_border(self%renderer_data, bounds%x, bounds%y, &
                             bounds%width, bounds%height, border_color)
    end if
    
    ! Center and draw text
    if (associated(self%get_text_size)) then
        call self%get_text_size(self%renderer_data, label, text_width, text_height)
    else
        text_width = real(len_trim(label)) * 8.0  ! Fallback estimate
        text_height = 16.0
    end if
    text_x = bounds%x + (bounds%width - text_width) * 0.5
    text_y = bounds%y + (bounds%height - text_height) * 0.5
    
    if (associated(self%draw_text)) then
        call self%draw_text(self%renderer_data, label, text_x, text_y, text_color)
    end if
end subroutine render_button_default

! Default text widget rendering
subroutine render_text_default(self, id, text, bounds, visual_state, focused)
    class(renderer_t), intent(inout) :: self
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
    
    if (associated(self%draw_text)) then
        call self%draw_text(self%renderer_data, text, bounds%x, bounds%y, text_color)
    end if
end subroutine render_text_default

! Default slider rendering
subroutine render_slider_default(self, id, bounds, visual_state, dragging, value)
    class(renderer_t), intent(inout) :: self
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
    if (associated(self%draw_rectangle)) then
        call self%draw_rectangle(self%renderer_data, &
                               bounds%x, bounds%y + bounds%height * 0.4, &
                               bounds%width, bounds%height * 0.2, track_color)
    end if
    
    ! Draw knob
    knob_width = bounds%height * 0.8
    knob_x = bounds%x + (bounds%width - knob_width) * value
    if (associated(self%draw_rectangle)) then
        call self%draw_rectangle(self%renderer_data, &
                               knob_x, bounds%y + bounds%height * 0.1, &
                               knob_width, knob_width, knob_color)
    end if
end subroutine render_slider_default

! Default checkbox rendering
subroutine render_checkbox_default(self, id, label, bounds, visual_state, hover, checked)
    class(renderer_t), intent(inout) :: self
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
    if (associated(self%draw_rectangle)) then
        call self%draw_rectangle(self%renderer_data, &
                               bounds%x, bounds%y + (bounds%height - box_size) * 0.5, &
                               box_size, box_size, box_color)
    end if
    if (associated(self%draw_border)) then
        call self%draw_border(self%renderer_data, &
                             bounds%x, bounds%y + (bounds%height - box_size) * 0.5, &
                             box_size, box_size, border_color)
    end if
    
    ! Draw checkmark if checked
    if (checked .and. associated(self%draw_text)) then
        call self%draw_text(self%renderer_data, "X", bounds%x + box_size * 0.25, &
                          bounds%y + (bounds%height - box_size) * 0.5, check_color)
    end if
    
    ! Draw label
    label_x = bounds%x + box_size + 8.0
    if (associated(self%draw_text)) then
        call self%draw_text(self%renderer_data, label, label_x, bounds%y, text_color)
    end if
end subroutine render_checkbox_default

! Default viewport rendering
subroutine render_viewport_default(self, id, bounds, visual_state, active)
    class(renderer_t), intent(inout) :: self
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
    
    if (associated(self%draw_rectangle)) then
        call self%draw_rectangle(self%renderer_data, &
                               bounds%x, bounds%y, bounds%width, bounds%height, bg_color)
    end if
    if (associated(self%draw_border)) then
        call self%draw_border(self%renderer_data, &
                             bounds%x, bounds%y, bounds%width, bounds%height, border_color)
    end if
end subroutine render_viewport_default

! Reset renderer state (for testing/mocking)
subroutine renderer_reset(self)
    class(renderer_t), intent(inout) :: self
    ! Reset procedure pointers and data
    self%draw_rectangle => null()
    self%draw_text => null()
    self%draw_line => null()
    self%draw_border => null()
    self%set_clip_region => null()
    self%get_text_size => null()
    self%renderer_data = c_null_ptr
    self%renderer_type = 0
end subroutine renderer_reset

end module fortui_widget_renderer