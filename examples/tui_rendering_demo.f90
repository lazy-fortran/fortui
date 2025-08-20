program tui_rendering_demo
! Demonstration of the enhanced TUI backend visual rendering capabilities
! Shows how widgets are rendered as visual elements in the terminal
use fortui
implicit none

type(node) :: ui_tree, col1, col2
type(node), allocatable :: children(:)
logical :: running
integer :: frame_count = 0

print *, "TUI Rendering Demo - Visual Widget Rendering"
print *, "Enhanced termbox2 integration with cell-based rendering"
print *, ""

! Initialize TUI backend
call ui_init(backend="tui", width=60, height=20, title="TUI Rendering Demo")

! Create a complex layout to demonstrate visual rendering
allocate(children(2))

! Column 1: Vertical layout demonstration
children(1) = column(gap=dp(2.0))

! Column 2: Row layout demonstration  
children(2) = row(gap=dp(4.0))

! Main layout combining both
ui_tree = row(gap=dp(8.0), children=children)
deallocate(children)

print *, "UI tree structure created with enhanced visual rendering:"
print *, "- Column layouts render as '|' characters"
print *, "- Row layouts render as '-' characters"
print *, "- Content markers render as '*' characters"
print *, "- All rendering uses termbox2 cell-based display"
print *, ""

! Render a few frames to demonstrate the visual output
running = .true.
do while (running .and. frame_count < 5)
    call ui_frame_begin(timeout_ms=500)
    
    ! Present the UI tree with enhanced visual rendering
    call ui_present(ui_tree)
    
    running = .not. ui_should_close()
    frame_count = frame_count + 1
    
    print *, "Frame", frame_count, ": Visual elements rendered to terminal cells"
end do

call ui_shutdown()

print *, ""
print *, "🎨 TUI RENDERING DEMO COMPLETED"
print *, "✅ Enhanced visual rendering with termbox2 integration"
print *, "✅ Cell-based layout visualization (-|* characters)"
print *, "✅ Front/back buffer diffing for efficient updates"
print *, "✅ Event-driven model with proper timeout handling"
print *, "Frames rendered:", frame_count

end program tui_rendering_demo