module fortui_button_widget
! Button widget implementation for Widget-Renderer Collaboration Pattern
! Concrete implementation of renderable widget interface for buttons
! Issue #61: Encapsulates button behavior and state management
use fortui_renderable
use fortui_widget_renderer, only: widget_renderer_t, render_context_t, ui_rect
implicit none
private

public :: button_widget_t, button_state_t

! Button-specific state extending abstract widget state
type, extends(widget_state_t) :: button_state_t
    character(len=256) :: label = ""
    logical :: clicked_this_frame = .false.
    logical :: was_pressed_last_frame = .false.
end type button_state_t

! Button widget implementation
type, extends(renderable_widget_t) :: button_widget_t
    real :: x = 0.0
    real :: y = 0.0
    real :: width = 100.0
    real :: height = 30.0
    character(len=256) :: label = ""
contains
    procedure :: render => button_render
    procedure :: update_state => button_update_state
    procedure :: get_bounds => button_get_bounds
    procedure :: hit_test => button_hit_test
    procedure :: reset => button_reset
end type button_widget_t

contains

subroutine button_render(self, renderer, context, state)
    class(button_widget_t), intent(in) :: self
    class(widget_renderer_t), intent(inout) :: renderer
    type(render_context_t), intent(in) :: context
    class(widget_state_t), intent(in) :: state
    
    type(ui_rect) :: bounds
    
    select type(btn_state => state)
    type is (button_state_t)
        ! Get widget bounds
        call self%get_bounds(bounds)
        
        ! Use renderer's button drawing implementation
        call renderer%draw_button(btn_state%id, btn_state%label, bounds, &
                                 btn_state%visual_state, btn_state%clicked_this_frame)
    end select
end subroutine button_render

subroutine button_update_state(self, mouse_x, mouse_y, mouse_pressed, state)
    class(button_widget_t), intent(in) :: self
    real, intent(in) :: mouse_x, mouse_y
    logical, intent(in) :: mouse_pressed
    class(widget_state_t), intent(inout) :: state
    
    logical :: hit, was_pressed
    
    select type(btn_state => state)
    type is (button_state_t)
        was_pressed = btn_state%was_pressed_last_frame
        hit = self%hit_test(mouse_x, mouse_y)
        
        ! Update visual state based on mouse interaction
        if (.not. hit) then
            btn_state%visual_state = WIDGET_NORMAL
        else if (mouse_pressed) then
            btn_state%visual_state = WIDGET_PRESSED
        else
            btn_state%visual_state = WIDGET_HOVER
        end if
        
        ! Detect click (release over button after press)
        btn_state%clicked_this_frame = was_pressed .and. .not. mouse_pressed .and. hit
        btn_state%was_pressed_last_frame = mouse_pressed .and. hit
    end select
end subroutine button_update_state

subroutine button_get_bounds(self, bounds)
    class(button_widget_t), intent(in) :: self
    type(ui_rect), intent(out) :: bounds
    
    bounds%x = self%x
    bounds%y = self%y
    bounds%width = self%width
    bounds%height = self%height
end subroutine button_get_bounds

logical function button_hit_test(self, x, y) result(hit)
    class(button_widget_t), intent(in) :: self
    real, intent(in) :: x, y
    
    hit = (x >= self%x .and. x <= self%x + self%width .and. &
           y >= self%y .and. y <= self%y + self%height)
end function button_hit_test

subroutine button_reset(self)
    class(button_widget_t), intent(inout) :: self
    ! Reset method for testing - could reset internal state if needed
end subroutine button_reset

end module fortui_button_widget