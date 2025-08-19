program checkbox_demo
use fortui_widgets
use fortui_units
use fortui_core, only: node
implicit none

logical :: sound_enabled = .true.
logical :: notifications = .false.
logical :: auto_save = .true.
logical :: dark_mode = .false.
logical :: running = .true.
integer :: frame = 0
type(node) :: checkbox_node

do while (running .and. frame < 10)
    frame = frame + 1
    print *, "=== Settings Panel (Frame", frame, ") ==="
    
    ! Audio settings
    checkbox_node = checkbox("sound", sound_enabled, label="Enable Sound")
    checkbox_node = checkbox("notifications", notifications, label="Notifications")
    
    ! Application settings  
    checkbox_node = checkbox("auto_save", auto_save, label="Auto-save Documents")
    checkbox_node = checkbox("dark_mode", dark_mode, label="Dark Theme", &
                  width=dp(150.0))
    
    ! Display current settings
    print *, "Sound:", sound_enabled, "| Notifications:", notifications
    print *, "Auto-save:", auto_save, "| Dark mode:", dark_mode
    
    ! Exit condition
    if (.not. sound_enabled .and. .not. notifications) then
        print *, "All audio features disabled - exiting"
        running = .false.
    end if
end do
end program