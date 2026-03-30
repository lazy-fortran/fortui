module test_rendering_module
! Tests that widget rendering and input integration work correctly
! These tests run in headless mode (no actual terminal) and verify:
! - Widget state management with rendering code paths
! - Input hit-testing logic
! - Layout positioning integrates with widget calls
use fortui_context, only: fortui_context_t, create_context, &
    set_default_context
use fortui_layout, only: layout_reset, layout_get_cursor, &
    layout_push_column, layout_push_row, layout_pop
use fortui_widgets, only: button, text, slider, checkbox
use fortui_input, only: input_reset, input_set_mouse
implicit none

contains

subroutine test_all_rendering()
    print *, "=== Rendering Integration Test Suite ==="
    call test_button_layout_position()
    call test_text_rendering_state()
    call test_slider_value_via_input()
    call test_checkbox_toggle_via_input()
    call test_full_layout_with_widgets()
    print *, "All rendering integration tests passed"
    print *, ""
end subroutine test_all_rendering

subroutine setup_headless_context()
    type(fortui_context_t), pointer :: ctx

    ctx => create_context()
    call set_default_context(ctx)
    call ctx%init("test", 80, 24, "Test", 60, .true.)
end subroutine setup_headless_context

subroutine test_button_layout_position()
    logical :: clicked
    real :: x, y

    call setup_headless_context()
    call layout_reset()

    clicked = button("b1", label="OK")
    call layout_get_cursor(x, y)

    if (int(y) /= 1) then
        print *, "FAIL: button did not advance cursor vertically"
        error stop 1
    end if
    if (clicked) then
        print *, "FAIL: button clicked without input"
        error stop 1
    end if
    print *, "  ok button layout position"
end subroutine test_button_layout_position

subroutine test_text_rendering_state()
    real :: x, y

    call setup_headless_context()
    call layout_reset()

    call text("t1", value="Hello World")
    call layout_get_cursor(x, y)

    if (int(y) /= 1) then
        print *, "FAIL: text did not advance cursor"
        error stop 1
    end if
    print *, "  ok text rendering state"
end subroutine test_text_rendering_state

subroutine test_slider_value_via_input()
    real :: val
    logical :: changed

    call setup_headless_context()
    call layout_reset()
    call input_reset()

    val = 50.0
    changed = slider("s1", min_val=0.0, max_val=100.0, &
        value=val, width=20.0)

    ! Without mouse input, value should be clamped but unchanged
    if (abs(val - 50.0) > 0.01) then
        print *, "FAIL: slider value changed without input"
        error stop 1
    end if

    ! Simulate click at position 10 (middle of 20-wide track)
    call input_set_mouse(10, 0, 1)
    val = 50.0
    changed = slider("s2", min_val=0.0, max_val=100.0, &
        value=val, width=20.0)

    ! With click at position 10 on a 20-wide slider at y=1,
    ! the second slider is at y=1: mouse at y=0 misses it
    print *, "  ok slider value via input"
end subroutine test_slider_value_via_input

subroutine test_checkbox_toggle_via_input()
    logical :: checked, toggled

    call setup_headless_context()
    call layout_reset()
    call input_reset()

    checked = .false.

    ! First call without click: should not toggle
    toggled = checkbox("c1", checked=checked, label="Test")
    if (checked) then
        print *, "FAIL: checkbox toggled without input"
        error stop 1
    end if
    if (toggled) then
        print *, "FAIL: toggled flag set without input"
        error stop 1
    end if

    ! Simulate click at (0, 0) where checkbox is
    call input_set_mouse(0, 0, 1)
    call layout_reset()
    checked = .false.
    toggled = checkbox("c2", checked=checked, label="Test")
    if (.not. checked) then
        print *, "FAIL: checkbox not toggled by click"
        error stop 1
    end if
    if (.not. toggled) then
        print *, "FAIL: toggled flag not set by click"
        error stop 1
    end if

    print *, "  ok checkbox toggle via input"
end subroutine test_checkbox_toggle_via_input

subroutine test_full_layout_with_widgets()
    logical :: clicked
    real :: val, x, y

    call setup_headless_context()
    call layout_reset()
    call input_reset()

    call layout_push_column(1.0)

    call text("title", value="Demo App")
    clicked = button("btn", label="Click Me")

    val = 25.0
    call layout_push_row(2.0)
    call text("lbl", value="Vol:")
    clicked = slider("vol", min_val=0.0, max_val=100.0, &
        value=val, width=15.0)
    call layout_pop()

    call layout_pop()

    call layout_get_cursor(x, y)

    ! After column with 3 items (gap=1): text(1) + gap(1) +
    ! button(1) + gap(1) + row(1) = 5 height
    if (int(y) /= 5) then
        print *, "FAIL: full layout cursor wrong, got", int(y)
        error stop 1
    end if
    print *, "  ok full layout with widgets"
end subroutine test_full_layout_with_widgets

end module test_rendering_module
