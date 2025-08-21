module fortui_slider_widget
! Slider widget implementation for Widget-Renderer Collaboration Pattern
! Concrete implementation of renderable widget interface for sliders
! Issue #61: Encapsulates slider behavior and state management
use fortui_renderable
use fortui_widget_renderer, only: widget_renderer_t, render_context_t, ui_rect
implicit none
private

public :: slider_widget_t, slider_state_t

! Slider-specific state extending abstract widget state
type, extends(widget_state_t) :: slider_state_t
    real :: value = 0.0
    real :: min_value = 0.0
    real :: max_value = 1.0
    logical :: dragging = .false.
    logical :: value_changed = .false.
end type slider_state_t

! Slider widget implementation
type, extends(renderable_widget_t) :: slider_widget_t
    real :: x = 0.0
    real :: y = 0.0
    real :: width = 150.0
    real :: height = 24.0
contains
    procedure :: render => slider_render
    procedure :: update_state => slider_update_state
    procedure :: get_bounds => slider_get_bounds
    procedure :: hit_test => slider_hit_test
    procedure :: reset => slider_reset
end type slider_widget_t

contains

subroutine slider_render(self, renderer, context, state)
    class(slider_widget_t), intent(in) :: self
    class(widget_renderer_t), intent(inout) :: renderer
    type(render_context_t), intent(in) :: context
    class(widget_state_t), intent(in) :: state
    
    type(ui_rect) :: bounds
    real :: normalized_value
    
    select type(sld_state => state)
    type is (slider_state_t)
        ! Get widget bounds
        call self%get_bounds(bounds)
        
        ! Normalize value for rendering
        if (abs(sld_state%max_value - sld_state%min_value) > 1e-6) then
            normalized_value = (sld_state%value - sld_state%min_value) / &
                              (sld_state%max_value - sld_state%min_value)
        else
            normalized_value = 0.0
        end if
        
        normalized_value = max(0.0, min(1.0, normalized_value))
        
        ! Use renderer's slider drawing implementation
        call renderer%draw_slider(sld_state%id, bounds, sld_state%visual_state, &
                                 sld_state%dragging, normalized_value)
    end select
end subroutine slider_render

subroutine slider_update_state(self, mouse_x, mouse_y, mouse_pressed, state)
    class(slider_widget_t), intent(in) :: self
    real, intent(in) :: mouse_x, mouse_y
    logical, intent(in) :: mouse_pressed
    class(widget_state_t), intent(inout) :: state
    
    logical :: hit
    real :: new_value, relative_x
    
    select type(sld_state => state)
    type is (slider_state_t)
        hit = self%hit_test(mouse_x, mouse_y)
        sld_state%value_changed = .false.
        
        ! Handle dragging state
        if (hit .and. mouse_pressed .and. .not. sld_state%dragging) then
            ! Start dragging
            sld_state%dragging = .true.
            sld_state%visual_state = WIDGET_PRESSED
        else if (.not. mouse_pressed) then
            ! End dragging
            sld_state%dragging = .false.
            if (hit) then
                sld_state%visual_state = WIDGET_HOVER
            else
                sld_state%visual_state = WIDGET_NORMAL
            end if
        end if
        
        ! Update value during drag
        if (sld_state%dragging .and. self%width > 1e-6) then
            relative_x = (mouse_x - self%x) / self%width
            relative_x = max(0.0, min(1.0, relative_x))
            
            new_value = sld_state%min_value + relative_x * &
                       (sld_state%max_value - sld_state%min_value)
            
            if (abs(new_value - sld_state%value) > 1e-6) then
                sld_state%value = new_value
                sld_state%value_changed = .true.
            end if
        end if
        
        ! Update visual state when not dragging
        if (.not. sld_state%dragging) then
            if (hit) then
                sld_state%visual_state = WIDGET_HOVER
            else
                sld_state%visual_state = WIDGET_NORMAL
            end if
        end if
    end select
end subroutine slider_update_state

subroutine slider_get_bounds(self, bounds)
    class(slider_widget_t), intent(in) :: self
    type(ui_rect), intent(out) :: bounds
    
    bounds%x = self%x
    bounds%y = self%y
    bounds%width = self%width
    bounds%height = self%height
end subroutine slider_get_bounds

logical function slider_hit_test(self, x, y) result(hit)
    class(slider_widget_t), intent(in) :: self
    real, intent(in) :: x, y
    
    hit = (x >= self%x .and. x <= self%x + self%width .and. &
           y >= self%y .and. y <= self%y + self%height)
end function slider_hit_test

subroutine slider_reset(self)
    class(slider_widget_t), intent(inout) :: self
    ! Reset method for testing
end subroutine slider_reset

end module fortui_slider_widget