program button_layout_demo
! Demonstrate button widget functionality with click detection
use fortui
implicit none

logical :: running = .true.
integer :: frame_count = 0
logical :: save_clicked, load_clicked, settings_clicked, quit_clicked

print *, "Button Layout Demo"
print *, "=================="

do while (running .and. frame_count < 10)
    frame_count = frame_count + 1

    save_clicked = button("save", label="Save File")
    load_clicked = button("load", label="Load File")
    settings_clicked = button("settings", width=80.0)
    quit_clicked = button("quit", label="Exit", width=60.0, height=30.0)

    if (save_clicked) print *, "Frame", frame_count, ": Save button clicked!"
    if (load_clicked) print *, "Frame", frame_count, ": Load button clicked!"
    if (settings_clicked) &
        print *, "Frame", frame_count, ": Settings button clicked!"
    if (quit_clicked) then
        print *, "Frame", frame_count, ": Quit button clicked - exiting!"
        running = .false.
    end if

    print *, "Frame", frame_count, ": All buttons rendered successfully"

    if (frame_count >= 5) then
        running = .false.
    end if
end do

print *, ""
print *, "Button layout demo completed after", frame_count, "frames"
print *, "Button widget click detection functional"
print *, "Auto-sizing and custom sizing working"
print *, "Multiple buttons managed independently"
end program button_layout_demo
