module fortui_checkbox_widget
! Checkbox widget implementation for Widget-Renderer Collaboration Pattern
! Concrete implementation of renderable widget interface for checkboxes
! Issue #61: Encapsulates checkbox behavior and state management
use fortui_renderable
use fortui_widget_renderer, only: widget_renderer_t, render_context_t, ui_rect
implicit none
private

public :: checkbox_widget_t, checkbox_state_t

! Checkbox-specific state extending abstract widget state
type, extends(widget_state_t) :: checkbox_state_t
    character(len=256) :: label = ""
    logical :: checked = .false.
    logical :: clicked_this_frame = .false.
    logical :: was_pressed_last_frame = .false.
end type checkbox_state_t

! Checkbox widget implementation
type, extends(renderable_widget_t) :: checkbox_widget_t
    real :: x = 0.0
    real :: y = 0.0
    real :: width = 120.0
    real :: height = 24.0
    character(len=256) :: label = ""
contains
    procedure :: render => checkbox_render
    procedure :: update_state => checkbox_update_state
    procedure :: get_bounds => checkbox_get_bounds
    procedure :: hit_test => checkbox_hit_test
    procedure :: reset => checkbox_reset
end type checkbox_widget_t

contains

subroutine checkbox_render(self, renderer, context, state)
    class(checkbox_widget_t), intent(in) :: self
    class(widget_renderer_t), intent(inout) :: renderer
    type(render_context_t), intent(in) :: context
    class(widget_state_t), intent(in) :: state
    
    type(ui_rect) :: bounds
    logical :: hover
    
    select type(chk_state => state)
    type is (checkbox_state_t)
        ! Get widget bounds
        call self%get_bounds(bounds)
        
        ! Determine hover state
        hover = (chk_state%visual_state == WIDGET_HOVER .or. &
                chk_state%visual_state == WIDGET_PRESSED)
        
        ! Use renderer's checkbox drawing implementation
        call renderer%draw_checkbox(chk_state%id, chk_state%label, bounds, &
                                   chk_state%visual_state, hover, chk_state%checked)
    end select
end subroutine checkbox_render

subroutine checkbox_update_state(self, mouse_x, mouse_y, mouse_pressed, state)
    class(checkbox_widget_t), intent(in) :: self
    real, intent(in) :: mouse_x, mouse_y
    logical, intent(in) :: mouse_pressed
    class(widget_state_t), intent(inout) :: state
    
    logical :: hit, was_pressed
    
    select type(chk_state => state)
    type is (checkbox_state_t)
        was_pressed = chk_state%was_pressed_last_frame
        hit = self%hit_test(mouse_x, mouse_y)
        
        ! Update visual state based on mouse interaction
        if (.not. hit) then
            chk_state%visual_state = WIDGET_NORMAL
        else if (mouse_pressed) then
            chk_state%visual_state = WIDGET_PRESSED
        else
            chk_state%visual_state = WIDGET_HOVER
        end if
        
        ! Detect click and toggle checked state
        chk_state%clicked_this_frame = was_pressed .and. .not. mouse_pressed .and. hit
        if (chk_state%clicked_this_frame) then
            chk_state%checked = .not. chk_state%checked
        end if
        
        chk_state%was_pressed_last_frame = mouse_pressed .and. hit
    end select
end subroutine checkbox_update_state

subroutine checkbox_get_bounds(self, bounds)
    class(checkbox_widget_t), intent(in) :: self
    type(ui_rect), intent(out) :: bounds
    
    bounds%x = self%x
    bounds%y = self%y
    bounds%width = self%width
    bounds%height = self%height
end subroutine checkbox_get_bounds

logical function checkbox_hit_test(self, x, y) result(hit)
    class(checkbox_widget_t), intent(in) :: self
    real, intent(in) :: x, y
    
    hit = (x >= self%x .and. x <= self%x + self%width .and. &
           y >= self%y .and. y <= self%y + self%height)
end function checkbox_hit_test

subroutine checkbox_reset(self)
    class(checkbox_widget_t), intent(inout) :: self
    ! Reset method for testing
end subroutine checkbox_reset

end module fortui_checkbox_widget