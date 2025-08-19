program main
  use fortui
  implicit none
  
  type(node) :: ui_root
  logical :: running
  integer :: frame_count = 0
  
  print *, "fortui - Declarative UI Library for Modern Fortran"
  print *, "Demo: Basic UI initialization and shutdown"
  print *, "Press ESC to exit"
  
  ! Initialize with automatic backend selection
  call ui_init(backend="auto", width=80, height=25, title="fortui Demo")
  
  running = .true.
  do while (running .and. frame_count < 10)  ! Limited frames for demo
    call ui_frame_begin(timeout_ms=200)
    
    ! Present simple empty UI
    call ui_present(ui_root)
    
    running = .not. ui_should_close()
    frame_count = frame_count + 1
  end do
  
  call ui_shutdown()
  
  print *, "Demo completed successfully after", frame_count, "frames"
end program main
