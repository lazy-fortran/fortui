program backend_demo
use fortui
implicit none

type(node) :: ui, inner_layout
type(node), allocatable :: children(:)
logical :: running
integer :: frame = 0

! Backend Registry Pattern - automatic selection with graceful fallback
call ui_init("auto", 60, 20, "Backend Demo")

running = .true.
do while (running)
    call ui_frame_begin(timeout_ms=200)
    frame = frame + 1

    allocate(children(2))
    children(1) = node()
    children(2) = node()
    inner_layout = row(gap=16.0, children=children)

    deallocate(children)
    allocate(children(3))
    children(1) = node()
    children(2) = inner_layout
    children(3) = node()

    ui = column(gap=16.0, children=children)

    call ui_present(ui)
    running = .not. ui_should_close()

    deallocate(children)
end do

call ui_shutdown()
print *, "Demo completed after", frame, "frames"
end program
