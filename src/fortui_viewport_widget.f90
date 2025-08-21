module fortui_viewport_widget
! Viewport widget implementation for Widget-Renderer Collaboration Pattern
! Concrete implementation of renderable widget interface for viewports
! Issue #61: Encapsulates viewport behavior and state management
use fortui_renderable
use fortui_widget_renderer, only: widget_renderer_t, render_context_t, ui_rect
implicit none
private

public :: viewport_widget_t, viewport_state_t

! Viewport-specific state extending abstract widget state
type, extends(widget_state_t) :: viewport_state_t
    logical :: active = .false.
    logical :: dragging = .false.
    real :: drag_start_x = 0.0
    real :: drag_start_y = 0.0
    real :: pan_x = 0.0
    real :: pan_y = 0.0
    real :: zoom = 1.0
end type viewport_state_t

! Viewport widget implementation
type, extends(renderable_widget_t) :: viewport_widget_t
    real :: x = 0.0
    real :: y = 0.0
    real :: width = 300.0
    real :: height = 200.0
contains
    procedure :: render => viewport_render
    procedure :: update_state => viewport_update_state
    procedure :: get_bounds => viewport_get_bounds
    procedure :: hit_test => viewport_hit_test
    procedure :: reset => viewport_reset
end type viewport_widget_t

contains

subroutine viewport_render(self, renderer, context, state)
    class(viewport_widget_t), intent(in) :: self
    class(widget_renderer_t), intent(inout) :: renderer
    type(render_context_t), intent(in) :: context
    class(widget_state_t), intent(in) :: state
    
    type(ui_rect) :: bounds
    
    select type(vp_state => state)
    type is (viewport_state_t)
        ! Get widget bounds
        call self%get_bounds(bounds)
        
        ! Use renderer's viewport drawing implementation
        call renderer%draw_viewport(vp_state%id, bounds, vp_state%visual_state, &
                                   vp_state%active)
    end select
end subroutine viewport_render

subroutine viewport_update_state(self, mouse_x, mouse_y, mouse_pressed, state)
    class(viewport_widget_t), intent(in) :: self
    real, intent(in) :: mouse_x, mouse_y
    logical, intent(in) :: mouse_pressed
    class(widget_state_t), intent(inout) :: state
    
    logical :: hit
    
    select type(vp_state => state)
    type is (viewport_state_t)
        hit = self%hit_test(mouse_x, mouse_y)
        
        ! Update active state based on hit
        vp_state%active = hit
        
        ! Handle dragging for panning
        if (hit .and. mouse_pressed .and. .not. vp_state%dragging) then
            ! Start drag
            vp_state%dragging = .true.
            vp_state%drag_start_x = mouse_x
            vp_state%drag_start_y = mouse_y
            vp_state%visual_state = WIDGET_PRESSED
        else if (vp_state%dragging .and. mouse_pressed) then
            ! Continue drag - update pan offset
            vp_state%pan_x = vp_state%pan_x + (mouse_x - vp_state%drag_start_x)
            vp_state%pan_y = vp_state%pan_y + (mouse_y - vp_state%drag_start_y)
            vp_state%drag_start_x = mouse_x
            vp_state%drag_start_y = mouse_y
        else if (vp_state%dragging .and. .not. mouse_pressed) then
            ! End drag
            vp_state%dragging = .false.
            if (hit) then
                vp_state%visual_state = WIDGET_HOVER
            else
                vp_state%visual_state = WIDGET_NORMAL
            end if
        end if
        
        ! Update visual state when not dragging
        if (.not. vp_state%dragging) then
            if (hit) then
                vp_state%visual_state = WIDGET_HOVER
            else
                vp_state%visual_state = WIDGET_NORMAL
            end if
        end if
    end select
end subroutine viewport_update_state

subroutine viewport_get_bounds(self, bounds)
    class(viewport_widget_t), intent(in) :: self
    type(ui_rect), intent(out) :: bounds
    
    bounds%x = self%x
    bounds%y = self%y
    bounds%width = self%width
    bounds%height = self%height
end subroutine viewport_get_bounds

logical function viewport_hit_test(self, x, y) result(hit)
    class(viewport_widget_t), intent(in) :: self
    real, intent(in) :: x, y
    
    hit = (x >= self%x .and. x <= self%x + self%width .and. &
           y >= self%y .and. y <= self%y + self%height)
end function viewport_hit_test

subroutine viewport_reset(self)
    class(viewport_widget_t), intent(inout) :: self
    ! Reset method for testing
end subroutine viewport_reset

end module fortui_viewport_widget