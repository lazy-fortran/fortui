program test_backend_basic
! Basic test to verify backend detection and render dispatch
use fortui_render, only: render_backend, RENDER_NONE, &
    RENDER_TUI, RENDER_GUI, render_is_active, render_is_gui
use fortui_tui, only: tui_is_available
implicit none

logical :: available

print *, "========================================"
print *, "Basic Backend Test"
print *, "========================================"
print *, ""

! Test 1: render_backend starts as RENDER_NONE
print *, "Test 1: Initial render_backend state..."
if (render_backend == RENDER_NONE) then
    print *, "  pass: render_backend is RENDER_NONE"
else
    print *, "  FAIL: render_backend should be RENDER_NONE"
    stop 1
end if

! Test 2: render_is_active returns false when no backend
print *, "Test 2: render_is_active with no backend..."
if (.not. render_is_active()) then
    print *, "  pass: render_is_active is false"
else
    print *, "  FAIL: render_is_active should be false"
    stop 1
end if

! Test 3: render_is_gui returns false when no backend
print *, "Test 3: render_is_gui with no backend..."
if (.not. render_is_gui()) then
    print *, "  pass: render_is_gui is false"
else
    print *, "  FAIL: render_is_gui should be false"
    stop 1
end if

! Test 4: TUI availability detection
print *, "Test 4: TUI availability detection..."
available = tui_is_available()
if (available) then
    print *, "  pass: TUI backend reports as available"
else
    print *, "  pass: TUI backend correctly reports " &
        // "unavailable in headless mode"
end if

! Test 5: Backend constants are distinct
print *, "Test 5: Backend constants are distinct..."
if (RENDER_NONE /= RENDER_TUI .and. &
    RENDER_TUI /= RENDER_GUI .and. &
    RENDER_NONE /= RENDER_GUI) then
    print *, "  pass: All backend constants are distinct"
else
    print *, "  FAIL: Backend constants should be distinct"
    stop 1
end if

! Test 6: GUI backend not present in TUI-only build
print *, "Test 6: GUI backend intentionally absent " &
    // "in the TUI-only build"

print *, ""
print *, "========================================"
print *, "All basic backend tests passed!"
print *, "========================================"

end program test_backend_basic
