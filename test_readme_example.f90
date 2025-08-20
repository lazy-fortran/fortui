program backend_demo
  use fortui
  implicit none

  type(node) :: ui, inner_layout
  type(node), allocatable :: children(:)
  logical :: running
  integer :: frame = 0

  ! Backend Registry Pattern - automatic selection with graceful fallback
  call ui_init("auto", cw_unit(60.0), ch_unit(20.0), "Backend Demo")
  ! GUI preferred → TUI fallback → Clear error message
  
  running = .true.
  do while (running)
    call ui_frame_begin(timeout_ms=200)
    frame = frame + 1

    ! Create nested layout structure (works in both TUI and GUI)
    allocate(children(2))
    children(1) = node()  ! placeholder child
    children(2) = node()  ! placeholder child
    inner_layout = row(gap=cw(2.0), children=children)
    
    deallocate(children)
    allocate(children(3))
    children(1) = node()  ! header placeholder  
    children(2) = inner_layout
    children(3) = node()  ! footer placeholder
    
    ui = column(gap=ch(1.0), children=children)

    call ui_present(ui)
    running = .not. ui_should_close()
    
    deallocate(children)
  end do

  call ui_shutdown()
  print *, "Demo completed after", frame, "frames"
end program