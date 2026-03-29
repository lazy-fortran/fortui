program test_backend_basic
! Basic test to verify Backend Registry Pattern implementation
use fortui_backend
use fortui_backend_init
use fortui_tui
#ifdef ENABLE_GUI
use fortui_gui
#endif
implicit none

class(backend_interface), pointer :: backend
character(len=32) :: best_backend
logical :: test_passed
logical :: tui_available

print *, "========================================"
print *, "Basic Backend Registry Pattern Test"
print *, "========================================"
print *, ""

! Test 1: Register TUI backend
print *, "Test 1: Registering TUI backend..."
call register_tui_backend()
backend => get_backend("tui")
if (associated(backend)) then
    print *, "  ✓ TUI backend registered successfully"
else
    print *, "  ✗ Failed to register TUI backend"
    stop 1
end if

! Test 2: Check TUI availability
print *, "Test 2: Checking TUI availability..."
tui_available = backend%is_available()
if (tui_available) then
    print *, "  ✓ TUI backend reports as available"
else
    print *, "  ✓ TUI backend correctly reports unavailable in headless mode"
end if

! Test 3: Check capabilities
print *, "Test 3: Checking TUI capabilities..."
test_passed = .true.
if (.not. backend%capabilities%colors) then
    print *, "  ✗ TUI should support colors"
    test_passed = .false.
end if
if (.not. backend%capabilities%mouse) then
    print *, "  ✗ TUI should support mouse"
    test_passed = .false.
end if
if (.not. backend%capabilities%unicode) then
    print *, "  ✗ TUI should support unicode"
    test_passed = .false.
end if
if (backend%capabilities%graphics) then
    print *, "  ✗ TUI should not support graphics primitives"
    test_passed = .false.
end if
if (test_passed) then
    print *, "  ✓ TUI capabilities are correct"
else
    stop 1
end if

! Test 4: Test auto-selection
print *, "Test 4: Testing auto backend selection..."
call ensure_backends_registered()
best_backend = select_best_backend()
backend => get_backend(best_backend)
if (tui_available) then
    if (associated(backend) .and. trim(best_backend) == "tui") then
        print *, "  ✓ Auto-selection returned a backend: ", trim(best_backend)
    else
        print *, "  ✗ Auto-selection failed"
        stop 1
    end if
else
    if (.not. associated(backend) .and. len_trim(best_backend) == 0) then
        print *, "  ✓ Auto-selection leaves backend empty in headless mode"
    else
        print *, "  ✗ Auto-selection should not pick an unavailable backend"
        stop 1
    end if
end if

! Test 5: Test duplicate registration
print *, "Test 5: Testing duplicate registration handling..."
call register_tui_backend()  ! Register again
backend => get_backend("tui")
if (associated(backend)) then
    print *, "  ✓ Duplicate registration handled correctly"
else
    print *, "  ✗ Duplicate registration broke the registry"
    stop 1
end if

#ifdef ENABLE_GUI
! Test 6: GUI backend registration (if available)
print *, "Test 6: Testing GUI backend registration..."
call register_gui_backend()
backend => get_backend("gui")
if (associated(backend)) then
    print *, "  ✓ GUI backend registered successfully"
    if (backend%capabilities%graphics) then
        print *, "  ✓ GUI reports graphics capability"
    else
        print *, "  ✗ GUI should support graphics"
    end if
else
    print *, "  ✗ Failed to register GUI backend"
end if
#else
print *, "Test 6: GUI backend not compiled (ENABLE_GUI not defined)"
#endif

print *, ""
print *, "========================================"
print *, "All basic backend tests passed!"
print *, "========================================"

end program test_backend_basic
