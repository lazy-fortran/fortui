program backend_demo
  use fortui_core
  use fortui_widgets  ! For immediate-mode widget functions
  use fortui_units  
  use fortui_unit_types
  implicit none

  ! PURE IMMEDIATE MODE - NO OBJECTS
  logical :: running
  integer :: frame = 0
  logical :: btn_clicked
  character(len=20) :: frame_str

  ! Backend Registry Pattern - automatic selection with graceful fallback  
  call ui_init("auto", cw_unit(60.0), ch_unit(20.0), "Backend Demo")
  ! GUI preferred → TUI fallback → Clear error message
  
  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)
    frame = frame + 1

    ! IMMEDIATE-MODE UI - NO OBJECTS, JUST FUNCTION CALLS
    btn_clicked = button("exit_btn", "Exit Demo")
    if (btn_clicked) then
      running = .false.
    end if
    
    write(frame_str, '(I0)') frame
    call text("frame_counter", "Frame: " // trim(frame_str))
    
    ! Present the frame - IMMEDIATE MODE
    call ui_present()
    
    ! Check for quit events
    if (ui_should_close()) running = .false.
  end do
  
  call ui_shutdown()
end program backend_demo