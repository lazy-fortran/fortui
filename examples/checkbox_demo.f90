program checkbox_demo
use fortui_widgets
use fortui_units
implicit none

logical :: sound_enabled = .true.
logical :: notifications = .false.
logical :: auto_save = .true.
logical :: dark_mode = .false.
logical :: running = .true.
integer :: frame = 0

do while (running .and. frame < 10)
    frame = frame + 1
    print *, "=== Settings Panel (Frame", frame, ") ==="
    
    ! Audio settings
    call checkbox("sound", sound_enabled, label="Enable Sound")
    call checkbox("notifications", notifications, label="Notifications")
    
    ! Application settings  
    call checkbox("auto_save", auto_save, label="Auto-save Documents")
    call checkbox("dark_mode", dark_mode, label="Dark Theme", &
                  width=150.0)
    
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