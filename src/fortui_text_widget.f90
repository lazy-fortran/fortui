module fortui_text_widget
! Text widget implementation for Widget-Renderer Collaboration Pattern
! Concrete implementation of renderable widget interface for text display
! Issue #61: Encapsulates text widget behavior and state management
use fortui_renderable
use fortui_widget_renderer, only: widget_renderer_t, render_context_t, ui_rect
implicit none
private

public :: text_widget_t, text_state_t

! Text-specific state extending abstract widget state
type, extends(widget_state_t) :: text_state_t
    character(len=256) :: text = ""
    logical :: focused = .false.
end type text_state_t

! Text widget implementation
type, extends(renderable_widget_t) :: text_widget_t
    real :: x = 0.0
    real :: y = 0.0
    real :: width = 200.0
    real :: height = 20.0
    character(len=256) :: text = ""
contains
    procedure :: render => text_render
    procedure :: update_state => text_update_state
    procedure :: get_bounds => text_get_bounds
    procedure :: hit_test => text_hit_test
    procedure :: reset => text_reset
end type text_widget_t

contains

subroutine text_render(self, renderer, context, state)
    class(text_widget_t), intent(in) :: self
    class(widget_renderer_t), intent(inout) :: renderer
    type(render_context_t), intent(in) :: context
    class(widget_state_t), intent(in) :: state
    
    type(ui_rect) :: bounds
    
    select type(txt_state => state)
    type is (text_state_t)
        ! Get widget bounds
        call self%get_bounds(bounds)
        
        ! Use renderer's text drawing implementation
        call renderer%draw_text_widget(txt_state%id, txt_state%text, bounds, &
                                      txt_state%visual_state, txt_state%focused)
    end select
end subroutine text_render

subroutine text_update_state(self, mouse_x, mouse_y, mouse_pressed, state)
    class(text_widget_t), intent(in) :: self
    real, intent(in) :: mouse_x, mouse_y
    logical, intent(in) :: mouse_pressed
    class(widget_state_t), intent(inout) :: state
    
    logical :: hit
    
    select type(txt_state => state)
    type is (text_state_t)
        hit = self%hit_test(mouse_x, mouse_y)
        
        ! Text widgets can be focused on click
        if (hit .and. mouse_pressed) then
            txt_state%focused = .true.
            txt_state%visual_state = WIDGET_FOCUSED
        else if (.not. hit .and. mouse_pressed) then
            txt_state%focused = .false.
            txt_state%visual_state = WIDGET_NORMAL
        else if (hit .and. .not. mouse_pressed) then
            txt_state%visual_state = WIDGET_HOVER
        else
            txt_state%visual_state = WIDGET_NORMAL
        end if
    end select
end subroutine text_update_state

subroutine text_get_bounds(self, bounds)
    class(text_widget_t), intent(in) :: self
    type(ui_rect), intent(out) :: bounds
    
    bounds%x = self%x
    bounds%y = self%y
    bounds%width = self%width
    bounds%height = self%height
end subroutine text_get_bounds

logical function text_hit_test(self, x, y) result(hit)
    class(text_widget_t), intent(in) :: self
    real, intent(in) :: x, y
    
    hit = (x >= self%x .and. x <= self%x + self%width .and. &
           y >= self%y .and. y <= self%y + self%height)
end function text_hit_test

subroutine text_reset(self)
    class(text_widget_t), intent(inout) :: self
    ! Reset method for testing
end subroutine text_reset

end module fortui_text_widget