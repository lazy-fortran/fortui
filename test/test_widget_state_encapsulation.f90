program test_widget_state_encapsulation
use fortui_context, only: create_context, destroy_context, fortui_context_t, &
    set_default_context
use fortui_core, only: view
use fortui_widgets, only: button, checkbox, slider, text, viewport
implicit none

integer :: tests_run = 0
integer :: tests_passed = 0
logical :: all_tests_passed = .true.

call test_case("Context allocates widget state map", test_widget_state_map_ready())
call test_case("Button state stored in context", test_button_state_in_context())
call test_case("Button state isolated by context", test_button_state_isolation())
call test_case("Widget source uses context storage", test_widget_source_uses_context())
call test_case("Viewport state stored in context", test_viewport_state_in_context())

call print_test_summary()

if (.not. all_tests_passed) stop 1

contains

logical function test_widget_state_map_ready() result(passed)
    type(fortui_context_t), pointer :: ctx

    ctx => create_context()
    passed = allocated(ctx%widget_states%entries) .and. ctx%widget_states%capacity > 0
    call destroy_context(ctx)
end function test_widget_state_map_ready

logical function test_button_state_in_context() result(passed)
    type(fortui_context_t), pointer :: ctx
    logical :: clicked

    ctx => create_context()
    clicked = button(ctx, "button_state")
    passed = .not. clicked .and. ctx%widget_states%get("button_state", "button") > 0
    call destroy_context(ctx)
end function test_button_state_in_context

logical function test_button_state_isolation() result(passed)
    type(fortui_context_t), pointer :: ctx1, ctx2
    logical :: clicked

    ctx1 => create_context()
    ctx2 => create_context()

    clicked = button(ctx1, "shared_button")
    passed = ctx1%widget_states%get("shared_button", "button") > 0 .and. &
        ctx2%widget_states%get("shared_button", "button") == 0

    call destroy_context(ctx1)
    call destroy_context(ctx2)
end function test_button_state_isolation

logical function test_widget_source_uses_context() result(passed)
    passed = file_contains("src/fortui_widgets.f90", &
        'ctx%widget_states%get(id, "button")') .and. &
        file_contains("src/fortui_widgets.f90", 'ctx%widget_states%get(id, "text")') .and. &
        file_contains("src/fortui_widgets.f90", 'ctx%widget_states%get(id, "slider")') .and. &
        file_contains("src/fortui_widgets.f90", 'ctx%widget_states%get(id, "checkbox")') .and. &
        file_contains("src/fortui_widgets.f90", 'ctx%widget_states%get(id, "viewport")')
end function test_widget_source_uses_context

logical function test_viewport_state_in_context() result(passed)
    type(fortui_context_t), pointer :: ctx
    type(view) :: view_state
    logical :: changed

    ctx => create_context()
    call set_as_default_context(ctx)
    changed = viewport("plot", 40.0, 20.0, view_state)
    passed = .not. changed .and. ctx%widget_states%get("plot", "viewport") > 0
    call clear_default_context()
end function test_viewport_state_in_context

subroutine set_as_default_context(ctx)
    type(fortui_context_t), pointer :: ctx

    call set_default_context(ctx)
end subroutine set_as_default_context

subroutine clear_default_context()
    type(fortui_context_t), pointer :: ctx

    nullify(ctx)
    call set_default_context(ctx)
end subroutine clear_default_context

logical function file_contains(path, needle) result(found)
    character(*), intent(in) :: path, needle
    character(len=512) :: line
    integer :: ios, unit
    logical :: exists

    found = .false.
    inquire(file=path, exist=exists)
    if (.not. exists) return

    open(newunit=unit, file=path, status="old", action="read", iostat=ios)
    if (ios /= 0) return

    do
        read(unit, "(A)", iostat=ios) line
        if (ios /= 0) exit
        if (index(line, needle) > 0) then
            found = .true.
            exit
        end if
    end do

    close(unit)
end function file_contains

subroutine test_case(name, passed)
    character(*), intent(in) :: name
    logical, intent(in) :: passed

    tests_run = tests_run + 1
    if (passed) then
        tests_passed = tests_passed + 1
        write(*, "(A)") "PASS: " // trim(name)
    else
        all_tests_passed = .false.
        write(*, "(A)") "FAIL: " // trim(name)
    end if
end subroutine test_case

subroutine print_test_summary()
    write(*, "(A)") ""
    write(*, "(A,I0,A,I0)") "Widget state encapsulation tests: ", tests_passed, &
        " / ", tests_run
end subroutine print_test_summary

end program test_widget_state_encapsulation
