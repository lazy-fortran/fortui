program button_layout_demo
! Demonstrate button widget with immediate-mode cursor layout
use fortui
use fortui_layout, only: layout_reset, layout_get_cursor
implicit none

logical :: running = .true.
integer :: frame_count = 0
logical :: save_clicked, load_clicked, quit_clicked
real :: x, y

print *, "Button Layout Demo - Immediate-mode cursor positioning"
print *, "======================================================="

do while (running .and. frame_count < 5)
    frame_count = frame_count + 1
    call layout_reset()

    call column_begin(1.0)
    save_clicked = button("save", label="Save File")
    load_clicked = button("load", label="Load File")

    call row_begin(2.0)
    quit_clicked = button("quit", label="Exit")
    call row_end()

    call column_end()

    call layout_get_cursor(x, y)
    print *, "Frame", frame_count, ": cursor after layout at", x, y

    if (save_clicked) print *, "  Save clicked!"
    if (load_clicked) print *, "  Load clicked!"
    if (quit_clicked) running = .false.
end do

print *, ""
print *, "Button layout demo completed after", frame_count, "frames"
end program button_layout_demo
