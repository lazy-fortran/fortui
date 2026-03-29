program demo
use fortui
implicit none

real :: gain = 1.0
logical :: grid = .false.
type(node) :: viewport_node
type(view) :: v
type(node) :: ui_root
logical :: running
logical :: viewport_changed
integer :: frame_count = 0

print *, "fortui - Comprehensive Widget Demo"
print *, "===================================="
print *, "Demonstrating button, slider, checkbox, text, and viewport widgets"
print *, "Press ESC to exit"
print *, ""

call ui_init(backend="tui", width=100, height=35, title="plot demo")

running = .true.
do while (running)
    call ui_frame_begin(timeout_ms=200)
    frame_count = frame_count + 1

    if (button("zoom_in", "Zoom In")) then
        call zoom(v, 1.2)
        print *, "Frame", frame_count, ": Zoom in clicked! Scale:", v%scale_x
    end if

    if (button("zoom_out", "Zoom Out")) then
        call zoom(v, 1.0/1.2)
        print *, "Frame", frame_count, ": Zoom out clicked! Scale:", v%scale_x
    end if

    if (slider("gain", 0.1, 5.0, 0.1, gain)) then
        print *, "Frame", frame_count, ": Gain changed to:", gain
    end if

    if (checkbox("grid", grid, "Show Grid")) then
        ! State was toggled
    end if

    viewport_changed = viewport("plot", 80.0, 24.0, v)
    if (viewport_changed) then
        print *, "Frame", frame_count, ": Viewport view changed!"
    end if

    viewport_node = node()

    block
        call text("status", status_line(gain, v, grid))
    end block

    ui_root = build_demo_layout()

    call ui_present(ui_root)

    running = .not. ui_should_close()

    if (mod(frame_count, 50) == 0) then
        print *, "Frame", frame_count, ": gain=", gain, " grid=", grid, &
                 " scale=(", v%scale_x, ",", v%scale_y, ")"
    end if

    if (frame_count > 200) running = .false.
end do

call ui_shutdown()

print *, ""
print *, "Demo Statistics:"
print *, "=================="
print *, "Total frames processed:", frame_count
print *, "Final state:"
print *, "  - Gain:", gain
print *, "  - Grid enabled:", grid
print *, "  - Zoom scale: (", v%scale_x, ",", v%scale_y, ")"
print *, "  - Pan offset: (", v%off_x, ",", v%off_y, ")"

contains

subroutine zoom(v, f)
    type(view), intent(inout) :: v
    real, intent(in) :: f
    v%scale_x = v%scale_x * f
    v%scale_y = v%scale_y * f
end subroutine zoom

function status_line(g, v, show) result(s)
    real, intent(in) :: g
    type(view), intent(in) :: v
    logical, intent(in) :: show
    character(len=:), allocatable :: s
    character(len=96) :: buf
    write(buf, '("gain=",F4.2,"  scale=(",F4.2,",",F4.2, &
        &")  off=(",F5.1,",",F5.1,")  grid=",L1)') &
        g, v%scale_x, v%scale_y, v%off_x, v%off_y, show
    s = trim(buf)
end function status_line

function build_demo_layout() result(layout)
    type(node) :: layout
    type(node), allocatable :: children(:)

    allocate(children(3))
    children(1) = node()
    children(2) = node()
    children(3) = node()

    layout = column(gap=16.0, children=children)
    deallocate(children)
end function build_demo_layout

end program demo
