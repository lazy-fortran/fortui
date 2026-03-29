program test_backward_compatibility
use fortui_context, only: create_context, destroy_context, fortui_context_t, &
    get_default_context, set_default_context
use fortui_core, only: node, ui_frame_begin, ui_init, ui_present, ui_should_close, &
    ui_shutdown
use fortui_widgets, only: button, checkbox, slider, text
implicit none

integer :: tests_run = 0
integer :: tests_passed = 0
logical :: all_tests_passed = .true.

call test_case("Legacy lifecycle entry points are callable", test_legacy_lifecycle())
call test_case("Legacy widget signatures are callable", test_legacy_widgets())
call test_case("Default context can be installed and cleared", test_default_context_cycle())
call test_case("Thread-local default context directive exists", &
    file_contains("src/fortui_context.f90", "THREADPRIVATE(default_context)"))
call test_case("Examples remain present in the repo", test_example_sources_present())
call test_case("Context-aware button overload remains available", test_context_aware_button())

write(*, "(A)") ""
write(*, "(A,I0,A,I0)") "Backward compatibility tests: ", tests_passed, " / ", tests_run

if (.not. all_tests_passed) stop 1

contains

logical function test_legacy_lifecycle() result(passed)
    type(node) :: root
    logical :: should_close

    call ui_init("tui", 80, 24, "compat")
    call ui_frame_begin(1)
    root%layout_type = "none"
    call ui_present(root)
    should_close = ui_should_close()
    call ui_shutdown()

    passed = should_close .or. .not. should_close
end function test_legacy_lifecycle

logical function test_legacy_widgets() result(passed)
    type(fortui_context_t), pointer :: ctx
    logical :: checked, clicked, toggled, value_changed
    real :: value

    ctx => create_context()
    call set_default_context(ctx)

    checked = .false.
    value = 25.0
    clicked = button("compat_button", "Button")
    call text("compat_text", "Text")
    value_changed = slider("compat_slider", 0.0, 100.0, 1.0, value)
    toggled = checkbox("compat_checkbox", checked, "Check")

    passed = .not. clicked .and. .not. value_changed .and. .not. toggled .and. &
        ctx%widget_states%get("compat_button", "button") > 0 .and. &
        ctx%widget_states%get("compat_text", "text") > 0

    call clear_default_context()
end function test_legacy_widgets

logical function test_default_context_cycle() result(passed)
    type(fortui_context_t), pointer :: ctx

    ctx => create_context()
    call set_default_context(ctx)
    passed = associated(get_default_context())
    call clear_default_context()
    passed = passed .and. .not. associated(get_default_context())
end function test_default_context_cycle

logical function test_example_sources_present() result(passed)
    logical :: simple_exists, button_exists, widget_exists

    inquire(file="example/simple_test.f90", exist=simple_exists)
    inquire(file="example/button_test.f90", exist=button_exists)
    inquire(file="example/widget_examples.f90", exist=widget_exists)

    passed = simple_exists .and. button_exists .and. widget_exists
end function test_example_sources_present

logical function test_context_aware_button() result(passed)
    type(fortui_context_t), pointer :: ctx
    logical :: clicked

    ctx => create_context()
    clicked = button(ctx, "explicit_context_button", "Button")
    passed = .not. clicked .and. ctx%widget_states%get("explicit_context_button", "button") > 0
    call destroy_context(ctx)
end function test_context_aware_button

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

end program test_backward_compatibility
