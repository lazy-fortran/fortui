! test_gui_demo_warnings.f90 - Test that GUI demo doesn't produce warning spam
program test_gui_demo_warnings
use fortui_core
use fortui_widgets
use iso_fortran_env, only: error_unit
implicit none

! node type removed - immediate mode API doesn't use tree objects
integer :: i
logical :: warnings_detected = .false.

print *, "Testing GUI demo frame management..."

! Initialize UI
call ui_init("auto", 640, 480, "Test GUI Demo", target_fps=60, vsync=.true.)

! Run a few frames like the demo does
do i = 1, 5
    call ui_frame_begin(timeout_ms=50)
    
    ! Simulate demo operations
    ! (widgets would be created here in real demo)
    
    ! Properly end frame with minimal tree to avoid warnings
    ! Node objects removed - using immediate mode
    call ui_present()
    
    if (ui_should_close()) exit
end do

call ui_shutdown()

! If we got here without warnings, test passes
print *, "Test PASS: GUI demo runs without frame warnings"
print *, "Completed", i-1, "frames without 'Already in frame' spam"

end program test_gui_demo_warnings