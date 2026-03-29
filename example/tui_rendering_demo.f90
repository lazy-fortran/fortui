program tui_rendering_demo
! Demonstration of the enhanced TUI backend visual rendering capabilities
! Shows how widgets are rendered as visual elements in the terminal
use fortui
implicit none

type(node) :: ui_tree
type(node), allocatable :: children(:)
logical :: running
integer :: frame_count = 0

print *, "TUI Rendering Demo - Visual Widget Rendering"
print *, "Enhanced termbox2 integration with cell-based rendering"
print *, ""

call ui_init(backend="tui", width=60, height=20, &
             title="TUI Rendering Demo")

allocate(children(2))
children(1) = column(gap=2.0)
children(2) = row(gap=4.0)
ui_tree = row(gap=8.0, children=children)
deallocate(children)

print *, "UI tree structure created with enhanced visual rendering"
print *, ""

running = .true.
do while (running .and. frame_count < 5)
    call ui_frame_begin(timeout_ms=500)

    call ui_present(ui_tree)

    running = .not. ui_should_close()
    frame_count = frame_count + 1

    print *, "Frame", frame_count, &
        ": Visual elements rendered to terminal cells"
end do

call ui_shutdown()

print *, ""
print *, "TUI RENDERING DEMO COMPLETED"
print *, "Enhanced visual rendering with termbox2 integration"
print *, "Cell-based layout visualization"
print *, "Front/back buffer diffing for efficient updates"
print *, "Event-driven model with proper timeout handling"
print *, "Frames rendered:", frame_count

end program tui_rendering_demo
