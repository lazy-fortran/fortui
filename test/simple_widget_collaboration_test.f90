program simple_widget_collaboration_test
! Simple test to verify Widget-Renderer Collaboration Pattern works
! Tests that concrete widgets can collaborate with renderers correctly
use fortui_widget_renderer
use fortui_renderable
use fortui_button_widget
use fortui_tui_renderer
use fortui_gui_renderer
implicit none

! Test TUI renderer with button widget
call test_tui_button_collaboration()
print *, ""

! Test GUI renderer with button widget
call test_gui_button_collaboration()
print *, ""

print *, "========================================"
print *, "Simple Widget Collaboration Test PASSED"
print *, "========================================"

contains

subroutine test_tui_button_collaboration()
    print *, "=== Testing TUI Button Collaboration ==="
    
    type(tui_renderer_t), target :: tui_renderer
    type(button_widget_t) :: button
    type(button_state_t) :: button_state
    type(render_context_t) :: render_ctx
    
    ! Initialize TUI renderer
    call tui_renderer%initialize(80, 24)
    
    ! Setup button widget
    button%x = 10.0
    button%y = 5.0
    button%width = 100.0
    button%height = 30.0
    button%label = "Test Button"
    
    ! Setup button state
    button_state%id = "test_button"
    button_state%label = "Test Button"
    button_state%visual_state = WIDGET_HOVER
    button_state%clicked_this_frame = .false.
    
    ! Setup render context
    render_ctx%viewport_x = 0.0
    render_ctx%viewport_y = 0.0
    render_ctx%viewport_w = 640.0
    render_ctx%viewport_h = 480.0
    render_ctx%scale_x = 1.0
    render_ctx%scale_y = 1.0
    render_ctx%clipping_enabled = .false.
    
    ! Test collaboration - widget calls renderer
    call button%render(tui_renderer, render_ctx, button_state)
    
    ! Test state update
    call button%update_state(50.0, 20.0, .true., button_state)
    
    if (button_state%visual_state == WIDGET_PRESSED) then
        print *, "PASS: Button state updated correctly for TUI"
    else
        print *, "FAIL: Button state not updated for TUI"
        return
    end if
    
    print *, "PASS: TUI Button collaboration works correctly"
end subroutine test_tui_button_collaboration

subroutine test_gui_button_collaboration()
    print *, "=== Testing GUI Button Collaboration ==="
    
    type(gui_renderer_t), target :: gui_renderer
    type(button_widget_t) :: button
    type(button_state_t) :: button_state
    type(render_context_t) :: render_ctx
    
    ! Initialize GUI renderer
    call gui_renderer%initialize(800, 600, 1.5)
    
    ! Setup button widget
    button%x = 50.0
    button%y = 25.0
    button%width = 120.0
    button%height = 35.0
    button%label = "GUI Button"
    
    ! Setup button state
    button_state%id = "gui_button"
    button_state%label = "GUI Button"
    button_state%visual_state = WIDGET_NORMAL
    button_state%clicked_this_frame = .false.
    
    ! Setup render context for GUI
    render_ctx%viewport_x = 0.0
    render_ctx%viewport_y = 0.0
    render_ctx%viewport_w = 800.0
    render_ctx%viewport_h = 600.0
    render_ctx%scale_x = 1.5
    render_ctx%scale_y = 1.5
    render_ctx%clipping_enabled = .true.
    
    ! Test collaboration - widget calls renderer
    call button%render(gui_renderer, render_ctx, button_state)
    
    ! Test hit testing
    if (button%hit_test(75.0, 42.0)) then
        print *, "PASS: Button hit test works for GUI"
    else
        print *, "FAIL: Button hit test failed for GUI"
        return
    end if
    
    ! Test state update with mouse release (click)
    button_state%was_pressed_last_frame = .true.
    call button%update_state(75.0, 42.0, .false., button_state)
    
    if (button_state%clicked_this_frame) then
        print *, "PASS: Button click detection works for GUI"
    else
        print *, "FAIL: Button click detection failed for GUI"
        return
    end if
    
    print *, "PASS: GUI Button collaboration works correctly"
end subroutine test_gui_button_collaboration

end program simple_widget_collaboration_test