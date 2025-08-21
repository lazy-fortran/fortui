module fortui_renderable
! Widget rendering contract for Widget-Renderer Collaboration Pattern
! Defines abstract interface for renderable widgets with state management
! Issue #61: Establishes proper widget behavior encapsulation
use fortui_widget_renderer, only: widget_renderer_t, render_context_t, ui_rect
use fortui_widget_renderer, only: WIDGET_NORMAL, WIDGET_HOVER, WIDGET_PRESSED, WIDGET_FOCUSED, WIDGET_DISABLED
implicit none
private

public :: renderable_widget_t, widget_state_t
public :: WIDGET_NORMAL, WIDGET_HOVER, WIDGET_PRESSED, WIDGET_FOCUSED, WIDGET_DISABLED

! Abstract widget state base class
type, abstract :: widget_state_t
    character(len=256) :: id = ""
    integer :: visual_state = WIDGET_NORMAL
    logical :: visible = .true.
    logical :: interactive = .true.
end type widget_state_t

! Abstract renderable widget interface
type, abstract :: renderable_widget_t
contains
    procedure(render_interface), deferred :: render
    procedure(update_state_interface), deferred :: update_state
    procedure(get_bounds_interface), deferred :: get_bounds
    procedure(hit_test_interface), deferred :: hit_test
end type renderable_widget_t

! Abstract interfaces for widget behavior
abstract interface
    subroutine render_interface(self, renderer, context, state)
        import :: renderable_widget_t, widget_renderer_t, render_context_t, widget_state_t
        class(renderable_widget_t), intent(in) :: self
        class(widget_renderer_t), intent(inout) :: renderer
        type(render_context_t), intent(in) :: context
        class(widget_state_t), intent(in) :: state
    end subroutine render_interface
    
    subroutine update_state_interface(self, mouse_x, mouse_y, mouse_pressed, state)
        import :: renderable_widget_t, widget_state_t
        class(renderable_widget_t), intent(in) :: self
        real, intent(in) :: mouse_x, mouse_y
        logical, intent(in) :: mouse_pressed
        class(widget_state_t), intent(inout) :: state
    end subroutine update_state_interface
    
    subroutine get_bounds_interface(self, bounds)
        import :: renderable_widget_t, ui_rect
        class(renderable_widget_t), intent(in) :: self
        type(ui_rect), intent(out) :: bounds
    end subroutine get_bounds_interface
    
    logical function hit_test_interface(self, x, y) result(hit)
        import :: renderable_widget_t
        class(renderable_widget_t), intent(in) :: self
        real, intent(in) :: x, y
    end function hit_test_interface
end interface

end module fortui_renderable